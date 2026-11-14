//==============================================================================
//
// File:		PartsUpdateController.m
//
// Purpose:		Keeps the LDraw folder up to date with LDraw's part library:
//				looks for an update, offers it, installs it, and has the parts
//				read again. LDrawLibraryUpdate does the work and decides what
//				to do; this shows it.
//
// Notes:		The offer is a panel, not an alert, so it does not stop the
//				user from opening or editing a model.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//==============================================================================
#import "PartsUpdateController.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawLibraryUpdate/LDrawLibraryNewParts.h>
#import <LDrawLibraryUpdate/LDrawLibraryRelease.h>
#import <LDrawLibraryUpdate/LDrawLibraryUpdateError.h>
#import <LDrawLibraryUpdate/LDrawLibraryUpdatePolicy.h>
#import <LDrawLibraryUpdate/LDrawLibraryUpdater.h>

#import "DownloadProgressPanel.h"
#import "LDrawApplication.h"
#import "PartLibraryController.h"
#import "PreferencesForm.h"

NSString * const PartsUpdateStateDidChangeNotification = @"PartsUpdateStateDidChangeNotification";

static const CGFloat OfferTextWidth = 420;

// What the controller is doing.
typedef NS_ENUM(NSInteger, PartsUpdateState)
{
	PartsUpdateStateIdle		= 0,
	PartsUpdateStateChecking	= 1,
	PartsUpdateStateInstalling	= 2,
};


//========== PerformOnMainRunLoop ==============================================
//
// Purpose:		Runs the block on the main thread, from the run loop and not
//				from the main dispatch queue. An alert shown from a block of
//				that queue holds up all its other blocks while it is open.
//
//==============================================================================
static void PerformOnMainRunLoop(void (^block)(void))
{
	CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, block);
	CFRunLoopWakeUp(CFRunLoopGetMain());
}


@implementation PartsUpdateController
{
	LDrawLibraryUpdater				*updater;			// of the check, the offer or the update
	PartsUpdateState				 state;
	BOOL							 terminatesWhenDone;	// the app quits once the update ends

	// The update under way.
	DownloadProgressPanel			*progressPanel;
	NSProgress						*installProgress;
	BOOL							 installAskedByUser;	// not one a launch started on its own

	// The offer on screen.
	NSPanel							*offerPanel;
	NSButton						*offerAutomaticBox;
	NSArray<LDrawLibraryRelease *>	*offeredReleases;
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- sharedController ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (PartsUpdateController *) sharedController
{
	static PartsUpdateController	*controller	= nil;
	static dispatch_once_t			 once;

	dispatch_once(&once, ^{
		controller = [[PartsUpdateController alloc] init];
	});
	return controller;

}//end sharedController


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== isBusy ============================================================
//==============================================================================
- (BOOL) isBusy
{
	return self->state != PartsUpdateStateIdle;
}


//========== installedRelease ==================================================
//==============================================================================
- (NSString *) installedRelease
{
	NSURL *folderURL = [self folderURL];

	return (folderURL != nil) ? [LDrawLibraryUpdater installedReleaseInFolderURL:folderURL] : nil;
}


//========== lastCheckDate =====================================================
//==============================================================================
- (NSDate *) lastCheckDate
{
	id date = [[NSUserDefaults standardUserDefaults] objectForKey:LIBRARY_UPDATE_CHECK_DATE_KEY];

	return [date isKindOfClass:[NSDate class]] ? date : nil;
}


//========== folderURL =========================================================
//
// Purpose:		The LDraw folder, or nil when none is chosen.
//
//==============================================================================
- (NSURL *) folderURL
{
	NSString *path = [[LDrawPaths sharedPaths] preferredLDrawPath];

	return (path != nil) ? [NSURL fileURLWithPath:path isDirectory:YES] : nil;
}


//========== updaterIsForCurrentFolder =========================================
//
// Purpose:		Whether the check, offer or update is for the LDraw folder in
//				use. The user can choose another in Settings at any time.
//
//==============================================================================
- (BOOL) updaterIsForCurrentFolder
{
	return [[self->updater folderURL] isEqual:[self folderURL]];
}


//========== setState: =========================================================
//
// Purpose:		Notes what is under way, and tells the windows that show it.
//
//==============================================================================
- (void) setState:(PartsUpdateState)newState
{
	self->state = newState;
	[[NSNotificationCenter defaultCenter] postNotificationName:PartsUpdateStateDidChangeNotification object:nil];
}


#pragma mark -
#pragma mark NEW PARTS
#pragma mark -

//========== restoreNewParts ===================================================
//
// Purpose:		Tells the part library which parts the folder's last update
//				added, so the Part Browser lists them.
//
//==============================================================================
- (void) restoreNewParts
{
	NSUserDefaults			*defaults	= [NSUserDefaults standardUserDefaults];
	NSDictionary			*saved		= [defaults dictionaryForKey:LIBRARY_UPDATE_NEW_PARTS_KEY];
	LDrawLibraryNewParts	*newParts	= [[LDrawLibraryNewParts alloc] initWithDictionary:saved];
	NSString				*title		= nil;

	// The list was saved for one folder, and is not used for another.
	if([newParts isOfFolderPath:[[LDrawPaths sharedPaths] preferredLDrawPath]] == NO)
		newParts = nil;

	if(newParts != nil)
		title = [NSString stringWithFormat:NSLocalizedString(@"New in %@", nil), [newParts releaseIdentifier]];

	[[LDrawPartLibrary sharedPartLibrary] setPartNamesFromLastUpdate:([newParts partNames] ?: @[]) title:title];

}//end restoreNewParts


//========== saveNewPartNames:ofRelease: =======================================
//
// Purpose:		Keeps the parts an update added, for the next launches.
//
//==============================================================================
- (void) saveNewPartNames:(NSArray<NSString *> *)names ofRelease:(NSString *)release
{
	NSString				*folderPath	= [[self->updater folderURL] path];
	LDrawLibraryNewParts	*newParts	= nil;

	newParts = [[LDrawLibraryNewParts alloc] initWithPartNames:names
											 releaseIdentifier:release
													folderPath:folderPath];

	[[NSUserDefaults standardUserDefaults] setObject:[newParts dictionaryRepresentation]
											  forKey:LIBRARY_UPDATE_NEW_PARTS_KEY];

}//end saveNewPartNames:ofRelease:


#pragma mark -
#pragma mark CHECKING
#pragma mark -

//========== checkAtLaunch =====================================================
//==============================================================================
- (void) checkAtLaunch
{
	LDrawLibraryUpdateMode mode = [[NSUserDefaults standardUserDefaults] integerForKey:LIBRARY_UPDATE_MODE_KEY];

	if([LDrawLibraryUpdatePolicy isLaunchCheckDueInMode:mode lastCheckDate:[self lastCheckDate] now:[NSDate date]])
		[self checkAskedByUser:NO];

}//end checkAtLaunch


//========== checkForPartsUpdate: ==============================================
//
// Purpose:		Bricksmith > Check for Parts Update…
//
//==============================================================================
- (IBAction) checkForPartsUpdate:(id)sender
{
	// An offer for another folder is out of date.
	if(self->offerPanel != nil && [self updaterIsForCurrentFolder] == NO)
		[self closeOffer];

	if(self->offerPanel != nil)
	{
		[self->offerPanel makeKeyAndOrderFront:nil];
		return;
	}
	[self checkAskedByUser:YES];

}//end checkForPartsUpdate:


//========== checkAskedByUser: =================================================
//
// Purpose:		Asks LDraw's server for its releases. A check the user asked
//				for says what it found; one at launch only offers an update.
//
//==============================================================================
- (void) checkAskedByUser:(BOOL)asked
{
	NSURL *folderURL = [self folderURL];

	if([self isBusy] || self->offerPanel != nil)
		return;

	if(folderURL == nil)
	{
		if(asked)
		{
			[self showMessage:NSLocalizedString(@"There is no LDraw folder to update.", nil)
			  informativeText:NSLocalizedString(@"Choose the folder in Settings.", nil)];
		}
		return;
	}

	self->updater = [[LDrawLibraryUpdater alloc] initWithFolderURL:folderURL];
	[self setState:PartsUpdateStateChecking];

	[self->updater fetchReleaseListWithCompletionQueue:nil
											completion:^(LDrawLibraryReleaseList *list, NSError *error) {
		PerformOnMainRunLoop(^{
			[self setState:PartsUpdateStateIdle];
			[self didFetchReleaseList:list error:error askedByUser:asked];
		});
	}];

}//end checkAskedByUser:


//========== didFetchReleaseList:error:askedByUser: ============================
//
// Purpose:		Does what the update policy says: offers or installs what the
//				folder needs, or says why it needs nothing.
//
//==============================================================================
- (void) didFetchReleaseList:(LDrawLibraryReleaseList *)list error:(NSError *)error askedByUser:(BOOL)asked
{
	NSUserDefaults					*defaults	= [NSUserDefaults standardUserDefaults];
	NSURL							*folderURL	= [self->updater folderURL];
	NSString						*installed	= [LDrawLibraryUpdater installedReleaseInFolderURL:folderURL];
	LDrawLibraryUpdateMode			 mode		= [defaults integerForKey:LIBRARY_UPDATE_MODE_KEY];
	NSString						*skipped	= [defaults stringForKey:LIBRARY_UPDATE_SKIPPED_RELEASE_KEY];
	NSArray<LDrawLibraryRelease *>	*releases	= nil;
	NSString						*text		= nil;

	// Another folder was chosen during the check. A launch checks it the next
	// time; the user who asked gets an answer for the new one.
	if([self updaterIsForCurrentFolder] == NO)
	{
		if(asked)
			[self checkAskedByUser:YES];
		return;
	}

	if(list == nil)
	{
		if(asked)
			[[NSAlert alertWithError:error] runModal];
		else
			NSLog(@"Could not look for an LDraw parts update: %@", error);
		return;
	}

	[defaults setObject:[NSDate date] forKey:LIBRARY_UPDATE_CHECK_DATE_KEY];
	[[NSNotificationCenter defaultCenter] postNotificationName:PartsUpdateStateDidChangeNotification object:nil];

	releases = [list releasesToInstallAfter:installed];

	switch([LDrawLibraryUpdatePolicy actionForList:list
										 installed:installed
											  mode:mode
									skippedRelease:skipped
									   askedByUser:asked])
	{
		case LDrawLibraryUpdateActionNone:
			break;

		case LDrawLibraryUpdateActionUpToDate:
			text = [NSString stringWithFormat:NSLocalizedString(@"The LDraw folder holds update %@, the newest.", nil),
					installed];
			[self showMessage:NSLocalizedString(@"Your LDraw parts are up to date.", nil) informativeText:text];
			break;

		case LDrawLibraryUpdateActionNoArchive:
			text = [NSString stringWithFormat:NSLocalizedString(@"The LDraw folder holds update %@. LDraw lists no "
																@"zip archive that brings it to update %@.", nil),
					installed, [list latestIdentifier]];
			[self showMessage:NSLocalizedString(@"No LDraw parts update can be installed.", nil) informativeText:text];
			break;

		case LDrawLibraryUpdateActionOffer:
			[self offerReleases:releases installed:installed makeKey:asked];
			break;

		case LDrawLibraryUpdateActionInstall:
			[self installReleases:releases makeKey:NO];
			break;
	}

}//end didFetchReleaseList:error:askedByUser:


//========== showMessage:informativeText: ======================================
//==============================================================================
- (void) showMessage:(NSString *)message informativeText:(NSString *)text
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert setMessageText:message];
	[alert setInformativeText:text];
	[alert runModal];
}


#pragma mark -
#pragma mark THE OFFER
#pragma mark -

//========== descriptionOfReleases:installed: ==================================
//
// Purpose:		What the folder has, how big the download is, and where it
//				goes.
//
//==============================================================================
- (NSString *) descriptionOfReleases:(NSArray<LDrawLibraryRelease *> *)releases installed:(NSString *)installed
{
	NSString	*folderPath	= [[[self->updater folderURL] path] stringByAbbreviatingWithTildeInPath];
	int64_t		 byteCount	= [LDrawLibraryRelease byteCountOfReleases:releases];
	NSString	*size		= nil;
	NSString	*has		= nil;
	NSString	*download	= nil;
	NSString	*place		= nil;

	size = [NSByteCountFormatter stringFromByteCount:byteCount countStyle:NSByteCountFormatterCountStyleFile];

	if(installed != nil)
		has = [NSString stringWithFormat:NSLocalizedString(@"Your LDraw folder holds update %@.", nil), installed];
	else
		has = NSLocalizedString(@"Your LDraw folder does not say which update it holds.", nil);

	if([[releases firstObject] isComplete])
		download = [NSString stringWithFormat:NSLocalizedString(@"The complete library is downloaded, %@.", nil), size];
	else if([releases count] == 1)
		download = [NSString stringWithFormat:NSLocalizedString(@"The download is %@.", nil), size];
	else
	{
		download = [NSString stringWithFormat:NSLocalizedString(@"%lu updates are downloaded, %@ in all.", nil),
					(unsigned long)[releases count], size];
	}

	place = [NSString stringWithFormat:NSLocalizedString(@"The parts go into %@. Its Unofficial folder is not "
														 @"changed.", nil), folderPath];

	return [@[has, download, place] componentsJoinedByString:@" "];

}//end descriptionOfReleases:installed:


//========== offerReleases:installed:makeKey: ==================================
//
// Purpose:		Shows the panel that offers an update, with Update, Later and
//				Skip This Update. It floats over the windows and takes the
//				keyboard only when the user asked for the check.
//
//==============================================================================
- (void) offerReleases:(NSArray<LDrawLibraryRelease *> *)releases
			 installed:(NSString *)installed
			   makeKey:(BOOL)makeKey
{
	NSString	*details	= [self descriptionOfReleases:releases installed:installed];
	NSString	*boxTitle	= NSLocalizedString(@"Install future updates without asking", nil);
	NSString	*message	= nil;
	NSTextField	*title		= nil;
	NSTextField	*text		= [NSTextField wrappingLabelWithString:details];
	NSButton	*update		= nil;
	NSButton	*later		= nil;
	NSButton	*skip		= nil;
	NSView		*gap		= [[NSView alloc] init];
	NSStackView	*buttons	= nil;
	NSStackView	*stack		= nil;
	NSView		*content	= nil;

	message	= [NSString stringWithFormat:NSLocalizedString(@"LDraw parts update %@ is available", nil),
			   [LDrawLibraryRelease identifierReachedByReleases:releases]];
	title	= [NSTextField labelWithString:message];

	update = [NSButton buttonWithTitle:NSLocalizedString(@"Update", nil)
								target:self
								action:@selector(installOffer:)];
	later = [NSButton buttonWithTitle:NSLocalizedString(@"Later", nil)
							   target:self
							   action:@selector(postponeOffer:)];
	skip = [NSButton buttonWithTitle:NSLocalizedString(@"Skip This Update", nil)
							  target:self
							  action:@selector(skipOffer:)];

	self->offeredReleases	= releases;
	self->offerAutomaticBox	= [NSButton checkboxWithTitle:boxTitle target:nil action:NULL];

	[title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	[text setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[text setSelectable:NO];
	[text setPreferredMaxLayoutWidth:OfferTextWidth];
	[[text widthAnchor] constraintEqualToConstant:OfferTextWidth].active = YES;
	[update setKeyEquivalent:@"\r"];
	[later setKeyEquivalent:@"\e"];

	// The gap takes the room between Skip This Update and the other two.
	[gap setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	buttons = [NSStackView stackViewWithViews:@[skip, gap, later, update]];

	stack = [NSStackView stackViewWithViews:@[title, text, self->offerAutomaticBox, buttons]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:12];
	[[buttons widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;

	content = [PreferencesForm containerForView:stack margins:NSEdgeInsetsMake(20, 20, 20, 20)];

	self->offerPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 200)
												  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
													backing:NSBackingStoreBuffered
													  defer:NO];
	[self->offerPanel setTitle:NSLocalizedString(@"Parts Update", nil)];
	[self->offerPanel setContentView:content];
	[self->offerPanel setContentSize:[content fittingSize]];
	[self->offerPanel setReleasedWhenClosed:NO];
	[self->offerPanel setFloatingPanel:YES];
	[self->offerPanel setDelegate:self];
	[self->offerPanel center];

	if(makeKey)
		[self->offerPanel makeKeyAndOrderFront:nil];
	else
		[self->offerPanel orderFront:nil];

}//end offerReleases:installed:makeKey:


//========== installOffer: =====================================================
//
// Purpose:		Update: installs the offered update.
//
//==============================================================================
- (IBAction) installOffer:(id)sender
{
	NSArray<LDrawLibraryRelease *> *releases = self->offeredReleases;

	if([self->offerAutomaticBox state] == NSControlStateValueOn)
	{
		[[NSUserDefaults standardUserDefaults] setInteger:LDrawLibraryUpdateModeInstall
												   forKey:LIBRARY_UPDATE_MODE_KEY];
		[[NSNotificationCenter defaultCenter] postNotificationName:PartsUpdateStateDidChangeNotification object:nil];
	}

	[self closeOffer];

	// The folder changed since the check, so look again for the new one.
	if([self updaterIsForCurrentFolder] == NO)
	{
		[self checkAskedByUser:YES];
		return;
	}
	[self installReleases:releases makeKey:YES];

}//end installOffer:


//========== postponeOffer: ====================================================
//
// Purpose:		Later: the next day's launch offers the update again.
//
//==============================================================================
- (IBAction) postponeOffer:(id)sender
{
	[self closeOffer];
}


//========== skipOffer: ========================================================
//
// Purpose:		Skip This Update: a launch offers only a newer update.
//
//==============================================================================
- (IBAction) skipOffer:(id)sender
{
	NSString *skipped = [LDrawLibraryRelease identifierReachedByReleases:self->offeredReleases];

	[[NSUserDefaults standardUserDefaults] setObject:skipped forKey:LIBRARY_UPDATE_SKIPPED_RELEASE_KEY];
	[self closeOffer];
}


//========== closeOffer ========================================================
//==============================================================================
- (void) closeOffer
{
	[self->offerPanel close];
}


//========== windowWillClose: ==================================================
//
// Purpose:		The offer is gone, by a button or the close box.
//
//==============================================================================
- (void) windowWillClose:(NSNotification *)notification
{
	NSPanel *panel = self->offerPanel;

	// The panel is still closing, and this is its last owner, so it is let go
	// of a moment later.
	dispatch_async(dispatch_get_main_queue(), ^{
		(void)panel;
	});

	self->offerPanel		= nil;
	self->offerAutomaticBox	= nil;
	self->offeredReleases	= nil;
}


#pragma mark -
#pragma mark INSTALLING
#pragma mark -

//========== installReleases:makeKey: ==========================================
//
// Purpose:		Downloads the releases and puts their files into the LDraw
//				folder, showing the progress. The panel takes the keyboard only
//				when the user asked for the update.
//
//==============================================================================
- (void) installReleases:(NSArray<LDrawLibraryRelease *> *)releases makeKey:(BOOL)makeKey
{
	NSString	*newest		= [LDrawLibraryRelease identifierReachedByReleases:releases];
	NSString	*finishing	= NSLocalizedString(@"Installing the parts…", nil);
	NSString	*message	= nil;

	if([self updaterIsForCurrentFolder] == NO || [self isBusy])
		return;

	message = [NSString stringWithFormat:NSLocalizedString(@"Downloading LDraw parts update %@…", nil), newest];

	[self setState:PartsUpdateStateInstalling];
	self->installAskedByUser = makeKey;

	self->installProgress = [self->updater installReleases:releases
										   completionQueue:nil
												completion:^(NSArray<NSString *> *addedPartNames, NSError *error) {
		PerformOnMainRunLoop(^{
			[self->progressPanel close];
			self->progressPanel		= nil;
			self->installProgress	= nil;
			[self didInstallRelease:newest addedPartNames:addedPartNames error:error];
		});
	}];

	self->progressPanel = [[DownloadProgressPanel alloc] initWithProgress:self->installProgress
																   window:nil
																  makeKey:makeKey
																  message:message
														 finishingMessage:finishing];

}//end installReleases:makeKey:


//========== didInstallRelease:addedPartNames:error: ===========================
//
// Purpose:		After an update, keeps the list of its new parts and reads the
//				LDraw folder again. That also reads the changed parts of the
//				open models, and reports the part overrides the folder now has
//				newer versions of.
//
//==============================================================================
- (void) didInstallRelease:(NSString *)release
			addedPartNames:(NSArray<NSString *> *)addedPartNames
					 error:(NSError *)error
{
	PartLibraryController	*libraryController	= [LDrawApplication sharedPartLibraryController];
	BOOL					 ownError			= [[error domain] isEqualToString:LDrawLibraryUpdateErrorDomain];
	BOOL					 canceled			= (ownError && [error code] == LDrawLibraryUpdateErrorCanceled);
	BOOL					 busy				= (ownError && [error code] == LDrawLibraryUpdateErrorBusy);

	// A run that added no parts, such as one another app already installed,
	// keeps the last list.
	if(error == nil && [addedPartNames count] > 0)
		[self saveNewPartNames:addedPartNames ofRelease:release];
	[self setState:PartsUpdateStateIdle];

	// The quit waited for the update. The next launch reads the folder.
	if(self->terminatesWhenDone)
	{
		[NSApp replyToApplicationShouldTerminate:YES];
		return;
	}

	if(error != nil)
	{
		// A launch that finds another app updating the folder says nothing.
		if(busy && self->installAskedByUser == NO)
			NSLog(@"Did not update the LDraw parts: %@", error);
		else if(canceled == NO)
			[[NSAlert alertWithError:error] runModal];
		return;
	}

	[libraryController reloadPartCatalog:^(BOOL success) {
		[libraryController reportOutdatedPartOverrides];
	}];

}//end didInstallRelease:addedPartNames:error:


#pragma mark -
#pragma mark QUITTING
#pragma mark -

//========== shouldTerminate ===================================================
//
// Purpose:		Called when the app quits. A download is canceled, and the quit
//				waits for the update to end: once the files are being put in
//				place, stopping would leave the folder half updated.
//
//==============================================================================
- (NSApplicationTerminateReply) shouldTerminate
{
	if(self->state != PartsUpdateStateInstalling)
		return NSTerminateNow;

	self->terminatesWhenDone = YES;
	[self->installProgress cancel];
	return NSTerminateLater;

}//end shouldTerminate


#pragma mark -
#pragma mark MENUS
#pragma mark -

//========== validateMenuItem: =================================================
//
// Purpose:		Check for Parts Update… is off while a check or an update runs.
//
//==============================================================================
- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(checkForPartsUpdate:))
		return [self isBusy] == NO;
	return YES;
}

@end
