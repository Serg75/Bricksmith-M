//==============================================================================
//
// File:		PartsLimitController.h
//
// Purpose:		A document's side of the parts limit: the Parts menu and the
//				problem button in the scope bar, and the check of the model.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

@class LDrawDocument;
@class LDrawPartLimitReport;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class PartsLimitController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsLimitController : NSObject <NSMenuDelegate>

- (instancetype) initWithDocument:(LDrawDocument *)document;

// Puts the controls into the scope bar, between the model menu and the step
// controls. The model menu gives up the room.
- (void) installAfterView:(NSView *)modelMenu beforeView:(NSView *)stepControls;

- (void) setHidden:(BOOL)hidden;
- (void) layout;

// Checks the model again once the current event is done.
- (void) setNeedsCheck;

// The last check, or nil before the first.
@property (nonatomic, readonly, nullable) LDrawPartLimitReport *report;

@end

NS_ASSUME_NONNULL_END
