//==============================================================================
//
//  File:       LDrawDocumentTree.m
//  Package:    LDrawEditing
//
//  Purpose:    Contains methods to examine document structure.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawDocumentTree.h>

#import <LDrawEditing/LDrawClipboard.h>
#import <math.h>

#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/LDrawComment.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawLSynthDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawObjectWithValue.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LPubRemoveGroup.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/MacLDraw.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/PartSpecific.h>

static BOOL LDrawDirectiveSupportsGroup(id object)
{
	return [object isKindOfClass:[LDrawDirective class]]
		&& [object respondsToSelector:@selector(group)];
}


@interface LDrawDocumentTree ()
+ (LDrawDirective *)similarDirective:(LDrawDirective *)directive amongObjects:(id)objects;
/// Model→file, step→model, leaf→container, plus acceptsDroppedDirective:.
+ (BOOL)canNestDirective:(LDrawDirective *)directive inParent:(id)parent;
/// MPD submodel or peer file referenced by the part; nil if it cannot be split.
+ (nullable LDrawModel *)referencedModelForSplitPart:(LDrawPart *)part;
/// New parts at the anchor's world transform. Does not mutate the tree.
+ (NSArray<LDrawPart *> *)partsExpandedFromAnchor:(LDrawPart *)anchor
										  inModel:(LDrawModel *)model;
/// World transform to apply to other instances, and its inverse for the
/// enclosing model. Rotation-axis uses PartSpecific for the part name.
+ (BOOL)originTransform:(Matrix4 *)outTransform
			 correction:(Matrix4 *)outCorrection
			  forAnchor:(LDrawPart *)anchor
				   kind:(LDrawOriginChangeKind)kind;
/// Nested parts under selected containers (via applyToAllParts:).
+ (NSArray<LDrawPart *> *)partsToRebaseInSelection:(NSArray *)selection;
/// Leaf-directive paste goes into a step. Nil if parent is not a step; the
/// host then uses the selected step / next-to-similar.
+ (nullable LDrawContainer *)pasteStepParentFromParent:(nullable id)parent;
/// Duplicate of the current selection should insert as a new MPD model.
+ (BOOL)selectionIsModelForDuplicate:(NSArray *)selection;
/// YES if a matching selected part was found. outParent is that part's
/// enclosing container; outIndex is immediately after it.
+ (BOOL)nextToSimilarPlacementForDirective:(LDrawDirective *)directive
							   inSelection:(NSArray *)selection
									parent:(LDrawContainer * _Nullable * _Nullable)outParent
									 index:(NSInteger * _Nullable)outIndex;
/// Drop-on is never allowed. Same-outline + disallow-to-source is none.
/// Nesting uses canNestDirective:inParent:. Same outline is move, else copy.
+ (LDrawOutlineDropKind)outlineDropKindForDropOnItem:(BOOL)isDropOnItem
									hasDirectiveData:(BOOL)hasDirectiveData
									   isSameOutline:(BOOL)isSameOutline
								disallowDragToSource:(BOOL)disallowDragToSource
										   directive:(nullable id)directive
											  parent:(nullable id)parent;
@end

@interface LDrawViewDropMove ()
- (instancetype)initWithDirective:(LDrawDrawableElement *)directive
					 displacement:(Vector3)displacement;
@end

@interface LDrawCompliantNameChange ()
- (instancetype)initWithModel:(LDrawMPDModel *)model
				compliantName:(NSString *)compliantName
				renameInPlace:(BOOL)renameInPlace;
@end

@interface LDrawStepExportFile ()
- (instancetype)initWithFolderName:(NSString *)folderName
						  fileName:(NSString *)fileName
						 ldrString:(NSString *)ldrString;
@end

@implementation LDrawDocumentTree

//---------- similarDirective:amongObjects: --------------------------[static]--
///
/// @abstract	Returns the part that is similar to the given one, or NSNotFound
///				if there is no such directive or given directive is not a part.
///
/// @param 		directive	- given directive which copy we are looking for.
/// @param 		objects		- we are searching withing this set of objects.
///
//------------------------------------------------------------------------------
+ (LDrawDirective *)similarDirective:(LDrawDirective *)directive
						amongObjects:(id)objects
{
	if ([directive isKindOfClass:[LDrawPart class]]) {
		LDrawPart *part = (LDrawPart *)directive;
		for (id object in objects) {
			if ([object isKindOfClass:[LDrawPart class]]) {
				LDrawPart *p = (LDrawPart *)object;
				Matrix4 m1 = part.transformationMatrix;
				Matrix4 m2 = p.transformationMatrix;
				if (	[part.displayName isEqualToString:p.displayName]
					&& 	part.LDrawColor == p.LDrawColor
					&& 	Matrix4EqualMatrices(&m1, &m2))
				{
					return object;
				}
			}
		}
	}
	return nil;
	
} // end similarDirective:amongObjects:


//---------- groupsBeforeStep ----------------------------------------[static]--
///
/// @abstract	Gathers all group names declared until given step.
///
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *)groupsBeforeStep:(LDrawStep *)step
{
	NSMutableSet<NSString *>	*groups	= [NSMutableSet set];
	LDrawModel					*model 	= step.enclosingModel;
	
	for (LDrawStep *currentStep in model.steps) {
		if (currentStep == step) {
			break;
		}
		
		for (id object in currentStep.subdirectives) {
			if ([object respondsToSelector:@selector(group)]) {
				NSString *group = [object group];
				if (group.length > 0) {
					[groups addObject:group];
				}
			}
		}
	}
	
	return groups;
	
} // end groupsBeforeStep


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


//---------- canNestDirective:inParent: ------------------------------[static]--
//
// Purpose:		Whether a dragged directive may land in the proposed parent.
//				Models must land in a file, steps in a model, other leaves in a
//				container. Prohibit dropping onto a container that it's not
//				happy to accept (acceptsDroppedDirective:).
//
//------------------------------------------------------------------------------
+ (BOOL)canNestDirective:(LDrawDirective *)directive inParent:(id)parent
{
	if ([directive isKindOfClass:[LDrawModel class]] == YES
	   && [parent isKindOfClass:[LDrawFile class]] == NO)
	{
		return NO;
	}
	if ([directive isKindOfClass:[LDrawStep class]] == YES
	   && [parent isKindOfClass:[LDrawModel class]] == NO)
	{
		return NO;
	}
	if ([directive isKindOfClass:[LDrawContainer class]] == NO
	   && [parent isKindOfClass:[LDrawContainer class]] == NO)
	{
		return NO;
	}
	if ([parent isKindOfClass:[LDrawContainer class]]
	   && [(LDrawContainer *)parent acceptsDroppedDirective:directive] == NO)
	{
		return NO;
	}
	return YES;
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
	if ([selection count] == 0) return [NSArray array];
	id thing = [selection objectAtIndex:0];
	if ([thing isKindOfClass:[LDrawPart class]] == NO) return [NSArray array];

	LDrawPart *anchor = (LDrawPart *)thing;
	Matrix4    transformMatrix;
	Matrix4    correction;
	if ([self originTransform:&transformMatrix
				  correction:&correction
				   forAnchor:anchor
						kind:kind] == NO)
	{
		return [NSArray array];
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
			grouped[modelName] = [NSMutableArray arrayWithObject:directive];
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


//---------- partitionPastedObjects:models:steps:directives: ---------[static]--
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				Reset default icons, then bucket unarchived objects into models
//				/ steps / other directives. Paste inserts the first non-empty
//				bucket. The host still inserts (undo).
//
//------------------------------------------------------------------------------
+ (void)partitionPastedObjects:(NSArray *)objects
						models:(NSMutableArray *)models
						 steps:(NSMutableArray *)steps
					directives:(NSMutableArray *)directives
{
	for (id currentObject in objects)
	{
		if ([currentObject isKindOfClass:[LDrawDirective class]])
		{
			NSString *iconName = [[currentObject class] defaultIconName];
			if (iconName != nil)
			{
				[currentObject setIconName:iconName];
			}
		}

		if ([currentObject isKindOfClass:[LDrawModel class]])
		{
			[models addObject:currentObject];
		}
		else if ([currentObject isKindOfClass:[LDrawStep class]])
		{
			[steps addObject:currentObject];
		}
		else
		{
			[directives addObject:currentObject];
		}
	}
}


//---------- pasteStepParentFromParent: -----------------------------[static]--
//
// Purpose:		Return the step-level container to paste into, walking up from
//				parent if needed.
//
//------------------------------------------------------------------------------
+ (LDrawContainer *)pasteStepParentFromParent:(id)parent
{
	if ([parent isKindOfClass:[LDrawStep class]]) return parent;
	return nil;
}


//---------- pasteModelParentFromParent: ----------------------------[static]--
//
// Purpose:		Return the MPD model to paste a new model next to, walking up
//				from parent if needed.
//
//------------------------------------------------------------------------------
+ (LDrawMPDModel *)pasteModelParentFromParent:(id)parent
{
	if ([parent isKindOfClass:[LDrawMPDModel class]]) return parent;
	return nil;
}


//---------- selectionIsModelForDuplicate: ---------------------------[static]--
//
// Purpose:		Makes a copy of the selected object. Duplicate of the current
//				selection should insert as a new MPD model when the first
//				selected object is a model.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionIsModelForDuplicate:(NSArray *)selection
{
	return [[selection firstObject] isKindOfClass:[LDrawMPDModel class]];
}


//---------- insertIndexAfterModel:inFile: ---------------------------[static]--
//
// Purpose:		Returns index of the next model that follows another one, which
//				encloses the current selection, or NSNotFound if there is no
//				selection.
//
//------------------------------------------------------------------------------
+ (NSInteger)insertIndexAfterModel:(LDrawModel *)model inFile:(LDrawFile *)file
{
	if (model == nil || file == nil)
	{
		return NSNotFound;
	}

	NSInteger indexOfObject = [file indexOfDirective:model];
	if (indexOfObject != NSNotFound)
	{
		indexOfObject++;
	}
	return indexOfObject;
}


//---------- nextToSimilarPlacementForDirective:inSelection:parent:index:
//																     [static]--
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				For part duplication: if true, paste duplicated parts next to
//				originals. YES if a matching selected part was found.
//
//------------------------------------------------------------------------------
+ (BOOL)nextToSimilarPlacementForDirective:(LDrawDirective *)directive
							   inSelection:(NSArray *)selection
									parent:(LDrawContainer * _Nullable * _Nullable)outParent
									 index:(NSInteger * _Nullable)outIndex
{
	LDrawDirective *similar = [self similarDirective:directive amongObjects:selection];
	if (similar == nil)
	{
		return NO;
	}

	LDrawContainer *parent = (LDrawContainer *)[similar enclosingDirective];
	if (parent == nil)
	{
		return NO;
	}

	if (outParent != NULL)
	{
		*outParent = parent;
	}
	if (outIndex != NULL)
	{
		*outIndex = [parent indexOfDirective:similar] + 1;
	}
	return YES;
}


//---------- resolveStepPasteParent:index:forDirective:... -------------[static]--
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				For part duplication: if true, paste duplicated parts next to
//				originals.
//
//------------------------------------------------------------------------------
+ (void)resolveStepPasteParent:(LDrawContainer * __autoreleasing *)outParent
						 index:(NSInteger *)outIndex
				  forDirective:(LDrawDirective *)directive
						parent:(id)parent
				 insertAtIndex:(NSInteger)insertAtIndex
				 nextToSimilar:(BOOL)nextToSimilar
				   inSelection:(NSArray *)selection
			fallbackParentStep:(LDrawContainer *)fallbackParentStep
{
	LDrawContainer *parentStep = nil;
	NSInteger       realIndex  = insertAtIndex;

	if (nextToSimilar)
	{
		if ([self nextToSimilarPlacementForDirective:directive
										inSelection:selection
											 parent:&parentStep
											  index:&realIndex] == NO)
		{
			parentStep = fallbackParentStep;
			realIndex  = NSNotFound;
		}
	}
	else
	{
		parentStep = [self pasteStepParentFromParent:parent];
	}

	if (outParent != NULL)
		*outParent = parentStep;
	if (outIndex != NULL)
		*outIndex = realIndex;
}


//---------- modelPasteStartIndexForInsertAtIndex:defaultIndex: ------[static]--
//
// Purpose:		Model paste uses the explicit drop index, or the next model slot.
//
//------------------------------------------------------------------------------
+ (NSInteger)modelPasteStartIndexForInsertAtIndex:(NSInteger)insertAtIndex
									 defaultIndex:(NSInteger)defaultIndex
{
	if (insertAtIndex != NSNotFound)
		return insertAtIndex;
	return defaultIndex;
}


//---------- nextSequentialModelInsertIndexAfter: --------------------[static]--
//
// Purpose:		Each pasted model after the first goes at the next index.
//
//------------------------------------------------------------------------------
+ (NSInteger)nextSequentialModelInsertIndexAfter:(NSInteger)index
{
	if (index != NSNotFound)
		return index + 1;
	return NSNotFound;
}


//---------- duplicatePasteIndexForSelection:defaultNextModelIndex: --[static]--
//
// Purpose:		Makes a copy of the selected object. Duplicate of the current
//				selection should insert as a new MPD model when the first
//				selected object is a model.
//
//------------------------------------------------------------------------------
+ (NSInteger)duplicatePasteIndexForSelection:(NSArray *)selection
					   defaultNextModelIndex:(NSInteger)defaultNextModelIndex
{
	if ([self selectionIsModelForDuplicate:selection])
		return defaultNextModelIndex;
	return NSNotFound;
}


//---------- selectionCanSetGroup: -----------------------------------[static]--
//
// Purpose:		Set/edit MLCAD group. Menu enable: every selected object can
//				take a group.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanSetGroup:(NSArray *)selection
{
	if ([selection count] == 0)
	{
		return NO;
	}
	for (id directive in selection)
	{
		if (LDrawDirectiveSupportsGroup(directive) == NO)
		{
			return NO;
		}
	}
	return YES;
}


//---------- groupNamesInSelection: ----------------------------------[static]--
//
// Purpose:		Set/edit MLCAD group. Unique current group names (nil stored as
//				@""). Returns nil if any selected object cannot take a group.
//
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *)groupNamesInSelection:(NSArray *)selection
{
	NSMutableSet<NSString *> *groups = [NSMutableSet set];
	for (id object in selection)
	{
		if (LDrawDirectiveSupportsGroup(object) == NO)
		{
			return nil;
		}
		NSString *group = [object group];
		[groups addObject:(group != nil) ? group : @""];
	}
	return groups;
}


//---------- nonEmptyGroupNamesFromSet: ------------------------------[static]--
//
// Purpose:		Non-empty names for a combo list. Order is that of the set.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)nonEmptyGroupNamesFromSet:(NSSet<NSString *> *)groups
{
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	for (NSString *name in groups)
	{
		if ([name length] > 0)
		{
			[names addObject:name];
		}
	}
	return names;
}


//---------- normalizedGroupName: ------------------------------------[static]--
//
// Purpose:		Trim whitespace; nil stays nil.
//
//------------------------------------------------------------------------------
+ (NSString *)normalizedGroupName:(NSString *)name
{
	if (name == nil)
	{
		return nil;
	}
	return [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


//---------- groupChangesInSelection:toGroupName: --------------------[static]--
//
// Purpose:		Set/edit MLCAD group. LDrawObjectWithValue pairs for directives
//				whose group differs from newName.
//
//------------------------------------------------------------------------------
+ (NSArray *)groupChangesInSelection:(NSArray *)selection
						 toGroupName:(NSString *)newName
{
	NSMutableArray *changes = [NSMutableArray array];
	for (id object in selection)
	{
		if (LDrawDirectiveSupportsGroup(object) == NO)
		{
			continue;
		}
		if ([newName isEqualToString:[object group]] == NO)
		{
			[changes addObject:[[LDrawObjectWithValue alloc] initWithObject:object value:newName]];
		}
	}
	return changes;
}


//---------- invertedGroupChanges: -----------------------------------[static]--
//
// Purpose:		Current groups of the same objects, for undo. Must run before
//				applying.
//
//------------------------------------------------------------------------------
+ (NSArray *)invertedGroupChanges:(NSArray *)directivesAndGroups
{
	NSMutableArray *inverted = [NSMutableArray array];
	for (LDrawObjectWithValue *pair in directivesAndGroups)
	{
		id        directive = pair.object;
		NSString *oldGroup  = [directive valueForKey:@"group"];
		[inverted addObject:[[LDrawObjectWithValue alloc] initWithObject:directive
																   value:(oldGroup != nil) ? oldGroup : @""]];
	}
	return inverted;
}


//---------- applyGroupChanges: --------------------------------------[static]--
//
// Purpose:		Set/edit MLCAD group. Sets each pair's group name. The host
//				still registers undo.
//
//------------------------------------------------------------------------------
+ (void)applyGroupChanges:(NSArray *)directivesAndGroups
{
	for (LDrawObjectWithValue *pair in directivesAndGroups)
	{
		[pair.object setValue:pair.value forKey:@"group"];
	}
}


//---------- mlcadGroupDialogMessageKey ------------------------------[static]--
//
// Purpose:		MLCAD group dialog localization keys. The host still localizes
//				and shows the alert.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogMessageKey
{
	return @"MLCADGroupDialogMessage";
}


//---------- mlcadGroupDialogInformativeKey -------------------------[static]--
//
// Purpose:		Localization key for the MLCAD group-name dialog informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogInformativeKey
{
	return @"MLCADGroupDialogInformative";
}


//---------- mlcadGroupDialogSetButtonKey ---------------------------[static]--
//
// Purpose:		Localization key for the MLCAD group-name dialog Set button.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogSetButtonKey
{
	return @"SetButtonName";
}


//---------- mlcadGroupDialogCancelButtonKey ------------------------[static]--
//
// Purpose:		Localization key for the MLCAD group-name dialog Cancel button.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogCancelButtonKey
{
	return @"CancelButtonName";
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


//---------- shouldDisallowDraggingItems: ----------------------------[static]--
//
// Purpose:		Disallow dragging if it is the only step in the model.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldDisallowDraggingItems:(NSArray *)items
{
	if ([items count] != 1)
	{
		return NO;
	}

	id firstItem = [items objectAtIndex:0];
	if ([firstItem isKindOfClass:[LDrawStep class]] == NO)
	{
		return NO;
	}
	return [[[firstItem enclosingModel] steps] count] == 1;
}


//---------- outlineDropParent:file: ---------------------------------[static]--
//
// Purpose:		Fix our logic for handling drags to the root of the outline.
//				Identify the root object if needed: nil means the file.
//
//------------------------------------------------------------------------------
+ (nullable id)outlineDropParent:(nullable id)proposedParent file:(nullable LDrawFile *)file
{
	if (proposedParent == nil)
	{
		return file;
	}
	return proposedParent;
}


//---------- outlineDropKindForDropOnItem:… --------------------------[static]--
//
// Purpose:		Whether a drop is allowed, and whether it is a move or a copy.
//
//				We must make sure we have the proper pasteboard type available.
//				Drop-on is not a "drop-on" operation we accept. If the drag is
//				acceptable, same-outline is a move; otherwise copy.
//
//				Eliminate illegal positions: dragging the only step back into
//				the source, and nesting that canNestDirective:inParent: rejects.
//
//------------------------------------------------------------------------------
+ (LDrawOutlineDropKind)outlineDropKindForDropOnItem:(BOOL)isDropOnItem
									hasDirectiveData:(BOOL)hasDirectiveData
									   isSameOutline:(BOOL)isSameOutline
								disallowDragToSource:(BOOL)disallowDragToSource
										   directive:(nullable id)directive
											  parent:(nullable id)parent
{
	// We must make sure we have the proper pasteboard type available.
	if (isDropOnItem || hasDirectiveData == NO)
	{
		return LDrawOutlineDropNone;
	}

	// This drag is acceptable. Now figure out the operation.
	LDrawOutlineDropKind kind = isSameOutline ? LDrawOutlineDropMove : LDrawOutlineDropCopy;

	//---------- Eliminate Illegal Positions -------------------------------
	if (isSameOutline && disallowDragToSource)
	{
		return LDrawOutlineDropNone;
	}
	if ([self canNestDirective:directive inParent:parent] == NO)
	{
		return LDrawOutlineDropNone;
	}
	return kind;
}


//---------- outlineDropKindForValidateDropWithProposedParent:... ----[static]--
//
// Purpose:		Returns the representation of item given for the given table
//				column.
//
//------------------------------------------------------------------------------
+ (LDrawOutlineDropKind)outlineDropKindForValidateDropWithProposedParent:(id)proposedParent
																	file:(LDrawFile *)file
															  dropOnItem:(BOOL)dropOnItem
														 pasteboardTypes:(NSArray *)types
													disallowDragToSource:(BOOL)disallow
															 sameOutline:(BOOL)sameOutline
												archivedDirectiveObjects:(NSArray *)archivedDirectiveObjects
{
	id		 parent			= [self outlineDropParent:proposedParent file:file];
	BOOL	 hasDirective	= [types containsObject:LDrawDirectivePboardType];
	id		 currentObject	= nil;

	if (dropOnItem == NO && hasDirective && [archivedDirectiveObjects count] > 0)
	{
		currentObject = [LDrawClipboard unarchivedDirectiveFromData:[archivedDirectiveObjects objectAtIndex:0]];
	}

	return [self outlineDropKindForDropOnItem:dropOnItem
							 hasDirectiveData:hasDirective
								isSameOutline:sameOutline
						 disallowDragToSource:disallow
									directive:currentObject
									   parent:parent];
}






//---------- outlineDropUndoActionKeyForSameOutline: -----------------[static]--
//
// Purpose:		UndoReorder for same-outline moves. Cross-outline paste leaves
//				the host's default undo name. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineDropUndoActionKeyForSameOutline:(BOOL)sameOutline
{
	if (sameOutline)
		return @"UndoReorder";
	return nil;
}


//---------- viewDropPasteUndoActionKey ------------------------------[static]--
//
// Purpose:		The user has deposited some drag-and-drop parts into an
//				LDrawView (paste path, not same-document move). The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)viewDropPasteUndoActionKey
{
	return @"UndoDrop";
}


//---------- duplicateUndoActionKey ----------------------------------[static]--
//
// Purpose:		Makes a copy of the selected object. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicateUndoActionKey
{
	return @"UndoDuplicate";
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


//---------- missingPiecesMessageKey ---------------------------------[static]--
//
// Purpose:		Missing / moved pieces and external-change alert keys. The host
//				still localizes and presents.
//
//------------------------------------------------------------------------------
+ (NSString *)missingPiecesMessageKey
{
	return @"MissingPiecesMessage";
}


//---------- missingPiecesInformativeKey ----------------------------[static]--
//
// Purpose:		Localization key for the missing-pieces alert informative text.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)missingPiecesInformativeKey
{
	return @"MissingPiecesInformative";
}


//---------- movedPiecesMessageKey ----------------------------------[static]--
//
// Purpose:		Localization key for the alert when parts were moved by another
//				app. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)movedPiecesMessageKey
{
	return @"MovedPiecesMessage";
}


//---------- movedPiecesInformativeKey ------------------------------[static]--
//
// Purpose:		Localization key for the informative text of that moved-parts
//				alert. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)movedPiecesInformativeKey
{
	return @"MovedPiecesInformative";
}


//---------- openingFileFormatKey -----------------------------------[static]--
//
// Purpose:		Localization key format for the opening-file progress message.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)openingFileFormatKey
{
	return @"OpeningFileX";
}


//---------- unsavedDocumentMessageFormatKey ------------------------[static]--
//
// Purpose:		Localization key format for the unsaved-document alert message.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentMessageFormatKey
{
	return @"UnsavedDocumentMessage";
}


//---------- unsavedDocumentInformativeKey --------------------------[static]--
//
// Purpose:		Localization key for the unsaved-document alert informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentInformativeKey
{
	return @"UnsavedDocumentInformative";
}


//---------- unsavedDocumentRevertButtonKey -------------------------[static]--
//
// Purpose:		Localization key for the Revert button on the unsaved-document
//				alert. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentRevertButtonKey
{
	return @"UnsavedDocumentRevertButton";
}


//---------- unsavedDocumentKeepButtonKey ---------------------------[static]--
//
// Purpose:		Localization key for the Keep button on the unsaved-document
//				alert. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentKeepButtonKey
{
	return @"UnsavedDocumentKeepButton";
}


//---------- okButtonNameKey ----------------------------------------[static]--
//
// Purpose:		Localization key for a generic OK button. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)okButtonNameKey
{
	return @"OKButtonName";
}


//---------- cancelButtonNameKey ------------------------------------[static]--
//
// Purpose:		Localization key for a generic Cancel button. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)cancelButtonNameKey
{
	return @"CancelButtonName";
}


//---------- shouldPromptUnsavedExternalChangeWhenDocumentEdited:… ---[static]--
//
// Purpose:		File on disk newer than last known date: prompt if edited.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldPromptUnsavedExternalChangeWhenDocumentEdited:(BOOL)edited
										 fileNewerThanKnown:(BOOL)fileNewer
{
	return fileNewer && edited;
}


//---------- shouldSilentRevertExternalChangeWhenDocumentEdited:… ----[static]--
//
// Purpose:		File on disk newer than last known date: silent revert if not
//				edited.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldSilentRevertExternalChangeWhenDocumentEdited:(BOOL)edited
										fileNewerThanKnown:(BOOL)fileNewer
{
	return fileNewer && edited == NO;
}


//---------- donatingParentsFromMovedDirectives: ---------------------[static]--
//
// Purpose:		Gather up (unique) parents that are donating child nodes to this
//				move. If the parents support tidying up they'll be given a
//				chance later. This is intended for e.g. containers such as
//				LDrawSynth that may need to take action if their subdirectives
//				change.
//
//				The file (outline root) is omitted; the outline represents that
//				parent as nil.
//
//------------------------------------------------------------------------------
+ (NSSet *)donatingParentsFromMovedDirectives:(NSArray *)directives
{
	NSMutableSet *parents = [NSMutableSet set];
	for (id item in directives)
	{
		id parent = [item enclosingDirective];
		if (parent != nil && [parent isKindOfClass:[LDrawFile class]] == NO)
		{
			[parents addObject:parent];
		}
	}
	return parents;
}


//---------- cleanupAfterOutlineDropDonors:destination: --------------[static]--
//
// Purpose:		Ask the source and target parents to cleanup if they can e.g.
//				used for updating container selection state.
//
//------------------------------------------------------------------------------
+ (void)cleanupAfterOutlineDropDonors:(NSSet *)donors destination:(nullable id)newParent
{
	for (id parent in donors)
	{
		if ([parent isKindOfClass:[LDrawContainer class]]
		   && [parent respondsToSelector:@selector(cleanupAfterDropIsDonor:)])
		{
			[parent performSelector:@selector(cleanupAfterDropIsDonor:)
						 withObject:[NSNumber numberWithBool:YES]];
		}
	}
	if ([newParent respondsToSelector:@selector(cleanupAfterDropIsDonor:)])
	{
		[newParent performSelector:@selector(cleanupAfterDropIsDonor:)
						withObject:[NSNumber numberWithBool:NO]];
	}
}


//---------- outlineChildCountOfItem:file: ---------------------------[static]--
//
// Purpose:		Returns the number of items which should be displayed under an
//				expanded item.
//
//------------------------------------------------------------------------------
+ (NSInteger)outlineChildCountOfItem:(nullable id)item file:(nullable LDrawFile *)file
{
	NSInteger numberOfChildren = 0;

	// root object; return the number of submodels
	if (item == nil)
		numberOfChildren = [[file submodels] count];

	// a step or model (or something); return the nth directives command
	else if ([item isKindOfClass:[LDrawContainer class]])
		numberOfChildren = [[item subdirectives] count];

	return numberOfChildren;
}


//---------- outlineItemIsExpandable: --------------------------------[static]--
//
// Purpose:		Returns the number of items which should be displayed under an
//				expanded item.
//
//------------------------------------------------------------------------------
+ (BOOL)outlineItemIsExpandable:(nullable id)item
{
	// You can expand models and steps.
	if ([item isKindOfClass:[LDrawContainer class]] )
		return YES;
	else
		return NO;
}


//---------- containerEnclosingOutlineItem: --------------------------[static]--
//
// Purpose:		The container that encloses (or is) the current selection, or
//				nil if there is no container in the selection chain.
//
// Notes:		If we are doing a copy-drag operation, the host still remembers
//				the original selection and passes that item. (We can't use the
//				current selection during copy drag because we clear it when the
//				drag begins.)
//
//------------------------------------------------------------------------------
+ (LDrawContainer *)containerEnclosingOutlineItem:(id)item
{
	if ([item isKindOfClass:[LDrawContainer class]]) return item;
	return [item enclosingDirective];
}


//---------- outlineChild:ofItem:file: -------------------------------[static]--
//
// Purpose:		Returns the child of item at the position index.
//
//------------------------------------------------------------------------------
+ (id)outlineChild:(NSInteger)index ofItem:(nullable id)item file:(nullable LDrawFile *)file
{
	NSArray *children = nil;

	// children of the root object; the nth of models.
	if (item == nil)
		children = [file submodels];

	// a container; return the nth subdirective.
	else if ([item isKindOfClass:[LDrawContainer class]])
		children = [item subdirectives];

	return [children objectAtIndex:index];
}


//---------- outlineSyntaxColorKeyForDirective: ----------------------[static]--
//
// Purpose:		Applies syntax coloring to the specified directive, which will
//				be displayed with the text representation. This is the
//				preference key for the object's syntax color; the host still
//				looks up NSColor.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineSyntaxColorKeyForDirective:(id)item
{
	NSString *colorKey = nil; //preference key for object's syntax color.

	// Find the specified syntax color for the directive.
	if ([item isKindOfClass:[LDrawModel class]])
		colorKey = SYNTAX_COLOR_MODELS_KEY;

	else if ([item isKindOfClass:[LDrawStep class]])
		colorKey = SYNTAX_COLOR_STEPS_KEY;

	else if ([item isKindOfClass:[LDrawComment class]])
		colorKey = SYNTAX_COLOR_COMMENTS_KEY;

	else if ([item isKindOfClass:[LDrawPart class]])
		colorKey = SYNTAX_COLOR_PARTS_KEY;

	else if ([item isKindOfClass:[LDrawLSynth class]] ||
			 [item isKindOfClass:[LDrawLSynthDirective class]])
		colorKey = SYNTAX_COLOR_PARTS_KEY;

	else if ([item isKindOfClass:[LDrawLine				class]] ||
			[item isKindOfClass:[LDrawTriangle			class]] ||
			[item isKindOfClass:[LDrawQuadrilateral		class]] ||
			[item isKindOfClass:[LDrawConditionalLine	class]]    )
		colorKey = SYNTAX_COLOR_PRIMITIVES_KEY;

	else if ([item isKindOfClass:[LDrawColor class]])
		colorKey = SYNTAX_COLOR_COLORS_KEY;

	else if ([item isKindOfClass:[LPubRemoveGroup class]])
		colorKey = SYNTAX_COLOR_REMOVE_GROUP_KEY;

	else
		colorKey = SYNTAX_COLOR_UNKNOWN_KEY;

	return colorKey;
}


//---------- outlineSyntaxFallbackColorForKey: -----------------------[static]--
//
// Purpose:		Default syntax color when user-defaults unarchiving fails for
//				the given preference key. The host still instantiates NSColor.
//
// Notes:		Fallback to default color if unarchiving failed.
//				Can be removed in the future.
//
//------------------------------------------------------------------------------
+ (LDrawOutlineSyntaxFallbackColor)outlineSyntaxFallbackColorForKey:(NSString *)colorKey
{
	if ([colorKey isEqualToString:SYNTAX_COLOR_COMMENTS_KEY])
		return LDrawOutlineSyntaxFallbackSystemGreen;
	if ([colorKey isEqualToString:SYNTAX_COLOR_PARTS_KEY])
		return LDrawOutlineSyntaxFallbackSystemBlue;
	if ([colorKey isEqualToString:SYNTAX_COLOR_PRIMITIVES_KEY])
		return LDrawOutlineSyntaxFallbackSystemOrange;
	if ([colorKey isEqualToString:SYNTAX_COLOR_MODELS_KEY])
		return LDrawOutlineSyntaxFallbackSystemPurple;
	if ([colorKey isEqualToString:SYNTAX_COLOR_STEPS_KEY])
		return LDrawOutlineSyntaxFallbackSystemYellow;
	if ([colorKey isEqualToString:SYNTAX_COLOR_COLORS_KEY])
		return LDrawOutlineSyntaxFallbackSystemPink;
	if ([colorKey isEqualToString:SYNTAX_COLOR_REMOVE_GROUP_KEY])
		return LDrawOutlineSyntaxFallbackSystemRed;
	return LDrawOutlineSyntaxFallbackLabel;
}



//---------- outlineObliquenessForDirective: -------------------------[static]--
//
// Purpose:		Hidden directives are shown italicized in the outline.
//
//------------------------------------------------------------------------------
+ (double)outlineObliquenessForDirective:(id)item
{
	if ([item respondsToSelector:@selector(isHidden)])
		if ([(id)item isHidden])
			return 0.5;
	return 0.0;
}


//---------- outlineIconNameForItem: --------------------------------[static]--
//
// Purpose:		Return the outline-view icon name for a file-contents item.
//				The host still instantiates NSImage.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineIconNameForItem:(id)item
{
	if ([item isKindOfClass:[LDrawDirective class]] == NO) return nil;
	NSString *imageName = [item iconName];
	if (imageName == nil || [imageName isEqualToString:@""]) return nil;
	return imageName;
}


//---------- outlineDescriptionForItem: -----------------------------[static]--
//
// Purpose:		Return the outline-view display string for a file-contents item.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineDescriptionForItem:(id)item
{
	// Start off with a simple error message. Hopefully we won't see it.
	if ([item isKindOfClass:[LDrawDirective class]] == NO)
	{
		return @"<Something went wrong here.>";
	}

	// an LDraw directive; thank goodness! It knows how to describe itself.
	// The description will form the basis of the attributed text for the cell.
	return [item browsingDescription];
}


//---------- viewDropIsSameDocumentMoveFromSource:toDocument:selectionCount:
//																     [static]--
//
// Purpose:		The user has deposited some drag-anddrop parts into an
//				LDrawView. Now they need to be imported into the model.
//
// Notes:		Just like in -duplicate: and
//				-outlineView:acceptDrop:item:childIndex:, we appropriate the
//				pasting architecture to simplify importing the parts.
//
//				Being dragged within the same document. We must simply apply the
//				transforms from the dragged parts to the original parts, which
//				have been hidden during the drag.
//
//				Exception: If we have no current selection, it means this was a
//				copy drag. Just paste instead of updating. The host still reads
//				the AppKit dragging source and pastes or moves (undo).
//
//------------------------------------------------------------------------------
+ (BOOL)viewDropIsSameDocumentMoveFromSource:(nullable id)sourceFile
								  toDocument:(nullable id)documentFile
							  selectionCount:(NSInteger)selectionCount
{
	return sourceFile != nil
		&& sourceFile == documentFile
		&& selectionCount > 0;
}


//---------- viewDropMovesForSelection:droppedCopies: ----------------[static]--
//
// Purpose:		Pair selected drawables with dropped copies in order, then
//				compute the displacement from each original to its drag copy.
//				The host still applies the move (undo) and unhides the original.
//
//------------------------------------------------------------------------------
+ (NSArray *)viewDropMovesForSelection:(NSArray *)selection
						 droppedCopies:(NSArray *)droppedCopies
{
	NSMutableArray *moves              = [NSMutableArray array];
	NSInteger       dropDirectiveIndex = 0;
	NSInteger       droppedCount       = [droppedCopies count];

	for (id currentDirective in selection)
	{
		if (dropDirectiveIndex >= droppedCount)
		{
			break;
		}
		if ([currentDirective isKindOfClass:[LDrawDrawableElement class]])
		{
			id      dragPart         = [droppedCopies objectAtIndex:dropDirectiveIndex];
			Point3  originalPosition = [(LDrawDrawableElement *)currentDirective position];
			Point3  dragPosition     = [(LDrawDrawableElement *)dragPart position];
			Vector3 displacement     = V3Sub(dragPosition, originalPosition);

			[moves addObject:[[LDrawViewDropMove alloc] initWithDirective:currentDirective
															 displacement:displacement]];
			dropDirectiveIndex++;
		}
	}
	return moves;
}


//---------- viewDragOblivionDirectivesFromSelection: ----------------[static]--
//
// Purpose:		Now that we know they are really truly gone, we need to delete
//				their hidden ghosts.
//
//------------------------------------------------------------------------------
+ (NSArray *)viewDragOblivionDirectivesFromSelection:(NSArray *)selection
{
	return [self drawableDirectivesInSelection:selection];
}


//---------- unhideDirectivesInViewDropMoves: ------------------------[static]--
//
// Purpose:		The host still moveDirective: (undo) after a same-document drop.
//
//------------------------------------------------------------------------------
+ (void)unhideDirectivesInViewDropMoves:(NSArray *)moves
{
	for (LDrawViewDropMove *move in moves)
		[move.directive setHidden:NO];
}


//---------- restoreVisibilityBeforeDeletingViewDragOblivionDirectives:
//                                                          [static]--
//
// Purpose:		Even though the directive has been drag-deleted, we still need
//				to delete it in an undo-friendly way. That means we need to
//				restore its visibility, since we hid the part when dragging
//				began.
//
//------------------------------------------------------------------------------
+ (void)restoreVisibilityBeforeDeletingViewDragOblivionDirectives:(NSArray *)directives
{
	for (id directive in directives)
	{
		if ([directive respondsToSelector:@selector(setHidden:)])
			[(id)directive setHidden:NO];
	}
}


//---------- drawableDirectivesInSelection: --------------------------[static]--
//
// Purpose:		The parts which originated the most recent drag operation have
//				apparently been dragged clear out of the document. Maybe they
//				went into another document. Maybe they got dragged into empty
//				space. Whereever they went, they are gone now.
//
//				The trouble is that when we started dragging them, we just *hid*
//				them, in anticipation of their landing back within the document.
//				(It was too much trouble to delete them at the beginning,
//				because then we might have to reconstruct where they were in the
//				model hierarchy if they did stay in the same document.) Now that
//				we know they are really truly gone, we need to delete their
//				hidden ghosts.
//
//				The host still restores visibility and deletes in an
//				undo-friendly way.
//
//------------------------------------------------------------------------------
+ (NSArray *)drawableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *drawables = [NSMutableArray array];

	for (id currentDirective in selection)
	{
		if ([currentDirective isKindOfClass:[LDrawDrawableElement class]])
		{
			[drawables addObject:currentDirective];
		}
	}
	return drawables;
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


//---------- stepComponentFromOutlineItem: ---------------------------[static]--
//
// Purpose:		The drawable LDraw element that is currently selected (Part,
//				Quadrilateral, Triangle, etc.). Nil if the selection is not one
//				of these atomic LDraw commands.
//
// Notes:		If a model is selected, a step can't be. File, model, and step
//				are not step components; whatever else it is, it's what we are
//				looking for.
//
//------------------------------------------------------------------------------
+ (id)stepComponentFromOutlineItem:(id)item
{
	if (item == nil) return nil;
	if ([item isKindOfClass:[LDrawFile class]]) return nil;
	if ([item isKindOfClass:[LDrawModel class]]) return nil;
	if ([item isKindOfClass:[LDrawStep class]]) return nil;
	return item;
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



@implementation LDrawViewDropMove

//========== initWithDirective:displacement: ==================================
//
// Purpose:		Record one drawable and the displacement applied during a 3D-
//				view drop so the host can undo the move.
//
//==============================================================================
- (instancetype)initWithDirective:(LDrawDrawableElement *)directive
					 displacement:(Vector3)displacement
{
	self = [super init];
	if (self)
	{
		_directive    = directive;
		_displacement = displacement;
	}
	return self;
}

@end



@implementation LDrawCompliantNameChange

//========== initWithModel:compliantName:renameInPlace: =======================
//
// Purpose:		Record a pending MPD model rename to an LDraw-compliant name.
//
//==============================================================================
- (instancetype)initWithModel:(LDrawMPDModel *)model
				compliantName:(NSString *)compliantName
				renameInPlace:(BOOL)renameInPlace
{
	self = [super init];
	if (self)
	{
		_model          = model;
		_compliantName  = [compliantName copy];
		_renameInPlace  = renameInPlace;
	}
	return self;
}

@end


@implementation LDrawOriginPartUpdate
@end


@implementation LDrawSplitExpansion
@end



@implementation LDrawStepExportFile

//========== initWithFolderName:fileName:ldrString: ===========================
//
// Purpose:		Record one exported-steps file: destination folder, file name,
//				and LDR contents.
//
//==============================================================================
- (instancetype)initWithFolderName:(NSString *)folderName
						  fileName:(NSString *)fileName
						 ldrString:(NSString *)ldrString
{
	self = [super init];
	if (self)
	{
		_folderName = [folderName copy];
		_fileName   = [fileName copy];
		_ldrString  = [ldrString copy];
	}
	return self;
}

@end
