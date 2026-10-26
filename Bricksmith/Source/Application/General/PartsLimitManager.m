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
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawCombinedInventory.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableClient.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import "ImportSetController.h"
#import "InventoriesWindowController.h"
#import "PartsLimitOptionsController.h"

NSString * const PartsLimitBrowserSettingDidChangeNotification = @"PartsLimitBrowserSettingDidChangeNotification";

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
		[stack setEdgeInsets:NSEdgeInsetsMake(20, 20, 20, 20)];
		[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
		[[self->indicator widthAnchor] constraintEqualToConstant:340].active = YES;
		[[self->label leadingAnchor] constraintEqualToAnchor:[self->indicator leadingAnchor]].active = YES;
		[self->panel setContentView:stack];

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

	// Only data the user already asked for is kept up to date, quietly.
	if(		days > 0
	   &&	[self.updater hasCatalog]
	   &&	(checked == nil || -[checked timeIntervalSinceNow] > days * 24 * 60 * 60) )
	{
		[self.updater updateCatalogForcing:NO completion:^(BOOL changed, NSError *error) {
			if(error != nil)
				NSLog(@"Parts data update failed: %@", error);
		}];
	}

}//end start


//========== partLibraryDidChange: =============================================
//
// Purpose:		Gives the session the part library's records, whose keywords
//				link parts to Rebrickable.
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
		self->partRecords = records;
		[self.session setCatalogRecords:records];
	}

}//end partLibraryDidChange:


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
		{
			NSString				*identifier	= limit.inventoryIdentifier;
			LDrawCombinedInventory	*inventory	= [self.store combinedInventoryWithIdentifier:identifier];
			LDrawSetInventory		*set		= [self.store setInventoryForNumber:identifier];

			if(inventory != nil)
				return inventory.name;
			if(set != nil)
				return [NSString stringWithFormat:@"%@ %@", set.setNumber, set.name];
			return nil;
		}
	}
	return nil;

}//end titleForLimit:


//========== populateLimitMenu: ================================================
//
// Purpose:		All Parts, Available Now, the inventories and the sets, then
//				the commands. The limit in force has a check mark.
//
//==============================================================================
- (void) populateLimitMenu:(NSMenu *)menu
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

	[menu addItem:[NSMenuItem separatorItem]];
	[[menu addItemWithTitle:NSLocalizedString(@"Limit Options…", nil)
					 action:@selector(showLimitOptions:)
			  keyEquivalent:@""] setTarget:self];
	[[menu addItemWithTitle:NSLocalizedString(@"Import Set Parts…", nil)
					 action:@selector(importSetParts:)
			  keyEquivalent:@""] setTarget:self];
	[[menu addItemWithTitle:NSLocalizedString(@"Manage Inventories…", nil)
					 action:@selector(showInventories:)
			  keyEquivalent:@""] setTarget:self];

}//end populateLimitMenu:


//========== menuNeedsUpdate: ==================================================
//
// Purpose:		The View menu's Parts Limit submenu is filled when it opens.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	[self populateLimitMenu:menu];
}


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
	if([self.updater isUpdating])
		return;

	if([self.updater hasCatalog] == NO)
	{
		NSAlert *alert = [[NSAlert alloc] init];

		[alert setMessageText:NSLocalizedString(@"Download parts data from Rebrickable.com?", nil)];
		[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
			@"Bricksmith needs the parts of every LEGO set to know which parts are made now and to import "
			@"sets. Rebrickable.com offers them free: %@, kept in Application Support and updated at most "
			@"once a day.", nil), DownloadSizeText]];
		[alert addButtonWithTitle:NSLocalizedString(@"Download", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

		if([alert runModal] != NSAlertFirstButtonReturn)
		{
			if(completion != nil)
				completion(NO);
			return;
		}
	}

	NSProgress *progress = [self.updater updateCatalogForcing:force completion:^(BOOL changed, NSError *error) {
		[self->progressPanel close];
		self->progressPanel = nil;

		BOOL cancelled = (		[[error domain] isEqualToString:LDrawRebrickableErrorDomain]
						  &&	[error code] == LDrawRebrickableErrorCancelled );

		if(error != nil && cancelled == NO)
			[[NSAlert alertWithError:error] runModal];
		if(completion != nil)
			completion(error == nil && [self.updater hasCatalog]);
	}];

	self->progressPanel = [[PartsDataProgressPanel alloc] initWithProgress:progress window:window];

}//end updateDataForcing:window:completion:


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

	if(SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || result == NULL)
		return nil;

	NSData *data = (__bridge_transfer NSData *)result;
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

}//end apiKey


//========== setApiKey: ========================================================
//
// Purpose:		Keeps the key in the Keychain, or removes it for an empty one.
//
//==============================================================================
- (void) setApiKey:(NSString *)apiKey
{
	NSCharacterSet	*spaces		= [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString		*trimmed	= [apiKey stringByTrimmingCharactersInSet:spaces];
	NSDictionary	*query		= @{ (__bridge id)kSecClass			: (__bridge id)kSecClassGenericPassword,
									 (__bridge id)kSecAttrService	: KeychainService,
									 (__bridge id)kSecAttrAccount	: KeychainAccount };

	SecItemDelete((__bridge CFDictionaryRef)query);

	if([trimmed length] > 0)
	{
		NSMutableDictionary *item = [query mutableCopy];

		item[(__bridge id)kSecValueData] = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
		SecItemAdd((__bridge CFDictionaryRef)item, NULL);
	}

}//end setApiKey:


//========== client ============================================================
//
// Purpose:		A client with the user's key, or nil without one.
//
//==============================================================================
- (LDrawRebrickableClient *) client
{
	NSString *key = [self apiKey];
	return ([key length] > 0) ? [[LDrawRebrickableClient alloc] initWithAPIKey:key] : nil;
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
