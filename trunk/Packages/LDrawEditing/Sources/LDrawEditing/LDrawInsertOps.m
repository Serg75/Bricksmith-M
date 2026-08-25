//==============================================================================
//
//  File:       LDrawInsertOps.m
//  Package:    LDrawEditing
//
//  Purpose:    Default geometry for new primitives, named-part placement, and
//              submodel-reference cycle checks.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawEditing/LDrawInsertOps.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawComment.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawMetaCommand.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/LPubRemoveGroup.h>

/// Default extent of a newly inserted primitive, in LDraw units.
static const float kDefaultPrimitiveExtent = 80.0f;

@implementation LDrawInsertOps

//---------- anchorPositionForPart: ----------------------------------[static]--
//
// Purpose:		Position of the last-selected part, or the origin if there is
//				no part. New primitives are placed relative to this point.
//
//------------------------------------------------------------------------------
+ (Point3)anchorPositionForPart:(nullable LDrawPart *)part
{
	if (part == nil)
	{
		return ZeroPoint3;
	}
	return [part position];
}


//---------- lineAtAnchor:color: -------------------------------------[static]--
//
// Purpose:		Adds a new line primitive to the currently-displayed model.
//				The host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawLine *)lineAtAnchor:(Point3)anchor color:(LDrawColor *)color
{
	LDrawLine *newLine = [[LDrawLine alloc] init];
	[newLine setVertex1:anchor];
	[newLine setVertex2:V3Make(anchor.x + kDefaultPrimitiveExtent,
							   anchor.y - kDefaultPrimitiveExtent,
							   anchor.z)];
	[newLine setLDrawColor:color];
	return newLine;
}


//---------- triangleAtAnchor:color: ---------------------------------[static]--
//
// Purpose:		Adds a new triangle primitive to the currently-displayed model.
//				The host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawTriangle *)triangleAtAnchor:(Point3)anchor color:(LDrawColor *)color
{
	LDrawTriangle *newTriangle = [[LDrawTriangle alloc] init];
	[newTriangle setVertex1:anchor];
	[newTriangle setVertex2:V3Make(anchor.x + kDefaultPrimitiveExtent,
								   anchor.y - 0,
								   anchor.z)];
	[newTriangle setVertex3:V3Make(anchor.x + kDefaultPrimitiveExtent / 2.0f,
								   anchor.y - kDefaultPrimitiveExtent / 2.0f,
								   anchor.z)];
	[newTriangle setLDrawColor:color];
	return newTriangle;
}


//---------- quadrilateralAtAnchor:color: ----------------------------[static]--
//
// Purpose:		Adds a new quadrilateral primitive to the currently-displayed
//				model. The host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawQuadrilateral *)quadrilateralAtAnchor:(Point3)anchor color:(LDrawColor *)color
{
	LDrawQuadrilateral *newQuadrilateral = [[LDrawQuadrilateral alloc] init];
	[newQuadrilateral setVertex1:anchor];
	[newQuadrilateral setVertex2:V3Make(anchor.x + kDefaultPrimitiveExtent,
										anchor.y - 0,
										anchor.z)];
	[newQuadrilateral setVertex3:V3Make(anchor.x + kDefaultPrimitiveExtent,
										anchor.y - kDefaultPrimitiveExtent,
										anchor.z)];
	[newQuadrilateral setVertex4:V3Make(anchor.x + 0,
										anchor.y - kDefaultPrimitiveExtent,
										anchor.z)];
	[newQuadrilateral setLDrawColor:color];
	return newQuadrilateral;
}


//---------- conditionalLineAtAnchor:color: --------------------------[static]--
//
// Purpose:		Adds a new conditional-line primitive to the currently-displayed
//				model. The host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawConditionalLine *)conditionalLineAtAnchor:(Point3)anchor color:(LDrawColor *)color
{
	LDrawConditionalLine *newConditional = [[LDrawConditionalLine alloc] init];
	[newConditional setVertex1:anchor];
	[newConditional setVertex2:V3Make(anchor.x + kDefaultPrimitiveExtent,
									  anchor.y - kDefaultPrimitiveExtent,
									  anchor.z)];
	[newConditional setLDrawColor:color];
	return newConditional;
}


//---------- indexAfterDirective:inParent: ---------------------------[static]--
//
// Purpose:		Adds a new step wherever it belongs — after the selected step,
//				or at the end of the list (NSNotFound).
//
//------------------------------------------------------------------------------
+ (NSInteger)indexAfterDirective:(nullable LDrawDirective *)directive
						inParent:(nullable LDrawContainer *)parent
{
	if (parent == nil || directive == nil)
	{
		return NSNotFound;
	}

	NSInteger selectedIdx = [parent indexOfDirective:directive];
	if (selectedIdx == NSNotFound)
	{
		return NSNotFound;
	}

	NSInteger nextIdx = selectedIdx + 1;
	if (nextIdx >= (NSInteger)[[parent subdirectives] count])
	{
		return NSNotFound;
	}
	return nextIdx;
}


//---------- partNamed:color:copyingTransformFrom: -------------------[static]--
//
// Purpose:		Adds a part with the given name to the current step in the
//				currently-displayed model. Copies the transformation from the
//				previous part when there is one. The host still inserts and
//				names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawPart *)partNamed:(nullable NSString *)partName
				   color:(LDrawColor *)color
	copyingTransformFrom:(nullable LDrawPart *)anchor
{
	LDrawPart *newPart = [[LDrawPart alloc] init];

	// Set up the part attributes
	[newPart setLDrawColor:color];
	if (partName != nil)
	{
		[newPart setDisplayName:partName];
	}
	if (anchor != nil)
	{
		// Collect the transformation from the previous part and apply it to
		// the new one.
		[newPart setTransformComponents:[anchor transformComponents]];
	}
	return newPart;
}


//---------- destinationModelPreferring:fallingBackTo: ---------------[static]--
//
// Purpose:		Add a reference in the current model to the MPD submodel
//				selected. Destination is the selected model, or the active model
//				when nothing is selected.
//
//------------------------------------------------------------------------------
+ (nullable LDrawMPDModel *)destinationModelPreferring:(nullable LDrawMPDModel *)selected
										 fallingBackTo:(nullable LDrawMPDModel *)active
{
	if (selected != nil)
	{
		return selected;
	}
	return active;
}


//---------- insertingSubmodelNamed:inFile:wouldCycleWithDestination: [static]--
//
// Purpose:		True when inserting the named submodel into the destination
//				would be a circular reference (the referenced model already
//				contains a reference to the destination).
//
//------------------------------------------------------------------------------
+ (BOOL)insertingSubmodelNamed:(nullable NSString *)partName
						inFile:(nullable LDrawFile *)file
	 wouldCycleWithDestination:(nullable LDrawMPDModel *)destination
{
	LDrawMPDModel *referenced = [file modelWithName:partName];
	return [referenced containsReferenceTo:[destination modelName]];
}


//---------- canInsertSubmodel:intoActiveModel: ----------------------[static]--
//
// Purpose:		We can't insert a reference to the active model into itself.
//				That would be an inifinite loop.
//
//------------------------------------------------------------------------------
+ (BOOL)canInsertSubmodel:(id)representedModel
		  intoActiveModel:(id)activeModel
{
	return (representedModel != activeModel);
}


//---------- canInsertLSynthConstraintForPart: -----------------------[static]--
//
// Purpose:		We can only insert a constraint into an LDrawLSynth part.
//				Ensure it (or a constraint) is selected.
//
//------------------------------------------------------------------------------
+ (BOOL)canInsertLSynthConstraintForPart:(id)selectedPart
{
	if ([selectedPart isKindOfClass:[LDrawLSynth class]])
	{
		return YES;
	}
	return [[selectedPart enclosingDirective] isKindOfClass:[LDrawLSynth class]];
}


//---------- preferredPartTransformFromPart: -------------------------[static]--
//
// Purpose:		Returns the part transform which would be nice applied to new
//				parts. This is used during Drag-and-Drop to unpack directives
//				and show them in the right place.
//
//------------------------------------------------------------------------------
+ (TransformComponents)preferredPartTransformFromPart:(nullable LDrawPart *)part
{
	TransformComponents components = IdentityComponents;

	// If we have a previously-selected part, honor it.
	if (part != nil)
		components = [part transformComponents];

	return components;
}


//---------- comment -------------------------------------------------[static]--
//
// Purpose:		Adds a new comment primitive to the currently-displayed model.
//				The host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawComment *)comment
{
	return [[LDrawComment alloc] init];
}


//---------- metaCommand ---------------------------------------------[static]--
//
// Purpose:		Adds a new raw command to the currently-displayed model. The
//				host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LDrawMetaCommand *)metaCommand
{
	return [[LDrawMetaCommand alloc] init];
}


//---------- lpubCommand ---------------------------------------------[static]--
//
// Purpose:		Adds a new generic LPub command to the currently-displayed
//				model. The host still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LPubCommand *)lpubCommand
{
	return [[LPubCommand alloc] init];
}


//---------- lpubRemoveGroup -----------------------------------------[static]--
//
// Purpose:		Adds a new LPub Remove Group command to the currently-displayed
//				model. The placeholder group name is "group name". The host
//				still inserts and names the undo action.
//
//------------------------------------------------------------------------------
+ (LPubRemoveGroup *)lpubRemoveGroup
{
	LPubRemoveGroup *newCommand = [[LPubRemoveGroup alloc] init];
	newCommand.groupName = @"group name";
	return newCommand;
}


//---------- undoActionKeyForInsertKind: -----------------------------[static]--
//
// Purpose:		Localization keys for undo after inserting an object. The host
//				still localizes (and formats UndoAddLSynth with the type name).
//
//------------------------------------------------------------------------------
+ (NSString *)undoActionKeyForInsertKind:(LDrawInsertUndoKind)kind
{
	switch (kind)
	{
		case LDrawInsertUndoLine:             return @"UndoAddLine";
		case LDrawInsertUndoTriangle:         return @"UndoAddTriangle";
		case LDrawInsertUndoQuadrilateral:    return @"UndoAddQuadrilateral";
		case LDrawInsertUndoConditionalLine:  return @"UndoAddConditionalLine";
		case LDrawInsertUndoComment:          return @"UndoAddComment";
		case LDrawInsertUndoMetaCommand:      return @"UndoAddMetaCommand";
		case LDrawInsertUndoLPubCommand:      return @"UndoAddLPubCommand";
		case LDrawInsertUndoRemoveGroup:      return @"UndoAddRemoveGroup";
		case LDrawInsertUndoRelatedPart:      return @"UndoAddRelatedPart";
		case LDrawInsertUndoLSynthConstraint: return @"UndoAddLSynthConstraint";
		case LDrawInsertUndoModel:            return @"UndoAddModel";
		case LDrawInsertUndoStep:             return @"UndoAddStep";
		case LDrawInsertUndoPart:             return @"UndoAddPart";
	}
	return @"UndoAddPart";
}


//---------- undoActionFormatKeyForAddingLSynth ----------------------[static]--
//
// Purpose:		Format key for UndoAddLSynth (takes the synth type name). The
//				host still localizes and formats.
//
//------------------------------------------------------------------------------
+ (NSString *)undoActionFormatKeyForAddingLSynth
{
	return @"UndoAddLSynth";
}


//---------- shouldInsertSubmodelNamed:whenCircularReference: --------[static]--
//
// Purpose:		YES when partName is non-nil and the insert would not create a
//				cycle.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldInsertSubmodelNamed:(NSString *)partName
			whenCircularReference:(BOOL)circularReference
{
	return partName != nil && circularReference == NO;
}


//---------- circularReferenceMessageKey -----------------------------[static]--
//
// Purpose:		Alert keys when a submodel insert would cycle. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)circularReferenceMessageKey
{
	return @"CircularReferenceMessage";
}


//---------- circularReferenceInformativeKey ------------------------[static]--
//
// Purpose:		Localization key for the circular-reference alert informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)circularReferenceInformativeKey
{
	return @"CircularReferenceInformative";
}

@end
