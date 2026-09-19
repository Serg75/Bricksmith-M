//==============================================================================
//
//  File:       LDrawSelection+Drag.m
//  Package:    LDrawEditing
//
//  Purpose:    View drag helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawSelection.h>

@implementation LDrawSelection (Drag)

//---------- outlineItemForCopyDragContainerLookupWithCurrentItem:... [static]--
//
// Purpose:		If we are doing a copy-drag operation, remember the original
//				selection and use it. (We can't use the current selection during
//				copy drag because we clear it when the drag begins.)
//
//------------------------------------------------------------------------------
+ (id)outlineItemForCopyDragContainerLookupWithCurrentItem:(id)currentItem
									selectedBeforeCopyDrag:(NSArray *)beforeCopy
{
	if ([beforeCopy count] > 0)
		return [beforeCopy objectAtIndex:0];
	return currentItem;
}


//---------- prepareViewDragOriginals:asCopy: ------------------------[static]--
//
// Purpose:		The parts you see being dragged around are always copies of the
//				originals. When we aren't actually doing a copy drag, we just
//				hide the originals.
//
//------------------------------------------------------------------------------
+ (void)prepareViewDragOriginals:(NSArray *)drawables asCopy:(BOOL)copyFlag
{
	if (copyFlag == NO)
		[self setHidden:YES forDirectives:drawables];
}


@end
