//==============================================================================
//
// File:		PartsUpdateController.h
//
// Purpose:		Keeps the LDraw folder up to date with LDraw's part library:
//				looks for an update, offers it, installs it, and has the parts
//				read again.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//==============================================================================
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when a check or an update starts or ends, and when the offer turns on
// installing without asking. No object.
extern NSString * const PartsUpdateStateDidChangeNotification;

////////////////////////////////////////////////////////////////////////////////
//
// class PartsUpdateController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsUpdateController : NSObject <NSWindowDelegate>

+ (PartsUpdateController *) sharedController;

// Whether a check or an update is under way.
@property (nonatomic, readonly, getter=isBusy) BOOL busy;

// The update the LDraw folder holds, such as "2026-10", or nil.
- (nullable NSString *) installedRelease;

// When LDraw's server was last asked for its releases, or nil.
- (nullable NSDate *) lastCheckDate;

// Tells the part library which parts the folder's last update added.
- (void) restoreNewParts;

// Looks for an update when the setting allows, at most once a day. Says
// nothing when there is none or the server cannot be reached.
- (void) checkAtLaunch;

// Looks for an update now, and says what it found.
- (IBAction) checkForPartsUpdate:(nullable id)sender;

// For applicationShouldTerminate:. While an update runs, its download is
// canceled and the quit waits for it to end: NSTerminateLater, then
// replyToApplicationShouldTerminate:.
- (NSApplicationTerminateReply) shouldTerminate;

@end

NS_ASSUME_NONNULL_END
