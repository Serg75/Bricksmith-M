//==============================================================================
//
//  File:       LDrawSelection+Marquee.m
//  Package:    LDrawEditing
//
//  Purpose:    Marquee selection-mode helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import "LDrawSelectionInternal.h"

#import <LDrawEditing/LDrawSelection.h>

@implementation LDrawSelection (Marquee)

//---------- selectionModeFromModifiers: ----------------------------[static]--
//
// Purpose:		Map Shift / Option bits to replace, extend, subtract, or
//				intersection. Modifier bits match NSEventModifierFlags so an
//				AppKit host can pass event.modifierFlags through unchanged.
//
//------------------------------------------------------------------------------
+ (SelectionModeT)selectionModeFromModifiers:(NSUInteger)modifiers
{
	BOOL shift  = (modifiers & kLDrawModifierShift)  != 0;
	BOOL option = (modifiers & kLDrawModifierOption) != 0;

	if (shift)
	{
		return option ? SelectionIntersection : SelectionExtend;
	}
	return option ? SelectionSubtract : SelectionReplace;
}

//---------- mergedSelectionWithMarked:newDirectives:mode: -----------[static]--
//
// Purpose:		Bulk-select after a marquee. Calculate the union of the past
//				selection and this one if we are extending. Otherwise we only
//				want the new selection. Subtract removes the marquee from the
//				old set; intersection keeps the overlap.
//
//				If the array is empty, the host should deselect. The old
//				selection is still preserved when extension is used and the
//				marquee is empty (extend of nothing is the old set).
//
//------------------------------------------------------------------------------
+ (NSArray *)mergedSelectionWithMarked:(NSArray *)marked
						 newDirectives:(NSArray *)directives
								  mode:(SelectionModeT)mode
{
	if (mode == SelectionIntersection)
	{
		NSMutableSet *orig = [NSMutableSet setWithArray:marked];
		[orig intersectSet:[NSSet setWithArray:directives]];
		return [orig allObjects];
	}

	// Replace takes the new set; every other mode starts from the marked set.
	NSMutableArray *all = (mode != SelectionReplace)
		? [NSMutableArray arrayWithArray:marked]
		: [NSMutableArray arrayWithArray:directives];

	if (mode == SelectionExtend)
	{
		[all addObjectsFromArray:directives];
	}
	else if (mode == SelectionSubtract)
	{
		[all removeObjectsInArray:directives];
	}

	return all;
}


@end
