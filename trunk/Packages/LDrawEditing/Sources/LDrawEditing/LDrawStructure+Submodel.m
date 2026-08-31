//==============================================================================
//
//  File:       LDrawStructure+Submodel.m
//  Package:    LDrawEditing
//
//  Purpose:    Move-to-parent and model-from-selection rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>


@interface LDrawStructure (SubmodelPrivate)
+ (NSArray<LDrawPart *> *)partsToRebaseInSelection:(NSArray *)selection;
@end


@implementation LDrawStructure (Submodel)

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


//---------- moveToParentModelUndoActionKey --------------------------[static]--
//
// Purpose:		Localization key after moving selection to parent models.
//
//------------------------------------------------------------------------------
+ (NSString *)moveToParentModelUndoActionKey
{
	return @"UndoMoveToParentModel";
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

@end
