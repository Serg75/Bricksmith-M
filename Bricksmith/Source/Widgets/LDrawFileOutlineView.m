//==============================================================================
//
// File:		LDrawFileOutlineView.m
//
// Purpose:		Outline view which displays the contents of an LDrawFile.
//
//  Created by Allen Smith on 4/10/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import "LDrawFileOutlineView.h"


@implementation LDrawFileOutlineView

//========== awakeFromNib ======================================================
//
// Purpose:		Called when the view is loaded from a nib file.
//
//==============================================================================
- (void)awakeFromNib
{
	[super awakeFromNib];
	[self setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
	[self setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];

}//end awakeFromNib


//========== selectObjects: ====================================================
//
// Purpose:		Conveniently selects all the the objects in the array which are 
//				visible. Returns the indexes of the selected objects.
//
//==============================================================================
- (NSIndexSet *) selectObjects:(NSArray *)objects
{
	//Select all the objects which have been added.
	id                  currentObject       = nil;
	NSUInteger          indexOfObject       = 0;
	NSMutableIndexSet   *indexesToSelect    = [NSMutableIndexSet indexSet];
	NSInteger           counter             = 0;
	
	//Gather up the indices of the pasted objects.
	for(counter = 0; counter < [objects count]; counter++)
	{
		currentObject = [objects objectAtIndex:counter];
		indexOfObject = [self rowForItem:currentObject];
		[indexesToSelect addIndex:indexOfObject];
	}
	[self selectRowIndexes:indexesToSelect byExtendingSelection:NO];

	return indexesToSelect;
	
}//end selectObjects:


//========== rowIndexesForItems: ===============================================
//
// Purpose:		Now write the row indexes out. We'll use them to delete the
//				original objects in the event of a successful drag.
//
//==============================================================================
- (NSArray<NSNumber *> *)rowIndexesForItems:(NSArray *)items
{
	NSMutableArray *rowIndexes = [NSMutableArray arrayWithCapacity:[items count]];
	id              item       = nil;
	
	for(item in items)
	{
		[rowIndexes addObject:@([self rowForItem:item])];
	}
	return rowIndexes;
	
}//end rowIndexesForItems:


//========== itemsAtRowIndexes: ================================================
//
// Purpose:		Gather up the objects we'll be removing. Note we're doing this
//				*before* moving, so that the indexes are still correct.
//
//==============================================================================
- (NSArray *)itemsAtRowIndexes:(NSIndexSet *)indexes
{
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:[indexes count]];
	
	[indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		id object = [self itemAtRow:(NSInteger)idx];
		if(object != nil)
			[items addObject:object];
	}];
	return items;
	
}//end itemsAtRowIndexes:


@end
