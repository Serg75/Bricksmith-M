//==============================================================================
//
// File:		InventoriesWindowController.m
//
// Purpose:		The Inventories window: the imported sets, and the inventories
//				made of sets and loose parts.
//
// Notes:		The list is on the left, the selected set or inventory on the
//				right. Every change is saved in the store at once, and the
//				window follows the store.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "InventoriesWindowController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawCombinedInventory.h>
#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawInventoryPartsFile.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import "ImportSetController.h"
#import "PartsLimitManager.h"

// Kinds of rows in the list.
static NSString * const RowKindGroup		= @"group";
static NSString * const RowKindSet			= @"set";
static NSString * const RowKindInventory	= @"inventory";

static const CGFloat SidebarWidth	= 240;
static const CGFloat DetailInset	= 20;


@implementation InventoriesWindowController
{
	NSTableView						*sourceList;
	NSView							*detailView;
	NSArray<NSDictionary *>			*rows;				// kind, identifier, title
	NSString						*selectedKind;
	NSString						*selectedIdentifier;

	// The inventory shown
	NSTableView						*setCountsTable;
	NSArray<NSString *>				*setCountNumbers;	// its sets, in number order
}


//---------- sharedController ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (InventoriesWindowController *) sharedController
{
	static InventoriesWindowController	*shared	= nil;
	static dispatch_once_t				 once	= 0;

	dispatch_once(&once, ^{
		shared = [[InventoriesWindowController alloc] init];
	});
	return shared;
}


//========== init ==============================================================
//
// Purpose:		Builds the window: the list and the detail beside it.
//
//==============================================================================
- (instancetype) init
{
	NSWindowStyleMask	 styleMask	= (  NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
									   | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable);
	NSWindow			*window		= [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 480)
																styleMask:styleMask
																  backing:NSBackingStoreBuffered
																	defer:YES];

	self = [super initWithWindow:window];
	if (self)
	{
		NSSplitViewController	*split		= [[NSSplitViewController alloc] init];
		NSViewController		*sidebar	= [[NSViewController alloc] init];
		NSViewController		*detail		= [[NSViewController alloc] init];
		NSSplitViewItem			*item		= nil;

		self->detailView = [[NSView alloc] init];
		[sidebar setView:[self makeSidebar]];
		[detail setView:self->detailView];

		item = [NSSplitViewItem sidebarWithViewController:sidebar];
		[item setCanCollapse:NO];
		[item setMinimumThickness:SidebarWidth];
		[split addSplitViewItem:item];

		item = [NSSplitViewItem splitViewItemWithViewController:detail];
		[item setMinimumThickness:420];
		[split addSplitViewItem:item];

		[window setTitle:NSLocalizedString(@"Inventories", nil)];
		[window setContentViewController:split];
		[window setContentMinSize:NSMakeSize(680, 380)];
		[window setReleasedWhenClosed:NO];
		[window setTabbingMode:NSWindowTabbingModeDisallowed];
		if([window setFrameUsingName:@"InventoriesWindow"] == NO)
			[window center];
		[window setFrameAutosaveName:@"InventoriesWindow"];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(storeDidChange:)
													 name:LDrawInventoryStoreDidChangeNotification
												   object:[[PartsLimitManager sharedManager] store]];
		[self reloadRows];
	}
	return self;

}//end init


//========== makeSidebar =======================================================
//
// Purpose:		The list of sets and inventories, with Add and Remove under it.
//
//==============================================================================
- (NSView *) makeSidebar
{
	NSView			*view		= [[NSView alloc] init];
	NSScrollView	*scrollView	= [[NSScrollView alloc] init];
	NSPopUpButton	*addButton	= [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
	NSButton		*remove		= [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameRemoveTemplate]
													target:self
													action:@selector(removeSelection:)];
	NSStackView		*bar		= nil;

	sourceList = [[NSTableView alloc] init];
	[sourceList setStyle:NSTableViewStyleSourceList];
	[sourceList setHeaderView:nil];
	[sourceList addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"Name"]];
	[sourceList setDataSource:self];
	[sourceList setDelegate:self];

	[scrollView setDocumentView:sourceList];
	[scrollView setDrawsBackground:NO];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setAutohidesScrollers:YES];
	[scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];

	[addButton setBezelStyle:NSBezelStyleSmallSquare];
	[addButton setBordered:NO];
	[addButton addItemWithTitle:@""];
	[[addButton itemAtIndex:0] setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
	[[[addButton menu] addItemWithTitle:NSLocalizedString(@"Import Set Parts…", nil)
								 action:@selector(importSet:)
						  keyEquivalent:@""] setTarget:self];
	[[[addButton menu] addItemWithTitle:NSLocalizedString(@"New Inventory", nil)
								 action:@selector(newInventory:)
						  keyEquivalent:@""] setTarget:self];
	[[addButton cell] setArrowPosition:NSPopUpNoArrow];
	[remove setBezelStyle:NSBezelStyleSmallSquare];
	[remove setBordered:NO];
	[remove setImageScaling:NSImageScaleNone];
	for(NSView *button in @[addButton, remove])
	{
		[[button widthAnchor] constraintEqualToConstant:28].active = YES;
		[[button heightAnchor] constraintEqualToConstant:22].active = YES;
	}

	bar = [NSStackView stackViewWithViews:@[addButton, remove]];
	[bar setSpacing:0];
	[bar setEdgeInsets:NSEdgeInsetsMake(4, 8, 4, 8)];
	[bar setTranslatesAutoresizingMaskIntoConstraints:NO];

	[view addSubview:scrollView];
	[view addSubview:bar];
	[NSLayoutConstraint activateConstraints:@[
		[[scrollView leadingAnchor] constraintEqualToAnchor:[view leadingAnchor]],
		[[scrollView trailingAnchor] constraintEqualToAnchor:[view trailingAnchor]],
		[[scrollView topAnchor] constraintEqualToAnchor:[view topAnchor]],
		[[scrollView bottomAnchor] constraintEqualToAnchor:[bar topAnchor]],
		[[bar leadingAnchor] constraintEqualToAnchor:[view leadingAnchor]],
		[[bar bottomAnchor] constraintEqualToAnchor:[view bottomAnchor]],
	]];

	return view;

}//end makeSidebar


#pragma mark -
#pragma mark THE LIST
#pragma mark -

//========== reloadRows ========================================================
//
// Purpose:		Lists the store's sets and inventories, and keeps the
//				selection when it is still there.
//
//==============================================================================
- (void) reloadRows
{
	LDrawInventoryStore	*store		= [[PartsLimitManager sharedManager] store];
	NSMutableArray		*newRows	= [NSMutableArray array];
	NSUInteger			 selected	= NSNotFound;

	[newRows addObject:@{@"kind": RowKindGroup, @"title": NSLocalizedString(@"Sets", nil)}];
	for(NSString *number in [store setNumbers])
	{
		LDrawSetInventory *set = [store setInventoryForNumber:number];
		NSString *title = (set != nil) ? [NSString stringWithFormat:@"%@ %@", number, set.name] : number;

		[newRows addObject:@{@"kind": RowKindSet, @"identifier": number, @"title": title}];
	}

	[newRows addObject:@{@"kind": RowKindGroup, @"title": NSLocalizedString(@"Inventories", nil)}];
	for(LDrawCombinedInventory *inventory in [store combinedInventories])
	{
		[newRows addObject:@{@"kind": RowKindInventory,
							 @"identifier": inventory.identifier,
							 @"title": inventory.name}];
	}

	rows = newRows;
	[sourceList reloadData];

	for(NSUInteger index = 0; index < [rows count]; index++)
	{
		if(		[rows[index][@"kind"] isEqualToString:selectedKind ?: @""]
		   &&	[rows[index][@"identifier"] isEqualToString:selectedIdentifier ?: @""] )
			selected = index;
	}

	if(selected != NSNotFound)
		[sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:selected] byExtendingSelection:NO];
	else
	{
		selectedKind		= nil;
		selectedIdentifier	= nil;
	}
	[self showDetail];

}//end reloadRows


//========== selectKind:identifier: ============================================
//==============================================================================
- (void) selectKind:(NSString *)kind identifier:(NSString *)identifier
{
	selectedKind		= kind;
	selectedIdentifier	= identifier;
	[self reloadRows];
}


//**** NSTableViewDataSource ****
//========== numberOfRowsInTableView: ==========================================
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	if(tableView == setCountsTable)
		return [setCountNumbers count];
	return [rows count];
}


//**** NSTableViewDelegate ****
//========== tableView:isGroupRow: =============================================
//==============================================================================
- (BOOL) tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	return (tableView == sourceList && [rows[row][@"kind"] isEqualToString:RowKindGroup]);
}


//**** NSTableViewDelegate ****
//========== tableView:shouldSelectRow: ========================================
//==============================================================================
- (BOOL) tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	return ([self tableView:tableView isGroupRow:row] == NO);
}


//**** NSTableViewDelegate ****
//========== tableView:viewForTableColumn:row: =================================
//==============================================================================
- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if(tableView == setCountsTable)
		return [self setCountsViewForColumn:column row:row];

	NSDictionary	*entry	= rows[row];
	NSTableCellView	*cell	= [tableView makeViewWithIdentifier:@"Cell" owner:self];

	if(cell == nil)
	{
		NSImageView	*imageView	= [[NSImageView alloc] init];
		NSTextField	*textField	= [NSTextField labelWithString:@""];

		cell = [[NSTableCellView alloc] init];
		[cell setIdentifier:@"Cell"];
		[imageView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[textField setTranslatesAutoresizingMaskIntoConstraints:NO];
		[textField setLineBreakMode:NSLineBreakByTruncatingTail];
		[cell addSubview:imageView];
		[cell addSubview:textField];
		[cell setImageView:imageView];
		[cell setTextField:textField];
		[NSLayoutConstraint activateConstraints:@[
			[[imageView leadingAnchor] constraintEqualToAnchor:[cell leadingAnchor] constant:2],
			[[imageView centerYAnchor] constraintEqualToAnchor:[cell centerYAnchor]],
			[[imageView widthAnchor] constraintEqualToConstant:18],
			[[textField leadingAnchor] constraintEqualToAnchor:[imageView trailingAnchor] constant:6],
			[[textField trailingAnchor] constraintLessThanOrEqualToAnchor:[cell trailingAnchor] constant:-2],
			[[textField centerYAnchor] constraintEqualToAnchor:[cell centerYAnchor]],
		]];
	}

	NSString *symbol = nil;
	if([entry[@"kind"] isEqualToString:RowKindSet])
		symbol = @"shippingbox";
	else if([entry[@"kind"] isEqualToString:RowKindInventory])
		symbol = @"tray.2";

	[[cell textField] setStringValue:entry[@"title"]];
	[[cell imageView] setImage:(symbol != nil) ? [NSImage imageWithSystemSymbolName:symbol
															accessibilityDescription:nil] : nil];
	[[cell imageView] setHidden:(symbol == nil)];

	return cell;

}//end tableView:viewForTableColumn:row:


//**** NSTableViewDelegate ****
//========== tableViewSelectionDidChange: ======================================
//==============================================================================
- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [sourceList selectedRow];

	if([notification object] != sourceList)
		return;

	selectedKind		= (row >= 0) ? rows[row][@"kind"] : nil;
	selectedIdentifier	= (row >= 0) ? rows[row][@"identifier"] : nil;
	[self showDetail];

}//end tableViewSelectionDidChange:


#pragma mark -
#pragma mark THE DETAIL
#pragma mark -

//========== showDetail ========================================================
//
// Purpose:		Builds the right side for what is selected.
//
//==============================================================================
- (void) showDetail
{
	LDrawInventoryStore	*store		= [[PartsLimitManager sharedManager] store];
	NSView				*content	= nil;

	setCountsTable	= nil;
	setCountNumbers	= nil;

	if([selectedKind isEqualToString:RowKindSet])
		content = [self viewForSet:[store setInventoryForNumber:selectedIdentifier]];
	else if([selectedKind isEqualToString:RowKindInventory])
		content = [self viewForInventory:[store combinedInventoryWithIdentifier:selectedIdentifier]];

	if(content == nil)
	{
		NSString *text = NSLocalizedString(@"Import a set, or make an inventory of several sets and loose parts. "
										   @"Either can be the parts limit.", nil);
		content = [NSTextField wrappingLabelWithString:text];
		[(NSTextField *)content setTextColor:[NSColor secondaryLabelColor]];
	}

	[[detailView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	[content setTranslatesAutoresizingMaskIntoConstraints:NO];
	[detailView addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[[content leadingAnchor] constraintEqualToAnchor:[detailView leadingAnchor] constant:DetailInset],
		[[content trailingAnchor] constraintEqualToAnchor:[detailView trailingAnchor] constant:-DetailInset],
		[[content topAnchor] constraintEqualToAnchor:[detailView topAnchor] constant:DetailInset],
		[[content bottomAnchor] constraintLessThanOrEqualToAnchor:[detailView bottomAnchor] constant:-DetailInset],
	]];

}//end showDetail


//========== viewForSet: =======================================================
//
// Purpose:		A set's name, year, theme, part count and where it came from,
//				with Use as Limit and Refresh.
//
//==============================================================================
- (NSView *) viewForSet:(LDrawSetInventory *)set
{
	NSTextField		*title		= nil;
	NSGridView		*grid		= nil;
	NSString		*parts		= nil;
	NSString		*fetched	= @"";
	NSString		*source		= NSLocalizedString(@"Rebrickable downloads", nil);
	NSStackView		*buttons	= nil;

	if(set == nil)
		return nil;

	if([set.source isEqualToString:@"rebrickable-api"])
		source = NSLocalizedString(@"Rebrickable API", nil);

	if(set.fetchDate != nil)
		fetched = [NSDateFormatter localizedStringFromDate:set.fetchDate
												 dateStyle:NSDateFormatterMediumStyle
												 timeStyle:NSDateFormatterNoStyle];

	parts = [NSString localizedStringWithFormat:NSLocalizedString(@"%lu, and %lu spares", nil),
			 (unsigned long)set.partCount, (unsigned long)set.spareCount];

	title = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"%@ %@", set.setNumber, set.name]];
	[title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]];

	grid = [self gridWithRows:@[
		@[NSLocalizedString(@"Year", nil), [NSString stringWithFormat:@"%ld", (long)set.year]],
		@[NSLocalizedString(@"Theme", nil), set.themeName ?: @"—"],
		@[NSLocalizedString(@"Parts", nil), parts],
		@[NSLocalizedString(@"Imported", nil), [NSString stringWithFormat:@"%@ · %@", fetched, source]],
	]];

	buttons = [NSStackView stackViewWithViews:@[
		[NSButton buttonWithTitle:NSLocalizedString(@"Use as Limit", nil) target:self action:@selector(useAsLimit:)],
		[NSButton buttonWithTitle:NSLocalizedString(@"Refresh", nil) target:self action:@selector(refreshSet:)],
	]];

	return [self stackWithViews:@[title, grid, buttons]];

}//end viewForSet:


//========== viewForInventory: =================================================
//
// Purpose:		An inventory's name, its sets with a count each, its loose
//				parts, and Use as Limit.
//
//==============================================================================
- (NSView *) viewForInventory:(LDrawCombinedInventory *)inventory
{
	LDrawInventoryStore	*store			= [[PartsLimitManager sharedManager] store];
	NSTextField			*nameField		= nil;
	NSScrollView		*scrollView		= [[NSScrollView alloc] init];
	NSPopUpButton		*addSet			= [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
	NSButton			*removeSet		= nil;
	NSUInteger			 looseTotal		= 0;
	NSString			*looseText		= nil;
	NSArray				*columns		= @[@[@"number", NSLocalizedString(@"Set", nil), @90],
											@[@"name", NSLocalizedString(@"Name", nil), @220],
											@[@"count", NSLocalizedString(@"Count", nil), @60]];

	if(inventory == nil)
		return nil;

	nameField = [NSTextField textFieldWithString:inventory.name];
	[nameField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]];
	[nameField setTarget:self];
	[nameField setAction:@selector(renameInventory:)];
	[[nameField widthAnchor] constraintGreaterThanOrEqualToConstant:260].active = YES;

	// The sets
	setCountNumbers = [[inventory.setCounts allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	setCountsTable	= [[NSTableView alloc] init];
	for(NSArray *spec in columns)
	{
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
		[[column headerCell] setStringValue:spec[1]];
		[column setWidth:[spec[2] doubleValue]];
		[setCountsTable addTableColumn:column];
	}
	[setCountsTable setUsesAlternatingRowBackgroundColors:YES];
	[setCountsTable setDataSource:self];
	[setCountsTable setDelegate:self];
	[scrollView setDocumentView:setCountsTable];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setBorderType:NSBezelBorder];
	[[scrollView heightAnchor] constraintEqualToConstant:160].active = YES;
	[[scrollView widthAnchor] constraintGreaterThanOrEqualToConstant:400].active = YES;

	[addSet addItemWithTitle:NSLocalizedString(@"Add Set", nil)];
	for(NSString *number in [store setNumbers])
	{
		NSMenuItem *item = nil;

		if(inventory.setCounts[number] != nil)
			continue;
		item = [[addSet menu] addItemWithTitle:number action:@selector(addSetToInventory:) keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:number];
	}
	[addSet setEnabled:([addSet numberOfItems] > 1)];
	removeSet = [NSButton buttonWithTitle:NSLocalizedString(@"Remove Set", nil)
								   target:self
								   action:@selector(removeSetFromInventory:)];

	// The loose parts
	for(LDrawInventoryItem *item in inventory.looseItems)
		looseTotal += item.quantity + item.spareQuantity;

	if([inventory.looseItems count] > 0)
		looseText = [NSString localizedStringWithFormat:NSLocalizedString(@"%lu parts in %lu kinds", nil),
					 (unsigned long)looseTotal, (unsigned long)[inventory.looseItems count]];
	else
		looseText = NSLocalizedString(@"None", nil);

	NSStackView *setButtons		= [NSStackView stackViewWithViews:@[addSet, removeSet]];
	NSStackView *looseButtons	= [NSStackView stackViewWithViews:@[
		[NSButton buttonWithTitle:NSLocalizedString(@"Add Parts from File…", nil)
						   target:self
						   action:@selector(addPartsFromFile:)],
		[NSButton buttonWithTitle:NSLocalizedString(@"Remove Loose Parts", nil)
						   target:self
						   action:@selector(removeLooseParts:)],
	]];
	NSButton	*useAsLimit		= [NSButton buttonWithTitle:NSLocalizedString(@"Use as Limit", nil)
												target:self
												action:@selector(useAsLimit:)];

	return [self stackWithViews:@[nameField,
								  [self headingWithString:NSLocalizedString(@"Sets", nil)], scrollView, setButtons,
								  [self headingWithString:NSLocalizedString(@"Loose Parts", nil)],
								  [NSTextField labelWithString:looseText], looseButtons,
								  useAsLimit]];

}//end viewForInventory:


//========== setCountsViewForColumn:row: =======================================
//
// Purpose:		A cell of the inventory's set table. The count can be typed.
//
//==============================================================================
- (NSView *) setCountsViewForColumn:(NSTableColumn *)column row:(NSInteger)row
{
	LDrawInventoryStore		*store		= [[PartsLimitManager sharedManager] store];
	LDrawCombinedInventory	*inventory	= [store combinedInventoryWithIdentifier:selectedIdentifier];
	NSString				*number		= setCountNumbers[row];
	NSString				*identifier	= [column identifier];
	NSTextField				*cell		= nil;

	if([identifier isEqualToString:@"count"])
	{
		NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];

		[formatter setMinimum:@1];
		[formatter setAllowsFloats:NO];
		cell = [NSTextField textFieldWithString:[inventory.setCounts[number] stringValue] ?: @"1"];
		[cell setFormatter:formatter];
		[cell setBordered:NO];
		[cell setDrawsBackground:NO];
		[cell setAlignment:NSTextAlignmentRight];
		[cell setTag:row];
		[cell setTarget:self];
		[cell setAction:@selector(setCountChanged:)];
		return cell;
	}

	if([identifier isEqualToString:@"number"])
		cell = [NSTextField labelWithString:number];
	else
		cell = [NSTextField labelWithString:[store setInventoryForNumber:number].name
											?: NSLocalizedString(@"Not imported", nil)];
	[cell setLineBreakMode:NSLineBreakByTruncatingTail];
	return cell;

}//end setCountsViewForColumn:row:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== importSet: ========================================================
//==============================================================================
- (IBAction) importSet:(id)sender
{
	[ImportSetController runWithWindow:[self window]];
}


//========== newInventory: =====================================================
//
// Purpose:		Makes an empty inventory and selects it, with its name ready to
//				be typed.
//
//==============================================================================
- (IBAction) newInventory:(id)sender
{
	LDrawCombinedInventory	*inventory	= [LDrawCombinedInventory inventoryWithName:
										   NSLocalizedString(@"New Inventory", nil)];

	if([self saveInventory:inventory])
		[self selectKind:RowKindInventory identifier:inventory.identifier];

}//end newInventory:


//========== removeSelection: ==================================================
//
// Purpose:		Removes the selected set or inventory, once the user agrees.
//
//==============================================================================
- (IBAction) removeSelection:(id)sender
{
	LDrawInventoryStore	*store		= [[PartsLimitManager sharedManager] store];
	NSInteger			 row		= [sourceList selectedRow];
	NSAlert				*alert		= [[NSAlert alloc] init];
	BOOL				 isSet		= [selectedKind isEqualToString:RowKindSet];
	NSString			*identifier	= selectedIdentifier;

	if(row < 0 || identifier == nil)
		return;

	[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"Remove “%@”?", nil), rows[row][@"title"]]];
	[alert setInformativeText:isSet ? NSLocalizedString(@"Inventories that hold the set lose its parts.", nil)
									: NSLocalizedString(@"Its sets stay imported.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Remove", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

	[alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
		NSError *error = nil;

		if(response != NSAlertFirstButtonReturn)
			return;

		if(isSet)
			[store removeSetInventoryForNumber:identifier error:&error];
		else
			[store removeCombinedInventoryWithIdentifier:identifier error:&error];
		[self showError:error];
	}];

}//end removeSelection:


//========== useAsLimit: =======================================================
//==============================================================================
- (IBAction) useAsLimit:(id)sender
{
	PartsLimitManager	*manager	= [PartsLimitManager sharedManager];
	LDrawPartLimit		*limit		= [[[manager session] limit] limitWithKind:LDrawPartLimitKindInventory
														 inventoryIdentifier:selectedIdentifier];

	[manager setLimit:limit window:[self window]];

}//end useAsLimit:


//========== refreshSet: =======================================================
//
// Purpose:		Imports the selected set again, for Rebrickable's corrections.
//
//==============================================================================
- (IBAction) refreshSet:(id)sender
{
	PartsLimitManager *manager = [PartsLimitManager sharedManager];

	[sender setEnabled:NO];
	[[manager updater] importSetNumber:selectedIdentifier
								client:[manager client]
							completion:^(LDrawSetInventory *set, NSError *error) {
		[sender setEnabled:YES];
		[self showError:error];
	}];

}//end refreshSet:


//========== renameInventory: ==================================================
//==============================================================================
- (IBAction) renameInventory:(id)sender
{
	LDrawCombinedInventory	*inventory	= [self selectedInventory];
	NSString				*name		= [[sender stringValue] stringByTrimmingCharactersInSet:
										   [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if(inventory == nil || [name length] == 0 || [name isEqualToString:inventory.name])
		return;

	[self saveInventory:[inventory inventoryByRenamingTo:name]];

}//end renameInventory:


//========== addSetToInventory: ================================================
//==============================================================================
- (IBAction) addSetToInventory:(id)sender
{
	LDrawCombinedInventory	*inventory	= [self selectedInventory];
	NSMutableDictionary		*counts		= [inventory.setCounts mutableCopy];

	if(inventory == nil)
		return;

	counts[[sender representedObject]] = @1;
	[self saveInventory:[inventory inventoryByReplacingSetCounts:counts]];

}//end addSetToInventory:


//========== removeSetFromInventory: ===========================================
//==============================================================================
- (IBAction) removeSetFromInventory:(id)sender
{
	LDrawCombinedInventory	*inventory	= [self selectedInventory];
	NSMutableDictionary		*counts		= [inventory.setCounts mutableCopy];
	NSInteger				 row		= [setCountsTable selectedRow];

	if(inventory == nil || row < 0)
		return;

	[counts removeObjectForKey:setCountNumbers[row]];
	[self saveInventory:[inventory inventoryByReplacingSetCounts:counts]];

}//end removeSetFromInventory:


//========== setCountChanged: ==================================================
//
// Purpose:		How many copies of a set the inventory holds.
//
//==============================================================================
- (IBAction) setCountChanged:(id)sender
{
	LDrawCombinedInventory	*inventory	= [self selectedInventory];
	NSMutableDictionary		*counts		= [inventory.setCounts mutableCopy];
	NSInteger				 row		= [sender tag];
	NSInteger				 count		= [sender integerValue];

	if(inventory == nil || row < 0 || row >= (NSInteger)[setCountNumbers count] || count < 1)
		return;

	counts[setCountNumbers[row]] = @(count);
	if([counts isEqualToDictionary:inventory.setCounts] == NO)
		[self saveInventory:[inventory inventoryByReplacingSetCounts:counts]];

}//end setCountChanged:


//========== addPartsFromFile: =================================================
//
// Purpose:		Adds the parts of a parts list file to the loose parts.
//
//==============================================================================
- (IBAction) addPartsFromFile:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];

	[panel setAllowedContentTypes:@[UTTypePlainText, UTTypeCommaSeparatedText, UTTypeTabSeparatedText]];
	[panel setMessage:NSLocalizedString(@"Choose a Bricksmith piece count export, or a Rebrickable parts list "
										@"in CSV.", nil)];

	[panel beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
		LDrawCombinedInventory	*inventory	= [self selectedInventory];
		NSError					*error		= nil;
		NSArray					*items		= nil;

		if(response != NSModalResponseOK || inventory == nil)
			return;

		items = [LDrawInventoryPartsFile itemsFromFileAtURL:[panel URL] error:&error];
		if(items == nil)
		{
			[self showError:error];
			return;
		}

		items = [inventory.looseItems arrayByAddingObjectsFromArray:items];
		[self saveInventory:[inventory inventoryByReplacingLooseItems:items]];
	}];

}//end addPartsFromFile:


//========== removeLooseParts: =================================================
//==============================================================================
- (IBAction) removeLooseParts:(id)sender
{
	LDrawCombinedInventory *inventory = [self selectedInventory];

	if(inventory != nil && [inventory.looseItems count] > 0)
		[self saveInventory:[inventory inventoryByReplacingLooseItems:@[]]];

}//end removeLooseParts:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== selectedInventory =================================================
//==============================================================================
- (LDrawCombinedInventory *) selectedInventory
{
	if([selectedKind isEqualToString:RowKindInventory] == NO)
		return nil;
	return [[[PartsLimitManager sharedManager] store] combinedInventoryWithIdentifier:selectedIdentifier];
}


//========== saveInventory: ====================================================
//
// Purpose:		Saves an inventory, and says so when it cannot. The store's
//				change notice redraws the window.
//
//==============================================================================
- (BOOL) saveInventory:(LDrawCombinedInventory *)inventory
{
	NSError	*error	= nil;
	BOOL	 saved	= [[[PartsLimitManager sharedManager] store] saveCombinedInventory:inventory error:&error];

	[self showError:error];
	return saved;

}//end saveInventory:


//========== showError: ========================================================
//==============================================================================
- (void) showError:(NSError *)error
{
	if(error != nil)
		[[NSAlert alertWithError:error] beginSheetModalForWindow:[self window] completionHandler:nil];
}


//========== gridWithRows: =====================================================
//
// Purpose:		Label and value pairs, the labels gray and right-aligned.
//
//==============================================================================
- (NSGridView *) gridWithRows:(NSArray<NSArray<NSString *> *> *)pairs
{
	NSGridView *grid = [NSGridView gridViewWithViews:@[]];

	for(NSArray<NSString *> *pair in pairs)
	{
		NSTextField *label = [NSTextField labelWithString:pair[0]];

		[label setTextColor:[NSColor secondaryLabelColor]];
		[grid addRowWithViews:@[label, [NSTextField labelWithString:pair[1]]]];
	}
	[[grid columnAtIndex:0] setXPlacement:NSGridCellPlacementTrailing];
	[grid setColumnSpacing:12];
	[grid setRowSpacing:6];

	return grid;

}//end gridWithRows:


//========== headingWithString: ================================================
//==============================================================================
- (NSTextField *) headingWithString:(NSString *)string
{
	NSTextField *heading = [NSTextField labelWithString:string];

	[heading setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	return heading;
}


//========== stackWithViews: ===================================================
//==============================================================================
- (NSStackView *) stackWithViews:(NSArray<NSView *> *)views
{
	NSStackView *stack = [NSStackView stackViewWithViews:views];

	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:10];
	return stack;
}


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== storeDidChange: ===================================================
//
// Purpose:		Lists the store again once the current event is done, since a
//				save can come from a field of the detail being rebuilt.
//
//==============================================================================
- (void) storeDidChange:(NSNotification *)notification
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadRows) object:nil];
	[self performSelector:@selector(reloadRows) withObject:nil afterDelay:0];
}

@end
