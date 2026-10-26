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

@class LDrawPartLimit;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class PartsLimitOptionsController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsLimitOptionsController : NSObject

// Shows the sheet, or a panel without a window. The completion gets the limit
// with the new options, or nil for Cancel.
+ (void) runWithLimit:(LDrawPartLimit *)limit
			   window:(nullable NSWindow *)window
		   completion:(void (^)(LDrawPartLimit * _Nullable limit))completion;

@end

NS_ASSUME_NONNULL_END
