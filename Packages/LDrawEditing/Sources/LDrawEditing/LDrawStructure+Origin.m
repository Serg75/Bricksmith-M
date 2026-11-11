//==============================================================================
//
//  File:       LDrawStructure+Origin.m
//  Package:    LDrawEditing
//
//  Purpose:    Origin-change rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawTexture.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/LDrawPartSpecific.h>


//---------- roundedToStep() ---------------------------------------------------
//
// Purpose:		Rounds value to the nearest multiple of step. A step of zero or
//				less leaves the value as it is.
//
//------------------------------------------------------------------------------
static float roundedToStep(float value, float step)
{
	if (step <= 0)
	{
		return value;
	}
	return roundf(value / step) * step;
}


@implementation LDrawStructure (Origin)

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
		return (tag == LDrawChangeOriginMenuTag
			 || tag == LDrawChangeOriginByRotationMenuTag
			 || tag == LDrawAxesByPartRotationMenuTag);
	}

	if (tag == LDrawChangeOriginByRotationMenuTag)
	{
		*outKind = LDrawOriginChangeByRotationAxis;
		return YES;
	}
	if (tag == LDrawAxesByPartRotationMenuTag)
	{
		*outKind = LDrawOriginChangeByAxesAlignment;
		return YES;
	}
	if (tag == LDrawChangeOriginMenuTag)
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
		Vector3 rotCenter = [LDrawPartSpecific rotationCenterForPart:anchor.displayName];
		Vector3 rotPlane  = [LDrawPartSpecific rotationPlaneForPart:anchor.displayName];
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
//				LDrawPartSpecific rotation center.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanChangeOriginByRotation:(NSArray *)selection
{
	if ([self selectionCanChangeOrigin:selection] == NO)
	{
		return NO;
	}
	LDrawPart *part = [selection objectAtIndex:0];
	return [LDrawPartSpecific hasRotationCenter:[part displayName]];
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


//---------- centeringShiftForModel:gridSpacing: ---------------------[static]--
//
// Purpose:		Shift from the origin to the bottom center of the model's
//				bounds, rounded to the grid so parts on the grid stay on it.
//				Counts every step, not only the ones on display.
//
//------------------------------------------------------------------------------
+ (Vector3)centeringShiftForModel:(LDrawModel *)model gridSpacing:(float)gridSpacing
{
	if (model == nil)
	{
		return ZeroPoint3;
	}

	// Suppressed parts have no bounds, so settle suppression first.
	[model updateGroupSuppressionIfNeeded];
	Box3 bounds = [LDrawUtilities boundingBox3ForDirectives:[model steps]];
	if (V3EqualBoxes(bounds, InvalidBox))
	{
		return ZeroPoint3;
	}

	Point3 center       = V3CenterOfBox(bounds);
	float  verticalStep = [LDrawPart verticalGridSpacing:gridSpacing];

	// LDraw's Y axis points down, so the bottom is the largest Y.
	return V3Make(roundedToStep(center.x, gridSpacing),
				  roundedToStep(bounds.max.y, verticalStep),
				  roundedToStep(center.z, gridSpacing));
}


//---------- centeringMovesForModel:gridSpacing: ---------------------[static]--
//
// Purpose:		Moves the model's contents back by the centering shift. Each
//				part that uses the model moves by the same shift, turned the
//				way the part is turned, so the contents land where they were.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawDirectiveMove *> *)centeringMovesForModel:(LDrawModel *)model gridSpacing:(float)gridSpacing
{
	if ([self canCenterModel:model gridSpacing:gridSpacing] == NO)
	{
		return @[];
	}

	Vector3         shift = [self centeringShiftForModel:model gridSpacing:gridSpacing];
	Vector3         back  = V3Negate(shift);
	NSMutableArray *moves = [NSMutableArray array];

	for (LDrawStep *step in [model steps])
	{
		for (LDrawDirective *directive in [step subdirectives])
		{
			if ([directive conformsToProtocol:@protocol(LDrawMovableDirective)])
			{
				[moves addObject:[[LDrawDirectiveMove alloc] initWithDirective:(id)directive
																  displacement:back]];
			}
		}
	}

	for (LDrawModel *otherModel in [[model enclosingFile] submodels])
	{
		if (otherModel == model) continue;
		[otherModel applyToAllParts:^(LDrawPart *part){
			if ([part referencedMPDSubmodel] != model) return;
			Matrix4 rotation     = Matrix4ClearTranslation([part transformationMatrix]);
			Vector3 displacement = V3MulPointByProjMatrix(shift, rotation);
			[moves addObject:[[LDrawDirectiveMove alloc] initWithDirective:part
															  displacement:displacement]];
		}];
	}

	return moves;
}


//---------- canCenterModel:gridSpacing: -----------------------------[static]--
//
// Purpose:		Menu enable for Center Model.
//
//------------------------------------------------------------------------------
+ (BOOL)canCenterModel:(LDrawModel *)model gridSpacing:(float)gridSpacing
{
	if (model == nil)
	{
		return NO;
	}

	// A texture cannot move, so the model would come apart around it.
	for (LDrawStep *step in [model steps])
	{
		for (LDrawDirective *directive in [step subdirectives])
		{
			if ([directive isKindOfClass:[LDrawTexture class]]) return NO;
		}
	}

	Vector3 shift = [self centeringShiftForModel:model gridSpacing:gridSpacing];
	return V3EqualPoints(shift, ZeroPoint3) == NO;
}


//---------- centerModelUndoActionFormatKey --------------------------[static]--
//
// Purpose:		Localization key after centering a model. The format takes the
//				model's name.
//
//------------------------------------------------------------------------------
+ (NSString *)centerModelUndoActionFormatKey
{
	return @"UndoCenterModel";
}

@end
