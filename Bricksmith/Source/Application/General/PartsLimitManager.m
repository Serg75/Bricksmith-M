//==============================================================================
//
// File:		PartsLimitManager.m
//
// Purpose:		The app's one parts limit: where its data is kept, which limit
//				is chosen, and the menu every window shows it in.
//
// Notes:		The limit is an editor setting, kept in the defaults, never in
//				a model. The data lives in Application Support. The API key
//				lives in the Keychain.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "PartsLimitManager.h"

#import <Security/Security.h>

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawCombinedInventory.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawShortcutMap.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableClient.h>
#import <LDrawRebrickable/LDrawRebrickableColors.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import "ImportSetController.h"
#import "InventoriesWindowController.h"
#import "LDrawDocument.h"
#import "PartsLimitController.h"
#import "PartsLimitOptionsController.h"
#import "PreferencesForm.h"

NSString * const PartsLimitBrowserSettingDidChangeNotification = @"PartsLimitBrowserSettingDidChangeNotification";
NSString * const PartsLimitMarksDidChangeNotification = @"PartsLimitMarksDidChangeNotification";
NSString * const PartsDataUpdateDidEndNotification = @"PartsDataUpdateDidEndNotification";

static NSString * const KeychainService	= @"Bricksmith Rebrickable API Key";
static NSString * const KeychainAccount	= @"Rebrickable";

/// About how much the first download is, for the question before it.
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
// Purpose:		A small panel with a bar, a line of text and Cancel.
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
// Purpose:		Moves the bar. Past the downloads the catalog is built, which
//				has no steps of its own.
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
	LDrawRebrickableDownloads	*downloads;
	PartsDataProgressPanel		*progressPanel;
	NSArray						*partRecords;
	NSUInteger					 shortcutsGeneration;	// the newest read of the library's shortcuts
	BOOL						 shortcutsAreCurrent;	// a read of partRecords' shortcuts was started
	NSMutableArray				*waitingCompletions;	// asked for an update while one ran
	LDrawRebrickableClient		*sharedClient;			// one for the key, so calls keep a second apart
	BOOL						 isFetchingColors;
	NSString					*apiKeyRead;			// the Keychain's key, once read
	BOOL						 apiKeyWasRead;
	BOOL						 isAskingToDownload;	// the first download's question is up
}


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
// Purpose:		The data folder in Application Support, and the limit kept in
//				the defaults.
//
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self)
	{
		NSURL			*support	= [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
																		 inDomain:NSUserDomainMask
																appropriateForURL:nil
																		   create:YES
																			error:NULL];
		NSURL			*folder		= [[support URLByAppendingPathComponent:@"Bricksmith" isDirectory:YES]
									   URLByAppendingPathComponent:@"Parts Data" isDirectory:YES];
		NSDictionary	*saved		= [[NSUserDefaults standardUserDefaults] dictionaryForKey:PARTS_LIMIT_KEY];

		self->_store	= [[LDrawInventoryStore alloc] initWithFolderURL:folder];
		self->downloads	= [[LDrawRebrickableDownloads alloc] initWithFolderURL:
						   [folder URLByAppendingPathComponent:@"Rebrickable" isDirectory:YES]];
		self->_updater	= [[LDrawRebrickableUpdater alloc] initWithDownloads:self->downloads store:self->_store];
		self->_session	= [[LDrawPartLimitSession alloc] initWithStore:self->_store];

		[self->_session setLimit:[LDrawPartLimit limitWithDictionary:saved]];
	}
	return self;

}//end init


#pragma mark -
#pragma mark LAUNCH
#pragma mark -

//========== start =============================================================
//
// Purpose:		Follows the part library, and updates the data when it is due.
//
//==============================================================================
- (void) start
{
	NSInteger	 days		= [[NSUserDefaults standardUserDefaults] integerForKey:PARTS_DATA_UPDATE_INTERVAL_KEY];
	NSDate		*checked	= [self->downloads checkDateForFileNamed:@"inventory_parts"];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(partLibraryDidChange:)
												 name:LDrawPartLibraryDidChangeNotification
											   object:nil];
	[self partLibraryDidChange:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(readShortcutsIfNeeded)
												 name:LDrawPartLimitDidChangeNotification
											   object:self.session];
	[self applyMarkSettings];

	// Only data the user already asked for is kept up to date, quietly.
	if(		days > 0
	   &&	(checked == nil || -[checked timeIntervalSinceNow] > days * 24 * 60 * 60)
	   &&	[self.updater hasCatalog] )
	{
		[self.updater updateCatalogForcing:NO completion:^(BOOL changed, NSError *error) {
			if(error != nil)
				NSLog(@"Parts data update failed: %@", error);
			[self updateDidEndWithSuccess:(error == nil && [self.updater hasCatalog])];
		}];
	}

}//end start


//========== partLibraryDidChange: =============================================
//
// Purpose:		Gives the session the part library's records, whose keywords
//				link parts to Rebrickable, and then its shortcuts.
//
// Notes:		The library also posts this when favorites change, which leaves
//				the records as they were.
//
//==============================================================================
- (void) partLibraryDidChange:(NSNotification *)notification
{
	NSArray *records = [[LDrawPartLibrary sharedPartLibraryIfRegistered] allPartCatalogRecords];

	if([records count] > 0 && [records isEqualToArray:self->partRecords] == NO)
	{
		self->partRecords			= records;
		self->shortcutsAreCurrent	= NO;
		[self.session setCatalogRecords:records];
		[self readShortcutsIfNeeded];
	}

}//end partLibraryDidChange:


//========== readShortcutsIfNeeded =============================================
//
// Purpose:		Reads the library's shortcuts once something can use them: a
//				limit, a set or an inventory.
//
// Notes:		The read opens every part file, so it never runs for a user who
//				never limits parts.
//
//==============================================================================
- (void) readShortcutsIfNeeded
{
	LDrawInventoryStore *store = self.store;

	if(self->shortcutsAreCurrent || [self->partRecords count] == 0)
		return;
	if(		[self.session limit].kind == LDrawPartLimitKindNone
	   &&	[[store setNumbers] count] == 0
	   &&	[[store combinedInventories] count] == 0 )
		return;

	self->shortcutsAreCurrent = YES;
	[self readShortcutsOfRecords:self->partRecords];

}//end readShortcutsIfNeeded


//========== readShortcutsOfRecords: ===========================================
//
// Purpose:		Reads which parts are shortcuts on a background queue, since it
//				opens every part file, then gives the map to the session.
//
//==============================================================================
- (void) readShortcutsOfRecords:(NSArray<NSDictionary *> *)records
{
	NSUInteger generation = ++self->shortcutsGeneration;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSSet				*partNames	= [NSSet setWithArray:[records valueForKey:PART_NUMBER_KEY]];
		LDrawShortcutMap	*map		= [LDrawShortcutMap libraryMapWithPartNames:partNames];

		[map readPartsNamed:partNames];
		dispatch_async(dispatch_get_main_queue(), ^{
			// Drops this map when a newer read has started.
			if(generation == self->shortcutsGeneration)
				[self.session setShortcuts:map];
		});
	});

}//end readShortcutsOfRecords:


#pragma mark -
#pragma mark THE LIMIT
#pragma mark -

//========== setLimit:window: ==================================================
//
// Purpose:		Makes the limit the app's one, and keeps it in the defaults.
//				Available now needs the catalog, so the first time it asks to
//				download it.
//
//==============================================================================
- (void) setLimit:(LDrawPartLimit *)limit window:(NSWindow *)window
{
	if(limit.kind == LDrawPartLimitKindAvailableNow && [self.updater hasCatalog] == NO)
	{
		[self updateDataForcing:NO window:window completion:^(BOOL success) {
			if(success)
				[self setLimit:limit window:window];
		}];
		return;
	}

	[[NSUserDefaults standardUserDefaults] setObject:[limit dictionaryRepresentation] forKey:PARTS_LIMIT_KEY];
	[self.session setLimit:limit];

}//end setLimit:window:


//========== titleForLimit: ====================================================
//
// Purpose:		What the menus call a limit. Nil for an inventory the store
//				does not have.
//
//==============================================================================
- (NSString *) titleForLimit:(LDrawPartLimit *)limit
{
	switch(limit.kind)
	{
		case LDrawPartLimitKindNone:
			return NSLocalizedString(@"All Parts", nil);

		case LDrawPartLimitKindAvailableNow:
			return NSLocalizedString(@"Available Now", nil);

		case LDrawPartLimitKindInventory:
			return [self.store titleForInventoryIdentifier:limit.inventoryIdentifier];
	}
	return nil;

}//end titleForLimit:


//========== populateLimitMenu:commands: =======================================
//
// Purpose:		All Parts, Available Now, the inventories and the sets, then
//				the commands asked for. The limit in force has a check mark.
//
//==============================================================================
- (void) populateLimitMenu:(NSMenu *)menu commands:(PartsLimitMenuCommands)commands
{
	LDrawPartLimit	*current	= self.session.limit;
	NSMutableArray	*limits		= [NSMutableArray arrayWithObjects:[current limitWithKind:LDrawPartLimitKindNone
																	   inventoryIdentifier:nil],
								   [current limitWithKind:LDrawPartLimitKindAvailableNow inventoryIdentifier:nil], nil];
	NSUInteger		 fixedCount	= [limits count];

	[menu removeAllItems];

	for(LDrawCombinedInventory *inventory in [self.store combinedInventories])
		[limits addObject:[current limitWithKind:LDrawPartLimitKindInventory inventoryIdentifier:inventory.identifier]];
	for(NSString *setNumber in [self.store setNumbers])
		[limits addObject:[current limitWithKind:LDrawPartLimitKindInventory inventoryIdentifier:setNumber]];

	for(NSUInteger index = 0; index < [limits count]; index++)
	{
		LDrawPartLimit	*limit	= limits[index];
		NSMenuItem		*item	= nil;

		if(index == fixedCount)
			[menu addItem:[NSMenuItem separatorItem]];

		item = [menu addItemWithTitle:[self titleForLimit:limit] ?: @""
							   action:@selector(choosePartsLimit:)
						keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:limit];
		[item setState:[limit isEqual:current] ? NSControlStateValueOn : NSControlStateValueOff];
	}

	if(commands != PartsLimitMenuNoCommands)
		[menu addItem:[NSMenuItem separatorItem]];
	if(commands & PartsLimitMenuLimitOptions)
	{
		[[menu addItemWithTitle:NSLocalizedString(@"Limit Options…", nil)
						 action:@selector(showLimitOptions:)
				  keyEquivalent:@""] setTarget:self];
	}
	if(commands & PartsLimitMenuImportSetParts)
	{
		[[menu addItemWithTitle:NSLocalizedString(@"Import Set Parts…", nil)
						 action:@selector(importSetParts:)
				  keyEquivalent:@""] setTarget:self];
	}

}//end populateLimitMenu:commands:


//========== populatePullDownLimitMenu:commands: ===============================
//
// Purpose:		The same for a pull-down, whose first item is its title and
//				stays.
//
//==============================================================================
- (void) populatePullDownLimitMenu:(NSMenu *)menu commands:(PartsLimitMenuCommands)commands
{
	NSMenuItem *titleItem = [menu itemAtIndex:0];

	[self populateLimitMenu:menu commands:commands];
	[menu insertItem:titleItem atIndex:0];
}


//========== menuNeedsUpdate: ==================================================
//
// Purpose:		The View menu's Parts Limit submenu is filled when it opens. It
//				ends with the switch for the marks. Importing and the
//				inventories have their own items in the File and Window menus.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	NSMenuItem *marks = nil;

	[self populateLimitMenu:menu commands:PartsLimitMenuLimitOptions];
	[menu addItem:[NSMenuItem separatorItem]];

	marks = [menu addItemWithTitle:NSLocalizedString(@"Mark Limit Problems", nil)
							action:@selector(toggleLimitMarks:)
					 keyEquivalent:@""];
	[marks setTarget:self];
	[marks setState:[[NSUserDefaults standardUserDefaults] boolForKey:PARTS_LIMIT_MARKS_KEY]];

}//end menuNeedsUpdate:


#pragma mark -
#pragma mark THE MARKS
#pragma mark -

//========== applyMarkSettings =================================================
//
// Purpose:		Gives the drawing code the marks the settings ask for, and
//				redraws every model.
//
// Notes:		Only parts a check under a limit has seen dim, so with no limit
//				nothing does.
//
//==============================================================================
- (void) applyMarkSettings
{
	NSUserDefaults	*defaults		= [NSUserDefaults standardUserDefaults];
	BOOL			 marks			= [defaults boolForKey:PARTS_LIMIT_MARKS_KEY];
	BOOL			 dims			= [defaults boolForKey:PARTS_LIMIT_DIMS_OTHER_PARTS_KEY];
	NSInteger		 style			= [defaults integerForKey:PARTS_LIMIT_MARK_STYLE_KEY];
	NSColor			*notAvailable	= [PartsLimitManager markColorForKey:PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY];
	NSColor			*tooMany		= [PartsLimitManager markColorForKey:PARTS_LIMIT_TOO_MANY_COLOR_KEY];

	// Settings offer stripes, a tint or an outline.
	if(style != LDrawRenderMarkTint && style != LDrawRenderMarkOutline)
		style = LDrawRenderMarkStripes;

	[LDrawPart setLimitMarkStyle:marks ? style : LDrawRenderMarkNone];
	[LDrawPart setDimsAllowedParts:(marks && dims)];

	if(notAvailable != nil)
	{
		float rgb[3] = { notAvailable.redComponent, notAvailable.greenComponent, notAvailable.blueComponent };
		[LDrawPart setLimitMarkColor:rgb forStatus:LDrawPartLimitStatusNotAvailable];
	}
	if(tooMany != nil)
	{
		float rgb[3] = { tooMany.redComponent, tooMany.greenComponent, tooMany.blueComponent };
		[LDrawPart setLimitMarkColor:rgb forStatus:LDrawPartLimitStatusTooMany];
	}

	for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
	{
		if([document isKindOfClass:[LDrawDocument class]])
			[[(LDrawDocument *)document partsLimitController] redrawMarks];
	}

}//end applyMarkSettings


//---------- markColorForKey: ----------------------------------------[static]--
//
// Purpose:		A mark color kept as red, green and blue, or nil for anything
//				else.
//
//------------------------------------------------------------------------------
+ (NSColor *) markColorForKey:(NSString *)key
{
	NSArray *components = [[NSUserDefaults standardUserDefaults] arrayForKey:key];

	if([components count] != 3)
		return nil;
	for(id component in components)
	{
		if([component isKindOfClass:[NSNumber class]] == NO)
			return nil;
	}
	return [NSColor colorWithSRGBRed:[components[0] doubleValue]
							   green:[components[1] doubleValue]
								blue:[components[2] doubleValue]
							   alpha:1.0];

}//end markColorForKey:


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
	return [self.updater hasCatalog] ? [self->downloads checkDateForFileNamed:@"inventory_parts"] : nil;
}


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
		{
			if(self->waitingCompletions == nil)
				self->waitingCompletions = [NSMutableArray array];
			[self->waitingCompletions addObject:[completion copy]];
		}
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
		[self->progressPanel close];
		self->progressPanel = nil;

		BOOL cancelled = (		[[error domain] isEqualToString:LDrawRebrickableErrorDomain]
						  &&	[error code] == LDrawRebrickableErrorCancelled );

		if(error != nil && cancelled == NO)
			[[NSAlert alertWithError:error] runModal];
		if(completion != nil)
			completion(error == nil && [self.updater hasCatalog]);
		[self updateDidEndWithSuccess:(error == nil && [self.updater hasCatalog])];
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
	NSArray *waiting = self->waitingCompletions;

	self->waitingCompletions = nil;
	for(void (^completion)(BOOL) in waiting)
		completion(success);

	[[NSNotificationCenter defaultCenter] postNotificationName:PartsDataUpdateDidEndNotification object:nil];

	if(success)
		[self fetchColorLinksIfNeeded];

}//end updateDidEndWithSuccess:


//========== fetchColorLinksIfNeeded ===========================================
//
// Purpose:		With a key, fetches Rebrickable's own color links once. They
//				then win over the table that ships with the app.
//
//==============================================================================
- (void) fetchColorLinksIfNeeded
{
	LDrawRebrickableClient	*client	= [self client];
	NSURL					*folder	= [self->downloads folderURL];

	if(		client == nil
	   ||	self->isFetchingColors
	   ||	[LDrawRebrickableColors fetchedColorLinksInFolder:folder] != nil )
		return;

	self->isFetchingColors	= YES;
	client.completionQueue	= dispatch_get_main_queue();
	[LDrawRebrickableColors fetchColorLinksWithClient:client completion:^(NSDictionary *links, NSError *error) {
		NSDictionary	*data		= [self.store rebrickableIdentityData];
		NSError			*saveError	= nil;

		self->isFetchingColors = NO;
		if([links count] == 0)
		{
			NSLog(@"Could not fetch the colors from Rebrickable: %@", error);
			return;
		}

		// The catalog's next build reads the folder; one already built gets the links now.
		if(		[LDrawRebrickableColors saveFetchedColorLinks:links inFolder:folder error:&saveError]
		   &&	data != nil )
		{
			data = [LDrawPartIdentity rebrickableDataByUpdating:data
													  partLinks:nil
													 colorLinks:links
													  relations:nil
											   knownPartNumbers:nil];
			[self.store saveRebrickableIdentityData:data error:&saveError];
		}
		if(saveError != nil)
			NSLog(@"Could not keep the colors from Rebrickable: %@", saveError);
	}];

}//end fetchColorLinksIfNeeded


#pragma mark -
#pragma mark THE API KEY
#pragma mark -

//========== apiKey ============================================================
//==============================================================================
- (NSString *) apiKey
{
	NSDictionary	*query	= @{ (__bridge id)kSecClass			: (__bridge id)kSecClassGenericPassword,
								 (__bridge id)kSecAttrService	: KeychainService,
								 (__bridge id)kSecAttrAccount	: KeychainAccount,
								 (__bridge id)kSecReturnData	: @YES,
								 (__bridge id)kSecMatchLimit	: (__bridge id)kSecMatchLimitOne };
	CFTypeRef		 result	= NULL;

	if(self->apiKeyWasRead)
		return self->apiKeyRead;

	self->apiKeyWasRead = YES;
	if(SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == errSecSuccess && result != NULL)
	{
		NSData *data = (__bridge_transfer NSData *)result;
		self->apiKeyRead = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	}
	return self->apiKeyRead;

}//end apiKey


//========== setApiKey: ========================================================
//
// Purpose:		Keeps the key in the Keychain, or removes it for an empty one.
//
// Notes:		The old key is changed in place, so a failed save keeps it.
//
//==============================================================================
- (void) setApiKey:(NSString *)apiKey
{
	NSCharacterSet	*spaces		= [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString		*trimmed	= [apiKey stringByTrimmingCharactersInSet:spaces] ?: @"";
	NSDictionary	*query		= @{ (__bridge id)kSecClass			: (__bridge id)kSecClassGenericPassword,
									 (__bridge id)kSecAttrService	: KeychainService,
									 (__bridge id)kSecAttrAccount	: KeychainAccount };
	NSDictionary	*changes	= nil;
	OSStatus		 status		= errSecSuccess;

	if([trimmed isEqualToString:[self apiKey] ?: @""])
		return;

	if([trimmed length] == 0)
	{
		status = SecItemDelete((__bridge CFDictionaryRef)query);
		if(status == errSecItemNotFound)
			status = errSecSuccess;
	}
	else
	{
		changes	= @{ (__bridge id)kSecValueData : [trimmed dataUsingEncoding:NSUTF8StringEncoding] };
		status	= SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)changes);

		if(status == errSecItemNotFound)
		{
			NSMutableDictionary *item = [query mutableCopy];

			[item addEntriesFromDictionary:changes];
			status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
		}
	}

	if(status != errSecSuccess)
	{
		NSLog(@"Could not save the Rebrickable key in the Keychain: %d", (int)status);
		return;
	}

	self->apiKeyRead = ([trimmed length] > 0) ? trimmed : nil;
	if(self->apiKeyRead != nil)
		[self fetchColorLinksIfNeeded];

}//end setApiKey:


//========== client ============================================================
//
// Purpose:		A client with the user's key, or nil without one.
//
// Notes:		The same client while the key stays, since a client spaces only
//				its own calls.
//
//==============================================================================
- (LDrawRebrickableClient *) client
{
	NSString *key = [self apiKey];

	if([key length] == 0)
		return nil;
	if([self->sharedClient.apiKey isEqualToString:key] == NO)
		self->sharedClient = [[LDrawRebrickableClient alloc] initWithAPIKey:key];
	return self->sharedClient;
}


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== choosePartsLimit: =================================================
//
// Purpose:		A limit picked from a menu. Its item carries the limit.
//
//==============================================================================
- (IBAction) choosePartsLimit:(id)sender
{
	LDrawPartLimit *limit = [sender representedObject];

	if([limit isKindOfClass:[LDrawPartLimit class]])
		[self setLimit:limit window:[NSApp mainWindow]];
}


//========== showLimitOptions: =================================================
//==============================================================================
- (IBAction) showLimitOptions:(id)sender
{
	[PartsLimitOptionsController runWithLimit:self.session.limit
									   window:[NSApp mainWindow]
								   completion:^(LDrawPartLimit *limit) {
		if(limit != nil)
			[self setLimit:limit window:[NSApp mainWindow]];
	}];
}


//========== importSetParts: ===================================================
//==============================================================================
- (IBAction) importSetParts:(id)sender
{
	[ImportSetController runWithWindow:[NSApp mainWindow]];
}


//========== showInventories: ==================================================
//==============================================================================
- (IBAction) showInventories:(id)sender
{
	[[InventoriesWindowController sharedController] showWindow:sender];
}

@end
