//==============================================================================
//
//  File:       LDrawStructure.m
//  Package:    LDrawEditing
//
//  Purpose:    Delete, split, origin-change, submodel, LSynth-insert, and export rules.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawLSynthDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MacLDraw.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/PartSpecific.h>

@interface LDrawStructure ()
+ (nullable LDrawModel *)referencedModelForSplitPart:(LDrawPart *)part;
+ (NSArray<LDrawPart *> *)partsExpandedFromAnchor:(LDrawPart *)anchor
										  inModel:(LDrawModel *)model;
+ (BOOL)originTransform:(Matrix4 *)outTransform
			 correction:(Matrix4 *)outCorrection
			  forAnchor:(LDrawPart *)anchor
				   kind:(LDrawOriginChangeKind)kind;
+ (NSArray<LDrawPart *> *)partsToRebaseInSelection:(NSArray *)selection;
@end

@implementation LDrawStructure

//---------- deleteRefusalForDirective: ------------------------------[static]--
//
// Purpose:		Tests whether the specified directive should be allowed to be
//				deleted. The last remaining model or step in its parent cannot
//				be deleted. The host still displays the error sheet.
//
//------------------------------------------------------------------------------
+ (LDrawDeleteRefusal)deleteRefusalForDirective:(LDrawDirective *)directive
{
	LDrawContainer *parentDirective = [directive enclosingDirective];
	BOOL isLastDirective = ([[parentDirective subdirectives] count] <= 1);

	if ([directive isKindOfClass:[LDrawModel class]] && isLastDirective == YES)
	{
		return LDrawDeleteLastModel;
	}
	if ([directive isKindOfClass:[LDrawStep class]] && isLastDirective == YES)
	{
		return LDrawDeleteLastStep;
	}
	return LDrawDeleteAllowed;
}


//---------- deleteRefusalInformativeKey: ---------------------------[static]--
//
// Purpose:		Localization key explaining why a delete was refused (last model
//				or last step). Returns nil when the delete is allowed. The host
//				still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)deleteRefusalInformativeKey:(LDrawDeleteRefusal)refusal
{
	if (refusal == LDrawDeleteAllowed) return nil;
	if (refusal == LDrawDeleteLastModel) return @"DeleteLastModelInformative";
	return @"DeleteLastStepInformative";
}


//---------- directivesInReverseDeletionOrder: -----------------------[static]--
//
// Purpose:		We'll just try to delete everything. Count backwards so that if
//				a deletion fails, it's the thing at the top rather than the
//				bottom that remains. The host still checks can-delete and
//				deletes (undo).
//
//------------------------------------------------------------------------------
+ (NSArray *)directivesInReverseDeletionOrder:(NSArray *)directives
{
	return [[directives reverseObjectEnumerator] allObjects];
}


//---------- insertionParentForDirective:selectedContainer:visibleStep:[static]
//
// Purpose:		Adds newDirective to the bottom of the current step, or after
//				the currently-selected element in the step if there is one.
//				We may have the model itself selected, in which case we add this
//				new element to the very bottom of the model. Prefer an
//				"interesting" selected container that accepts the directive;
//				otherwise the last visible step.
//
//------------------------------------------------------------------------------
+ (LDrawContainer *)insertionParentForDirective:(LDrawDirective *)directive
							  selectedContainer:(LDrawContainer *)selectedContainer
									visibleStep:(LDrawContainer *)visibleStep
{
	if (	selectedContainer != nil
	   &&	[selectedContainer isKindOfClass:[LDrawFile class]] == NO
	   &&	[selectedContainer isKindOfClass:[LDrawModel class]] == NO
	   &&	[selectedContainer isKindOfClass:[LDrawStep class]] == NO
	   &&	[selectedContainer acceptsDroppedDirective:directive] == YES)
	{
		return selectedContainer;
	}
	return visibleStep;
}


//---------- splitStepDirectivesFromSelection:… ----------------------[static]--
//
// Purpose:		Takes the current selection and moves each selected directive
//				into a new step. The newly created step is inserted directly
//				BEFORE the last parent step of the selection. (Users can use
//				this to rapidly 'break down' a monolithic pile of bricks into
//				sane steps.)
//
// Notes:		The function will only move selection directives that are
//				children of steps from a single model.
//
//------------------------------------------------------------------------------
+ (NSArray *)splitStepDirectivesFromSelection:(NSArray *)selection
							  containingModel:(LDrawContainer * _Nullable * _Nullable)outModel
								   sourceStep:(LDrawStep * _Nullable * _Nullable)outSourceStep
								  insertIndex:(NSInteger * _Nullable)outInsertIndex
{
	NSMutableArray  *movedDirectives = [NSMutableArray arrayWithCapacity:[selection count]];
	LDrawContainer  *containingModel = nil;
	NSInteger        highestIndex    = 0;

	for (id child in selection)
	{
		LDrawDirective *parent = [child enclosingDirective];
		if (parent == nil)
		{
			continue;
		}

		LDrawContainer *model = [parent enclosingDirective];
		if (model == nil)
		{
			continue;
		}

		if (containingModel == nil)
		{
			containingModel = model;
		}
		if (containingModel == model)
		{
			highestIndex = MAX(highestIndex, [containingModel indexOfDirective:parent]);
			[movedDirectives addObject:child];
		}
	}

	if ([movedDirectives count] == 0)
	{
		return movedDirectives;
	}

	if (outModel != NULL)
	{
		*outModel = containingModel;
	}
	if (outInsertIndex != NULL)
	{
		*outInsertIndex = highestIndex;
	}
	if (outSourceStep != NULL)
	{
		*outSourceStep = (LDrawStep *)containingModel.subdirectives[highestIndex];
	}
	return movedDirectives;
}


//---------- transferRotationFromStep:toStep: ------------------------[static]--
//
// Purpose:		Copy rotation from the source step onto the destination, then
//				clear the source type. Do undo stuff before changing rotation
//				in the host.
//
//------------------------------------------------------------------------------
+ (void)transferRotationFromStep:(LDrawStep *)source toStep:(LDrawStep *)destination
{
	[destination setStepRotationType:[source stepRotationType]];
	[destination setRotationAngle:[source rotationAngle]];
	[source setStepRotationType:LDrawStepRotationNone];
}


//---------- referencedModelForSplitPart: ----------------------------[static]--
//
// Purpose:		Copy each part from a MPD sub-model into its location in the
//				parent model. This basically turns a reference to a sub-model
//				into a big pile of bricks that can be directly edited.
//
// Notes:		Only parts are copied; any step information and primitives in
//				the sub-module are ignored. This is the referenced MPD or peer
//				file, or nil if it cannot be split.
//
//------------------------------------------------------------------------------
+ (LDrawModel *)referencedModelForSplitPart:(LDrawPart *)part
{
	LDrawModel *model = [part referencedMPDSubmodel];
	if (model == nil)
	{
		model = [part referencedPeerFile];
	}
	return model;
}


//---------- partsExpandedFromAnchor:inModel: ------------------------[static]--
//
// Purpose:		New parts at the anchor's world transform. Does not mutate the
//				tree. The host still inserts (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPart *> *)partsExpandedFromAnchor:(LDrawPart *)anchor
										  inModel:(LDrawModel *)model
{
	Matrix4         xfrm  = [anchor transformationMatrix];
	NSMutableArray *added = [NSMutableArray array];

	[model applyToAllParts:^(LDrawPart *part) {
		Matrix4 local  = [part transformationMatrix];
		Matrix4 global = Matrix4Multiply(local, xfrm);

		LDrawPart *newPart = [[LDrawPart alloc] init];
		[newPart setLDrawColor:[part LDrawColor]];
		[newPart setDisplayName:[part displayName]];
		[newPart setTransformationMatrix:&global];
		[added addObject:newPart];
	}];
	return added;
}


//---------- splitExpansionsInSelection: -----------------------------[static]--
//
// Purpose:		Copy each part from a MPD sub-model into its location in the
//				parent model. This basically turns a reference to a sub-model
//				into a big pile of bricks that can be directly edited.
//
// Notes:		Only parts are copied; any step information and primitives in
//				the sub-module are ignored. The host still deletes the anchor
//				and inserts the copies (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawSplitExpansion *> *)splitExpansionsInSelection:(NSArray *)selection
{
	NSMutableArray *expansions = [NSMutableArray array];
	for (id thing in selection)
	{
		if ([thing isKindOfClass:[LDrawPart class]] == NO) continue;

		LDrawPart  *anchor = (LDrawPart *)thing;
		LDrawModel *model  = [self referencedModelForSplitPart:anchor];
		if (model == nil) continue;

		LDrawSplitExpansion *expansion = [LDrawSplitExpansion new];
		expansion.anchor = anchor;
		expansion.model = model;
		expansion.expandedParts = [self partsExpandedFromAnchor:anchor inModel:model];
		[expansions addObject:expansion];
	}
	return expansions;
}


//---------- originChangeKind:forMenuTag: ----------------------------[static]--
//
// Purpose:		Handles 3 related commands:
//				1. Moves every part in the selection's parent model so that the
//				   selected part is at 0,0,0.
//				2. Moves every part in the selection's parent model so that the
//				   rotation axis for selected part goes through 0,0,0.
//				3. Rotates every part in the selection's parent model so that
//				   the rotation of the selected part is aligned to 0, 90, 180
//				   or 270º.
//
//------------------------------------------------------------------------------
+ (BOOL)originChangeKind:(LDrawOriginChangeKind *)outKind forMenuTag:(NSInteger)tag
{
	if (outKind == NULL)
	{
		return (tag == changeOriginMenuTag
			 || tag == changeOriginByRotationMenuTag
			 || tag == axesByPartRotationMenuTag);
	}

	if (tag == changeOriginByRotationMenuTag)
	{
		*outKind = LDrawOriginChangeByRotationAxis;
		return YES;
	}
	if (tag == axesByPartRotationMenuTag)
	{
		*outKind = LDrawOriginChangeByAxesAlignment;
		return YES;
	}
	if (tag == changeOriginMenuTag)
	{
		*outKind = LDrawOriginChangeByPosition;
		return YES;
	}
	return NO;
}


//---------- originTransform:correction:forAnchor:kind: --------------[static]--
//
// Purpose:		World transform to apply to other instances, and its inverse for
//				the enclosing model. Also, find all uses of this MPD model and
//				adjust their location in the opposite direction so parent models
//				are not visually affected. The host still applies the matrices
//				(undo).
//
//------------------------------------------------------------------------------
+ (BOOL)originTransform:(Matrix4 *)outTransform
			 correction:(Matrix4 *)outCorrection
			  forAnchor:(LDrawPart *)anchor
				   kind:(LDrawOriginChangeKind)kind
{
	if (outTransform == NULL || outCorrection == NULL || anchor == nil)
	{
		return NO;
	}

	Matrix4 transformMatrix = IdentityMatrix4;

	if (kind == LDrawOriginChangeByRotationAxis)
	{
		Vector3 rotCenter = [PartSpecific rotationCenterForPart:anchor.displayName];
		Vector3 rotPlane  = [PartSpecific rotationPlaneForPart:anchor.displayName];
		Matrix4 anchorMatrix = [anchor transformationMatrix];
		rotCenter = V3MulPointByProjMatrix(rotCenter, anchorMatrix);
		rotPlane  = V3Val(V3MulPointByProjMatrix(rotPlane, Matrix4ClearTranslation(anchorMatrix)));
		Vector3 offset = V3Mul(rotCenter, rotPlane);
		transformMatrix = Matrix4Translate(IdentityMatrix4, offset);
	}
	else if (kind == LDrawOriginChangeByAxesAlignment)
	{
		TransformComponents components = [anchor transformComponents];
		Tuple3 rotation;
		rotation.x = degrees(components.rotate.x);
		rotation.y = degrees(components.rotate.y);
		rotation.z = degrees(components.rotate.z);
		transformMatrix = Matrix4Rotate(IdentityMatrix4, rotation);

		Tuple3 subRotation;
		subRotation.x = 0;
		subRotation.y = -roundf(rotation.y / 90.0f) * 90.0f;
		subRotation.z = 0;
		Matrix4 extraRotationMatrix = Matrix4Rotate(IdentityMatrix4, subRotation);
		transformMatrix = Matrix4Multiply(extraRotationMatrix, transformMatrix);
	}
	else
	{
		transformMatrix = Matrix4Translate(IdentityMatrix4, anchor.position);
	}

	*outTransform  = transformMatrix;
	*outCorrection = Matrix4Invert(transformMatrix);
	return YES;
}


//---------- originPartUpdatesForSelection:kind: ---------------------[static]--
//
// Purpose:		Handles 3 related commands:
//				1. Moves every part in the selection's parent model so that the
//				   selected part is at 0,0,0.
//				2. Moves every part in the selection's parent model so that the
//				   rotation axis for selected part goes through 0,0,0.
//				3. Rotates every part in the selection's parent model so that
//				   the rotation of the selected part is aligned to 0, 90, 180
//				   or 270º.
//
//				Also, find all uses of this MPD model and adjust their location
//				in the opposite direction so parent models are not visually
//				affected. The host still applies the matrices (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawOriginPartUpdate *> *)originPartUpdatesForSelection:(NSArray *)selection
															   kind:(LDrawOriginChangeKind)kind
{
	if ([selection count] == 0) return @[];
	id thing = [selection objectAtIndex:0];
	if ([thing isKindOfClass:[LDrawPart class]] == NO) return @[];

	LDrawPart *anchor = (LDrawPart *)thing;
	Matrix4    transformMatrix;
	Matrix4    correction;
	if ([self originTransform:&transformMatrix
				   correction:&correction
					forAnchor:anchor
						 kind:kind] == NO)
	{
		return @[];
	}

	NSMutableArray *updates     = [NSMutableArray array];
	LDrawModel     *parentModel = [anchor enclosingModel];

	// Iterate the model and move every part based on the anchor part's
	// inverse transform. This also moves the anchor to 0,0,0.
	[parentModel applyToAllParts:^(LDrawPart *part){
		Matrix4 old  = [part transformationMatrix];
		Matrix4 newM = Matrix4Multiply(old, correction);
		LDrawOriginPartUpdate *update = [LDrawOriginPartUpdate new];
		update.part = part;
		update.matrix = newM;
		update.previousComponents = [part transformComponents];
		[updates addObject:update];
	}];

	// Iterate sub-models. For every _other_ sub-model, search every
	// part and apply the anchor's transform to restore the model.
	NSArray *submodels = [[anchor enclosingFile] submodels];
	for (LDrawModel *model in submodels)
	{
		if (model == parentModel) continue;
		[model applyToAllParts:^(LDrawPart *part){
			if ([part referencedMPDSubmodel] != parentModel) return;
			Matrix4 old  = [part transformationMatrix];
			Matrix4 newM = Matrix4Multiply(transformMatrix, old);
			LDrawOriginPartUpdate *update = [LDrawOriginPartUpdate new];
			update.part = part;
			update.matrix = newM;
			update.previousComponents = [part transformComponents];
			[updates addObject:update];
		}];
	}

	return updates;
}


//---------- selectionCanSplitStep: ----------------------------------[static]--
//
// Purpose:		splitStep splits the selected directives out of their current
//				steps and puts them into a newly created step. The function will
//				only move selection directives that are children of steps from a
//				single model.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanSplitStep:(NSArray *)selection
{
	if ([selection count] == 0)
	{
		return NO;
	}

	LDrawModel *commonModel = nil;
	for (id currentDirective in selection)
	{
		LDrawModel     *model  = [currentDirective enclosingModel];
		LDrawContainer *parent = [currentDirective enclosingDirective];
		if (commonModel == nil)
		{
			commonModel = model;
		}

		if (	parent == nil || model == nil
		   ||	model != commonModel
		   ||	[parent isKindOfClass:[LDrawStep class]] == NO)
		{
			return NO;
		}
	}
	return YES;
}


//---------- selectionCanSplitModel: ---------------------------------[static]--
//
// Purpose:		Copy each part from a MPD sub-model into its location in the
//				parent model. This basically turns a reference to a sub-model
//				into a big pile of bricks that can be directly edited.
//
// Notes:		Only parts are copied; any step information and primitives in
//				the sub-module are ignored. Menu enable: every selected object
//				must be an LDrawPart.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanSplitModel:(NSArray *)selection
{
	if ([selection count] == 0)
	{
		return NO;
	}
	for (id object in selection)
	{
		if ([object class] != [LDrawPart class])
		{
			return NO;
		}
	}
	return YES;
}


//---------- selectionCanChangeOrigin: -------------------------------[static]--
//
// Purpose:		Handles 3 related commands:
//				1. Moves every part in the selection's parent model so that the
//				   selected part is at 0,0,0.
//				2. Moves every part in the selection's parent model so that the
//				   rotation axis for selected part goes through 0,0,0.
//				3. Rotates every part in the selection's parent model so that
//				   the rotation of the selected part is aligned to 0, 90, 180
//				   or 270º.
//
//				Menu enable: exactly one part selected.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanChangeOrigin:(NSArray *)selection
{
	return [selection count] == 1 && [[selection objectAtIndex:0] class] == [LDrawPart class];
}


//---------- selectionCanChangeOriginByRotation: ---------------------[static]--
//
// Purpose:		Change-origin by rotation axis. The selected part must have a
//				PartSpecific rotation center.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanChangeOriginByRotation:(NSArray *)selection
{
	if ([self selectionCanChangeOrigin:selection] == NO)
	{
		return NO;
	}
	LDrawPart *part = [selection objectAtIndex:0];
	return [PartSpecific hasRotationCenter:[part displayName]];
}


//---------- selectionCanMoveToParentModel: --------------------------[static]--
//
// Purpose:		Move selected directives from submodel to the parent model(s)
//				where this submodel is inserted as a part. This also works if
//				selected directives are located in different submodels.
//
//				Menu enable: non-empty selection that is not all models or all
//				steps.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanMoveToParentModel:(NSArray *)selection
{
	NSUInteger count = [selection count];
	if (count == 0)
	{
		return NO;
	}

	Class selTypes = [[selection objectAtIndex:0] class];
	for (id object in selection)
	{
		if ([object class] != selTypes)
		{
			selTypes = Nil;
			break;
		}
	}
	return selTypes != [LDrawMPDModel class] && selTypes != [LDrawStep class];
}


//---------- directivesGroupedByEnclosingModelName: ------------------[static]--
//
// Purpose:		Move selected directives to the parent model (the model from
//				where this submodel is inserted as a part). This also works if
//				selected directives are located in different submodels.
//
// Notes:		If we get empty submodels or empty steps after moving stuff then
//				they will be deleted.
//
//------------------------------------------------------------------------------
+ (NSDictionary<NSString *, NSArray<LDrawDirective *> *> *)directivesGroupedByEnclosingModelName:(NSArray *)directives
{
	NSMutableDictionary<NSString *, NSMutableArray<LDrawDirective *> *> *grouped = [NSMutableDictionary dictionary];

	for (LDrawDirective *directive in directives)
	{
		NSString *modelName = directive.enclosingModel.fileName;
		if (modelName == nil)
		{
			continue;
		}
		NSMutableArray<LDrawDirective *> *list = grouped[modelName];
		if (list == nil)
		{
			grouped[modelName] = [NSMutableArray arrayWithArray:@[directive]];
		}
		else
		{
			[list addObject:directive];
		}
	}
	return grouped;
}


//---------- copyOfDirective:placedAtReference: ----------------------[static]--
//
// Purpose:		Move selected directives to the parent model (the model from
//				where this submodel is inserted as a part). Part copies get the
//				instance's world transform; other directives are copies.
//
//------------------------------------------------------------------------------
+ (LDrawDirective *)copyOfDirective:(LDrawDirective *)directive
				  placedAtReference:(LDrawPart *)reference
{
	if ([directive isKindOfClass:[LDrawPart class]])
	{
		LDrawPart *part    = (LDrawPart *)directive;
		LDrawPart *newPart = [part copy];
		[newPart setLDrawColor:[part LDrawColor]];
		[newPart setDisplayName:[part displayName]];
		Matrix4 global = Matrix4Multiply([part transformationMatrix], [reference transformationMatrix]);
		[newPart setTransformationMatrix:&global];
		return newPart;
	}
	return [directive copy];
}


//---------- cleanupAfterRemovingFromModel:step: ---------------------[static]--
//
// Purpose:		If we get empty submodels or empty steps after moving stuff then
//				they will be deleted. The host still performs the deletes
//				(undo).
//
//------------------------------------------------------------------------------
+ (LDrawMoveToParentCleanup)cleanupAfterRemovingFromModel:(LDrawModel *)model
													 step:(LDrawStep *)step
{
	if (model != nil && [model numberElements] == 0)
	{
		return LDrawMoveToParentCleanupEmptyModel;
	}
	if (step != nil && [[step subdirectives] count] == 0)
	{
		return LDrawMoveToParentCleanupEmptyStep;
	}
	return LDrawMoveToParentCleanupNone;
}


//---------- anchorPartInSelection: ----------------------------------[static]--
//
// Purpose:		First part in selection order; used as the origin of a new
//				submodel.
//
//------------------------------------------------------------------------------
+ (LDrawPart *)anchorPartInSelection:(NSArray *)selection
{
	for (id directive in selection)
	{
		if ([directive isKindOfClass:[LDrawPart class]])
		{
			return directive;
		}
	}
	return nil;
}


//---------- modelFromSelectionAnchorMatrix:correction:forAnchor: ----[static]--
//
// Purpose:		Creates a new sub-model whose contents are the currently
//				selected parts. Parts are moved to the sub-model, using the
//				first selected part as the origin. Returns the anchor world
//				matrix and its inverse (to rebase nested parts).
//
//------------------------------------------------------------------------------
+ (BOOL)modelFromSelectionAnchorMatrix:(Matrix4 *)outAnchorMatrix
							correction:(Matrix4 *)outCorrection
							 forAnchor:(LDrawPart *)anchor
{
	if (outAnchorMatrix == NULL || outCorrection == NULL || anchor == nil)
	{
		return NO;
	}

	Matrix4 anchorMatrix = [anchor transformationMatrix];
	*outAnchorMatrix = anchorMatrix;
	*outCorrection   = Matrix4Invert(anchorMatrix);
	return YES;
}


//---------- partsToRebaseInSelection: -------------------------------[static]--
//
// Purpose:		Nested parts under selected containers (via applyToAllParts:).
//				These get the inverse of the anchor transform so they sit at
//				the new submodel origin.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPart *> *)partsToRebaseInSelection:(NSArray *)selection
{
	NSMutableArray *parts = [NSMutableArray array];
	for (id directive in selection)
	{
		if ([directive respondsToSelector:@selector(applyToAllParts:)])
		{
			[directive applyToAllParts:^(LDrawPart *part) {
				[parts addObject:part];
			}];
		}
	}
	return parts;
}


//---------- rebasedPartUpdatesInSelection:correction: ---------------[static]--
//
// Purpose:		Takes the current selection and makes a new MPD sub-model of the
//				selected parts. Parts are moved to the sub-model, using the
//				first selected part as the origin. Nested parts get the inverse
//				of the anchor transform. The host still applies them (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawOriginPartUpdate *> *)rebasedPartUpdatesInSelection:(NSArray *)selection
														 correction:(Matrix4)correction
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsToRebaseInSelection:selection])
	{
		Matrix4 old  = [part transformationMatrix];
		Matrix4 newM = Matrix4Multiply(old, correction);
		LDrawOriginPartUpdate *update = [LDrawOriginPartUpdate new];
		update.part = part;
		update.matrix = newM;
		update.previousComponents = [part transformComponents];
		[updates addObject:update];
	}
	return updates;
}


//---------- lastStepOfModel: ----------------------------------------[static]--
//
// Purpose:		Takes the current selection and makes a new MPD sub-model of the
//				selected parts. Parts are moved to the sub-model, using the
//				first selected part as the origin. Last step of a newly created
//				model is the destination for the moved directives.
//
//------------------------------------------------------------------------------
+ (LDrawStep *)lastStepOfModel:(LDrawModel *)model
{
	return (LDrawStep *)[[model steps] lastObject];
}


//---------- referencePartForSubmodelName:anchorMatrix:color: --------[static]--
//
// Purpose:		A new part is placed in the current model referencing the newly
//				made sub-model. This means the user sees the same contents, but
//				via a reference.
//
//------------------------------------------------------------------------------
+ (LDrawPart *)referencePartForSubmodelName:(NSString *)modelName
							   anchorMatrix:(Matrix4)anchorMatrix
									  color:(LDrawColor *)color
{
	LDrawPart *newPart = [[LDrawPart alloc] init];
	[newPart setLDrawColor:color];
	[newPart setDisplayName:modelName];
	[newPart setTransformationMatrix:&anchorMatrix];
	return newPart;
}


//---------- lsynthInsertionParent:index:forLastSelected: ------------[static]--
//
// Purpose:		Insert a synthesizable directive constraint into the model.
//				We don't distinguish between hose or band constraints since
//				both types can be used for either synthesizable type.
//
//------------------------------------------------------------------------------
+ (BOOL)lsynthInsertionParent:(LDrawContainer * _Nullable * _Nullable)outParent
						index:(NSInteger * _Nullable)outIndex
			  forLastSelected:(id)lastSelected
{
	if (lastSelected == nil)
	{
		return NO;
	}

	if ([lastSelected isKindOfClass:[LDrawLSynth class]])
	{
		if (outParent != NULL)
		{
			*outParent = lastSelected;
		}
		if (outIndex != NULL)
		{
			*outIndex = [[lastSelected subdirectives] count];
		}
		return YES;
	}

	if ([lastSelected isKindOfClass:[LDrawDirective class]])
	{
		LDrawContainer *parent = [lastSelected enclosingDirective];
		if ([parent isKindOfClass:[LDrawLSynth class]])
		{
			if (outParent != NULL)
			{
				*outParent = parent;
			}
			if (outIndex != NULL)
			{
				*outIndex = [parent indexOfDirective:lastSelected] + 1;
			}
			return YES;
		}
	}
	return NO;
}


//---------- lsynthDirectionCommandForMenuTag: -----------------------[static]--
//
// Purpose:		Insert an LSynth direction directive, INSIDE or OUTSIDE, which
//				causes a constraint to switch the side the band passes it.
//				INSIDE / OUTSIDE / CROSS from MacLDraw.h menu tags; nil if the
//				tag is unrelated.
//
//------------------------------------------------------------------------------
+ (NSString *)lsynthDirectionCommandForMenuTag:(NSInteger)tag
{
	if (tag == lsynthInsertINSIDETag)
	{
		return @"INSIDE";
	}
	if (tag == lsynthInsertOUTSIDETag)
	{
		return @"OUTSIDE";
	}
	if (tag == lsynthInsertCROSSTag)
	{
		return @"CROSS";
	}
	return nil;
}


//---------- lsynthInsertUndoKeyForMenuTag: -------------------------[static]--
//
// Purpose:		Undo action name key for inserting an LSynth object from a menu
//				tag. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)lsynthInsertUndoKeyForMenuTag:(NSInteger)tag
{
	if (tag == lsynthInsertINSIDETag) return @"UndoAddLSynthInside";
	if (tag == lsynthInsertOUTSIDETag) return @"UndoAddLSynthOutside";
	return @"UndoAddLSynthCross";
}


//---------- mpdSubmodelToActivateFromSelection: ---------------------[static]--
//
// Purpose:		If a single part is selected and the part is an MPD sub-model,
//				this is the current edited submodel to switch to.
//
//------------------------------------------------------------------------------
+ (LDrawMPDModel *)mpdSubmodelToActivateFromSelection:(NSArray *)selection
{
	if ([selection count] != 1)
	{
		return nil;
	}

	id currentObject = [selection objectAtIndex:0];
	if ([currentObject respondsToSelector:@selector(referencedMPDSubmodel)] == NO)
	{
		return nil;
	}

	LDrawModel *model = [currentObject referencedMPDSubmodel];
	if ([model isKindOfClass:[LDrawMPDModel class]])
	{
		return (LDrawMPDModel *)model;
	}
	return nil;
}


//---------- peerFileFromSelection:path: -----------------------------[static]--
//
// Purpose:		If a single part is selected and it's a peer file on disk, this
//				is the .ldr path to open in a new document. The host still opens
//				it.
//
//------------------------------------------------------------------------------
+ (BOOL)peerFileFromSelection:(NSArray *)selection
						 path:(NSString * _Nullable * _Nullable)outPath
{
	if (outPath != NULL)
	{
		*outPath = nil;
	}
	if ([selection count] != 1)
	{
		return NO;
	}

	id currentObject = [selection objectAtIndex:0];
	if ([currentObject respondsToSelector:@selector(referencedPeerFile)] == NO)
	{
		return NO;
	}

	LDrawModel *model = [currentObject referencedPeerFile];
	if (model == nil)
	{
		return NO;
	}
	if (outPath != NULL)
	{
		*outPath = [[model enclosingFile] path];
	}
	return YES;
}


//---------- splitStepUndoActionKey ----------------------------------[static]--
//
// Purpose:		Localization key after splitting a step. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)splitStepUndoActionKey
{
	return @"UndoSplitStep";
}


//---------- splitModelUndoActionKey ---------------------------------[static]--
//
// Purpose:		Localization key after expanding a split-able model. The host
//				still localizes. (Key casing matches the existing strings file.)
//
//------------------------------------------------------------------------------
+ (NSString *)splitModelUndoActionKey
{
	return @"undoSplitModel";
}


//---------- moveToParentModelUndoActionKey --------------------------[static]--
//
// Purpose:		Localization key after moving selection to parent models.
//
//------------------------------------------------------------------------------
+ (NSString *)moveToParentModelUndoActionKey
{
	return @"UndoMoveToParentModel";
}


//---------- changeOriginUndoActionKey -------------------------------[static]--
//
// Purpose:		Localization key after changing part origins.
//
//------------------------------------------------------------------------------
+ (NSString *)changeOriginUndoActionKey
{
	return @"UndoChangeOrigin";
}


//---------- modelFromSelectionUndoActionKey -------------------------[static]--
//
// Purpose:		Localization key after creating a submodel from the selection.
//
//------------------------------------------------------------------------------
+ (NSString *)modelFromSelectionUndoActionKey
{
	return @"UndoModelFromSelection";
}


//---------- convertPrimitivesUndoActionKey --------------------------[static]--
//
// Purpose:		Localization key after converting to high-res primitives.
//
//------------------------------------------------------------------------------
+ (NSString *)convertPrimitivesUndoActionKey
{
	return @"UndoConvertPrimitives";
}


//---------- deleteDirectiveErrorMessageKey --------------------------[static]--
//
// Purpose:		Format key for the delete-refusal alert (takes
//				browsingDescription). The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)deleteDirectiveErrorMessageKey
{
	return @"DeleteDirectiveError";
}


//---------- compliantNameChangesForSubmodels: -----------------------[static]--
//
// Purpose:		Ensures that the names of all submodels end in a recognized
//				LDraw extension (.ldr, .dat). Previous versions of Bricksmith
//				did not force this, and it was a seemingly sensible, Maclike
//				thing to do. Alas, MLCad will NOT RECOGNIZE submodels whose
//				names do not have an extension. (Why...?!) Furthermore,
//				according to the LDraw File Specification, a type 1 MUST point
//				to a "valid LDraw filename," which MUST include the extension.
//				http://www.ldraw.org/Article218.html#lt1 Sigh...
//
// Notes:		Find submodels with bad names. If the model name does not have
//				a valid LDraw file extension, the LDraw spec says we must give
//				it one. Ugh.
//
//				For files with only one model, we synthesize a name based on
//				the model description. We can safely do a direct rename of
//				these files. This also means LDrawMPDModel doesn't have to
//				clean up every official part we parse from the LDraw folder.
//
//				For MPD documents, we need to do a complex rename. The host
//				still calls renameModel:toName: and marks the document dirty.
//
//------------------------------------------------------------------------------
+ (NSArray *)compliantNameChangesForSubmodels:(NSArray *)submodels
{
	NSMutableArray *changes = [NSMutableArray array];
	BOOL renameInPlace = ([submodels count] == 1);

	for (LDrawMPDModel *currentSubmodel in submodels)
	{
		NSString *currentName    = [currentSubmodel modelName];
		NSString *acceptableName = [LDrawMPDModel ldrawCompliantNameForName:currentName];

		if ([acceptableName isEqualToString:currentName] == NO)
		{
			[changes addObject:[[LDrawCompliantNameChange alloc] initWithModel:currentSubmodel
																 compliantName:acceptableName
																 renameInPlace:renameInPlace]];
		}
	}
	return changes;
}


//---------- stepExportFilesFromFile:folderNameFormat:fileNameFormat: [static]--
//
// Purpose:		Output all the steps for all the submodels as a series of files,
//				one for each progressive step.
//
// Notes:		Move the target model to the top of the file. That way L3P will
//				know to render it!
//
//				Write out each step, then remove the step we just wrote, so
//				that the next cycle won't include it. We can safely do this
//				because we are working with a copy of the file. The host still
//				makes folders and writes bytes.
//
//------------------------------------------------------------------------------
+ (NSArray *)stepExportFilesFromFile:(LDrawFile *)file
					folderNameFormat:(NSString *)folderNameFormat
					  fileNameFormat:(NSString *)fileNameFormat
{
	NSMutableArray *exports = [NSMutableArray array];
	if (file == nil) return exports;

	NSArray        *submodels = [file submodels];
	NSInteger       modelCounter;

	for (modelCounter = 0; modelCounter < [submodels count]; modelCounter++)
	{
		LDrawFile *fileCopy = [file copy];
		LDrawMPDModel *currentModel = [[fileCopy submodels] objectAtIndex:modelCounter];
		[fileCopy removeDirective:currentModel];
		[fileCopy insertDirective:currentModel atIndex:0];
		[fileCopy setActiveModel:currentModel];

		NSString *folderName = [NSString stringWithFormat:folderNameFormat, [currentModel modelName]];
		NSInteger counter;

		for (counter = [[currentModel steps] count]-1; counter >= 0; counter--)
		{
			NSString *ldrString = [fileCopy write];
			NSString *fileName  = [NSString stringWithFormat:fileNameFormat,
								   [currentModel modelName],
								   (long)counter+1];
			[exports addObject:[[LDrawStepExportFile alloc] initWithFolderName:folderName
																	  fileName:fileName
																	 ldrString:ldrString]];
			[currentModel removeDirectiveAtIndex:counter];
		}
	}
	return exports;
}


//---------- exportedStepsFolderFormatKey ----------------------------[static]--
//
// Purpose:		Localization format keys for step export. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)exportedStepsFolderFormatKey
{
	return @"ExportedStepsFolderFormat";
}


//---------- exportedStepsFileFormatKey -----------------------------[static]--
//
// Purpose:		Localization key format for an exported-steps file name. The
//				host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)exportedStepsFileFormatKey
{
	return @"ExportedStepsFileFormat";
}


//---------- duplicateModelNameMessageFormatKey ----------------------[static]--
//
// Purpose:		Duplicate model-name alert keys. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicateModelNameMessageFormatKey
{
	return @"DuplicateModelnameMessage";
}


//---------- duplicateModelNameInformativeKey -----------------------[static]--
//
// Purpose:		Localization key for the duplicate-model-name alert informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicateModelNameInformativeKey
{
	return @"DuplicateModelnameInformative";
}


//---------- shouldRejectDuplicateModelRenameFrom:to:whenModelNameExists: ------
//
// Purpose:		YES when renaming to a different name that already exists in
//				the file. Duplicate model names are not allowed, because they
//				cause nasty things to happen when automatically renaming
//				references to them.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldRejectDuplicateModelRenameFrom:(NSString *)oldValue
										  to:(NSString *)newValue
						 whenModelNameExists:(BOOL)nameExists
{
	if (nameExists == NO)
		return NO;
	if (oldValue == nil || newValue == nil)
		return nameExists;
	return [newValue caseInsensitiveCompare:oldValue] != NSOrderedSame;
}


//---------- wrappedStepIndex:byDelta:stepCount: ---------------------[static]--
//
// Purpose:		Moves the step display forward or back, wrapping at the ends.
//
// Notes:		Wrap around? In C, the remainder of a negative dividend is
//				negative, so stepping back from 0 cannot use a raw `%`.
//
//------------------------------------------------------------------------------
+ (NSInteger)wrappedStepIndex:(NSInteger)current
					  byDelta:(NSInteger)delta
					stepCount:(NSInteger)count
{
	if (count <= 0) return 0;
	return ((current + delta) % count + count) % count;
}


//---------- highResSourceDirectivesFromSelection:activeModel: -------[static]--
//
// Purpose:		Changes low-res directives into high-res quality for "48"
//				folder. If nothing is selected, all directives in the first
//				step are converted. The host still replaces (undo).
//
//------------------------------------------------------------------------------
+ (NSArray *)highResSourceDirectivesFromSelection:(NSArray *)selection
									  activeModel:(LDrawModel *)model
{
	if ([selection count] > 0) return selection;
	return [[[model steps] firstObject] subdirectives];
}


@end
