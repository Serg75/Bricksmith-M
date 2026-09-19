//==============================================================================
//
//  File:       LDrawClipboard.m
//  Package:    LDrawEditing
//
//  Purpose:    NSKeyedArchiver packing for LDraw directives, plus the
//              "don't copy a child if its parent is selected" filter.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawEditing/LDrawClipboard.h>

#import <LDrawEditing/LDrawInsertion.h>
#import <LDrawEditing/LDrawViewportDrop.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/MatrixMath.h>


@interface LDrawClipboard ()
/// Directives whose ancestor is also in the list are omitted.
+ (NSArray *)rootDirectivesFromSelection:(NSArray *)directives;
+ (nullable NSData *)archivedDataForDirective:(id)directive;
+ (NSArray<NSData *> *)archivedDataForDirectives:(NSArray *)directives;
+ (NSString *)ldrStringForDirectives:(NSArray *)directives;
@end

@implementation LDrawClipboard

//---------- rootDirectivesFromSelection: ----------------------------[static]--
//
// Purpose:		Writes objects to the given pasteboard, ensuring that each
//				directive is written only once. Directives whose ancestor is
//				also in the list are omitted. The host still owns the
//				pasteboard.
//
//------------------------------------------------------------------------------
+ (NSArray *)rootDirectivesFromSelection:(NSArray *)directives
{
	NSMutableArray	*objectsToCopy		= [NSMutableArray array];
	NSMutableArray	*archivedContainers	= [NSMutableArray array];

	for (LDrawDirective *currentObject in directives)
	{
		if ([currentObject isAncestorInList:archivedContainers] == NO)
		{
			[objectsToCopy addObject:currentObject];
		}
		if ([currentObject isKindOfClass:[LDrawContainer class]])
		{
			[archivedContainers addObject:currentObject];
		}
	}
	return objectsToCopy;
}


//---------- archivedDataForDirective: -------------------------------[static]--
//
// Purpose:		Internally, archived LDrawDirectives are used to
//				copy/paste. NSKeyedArchiver packing of a single directive.
//
//------------------------------------------------------------------------------
+ (nullable NSData *)archivedDataForDirective:(id)directive
{
	return [NSKeyedArchiver archivedDataWithRootObject:directive requiringSecureCoding:NO error:nil];
}


//---------- archivedDataForDirectives: ------------------------------[static]--
//
// Purpose:		LDrawDirectivePboardType: array of LDrawDirectives converted
//				to NSData objects.
//
//------------------------------------------------------------------------------
+ (NSArray<NSData *> *)archivedDataForDirectives:(NSArray *)directives
{
	NSMutableArray *archivedObjects = [NSMutableArray arrayWithCapacity:[directives count]];
	for (id currentObject in directives)
	{
		NSData *data = [self archivedDataForDirective:currentObject];
		if (data != nil)
		{
			[archivedObjects addObject:data];
		}
	}
	return archivedObjects;
}


//---------- ldrStringForDirectives: ---------------------------------[static]--
//
// Purpose:		NSStringPboardType: array of strings representing the objects
//				in the format written to an LDraw file. For other applications,
//				we provide the LDraw file contents. Note that these strings
//				cannot be pasted back into the program. (Not using CRLF here
//				because any Mac program that knows enough to do DOS
//				line-endings will automatically add them to pasted content.)
//
//------------------------------------------------------------------------------
+ (NSString *)ldrStringForDirectives:(NSArray *)directives
{
	NSMutableString *stringedObjects = [NSMutableString stringWithCapacity:256];
	for (id currentObject in directives)
	{
		NSString *string = [currentObject write];
		[stringedObjects appendFormat:@"%@\n", string];
	}
	return stringedObjects;
}


//---------- unarchivedDirectiveFromData: ----------------------------[static]--
//
// Purpose:		Restore a directive from NSKeyedArchiver data written by
//				archivedDataForDirective:.
//
//------------------------------------------------------------------------------
+ (nullable id)unarchivedDirectiveFromData:(NSData *)data
{
	if (data == nil)
	{
		return nil;
	}
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
	[unarchiver setRequiresSecureCoding:NO];
	id currentObject = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
	[unarchiver finishDecoding];
	return currentObject;
}


//---------- unarchivedDirectivesFromDataArray: ----------------------[static]--
//
// Purpose:		Restore directives from an array of archived NSData objects.
//
//------------------------------------------------------------------------------
+ (NSArray *)unarchivedDirectivesFromDataArray:(NSArray *)archived
{
	NSMutableArray *directives = [NSMutableArray arrayWithCapacity:[archived count]];
	for (NSData *data in archived)
	{
		id currentObject = [self unarchivedDirectiveFromData:data];
		if (currentObject != nil)
		{
			[directives addObject:currentObject];
		}
	}
	return directives;
}


//---------- archivedDraggingDataFromSelection:drawableOriginals: ----[static]--
//
// Purpose:		Begin a drag-and-drop part insertion initiated in the directive
//				view.
//
// Notes:		The parts you see being dragged around are always copies of the
//				originals. When we aren't actually doing a copy drag, we just
//				hide the originals. At the end of the drag, we update the
//				originals with the new dragged positions, unhide them, and
//				discard the stuff on the pasteboard. This frees us from having
//				to remember what step each dragged element belonged to.
//
//				Only drawable (movable) directives are archived.
//				outDrawables is those originals so the host can hide them on a
//				move drag. The host still writes the pasteboard and deselects
//				on a copy drag.
//
//------------------------------------------------------------------------------
+ (NSArray<NSData *> *)archivedDraggingDataFromSelection:(NSArray *)selection
									   drawableOriginals:(NSArray * _Nullable * _Nullable)outDrawables
{
	NSArray *drawables = [LDrawViewportDrop drawableDirectivesInSelection:selection];
	if (outDrawables != NULL)
	{
		*outDrawables = drawables;
	}
	return [self archivedDataForDirectives:drawables];
}



//---------- archivedDraggingDataForPartNamed:color: -----------------[static]--
//
// Purpose:		Writes the current part-browser selection onto the pasteboard.
//
//				We got a part; let's add it. Set up the part attributes (name
//				and color), then archive. The host still writes
//				LDrawDraggingPboardType and marks the drag uninitialized so the
//				drop view can apply a preferred transform.
//
//------------------------------------------------------------------------------
+ (nullable NSArray<NSData *> *)archivedDraggingDataForPartNamed:(nullable NSString *)partName
														   color:(LDrawColor *)color
{
	if (partName == nil)
	{
		return nil;
	}

	LDrawPart *newPart  = [LDrawInsertion partNamed:partName color:color copyingTransformFrom:nil];
	NSData    *partData = [self archivedDataForDirective:newPart];
	if (partData == nil)
	{
		return @[];
	}
	return @[partData];
}


//---------- draggingOffsetFromModelPoint:firstPosition: -------------[static]--
//
// Purpose:		Offset of the originating click from the first dragged part’s
//				position.
//
// Notes:		When a drag enters a view, the first part's position is normally
//				set to the model point under the mouse. But that is incorrect
//				behavior when entering the originating view. The user almost
//				certainly did not click the mouse at the exact center of part 0,
//				but nevertheless he does not expect part 0 of his selection to
//				suddenly become centered under the mouse after dragging only one
//				pixel.
//
//				Instead we record the offset of his actual originating click
//				against the position of part 0. Now when this drag reenters its
//				originating view, its position will be adjusted by that offset.
//				Everything will come out looking right. The host still writes
//				the offset onto the pasteboard.
//
//------------------------------------------------------------------------------
+ (Vector3)draggingOffsetFromModelPoint:(Point3)modelPoint
						  firstPosition:(Point3)firstPosition
{
	return V3Sub(modelPoint, firstPosition);
}


//---------- dragOriginatedLocallyFromSource:destination: ------------[static]--
//
// Purpose:		A drag-and-drop part operation. Local drag is a move; otherwise
//				copy. The host still maps that to NSDragOperation.
//
//------------------------------------------------------------------------------
+ (BOOL)dragOriginatedLocallyFromSource:(id)source
							destination:(id)destination
{
	return source == destination;
}


//---------- viewportDragKindFromSource:destination: -----------------[static]--
//
// Purpose:		A drag-and-drop part operation. Local drag is a move; otherwise
//				copy. The host still maps that to NSDragOperation.
//
//------------------------------------------------------------------------------
+ (LDrawViewportDragKind)viewportDragKindFromSource:(id)source
								destination:(id)destination
{
	if ([self dragOriginatedLocallyFromSource:source destination:destination])
		return LDrawViewportDragKindMove;

	return LDrawViewportDragKindCopy;
}




//---------- copyPasteboardTypesIncludingStringType: -----------------[static]--
//
// Purpose:		This method places two arrays on the pasteboard for these types:
//				* LDrawDirectivePboardType: array of LDrawDirectives converted
//							to NSData objects.
//				* NSStringPboardType: array of strings representing the objects
//							in the format written to an LDraw file.
//
// Notes:		This method will clear the contents of the pasteboard. The host
//				still declareTypes: and writes both.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)copyPasteboardTypesIncludingStringType:(NSString *)stringType
{
	return @[
			LDrawDirectivePboardType, // our preferred type.
			stringType,               // representation for other applications.
	];
}


//---------- outlineRegisteredDragTypes ------------------------------[static]--
//
// Purpose:		File-contents outline. The host still registerForDraggedTypes:.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)outlineRegisteredDragTypes
{
	return @[LDrawDirectivePboardType];
}


//---------- outlineDragSourcePasteboardTypes ------------------------[static]--
//
// Purpose:		Row indexes of the original objects being dragged, plus a flag
//				disallowing a drop back onto the source. The host still writes
//				those values.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)outlineDragSourcePasteboardTypes
{
	return @[
			LDrawDragSourceRowsPboardType,
			LDrawDisallowDragToSourcePboardType];
}


//---------- outlineDragDisallowPropertyListForDisallow: -------------[static]--
//
// Purpose:		Disallow dragging if it is the only step in the model. The host
//				still setPropertyList:forType:.
//
//------------------------------------------------------------------------------
+ (id)outlineDragDisallowPropertyListForDisallow:(BOOL)disallow
{
	return disallow ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
}


//---------- outlinePasteboardDisallowsDragToSourceFromTypes:... -----[static]--
//
// Purpose:		Eliminate illegal positions: dragging the only step back into
//				the source.
//
//------------------------------------------------------------------------------
+ (BOOL)outlinePasteboardDisallowsDragToSourceFromTypes:(NSArray *)types
								   disallowPropertyList:(id)disallowPropertyList
{
	return [types containsObject:LDrawDisallowDragToSourcePboardType]
		&& [disallowPropertyList boolValue];
}


//---------- duplicationPasteboardName -------------------------------[static]--
//
// Purpose:		To take advantage of all the exceptionally cool copy/paste code
//				we already have, -duplicate: simply "copies" the selection onto
//				a private pasteboard then "pastes" it right back in. This avoids
//				destroying the general pasteboard.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicationPasteboardName
{
	return @"LDrawDuplicationPboard";
}


//---------- viewportDropPasteboardName ------------------------------[static]--
//
// Purpose:		Just like in -duplicate: and
//				-outlineView:acceptDrop:item:childIndex:, we appropriate the
//				pasting architecture to simplify importing the parts.
//
//------------------------------------------------------------------------------
+ (NSString *)viewportDropPasteboardName
{
	return @"LDrawDragAndDropPboard";
}


//---------- copyPayloadFromDirectives:archivedData:ldrString: -------[static]--
//
// Purpose:		Writes objects to the given pasteboard, ensuring that each
//				directive is written only once. Internally, we use
//				archived LDrawDirectives; for other applications we provide the
//				LDraw file contents. The host still declareTypes: and writes.
//
//------------------------------------------------------------------------------
+ (void)copyPayloadFromDirectives:(NSArray *)directives
					 archivedData:(NSArray<NSData *> * __autoreleasing *)outArchived
						ldrString:(NSString * __autoreleasing *)outString
{
	NSArray *objectsToCopy = [self rootDirectivesFromSelection:directives];

	if (outArchived != NULL)
		*outArchived = [self archivedDataForDirectives:objectsToCopy];
	if (outString != NULL)
		*outString = [self ldrStringForDirectives:objectsToCopy];
}


//---------- viewportRegisteredDragTypes -----------------------------[static]--
//
// Purpose:		Dragging parts around in or between viewports.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)viewportRegisteredDragTypes
{
	return @[LDrawDraggingPboardType];
}


//---------- viewportDragOffsetPasteboardTypes -----------------------[static]--
//
// Purpose:		Offset between the click location which originated the drag and
//				the position of the first dragged directive.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)viewportDragOffsetPasteboardTypes
{
	return @[LDrawDraggingInitialOffsetPboardType];
}


//---------- partBrowserDeclaredDragTypes ----------------------------[static]--
//
// Purpose:		Writes the current part-browser selection onto the pasteboard.
//				Uninitialized: the part has no transform yet.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)partBrowserDeclaredDragTypes
{
	return @[
			LDrawDraggingPboardType,
			LDrawDraggingIsUninitializedPboardType];
}


//---------- searchPanelRegisteredDragTypes --------------------------[static]--
//
// Purpose:		Register for dragging operations — we want to be able to drag
//				parts into the search box.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)searchPanelRegisteredDragTypes
{
	return @[
			LDrawDirectivePboardType,
			LDrawDraggingPboardType];
}


@end
