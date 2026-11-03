//==============================================================================
//
// File:		InventoriesWindowController.m
//
// Purpose:		The Inventories window: the imported sets, the inventories made
//				of sets and loose parts, and the parts matched by hand.
//
// Notes:		The list is on the left, the selected set or inventory on the
//				right. Every change is saved in the store at once, and the
//				window follows the store.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "InventoriesWindowController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawFeatures/LDrawUnmatchedParts.h>
#import <LDrawInventory/LDrawCombinedInventory.h>
#import <LDrawInventory/LDrawInventoryPartsFile.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableSetImporter.h>
#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import "ImportSetController.h"
#import "LDrawDocument.h"
#import "PartsLimitController.h"
#import "PartsLimitManager.h"
#import "PreferencesForm.h"

// Kinds of rows in the list.
static NSString * const RowKindGroup		= @"group";
static NSString * const RowKindSet			= @"set";
static NSString * const RowKindInventory	= @"inventory";
static NSString * const RowKindMatching		= @"matching";

static const CGFloat SidebarWidth			= 240;
static const CGFloat DetailInset			= 20;
static const CGFloat TableColumnMinWidth	= 40;


@implementation InventoriesWindowController
{
	NSTableView						*sourceList;
	NSButton						*removeButton;		// for a set or an inventory only
	NSView							*detailView;
	NSArray<NSDictionary *>			*rows;				// kind, identifier, title
	NSString						*selectedKind;
	NSString						*selectedIdentifier;

	// The inventory shown
	NSTableView						*setCountsTable;
	NSButton						*removeSetButton;	// for the set selected in the table only
	NSArray<NSString *>				*setCountNumbers;	// its sets, in number order

	// Matching
	NSTableView						*unmatchedTable;
	NSTableView						*matchesTable;
	NSButton						*removeMatchButton;	// for the match selected in the table only
	NSArray<LDrawUnmatchedPart *>	*unmatchedParts;	// the models' first, then the limit's inventory's
	NSString						*inventoryName;		// the limit's inventory, or nil
	NSArray<NSString *>				*matchNames;		// hand-matched LDraw names, in order
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

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
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(modelsDidChange:)
													 name:PartsLimitDidCheckNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(modelsDidChange:)
													 name:LDrawPartLimitDidChangeNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(modelsDidChange:)
													 name:PartsLimitFrontLimitDidChangeNotification
												   object:nil];
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

	removeButton = remove;
	sourceList = [[NSTableView alloc] init];
	[sourceList setStyle:NSTableViewStyleSourceList];
	[sourceList setHeaderView:nil];
	// A floating header sits at the top edge, away from its rows below the
	// list's top padding.
	[sourceList setFloatsGroupRows:NO];
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
		NSString *title = [store setInventoryForNumber:number].title ?: number;

		[newRows addObject:@{@"kind": RowKindSet, @"identifier": number, @"title": title}];
	}

	[newRows addObject:@{@"kind": RowKindGroup, @"title": NSLocalizedString(@"Inventories", nil)}];
	for(LDrawCombinedInventory *inventory in [store combinedInventories])
	{
		[newRows addObject:@{@"kind": RowKindInventory,
							 @"identifier": inventory.identifier,
							 @"title": inventory.name}];
	}

	[newRows addObject:@{@"kind": RowKindGroup, @"title": NSLocalizedString(@"Matching", nil)}];
	[newRows addObject:@{@"kind": RowKindMatching,
						 @"identifier": RowKindMatching,
						 @"title": NSLocalizedString(@"Unmatched Parts", nil)}];

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
		// The table would keep the old row's index, now another item.
		selectedKind		= nil;
		selectedIdentifier	= nil;
		[sourceList deselectAll:nil];
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


//========== sourceListViewForRow: =============================================
//
// Purpose:		A row of the list: its title, after a symbol of its kind.
//
//==============================================================================
- (NSView *) sourceListViewForRow:(NSInteger)row
{
	NSDictionary	*entry	= rows[row];
	NSTableCellView	*cell	= [sourceList makeViewWithIdentifier:@"Cell" owner:self];
	NSString		*symbol	= nil;

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

	if([entry[@"kind"] isEqualToString:RowKindSet])
		symbol = @"shippingbox";
	else if([entry[@"kind"] isEqualToString:RowKindInventory])
		symbol = @"tray.2";
	else if([entry[@"kind"] isEqualToString:RowKindMatching])
		symbol = @"link";

	[[cell textField] setStringValue:entry[@"title"]];
	[[cell imageView] setImage:(symbol != nil) ? [NSImage imageWithSystemSymbolName:symbol
														   accessibilityDescription:nil] : nil];
	[[cell imageView] setHidden:(symbol == nil)];

	return cell;

}//end sourceListViewForRow:


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
	unmatchedTable	= nil;
	matchesTable	= nil;

	[removeButton setEnabled:(		[selectedKind isEqualToString:RowKindSet]
							  ||	[selectedKind isEqualToString:RowKindInventory] )];

	if([selectedKind isEqualToString:RowKindSet])
		content = [self viewForSet:[store setInventoryForNumber:selectedIdentifier]];
	else if([selectedKind isEqualToString:RowKindInventory])
		content = [self viewForInventory:[store combinedInventoryWithIdentifier:selectedIdentifier]];
	else if([selectedKind isEqualToString:RowKindMatching])
		content = [self viewForMatching];

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

	if([set.source isEqualToString:LDrawRebrickableSourceAPI])
		source = NSLocalizedString(@"Rebrickable API", nil);

	if(set.fetchDate != nil)
		fetched = [NSDateFormatter localizedStringFromDate:set.fetchDate
												 dateStyle:NSDateFormatterMediumStyle
												 timeStyle:NSDateFormatterNoStyle];

	parts = [NSString localizedStringWithFormat:NSLocalizedString(@"%lu, and %lu spares", nil),
			 (unsigned long)set.partCount, (unsigned long)set.spareCount];

	title = [NSTextField wrappingLabelWithString:set.title];
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
	NSScrollView		*scrollView		= nil;
	NSPopUpButton		*addSet			= [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
	NSButton			*removeSet		= nil;
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
	setCountsTable	= [self tableWithColumns:columns];
	scrollView		= [self scrollViewForTable:setCountsTable height:160];

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
	[removeSet setEnabled:NO];
	removeSetButton = removeSet;

	// The loose parts
	if([inventory.looseItems count] > 0)
		looseText = [NSString localizedStringWithFormat:NSLocalizedString(@"%lu parts in %lu kinds", nil),
					 (unsigned long)inventory.loosePartCount, (unsigned long)[inventory.looseItems count]];
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


//========== setCountsFieldForColumn:row: ======================================
//
// Purpose:		A cell of the inventory's set table. The count can be typed.
//
//==============================================================================
- (NSTextField *) setCountsFieldForColumn:(NSTableColumn *)column row:(NSInteger)row
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

}//end setCountsFieldForColumn:row:


#pragma mark -
#pragma mark MATCHING
#pragma mark -

//========== viewForMatching ===================================================
//
// Purpose:		The parts that match nothing, with a field to match each by
//				hand, and the hand matches.
//
//==============================================================================
- (NSView *) viewForMatching
{
	NSTextField	*title		= [NSTextField labelWithString:NSLocalizedString(@"Unmatched Parts", nil)];
	NSTextField	*about		= nil;
	NSString	*text		= NSLocalizedString(@"Parts with no match have no data under the parts limit. Type what "
											@"a part is: the Rebrickable number of an LDraw part, or the LDraw "
											@"part of a Rebrickable number.", nil);
	NSArray		*unmatched	= @[@[@"part", NSLocalizedString(@"Part", nil), @110],
								@[@"description", NSLocalizedString(@"Description", nil), @140],
								@[@"count", NSLocalizedString(@"Count", nil), @50],
								@[@"match", NSLocalizedString(@"Match", nil), @90]];
	NSArray		*matches	= @[@[@"part", NSLocalizedString(@"LDraw Part", nil), @110],
								@[@"description", NSLocalizedString(@"Description", nil), @170],
								@[@"number", NSLocalizedString(@"Rebrickable Part", nil), @110]];
	NSButton	*remove		= [NSButton buttonWithTitle:NSLocalizedString(@"Remove Match", nil)
												 target:self
												 action:@selector(removeMatch:)];

	[remove setEnabled:NO];
	removeMatchButton = remove;

	[self loadUnmatchedParts];

	[title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]];
	about = [NSTextField wrappingLabelWithString:text];
	[about setTextColor:[NSColor secondaryLabelColor]];
	[[about widthAnchor] constraintLessThanOrEqualToConstant:520].active = YES;

	unmatchedTable	= [self tableWithColumns:unmatched];
	matchesTable	= [self tableWithColumns:matches];

	return [self stackWithViews:@[title, about,
								  [self scrollViewForTable:unmatchedTable height:170],
								  [self headingWithString:NSLocalizedString(@"Hand Matches", nil)],
								  [self scrollViewForTable:matchesTable height:90],
								  remove]];

}//end viewForMatching


//========== loadUnmatchedParts ================================================
//
// Purpose:		Finds the parts the open models place that match no LEGO part,
//				and the LEGO parts of the limit's inventory with no LDraw part.
//
//==============================================================================
- (void) loadUnmatchedParts
{
	PartsLimitManager		*manager	= [PartsLimitManager sharedManager];
	LDrawPartLimitSession	*session	= [manager session];
	LDrawInventoryStore		*store		= [manager store];
	LDrawPartLimit			*limit		= [[session tableForLimit:[manager frontLimit]] limit];
	NSMutableArray			*usages		= [NSMutableArray array];
	NSArray					*parts		= nil;

	// Each document keeps its walk of the model.
	for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
	{
		LDrawPartUsage *usage = nil;

		if([document isKindOfClass:[LDrawDocument class]])
			usage = [[(LDrawDocument *)document partsLimitController] usage];
		if(usage != nil)
			[usages addObject:usage];
	}
	parts = [LDrawUnmatchedParts partsInUsages:usages identity:[session identity] shortcuts:[session shortcuts]];

	inventoryName = nil;
	if(limit.kind == LDrawPartLimitKindInventory)
	{
		NSString	*identifier	= limit.inventoryIdentifier;
		NSArray		*items		= [store itemsForInventoryIdentifier:identifier] ?: @[];
		NSArray		*missing	= [LDrawUnmatchedParts partsInItems:items
															  limit:limit
														   identity:[session identity]
													 libraryHasPart:[PartsLimitManager libraryHasPartTest]];

		inventoryName	= [store titleForInventoryIdentifier:identifier];
		parts			= [parts arrayByAddingObjectsFromArray:missing];
	}
	unmatchedParts	= parts;
	matchNames		= [[[store identityOverrides] allKeys]
					   sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

}//end loadUnmatchedParts


//========== reloadUnmatchedParts ==============================================
//==============================================================================
- (void) reloadUnmatchedParts
{
	if(unmatchedTable == nil)
		return;

	[self loadUnmatchedParts];
	[unmatchedTable reloadData];
	[matchesTable reloadData];
}


//========== unmatchedFieldForColumn:row: ======================================
//
// Purpose:		A cell of the unmatched parts. The match can be typed.
//
//==============================================================================
- (NSTextField *) unmatchedFieldForColumn:(NSTableColumn *)column row:(NSInteger)row
{
	LDrawUnmatchedPart	*part		= unmatchedParts[row];
	NSString			*identifier	= [column identifier];
	BOOL				 isModel	= (part.partName != nil);
	NSTextField			*cell		= nil;

	if([identifier isEqualToString:@"match"])
	{
		cell = [NSTextField textFieldWithString:@""];
		[cell setPlaceholderString:isModel ? NSLocalizedString(@"Rebrickable no.", nil)
										   : NSLocalizedString(@"LDraw part", nil)];
		[cell setBordered:NO];
		[cell setDrawsBackground:NO];
		[cell setTag:row];
		[cell setTarget:self];
		[cell setAction:@selector(matchTyped:)];
		return cell;
	}

	if([identifier isEqualToString:@"part"])
		cell = [NSTextField labelWithString:isModel ? [part.partName stringByDeletingPathExtension]
													: part.rebrickablePartNumber];
	else if([identifier isEqualToString:@"description"])
		cell = [NSTextField labelWithString:[self descriptionOfUnmatchedPart:part]];
	else
	{
		cell = [NSTextField labelWithString:[NSString stringWithFormat:@"%lu", (unsigned long)part.count]];
		[cell setAlignment:NSTextAlignmentRight];
	}
	[cell setLineBreakMode:NSLineBreakByTruncatingTail];
	return cell;

}//end unmatchedFieldForColumn:row:


//========== descriptionOfUnmatchedPart: =======================================
//
// Purpose:		A model's part by its library description; an inventory's part
//				by where it is.
//
//==============================================================================
- (NSString *) descriptionOfUnmatchedPart:(LDrawUnmatchedPart *)part
{
	LDrawPartLibrary *library = [LDrawPartLibrary sharedPartLibrary];

	if(part.partName == nil)
		return [NSString stringWithFormat:NSLocalizedString(@"In %@, with no LDraw part", nil), inventoryName ?: @""];
	if([library categoryForPartName:part.partName] == nil)
		return NSLocalizedString(@"Not in the part library", nil);
	return [library descriptionForPartName:part.partName];

}//end descriptionOfUnmatchedPart:


//========== matchesFieldForColumn:row: ========================================
//==============================================================================
- (NSTextField *) matchesFieldForColumn:(NSTableColumn *)column row:(NSInteger)row
{
	NSString	*name		= [LDrawPartIdentity libraryPartName:matchNames[row]];
	NSString	*number		= [[[PartsLimitManager sharedManager] store] identityOverrides][matchNames[row]];
	NSString	*identifier	= [column identifier];
	NSTextField	*cell		= nil;

	if([identifier isEqualToString:@"part"])
		cell = [NSTextField labelWithString:matchNames[row]];
	else if([identifier isEqualToString:@"description"])
		cell = [NSTextField labelWithString:[[LDrawPartLibrary sharedPartLibrary] descriptionForPartName:name]];
	else
		cell = [NSTextField labelWithString:number ?: @""];
	[cell setLineBreakMode:NSLineBreakByTruncatingTail];
	return cell;

}//end matchesFieldForColumn:row:


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
	if(isSet == NO && [selectedKind isEqualToString:RowKindInventory] == NO)
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
//
// Purpose:		Makes the selected set or inventory the front model's limit.
//
//==============================================================================
- (IBAction) useAsLimit:(id)sender
{
	PartsLimitManager	*manager	= [PartsLimitManager sharedManager];
	LDrawPartLimit		*limit		= [[manager frontLimit] limitWithKind:LDrawPartLimitKindInventory
													  inventoryIdentifier:selectedIdentifier];

	[manager setLimit:limit document:nil window:[self window]];

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
	LDrawCombinedInventory	*renamed	= [inventory inventoryByRenamingTo:[sender stringValue]];

	if(inventory != nil && [renamed.name isEqualToString:inventory.name] == NO)
		[self saveInventory:renamed];

}//end renameInventory:


//========== addSetToInventory: ================================================
//==============================================================================
- (IBAction) addSetToInventory:(id)sender
{
	LDrawCombinedInventory *inventory = [self selectedInventory];

	if(inventory != nil)
		[self saveInventory:[inventory inventoryBySettingCount:1 forSetNumber:[sender representedObject]]];

}//end addSetToInventory:


//========== removeSetFromInventory: ===========================================
//==============================================================================
- (IBAction) removeSetFromInventory:(id)sender
{
	LDrawCombinedInventory	*inventory	= [self selectedInventory];
	NSInteger				 row		= [setCountsTable selectedRow];

	if(inventory != nil && row >= 0)
		[self saveInventory:[inventory inventoryBySettingCount:0 forSetNumber:setCountNumbers[row]]];

}//end removeSetFromInventory:


//========== setCountChanged: ==================================================
//
// Purpose:		Saves the count typed for one of the inventory's sets.
//
//==============================================================================
- (IBAction) setCountChanged:(id)sender
{
	LDrawCombinedInventory	*inventory	= [self selectedInventory];
	LDrawCombinedInventory	*changed	= nil;
	NSInteger				 row		= [sender tag];
	NSInteger				 count		= [sender integerValue];

	// The field's formatter keeps the count at 1 or more; removing is a button.
	if(inventory == nil || row < 0 || row >= (NSInteger)[setCountNumbers count] || count < 1)
		return;

	changed = [inventory inventoryBySettingCount:count forSetNumber:setCountNumbers[row]];
	if([changed.setCounts isEqualToDictionary:inventory.setCounts] == NO)
		[self saveInventory:changed];

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

		[self saveInventory:[inventory inventoryByAddingLooseItems:items]];
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


//========== matchTyped: =======================================================
//
// Purpose:		Saves what the user typed as a hand match: a Rebrickable number
//				for an LDraw part, or an LDraw part for a Rebrickable number.
//
//==============================================================================
- (IBAction) matchTyped:(id)sender
{
	LDrawInventoryStore	*store		= [[PartsLimitManager sharedManager] store];
	NSInteger			 row		= [sender tag];
	NSDictionary		*overrides	= nil;
	NSError				*error		= nil;

	if(row < 0 || row >= (NSInteger)[unmatchedParts count])
		return;

	overrides = [LDrawUnmatchedParts overrides:[store identityOverrides]
								byMatchingPart:unmatchedParts[row]
										toText:[sender stringValue]
								libraryHasPart:[PartsLimitManager libraryHasPartTest]
										 error:&error];
	if(overrides != nil && [overrides isEqualToDictionary:[store identityOverrides] ?: @{}] == NO)
		[store saveIdentityOverrides:overrides error:&error];
	[self showError:error];

}//end matchTyped:


//========== removeMatch: ======================================================
//==============================================================================
- (IBAction) removeMatch:(id)sender
{
	LDrawInventoryStore	*store		= [[PartsLimitManager sharedManager] store];
	NSInteger			 row		= [matchesTable selectedRow];
	NSDictionary		*overrides	= nil;
	NSError				*error		= nil;

	if(row < 0 || row >= (NSInteger)[matchNames count])
		return;

	overrides = [LDrawUnmatchedParts overrides:[store identityOverrides]
						   byMatchingPartNamed:matchNames[row]
								  toPartNumber:nil];
	[store saveIdentityOverrides:overrides error:&error];
	[self showError:error];

}//end removeMatch:


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//**** NSTableViewDataSource ****
//========== numberOfRowsInTableView: ==========================================
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	if(tableView == setCountsTable)
		return [setCountNumbers count];
	if(tableView == unmatchedTable)
		return [unmatchedParts count];
	if(tableView == matchesTable)
		return [matchNames count];
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
		return [PreferencesForm tableCellWithField:[self setCountsFieldForColumn:column row:row]];
	if(tableView == unmatchedTable)
		return [PreferencesForm tableCellWithField:[self unmatchedFieldForColumn:column row:row]];
	if(tableView == matchesTable)
		return [PreferencesForm tableCellWithField:[self matchesFieldForColumn:column row:row]];
	return [self sourceListViewForRow:row];
}


//**** NSTableViewDelegate ****
//========== tableViewSelectionDidChange: ======================================
//==============================================================================
- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [sourceList selectedRow];

	if([notification object] == setCountsTable)
		[removeSetButton setEnabled:([setCountsTable selectedRow] >= 0)];
	if([notification object] == matchesTable)
		[removeMatchButton setEnabled:([matchesTable selectedRow] >= 0)];
	if([notification object] != sourceList)
		return;

	selectedKind		= (row >= 0) ? rows[row][@"kind"] : nil;
	selectedIdentifier	= (row >= 0) ? rows[row][@"identifier"] : nil;
	[self showDetail];

}//end tableViewSelectionDidChange:


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


//========== modelsDidChange: ==================================================
//
// Purpose:		A model was checked again, or the limit changed. The unmatched
//				parts are found again a moment later, once edits settle.
//
//==============================================================================
- (void) modelsDidChange:(NSNotification *)notification
{
	if(unmatchedTable == nil || [[self window] isVisible] == NO)
		return;

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadUnmatchedParts) object:nil];
	[self performSelector:@selector(reloadUnmatchedParts) withObject:nil afterDelay:0.5];
}


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


//========== tableWithColumns: =================================================
//
// Purpose:		A table with these columns, each an identifier, a title and a
//				width.
//
//==============================================================================
- (NSTableView *) tableWithColumns:(NSArray<NSArray *> *)columns
{
	NSTableView *table = [[NSTableView alloc] init];

	for(NSArray *spec in columns)
	{
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
		[[column headerCell] setStringValue:spec[1]];
		[column setWidth:[spec[2] doubleValue]];
		[column setMinWidth:TableColumnMinWidth];
		[table addTableColumn:column];
	}
	// The columns share the table's width, so widening one takes room from
	// all the others instead of only the last.
	[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[table setUsesAlternatingRowBackgroundColors:YES];
	[table setDataSource:self];
	[table setDelegate:self];
	return table;

}//end tableWithColumns:


//========== scrollViewForTable:height: ========================================
//==============================================================================
- (NSScrollView *) scrollViewForTable:(NSTableView *)table height:(CGFloat)height
{
	NSScrollView *scrollView = [[NSScrollView alloc] init];

	[scrollView setDocumentView:table];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setBorderType:NSBezelBorder];
	[[scrollView heightAnchor] constraintEqualToConstant:height].active = YES;
	[[scrollView widthAnchor] constraintGreaterThanOrEqualToConstant:400].active = YES;
	return scrollView;

}//end scrollViewForTable:height:


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

@end
