//==============================================================================
//
// File:		PartsLimitOptionsController.h
//
// Purpose:		A sheet with the options of the parts limit: how far back
//				Available Now looks, spares, and how parts and colors match.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class PartsLimitOptionsController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsLimitOptionsController : NSObject

// Shows the sheet, or a panel without a window. Each change applies to the
// app's limit at once.
+ (void) showWithWindow:(nullable NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
