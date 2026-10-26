//==============================================================================
//
// File:		ImportSetController.h
//
// Purpose:		A sheet to find a LEGO set by number or name and import its
//				parts, to use as the parts limit.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class ImportSetController
//
////////////////////////////////////////////////////////////////////////////////
@interface ImportSetController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>

// Shows the sheet, or a panel without a window. Without the parts data or an
// API key, it first offers to download the data.
+ (void) runWithWindow:(nullable NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
