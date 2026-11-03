//==============================================================================
//
// File:		InventoriesWindowController.h
//
// Purpose:		The Inventories window: the imported sets, the inventories made
//				of sets and loose parts, and the parts matched by hand.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class InventoriesWindowController
//
////////////////////////////////////////////////////////////////////////////////
@interface InventoriesWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

+ (InventoriesWindowController *) sharedController;

@end

NS_ASSUME_NONNULL_END
