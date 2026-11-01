//==============================================================================
//
// File:		PartsLimitManager.h
//
// Purpose:		The app's one parts limit: where its data is kept, which limit
//				is chosen, and the menu every window shows it in.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

@class LDrawInventoryStore;
@class LDrawPartLimit;
@class LDrawPartLimitSession;
@class LDrawRebrickableClient;
@class LDrawRebrickableUpdater;

NS_ASSUME_NONNULL_BEGIN

// Posted when the Part Browser setting in Settings changes. No object.
extern NSString * const PartsLimitBrowserSettingDidChangeNotification;

// Posted when the marks are turned on or off, or their look changes. No object.
extern NSString * const PartsLimitMarksDidChangeNotification;

// Posted when an update of the parts data ends, however it ended. No object.
extern NSString * const PartsDataUpdateDidEndNotification;

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

// The limit
- (void) setLimit:(LDrawPartLimit *)limit window:(nullable NSWindow *)window;
- (void) populateLimitMenu:(NSMenu *)menu;
- (nullable NSString *) titleForLimit:(LDrawPartLimit *)limit;

// The marks
- (void) applyMarkSettings;

// The data
- (void) updateDataForcing:(BOOL)force
					window:(nullable NSWindow *)window
				completion:(nullable void (^)(BOOL success))completion;
- (nullable NSDate *) dataDate;

// The API key, kept in the Keychain
@property (nonatomic, copy, nullable) NSString *apiKey;
- (nullable LDrawRebrickableClient *) client;

// Actions
- (IBAction) choosePartsLimit:(nullable id)sender;
- (IBAction) showLimitOptions:(nullable id)sender;
- (IBAction) importSetParts:(nullable id)sender;
- (IBAction) showInventories:(nullable id)sender;
- (IBAction) toggleLimitMarks:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
