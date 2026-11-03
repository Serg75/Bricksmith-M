//==============================================================================
//
// File:		PartsLimitManager.h
//
// Purpose:		The app's parts limits: where their data is kept, the default
//				limit, each model's limit, and the menus that choose them.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawFeatures/LDrawPartLimitPresentation.h>

@class LDrawDocument;
@class LDrawInventoryStore;
@class LDrawPartLimit;
@class LDrawPartLimitSession;
@class LDrawPartLimitTable;
@class LDrawRebrickableUpdater;

NS_ASSUME_NONNULL_BEGIN

// Posted when the Part Browser setting in Settings changes. No object.
extern NSString * const PartsLimitBrowserSettingDidChangeNotification;

// Posted when the marks are turned on or off, or their look changes. No object.
extern NSString * const PartsLimitMarksDidChangeNotification;

// Posted when an update of the parts data ends, however it ended. No object.
extern NSString * const PartsDataUpdateDidEndNotification;

// Posted when the front model's limit may have changed, for the windows that
// follow it. No object.
extern NSString * const PartsLimitFrontLimitDidChangeNotification;

////////////////////////////////////////////////////////////////////////////////
//
// class PartsLimitManager
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsLimitManager : NSObject <NSMenuDelegate>

+ (PartsLimitManager *) sharedManager;

@property (nonatomic, readonly) LDrawInventoryStore		*store;
@property (nonatomic, readonly) LDrawPartLimitSession	*session;
@property (nonatomic, readonly) LDrawRebrickableUpdater	*updater;

// Launch
- (void) start;

// The limit. A nil document is the front model, and with none open only the
// default changes.
- (void) setLimit:(LDrawPartLimit *)limit
		 document:(nullable LDrawDocument *)document
		   window:(nullable NSWindow *)window;
- (LDrawPartLimit *) limitOfDocument:(nullable LDrawDocument *)document;
- (nullable LDrawDocument *) frontDocument;
- (LDrawPartLimit *) frontLimit;
- (nullable LDrawPartLimitTable *) frontRestrictingTable;
- (void) frontLimitMayHaveChanged;
- (void) populatePullDownLimitMenu:(NSMenu *)menu current:(LDrawPartLimit *)current target:(id)target;
- (NSString *) titleForLimit:(LDrawPartLimit *)limit;

// The marks
- (void) applyMarkSettings;
+ (NSColor *) markColorForKey:(NSString *)key;
+ (NSColor *) colorForBadgeTint:(LDrawPartLimitBadgeTint)tint;

// The data
- (void) updateDataForcing:(BOOL)force
					window:(nullable NSWindow *)window
				completion:(nullable void (^)(BOOL success))completion;
- (nullable NSDate *) dataDate;
+ (BOOL (^)(NSString *partName)) libraryHasPartTest;

// Actions
- (IBAction) choosePartsLimit:(nullable id)sender;
- (IBAction) showLimitOptions:(nullable id)sender;
- (IBAction) showInventories:(nullable id)sender;
- (IBAction) toggleLimitMarks:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
