//==============================================================================
//
// File:		LDrawFileOutlineView.h
//
// Purpose:		Outline view which displays the contents of an LDrawFile.
//
//  Created by Allen Smith on 4/10/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>


@interface LDrawFileOutlineView : NSOutlineView {

}

- (NSIndexSet *) selectObjects:(NSArray *)objects;

/// Row indexes for an outline drag, written to LDrawDragSourceRowsPboardType
/// so a successful drop can delete the originals.
- (NSArray<NSNumber *> *)rowIndexesForItems:(NSArray *)items;

/// Items at the given rows. Same-outline acceptDrop gathers these *before*
/// moving so the indexes are still correct.
- (NSArray *)itemsAtRowIndexes:(NSIndexSet *)indexes;

@end
