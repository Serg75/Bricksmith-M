//==============================================================================
//
// File:		PartsLimitManager.m
//
// Purpose:		The app's one parts limit: where its data is kept, which limit
//				is chosen, and the menu every window shows it in.
//
// Notes:		The limit is an editor setting, kept in the defaults, never in
//				a model. The data lives in Application Support.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "PartsLimitManager.h"

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawFeatures/LDrawPreferences.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import "InventoriesWindowController.h"
#import "LDrawDocument.h"
#import "PartsLimitController.h"
#import "PartsLimitOptionsController.h"
#import "PreferencesForm.h"

NSString * const PartsLimitBrowserSettingDidChangeNotification = @"PartsLimitBrowserSettingDidChangeNotification";
NSString * const PartsLimitMarksDidChangeNotification = @"PartsLimitMarksDidChangeNotification";
NSString * const PartsDataUpdateDidEndNotification = @"PartsDataUpdateDidEndNotification";
NSString * const PartsLimitFrontLimitDidChangeNotification = @"PartsLimitFrontLimitDidChangeNotification";

// About how much the first download is, for the question before it.
static NSString * const DownloadSizeText = @"about 18 MB";


////////////////////////////////////////////////////////////////////////////////
//
// class PartsDataProgressPanel
//
// Shows a download's progress in a sheet, or a panel without a window.
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsDataProgressPanel : NSObject
- (instancetype) initWithProgress:(NSProgress *)progress window:(nullable NSWindow *)window;
- (void) close;
@end


@implementation PartsDataProgressPanel
{
	NSPanel				*panel;
	NSWindow			*parent;
	NSProgress			*progress;
	NSProgressIndicator	*indicator;
	NSTextField			*label;
}

//========== initWithProgress:window: ==========================================
//
// Purpose:		Shows a small panel with a bar, a line of text and Cancel.
//
//==============================================================================
- (instancetype) initWithProgress:(NSProgress *)aProgress window:(NSWindow *)window
{
	self = [super init];
	if (self)
	{
		NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil)
											  target:self
											  action:@selector(cancel:)];

		self->progress	= aProgress;
		self->parent	= window;
		self->panel		= [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 110)
													 styleMask:NSWindowStyleMaskTitled
													   backing:NSBackingStoreBuffered
														 defer:NO];
		self->label		= [NSTextField labelWithString:NSLocalizedString(@"Downloading parts data from "
																		 @"Rebrickable.com…", nil)];
		self->indicator	= [[NSProgressIndicator alloc] init];

		[self->indicator setIndeterminate:NO];
		[self->indicator setMinValue:0];
		[self->indicator setMaxValue:1];
		[cancel setKeyEquivalent:@"\e"];

		NSStackView *stack = [NSStackView stackViewWithViews:@[self->label, self->indicator, cancel]];
		[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[stack setAlignment:NSLayoutAttributeTrailing];
		[[self->indicator widthAnchor] constraintEqualToConstant:340].active = YES;
		[[self->label leadingAnchor] constraintEqualToAnchor:[self->indicator leadingAnchor]].active = YES;

		NSView *content = [PreferencesForm containerForView:stack margins:NSEdgeInsetsMake(20, 20, 20, 20)];
		[self->panel setContentView:content];
		[self->panel setContentSize:[content fittingSize]];

		[self->progress addObserver:self forKeyPath:@"fractionCompleted" options:0 context:NULL];

		if(window != nil)
			[window beginSheet:self->panel completionHandler:nil];
		else
		{
			[self->panel center];
			[self->panel makeKeyAndOrderFront:nil];
		}
	}
	return self;

}//end initWithProgress:window:


//========== observeValueForKeyPath:ofObject:change:context: ===================
//
// Purpose:		Moves the bar. After the downloads the catalog is built, which
//				reports no progress, so the bar spins.
//
//==============================================================================
- (void) observeValueForKeyPath:(NSString *)keyPath
					   ofObject:(id)object
						 change:(NSDictionary *)change
						context:(void *)context
{
	double fraction = [self->progress fractionCompleted];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self->indicator setDoubleValue:fraction];
		if(fraction >= 1.0)
		{
			[self->indicator setIndeterminate:YES];
			[self->indicator startAnimation:nil];
			[self->label setStringValue:NSLocalizedString(@"Building the parts catalog…", nil)];
		}
	});
}


//========== cancel: ===========================================================
//==============================================================================
- (void) cancel:(id)sender
{
	[self->progress cancel];
}


//========== close =============================================================
//==============================================================================
- (void) close
{
	[self->progress removeObserver:self forKeyPath:@"fractionCompleted"];

	if(self->parent != nil)
		[self->parent endSheet:self->panel];
	[self->panel orderOut:nil];
}

@end


@implementation PartsLimitManager
{
	PartsDataProgressPanel		*progressPanel;
	NSMutableArray				*waitingCompletions;	// of requests made while an update ran
	BOOL						 identityDataIsCurrent;	// the saved identity data was checked this launch
	BOOL						 isAskingToDownload;	// the first download's question is up
	LDrawPartLimit				*postedFrontLimit;		// the front limit last told about
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- sharedManager -------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (PartsLimitManager *) sharedManager
{
	static PartsLimitManager	*shared	= nil;
	static dispatch_once_t		 once	= 0;

	dispatch_once(&once, ^{
		shared = [[PartsLimitManager alloc] init];
	});
	return shared;
}


//========== init ==============================================================
//
// Purpose:		Sets up the data folder in Application Support, and the limit
//				saved in the defaults.
//
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self)
	{
		NSFileManager	*files			= [NSFileManager defaultManager];
		NSURL			*support		= [files URLForDirectory:NSApplicationSupportDirectory
														inDomain:NSUserDomainMask
											   appropriateForURL:nil
														  create:YES
														   error:NULL];
		NSURL			*bricksmith		= [support URLByAppendingPathComponent:@"Bricksmith" isDirectory:YES];
		NSURL			*folder			= [bricksmith URLByAppendingPathComponent:@"Parts Data" isDirectory:YES];
		NSURL			*rebrickable	= [folder URLByAppendingPathComponent:@"Rebrickable" isDirectory:YES];
		NSDictionary	*saved			= [[NSUserDefaults standardUserDefaults] dictionaryForKey:PARTS_LIMIT_KEY];

		self->_store	= [[LDrawInventoryStore alloc] initWithFolderURL:folder];
		self->_updater	= [[LDrawRebrickableUpdater alloc]
						   initWithDownloads:[[LDrawRebrickableDownloads alloc] initWithFolderURL:rebrickable]
									   store:self->_store];
		self->_session	= [[LDrawPartLimitSession alloc] initWithStore:self->_store];

		[self->_session setLimit:[LDrawPartLimit limitWithDictionary:saved]];
		self->waitingCompletions = [NSMutableArray array];
	}
	return self;

}//end init


//========== start =============================================================
//
// Purpose:		Follows the part library, and updates the data when it is due.
//
//==============================================================================
- (void) start
{
	NSInteger days = [[NSUserDefaults standardUserDefaults] integerForKey:PARTS_DATA_UPDATE_INTERVAL_KEY];

	[self updateIdentityDataIfNeeded];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(partLibraryDidChange:)
												 name:LDrawPartLibraryDidChangeNotification
											   object:nil];
	[self partLibraryDidChange:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateIdentityDataIfNeeded)
												 name:LDrawPartLimitDidChangeNotification
											   object:self.session];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(windowsDidChange:)
												 name:NSWindowDidBecomeMainNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(windowsDidChange:)
												 name:NSWindowWillCloseNotification
											   object:nil];
	[self applyMarkSettings];

	// Only data the user already asked for is kept up to date, quietly.
	if([self.updater isUpdateDueAfterDays:days])
	{
		[self.updater updateCatalogForcing:NO completion:^(BOOL changed, NSError *error) {
			if(error != nil)
				NSLog(@"Parts data update failed: %@", error);
			[self updateDidEndWithSuccess:(error == nil && [self.updater hasCatalog])];
		}];
	}

}//end start


#pragma mark -
#pragma mark THE LIMIT
#pragma mark -

//========== setLimit:document:window: =========================================
//
// Purpose:		Makes the limit the model's, kept with its file, and the
//				default for models with none of their own. Available Now needs
//				the catalog, so the first time it asks to download it.
//
//==============================================================================
- (void) setLimit:(LDrawPartLimit *)limit document:(LDrawDocument *)document window:(NSWindow *)window
{
	LDrawDocument *target = document ?: [self frontDocument];

	if(limit.kind == LDrawPartLimitKindAvailableNow && [self.updater hasCatalog] == NO)
	{
		[self updateDataForcing:NO window:window completion:^(BOOL success) {
			if(success)
				[self setLimit:limit document:target window:window];
		}];
		return;
	}

	[[target partsLimitController] setLimit:limit];
	[[NSUserDefaults standardUserDefaults] setObject:[limit dictionaryRepresentation] forKey:PARTS_LIMIT_KEY];
	[self.session setLimit:limit];
	[self frontLimitMayHaveChanged];

}//end setLimit:document:window:


//========== limitOfDocument: ==================================================
//
// Purpose:		The model's limit, or the default with no model.
//
//==============================================================================
- (LDrawPartLimit *) limitOfDocument:(LDrawDocument *)document
{
	return [[document partsLimitController] limit] ?: self.session.limit;
}


//========== frontDocument =====================================================
//
// Purpose:		The main window's model, or with another window main, such as
//				a panel, the model whose window is in front of the others'.
//
//==============================================================================
- (LDrawDocument *) frontDocument
{
	NSDocument *current = [[NSDocumentController sharedDocumentController] currentDocument];

	if([current isKindOfClass:[LDrawDocument class]])
		return (LDrawDocument *)current;

	for(NSDocument *document in [NSApp orderedDocuments])
	{
		if([document isKindOfClass:[LDrawDocument class]])
			return (LDrawDocument *)document;
	}
	return nil;

}//end frontDocument


//========== frontLimit ========================================================
//==============================================================================
- (LDrawPartLimit *) frontLimit
{
	return [self limitOfDocument:[self frontDocument]];
}


//========== frontRestrictingTable =============================================
//==============================================================================
- (LDrawPartLimitTable *) frontRestrictingTable
{
	return [self.session restrictingTableForLimit:[self frontLimit]];
}


//========== frontLimitMayHaveChanged ==========================================
//
// Purpose:		Tells the windows that follow the front model when its limit
//				is another than last time.
//
//==============================================================================
- (void) frontLimitMayHaveChanged
{
	LDrawPartLimit *limit = [self frontLimit];

	if([limit isEqual:self->postedFrontLimit])
		return;

	self->postedFrontLimit = limit;
	[self updateIdentityDataIfNeeded];
	[[NSNotificationCenter defaultCenter] postNotificationName:PartsLimitFrontLimitDidChangeNotification object:nil];

}//end frontLimitMayHaveChanged


//========== titleForLimit: ====================================================
//
// Purpose:		What the menus call a limit.
//
//==============================================================================
- (NSString *) titleForLimit:(LDrawPartLimit *)limit
{
	return [LDrawPartLimitPresentation titleForLimit:limit store:self.store];

}//end titleForLimit:


//========== populateLimitMenu:current:target: =================================
//
// Purpose:		Fills the menu with All Parts, Available Now, the sets and the
//				inventories, then Limit Options, for the target to choose. The
//				current limit has a check mark.
//
//==============================================================================
- (void) populateLimitMenu:(NSMenu *)menu current:(LDrawPartLimit *)current target:(id)target
{
	NSArray *limits = [self.session choosableLimitsWithOptionsOf:current];

	[menu removeAllItems];

	for(NSUInteger index = 0; index < [limits count]; index++)
	{
		LDrawPartLimit	*limit		= limits[index];
		LDrawPartLimit	*previous	= (index > 0) ? limits[index - 1] : nil;
		NSMenuItem		*item		= nil;

		// A line before the first inventory.
		if(limit.kind == LDrawPartLimitKindInventory && previous.kind != LDrawPartLimitKindInventory)
			[menu addItem:[NSMenuItem separatorItem]];

		item = [menu addItemWithTitle:[self titleForLimit:limit]
							   action:@selector(choosePartsLimit:)
						keyEquivalent:@""];
		[item setTarget:target];
		[item setRepresentedObject:limit];
		[item setState:[limit isEqual:current] ? NSControlStateValueOn : NSControlStateValueOff];
	}

	[menu addItem:[NSMenuItem separatorItem]];
	[[menu addItemWithTitle:NSLocalizedString(@"Limit Options…", nil)
					 action:@selector(showLimitOptions:)
			  keyEquivalent:@""] setTarget:target];

}//end populateLimitMenu:current:target:


//========== populatePullDownLimitMenu:current:target: =========================
//
// Purpose:		Fills a pull-down's menu the same way, keeping its first item,
//				which is the title.
//
//==============================================================================
- (void) populatePullDownLimitMenu:(NSMenu *)menu current:(LDrawPartLimit *)current target:(id)target
{
	NSMenuItem *titleItem = [menu itemAtIndex:0];

	[self populateLimitMenu:menu current:current target:target];
	[menu insertItem:titleItem atIndex:0];
}


#pragma mark -
#pragma mark THE MARKS
#pragma mark -

//========== applyMarkSettings =================================================
//
// Purpose:		Gives the drawing code the marks the settings ask for, and
//				redraws every model.
//
//==============================================================================
- (void) applyMarkSettings
{
	[LDrawPreferences applyPartsLimitMarksFromDefaults:[NSUserDefaults standardUserDefaults]];

	for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
	{
		if([document isKindOfClass:[LDrawDocument class]])
			[[(LDrawDocument *)document partsLimitController] redrawMarks];
	}

}//end applyMarkSettings


//---------- markColorForKey: ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSColor *) markColorForKey:(NSString *)key
{
	float rgb[3];

	[LDrawPreferences getPartsLimitMarkColor:rgb forKey:key inDefaults:[NSUserDefaults standardUserDefaults]];
	return [NSColor colorWithSRGBRed:rgb[0] green:rgb[1] blue:rgb[2] alpha:1.0];

}//end markColorForKey:


//---------- colorForBadgeTint: --------------------------------------[static]--
//
// Purpose:		The marks' colors from Settings, or gray for the rest.
//
//------------------------------------------------------------------------------
+ (NSColor *) colorForBadgeTint:(LDrawPartLimitBadgeTint)tint
{
	if(tint == LDrawPartLimitBadgeTintNotAvailable)
		return [self markColorForKey:PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY];
	if(tint == LDrawPartLimitBadgeTintTooMany)
		return [self markColorForKey:PARTS_LIMIT_TOO_MANY_COLOR_KEY];
	return [NSColor secondaryLabelColor];

}//end colorForBadgeTint:


#pragma mark -
#pragma mark THE DATA
#pragma mark -

//========== dataDate ==========================================================
//
// Purpose:		When the parts data was last checked with Rebrickable, or nil
//				when it never was.
//
//==============================================================================
- (NSDate *) dataDate
{
	return [self.updater lastCheckDate];
}


//---------- libraryHasPartTest --------------------------------------[static]--
//
// Purpose:		Answers whether the part library has a part, such as
//				"3001.dat".
//
//------------------------------------------------------------------------------
+ (BOOL (^)(NSString *partName)) libraryHasPartTest
{
	LDrawPartLibrary *library = [LDrawPartLibrary sharedPartLibrary];

	return ^BOOL(NSString *partName) {
		return [library categoryForPartName:partName] != nil;
	};

}//end libraryHasPartTest


//========== updateIdentityDataIfNeeded ========================================
//
// Purpose:		Brings the saved color links and rubber parts up to date with
//				the downloads, once a launch, when something uses them.
//
//==============================================================================
- (void) updateIdentityDataIfNeeded
{
	NSError *error = nil;

	if(self->identityDataIsCurrent || [self.session needsPartsData] == NO)
		return;

	self->identityDataIsCurrent = YES;
	if([self.updater updateIdentityData:&error] == NO)
		NSLog(@"Could not update the saved parts data: %@", error);

}//end updateIdentityDataIfNeeded


//========== updateDataForcing:window:completion: ==============================
//
// Purpose:		Updates the parts data, showing the progress. The first time,
//				it asks before downloading.
//
//==============================================================================
- (void) updateDataForcing:(BOOL)force window:(NSWindow *)window completion:(void (^)(BOOL success))completion
{
	NSAlert *alert = nil;

	// The update under way, or the question about it, answers this one too.
	if([self.updater isUpdating] || self->isAskingToDownload)
	{
		if(completion != nil)
			[self->waitingCompletions addObject:[completion copy]];
		return;
	}

	if([self.updater hasCatalog])
	{
		[self startUpdateForcing:force window:window completion:completion];
		return;
	}

	alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Download parts data from Rebrickable.com?", nil)];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
		@"Bricksmith needs the parts of every LEGO set to know which parts are made now and to import "
		@"sets. Rebrickable.com offers them free: %@, kept in Application Support and updated at most "
		@"once a day.", nil), DownloadSizeText]];
	[alert addButtonWithTitle:NSLocalizedString(@"Download", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

	void (^answer)(NSModalResponse) = ^(NSModalResponse response) {
		self->isAskingToDownload = NO;
		if(response == NSAlertFirstButtonReturn)
		{
			[self startUpdateForcing:force window:window completion:completion];
			return;
		}
		if(completion != nil)
			completion(NO);
		[self updateDidEndWithSuccess:NO];
	};

	self->isAskingToDownload = YES;
	if(window != nil)
		[alert beginSheetModalForWindow:window completionHandler:answer];
	else
		answer([alert runModal]);

}//end updateDataForcing:window:completion:


//========== startUpdateForcing:window:completion: =============================
//
// Purpose:		Updates the parts data, showing the progress on the window.
//
//==============================================================================
- (void) startUpdateForcing:(BOOL)force window:(NSWindow *)window completion:(void (^)(BOOL success))completion
{
	NSProgress *progress = [self.updater updateCatalogForcing:force completion:^(BOOL changed, NSError *error) {
		BOOL	canceled	= (		[[error domain] isEqualToString:LDrawRebrickableErrorDomain]
							   &&	[error code] == LDrawRebrickableErrorCanceled );
		BOOL	success		= (error == nil && [self.updater hasCatalog]);

		[self->progressPanel close];
		self->progressPanel = nil;

		if(error != nil && canceled == NO)
			[[NSAlert alertWithError:error] runModal];
		if(completion != nil)
			completion(success);
		[self updateDidEndWithSuccess:success];
	}];

	self->progressPanel = [[PartsDataProgressPanel alloc] initWithProgress:progress window:window];

}//end startUpdateForcing:window:completion:


//========== updateDidEndWithSuccess: ==========================================
//
// Purpose:		Answers the requests that came while the update ran, and tells
//				the windows that show the data.
//
//==============================================================================
- (void) updateDidEndWithSuccess:(BOOL)success
{
	NSArray *waiting = [self->waitingCompletions copy];

	[self->waitingCompletions removeAllObjects];
	for(void (^completion)(BOOL) in waiting)
		completion(success);

	[[NSNotificationCenter defaultCenter] postNotificationName:PartsDataUpdateDidEndNotification object:nil];

}//end updateDidEndWithSuccess:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== choosePartsLimit: =================================================
//
// Purpose:		A limit picked from View > Parts Limit, for the front model.
//				Its item carries the limit.
//
//==============================================================================
- (IBAction) choosePartsLimit:(id)sender
{
	LDrawPartLimit *limit = [sender representedObject];

	if([limit isKindOfClass:[LDrawPartLimit class]])
		[self setLimit:limit document:nil window:[NSApp mainWindow]];
}


//========== showLimitOptions: =================================================
//==============================================================================
- (IBAction) showLimitOptions:(id)sender
{
	LDrawDocument *document = [self frontDocument];

	[PartsLimitOptionsController showForDocument:document window:[document windowForSheet] ?: [NSApp mainWindow]];
}


//========== showInventories: ==================================================
//==============================================================================
- (IBAction) showInventories:(id)sender
{
	[[InventoriesWindowController sharedController] showWindow:sender];
}


//========== toggleLimitMarks: =================================================
//
// Purpose:		View > Parts Limit > Mark Limit Problems.
//
//==============================================================================
- (IBAction) toggleLimitMarks:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	[defaults setBool:([defaults boolForKey:PARTS_LIMIT_MARKS_KEY] == NO) forKey:PARTS_LIMIT_MARKS_KEY];
	[self applyMarkSettings];
	[[NSNotificationCenter defaultCenter] postNotificationName:PartsLimitMarksDidChangeNotification object:nil];

}//end toggleLimitMarks:


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//**** NSMenuDelegate ****
//========== menuNeedsUpdate: ==================================================
//
// Purpose:		Fills View > Parts Limit as it opens: the limits, with the
//				front model's checked, Limit Options, and Mark Limit Problems.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	NSMenuItem *marks = nil;

	[self populateLimitMenu:menu current:[self frontLimit] target:self];
	[menu addItem:[NSMenuItem separatorItem]];

	marks = [menu addItemWithTitle:NSLocalizedString(@"Mark Limit Problems", nil)
							action:@selector(toggleLimitMarks:)
					 keyEquivalent:@""];
	[marks setTarget:self];
	[marks setState:[[NSUserDefaults standardUserDefaults] boolForKey:PARTS_LIMIT_MARKS_KEY]];

}//end menuNeedsUpdate:


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== partLibraryDidChange: =============================================
//
// Purpose:		Gives the session the part library's records, whose keywords
//				link parts to Rebrickable, and the rubber colors.
//
// Notes:		The colors are read once, so they wait until a library has
//				loaded and the LDraw folder is known.
//
//==============================================================================
- (void) partLibraryDidChange:(NSNotification *)notification
{
	NSArray *records = [[LDrawPartLibrary sharedPartLibraryIfRegistered] allPartCatalogRecords];

	if([records count] > 0)
		[self.session setCatalogRecords:records
					   rubberColorCodes:[[LDrawColorLibrary sharedColorLibrary]
										 colorCodesWithMaterial:LDrawColorMaterialRubber]];

}//end partLibraryDidChange:


//========== windowsDidChange: =================================================
//
// Purpose:		Another window came in front, or one is closing. A closing
//				document leaves the list after this event, so the check waits.
//
//==============================================================================
- (void) windowsDidChange:(NSNotification *)notification
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(frontLimitMayHaveChanged) object:nil];
	[self performSelector:@selector(frontLimitMayHaveChanged) withObject:nil afterDelay:0];
}

@end
