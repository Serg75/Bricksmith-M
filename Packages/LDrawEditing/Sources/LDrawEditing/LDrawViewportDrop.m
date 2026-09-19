//==============================================================================
//
//  File:       LDrawViewportDrop.m
//  Package:    LDrawEditing
//
//  Purpose:    3D-viewport drop moves and hidden originals after a drag leaves
//              the document.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawViewportDrop.h>

#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/MatrixMath.h>

@implementation LDrawViewportDrop

//---------- viewportDropPasteUndoActionKey --------------------------[static]--
//
// Purpose:		The user has deposited some drag-and-drop parts into a 3D
//				viewport (paste path, not same-document move). The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)viewportDropPasteUndoActionKey
{
	return @"UndoDrop";
}


//---------- viewportDropIsSameDocumentMoveFromSource:toDocument:selectionCount:
//																     [static]--
//
// Purpose:		The user has deposited some drag-and-drop parts into a 3D
//				viewport. Now they need to be imported into the model.
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
+ (BOOL)viewportDropIsSameDocumentMoveFromSource:(nullable id)sourceFile
									  toDocument:(nullable id)documentFile
								  selectionCount:(NSInteger)selectionCount
{
	return sourceFile != nil
		&& sourceFile == documentFile
		&& selectionCount > 0;
}


//---------- viewportDropMovesForSelection:droppedCopies: ------------[static]--
//
// Purpose:		Pair selected drawables with dropped copies in order, then
//				compute the displacement from each original to its drag copy.
//				The host still applies the move (undo) and unhides the original.
//
//------------------------------------------------------------------------------
+ (NSArray *)viewportDropMovesForSelection:(NSArray *)selection
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

			[moves addObject:[[LDrawViewportDropMove alloc] initWithDirective:currentDirective
																 displacement:displacement]];
			dropDirectiveIndex++;
		}
	}
	return moves;
}


//---------- viewportDragOblivionDirectivesFromSelection: ------------[static]--
//
// Purpose:		Now that we know they are really truly gone, we need to delete
//				their hidden ghosts.
//
//------------------------------------------------------------------------------
+ (NSArray *)viewportDragOblivionDirectivesFromSelection:(NSArray *)selection
{
	return [self drawableDirectivesInSelection:selection];
}


//---------- unhideDirectivesInViewportDropMoves: --------------------[static]--
//
// Purpose:		The host still moveDirective: (undo) after a same-document drop.
//
//------------------------------------------------------------------------------
+ (void)unhideDirectivesInViewportDropMoves:(NSArray *)moves
{
	for (LDrawViewportDropMove *move in moves)
		[move.directive setHidden:NO];
}


//---------- restoreVisibilityBeforeDeletingViewportDragOblivionDirectives:
//                                                          [static]--
//
// Purpose:		Even though the directive has been drag-deleted, we still need
//				to delete it in an undo-friendly way. That means we need to
//				restore its visibility, since we hid the part when dragging
//				began.
//
//------------------------------------------------------------------------------
+ (void)restoreVisibilityBeforeDeletingViewportDragOblivionDirectives:(NSArray *)directives
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
//				space. Wherever they went, they are gone now.
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


@end
