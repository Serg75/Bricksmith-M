//==============================================================================
//
// File:		PartComparisonController.h
//
// Purpose:		A window that shows a part from the overrides folder next to
//				the library's, with the two views turning together.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

@class LDrawColor;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class PartComparisonController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartComparisonController : NSWindowController

+ (PartComparisonController *) sharedController;

/// Shows the part's two sides in the color. NO, showing nothing, when they are
/// the same: the part is not overridden and uses no part that is.
- (BOOL) showPartNamed:(NSString *)partName color:(nullable LDrawColor *)color;

@end

NS_ASSUME_NONNULL_END
