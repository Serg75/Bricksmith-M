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

@class IconTextCell;
@class LDrawDocument;
@class LDrawPart;
@class LDrawPartLimit;
@class LDrawPartLimitReport;
@class LDrawPartLimitTable;
@class LDrawPartUsage;

NS_ASSUME_NONNULL_BEGIN

// Posted after a document checked its model, so part browsers can count again.
// Object is the document.
extern NSString * const PartsLimitDidCheckNotification;

////////////////////////////////////////////////////////////////////////////////
//
// class PartsLimitController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsLimitController : NSObject <NSMenuDelegate>

// The model's limit comes from its file, or is the default.
- (instancetype) initWithDocument:(LDrawDocument *)document;

// The model's limit. Setting it keeps it with the model's file, and checks
// the model again.
@property (nonatomic, copy) LDrawPartLimit *limit;

// What the limit allows, when it restricts and has its data.
- (nullable LDrawPartLimitTable *) restrictingTable;

// Keeps the model's own limit with its file again, after a save wrote it.
- (void) keepLimitWithFileAtURL:(NSURL *)url;

// Puts the controls into the scope bar, between the model menu and the step
// controls. The model menu gives up the room.
- (void) installAfterView:(NSView *)modelMenu beforeView:(NSView *)stepControls;

- (void) setHidden:(BOOL)hidden;

// Checks the model again once the current event is done.
- (void) setNeedsCheck;

// Redraws the model for new marks.
- (void) redrawMarks;

// The last check, or nil before the first.
@property (nonatomic, readonly, nullable) LDrawPartLimitReport *report;

// What the model uses, walked when first asked for after an edit.
@property (nonatomic, readonly, nullable) LDrawPartUsage *usage;

// File Contents and the inspector, while the marks are on.
- (void) configureBadgeOfCell:(IconTextCell *)cell forItem:(id)item;
- (nullable NSString *) toolTipForItem:(id)item;
- (nullable NSString *) limitLineForPart:(LDrawPart *)part;

// Edit > Select Parts with Limit Problems.
- (BOOL) selectProblemParts;

// The window's Parts menu.
- (IBAction) choosePartsLimit:(nullable id)sender;
- (IBAction) showLimitOptions:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
