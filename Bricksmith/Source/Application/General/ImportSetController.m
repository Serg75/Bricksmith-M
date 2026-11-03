//==============================================================================
//
// File:		ImportSetController.m
//
// Purpose:		A sheet to find a LEGO set by number or name and import its
//				parts, to use as the parts limit.
//
// Notes:		Sets are found and imported from the downloaded data.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "ImportSetController.h"

#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>
#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import "PartsLimitManager.h"
#import "PreferencesForm.h"

// How many matches the table lists.
static const NSUInteger ImportSetMatchLimit = 200;

// The sheet on screen. It keeps itself until it closes.
static ImportSetController *runningController = nil;


@implementation ImportSetController
{
	NSWindow				*parent;
	NSPanel					*panel;
	NSSearchField			*searchField;
	NSTableView				*table;
	NSTextField				*statusLabel;
	NSProgressIndicator		*spinner;
	NSButton				*useAsLimitCheckbox;
	NSButton				*importButton;

	LDrawRebrickableSetList				*setList;
	NSArray<LDrawRebrickableSet *>		*matches;
	BOOL								 isImporting;
	BOOL								 isClosed;
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- runWithWindow: ------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (void) runWithWindow:(NSWindow *)window
{
	PartsLimitManager *manager = [PartsLimitManager sharedManager];

	if(runningController != nil)
	{
		[runningController->panel makeKeyAndOrderFront:nil];
		return;
	}

	// The set list comes with the data.
	if([[manager updater] hasCatalog] == NO)
	{
		[manager updateDataForcing:NO window:window completion:^(BOOL success) {
			if(success)
				[self runWithWindow:window];
		}];
		return;
	}

	runningController = [[ImportSetController alloc] init];
	runningController->parent = window;
	[runningController show];

}//end runWithWindow:


//========== show ==============================================================
//
// Purpose:		Builds the sheet: a search field, the matching sets, and
//				Import.
//
//==============================================================================
- (void) show
{
	NSScrollView	*scrollView		= [[NSScrollView alloc] init];
	NSButton		*cancelButton	= [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil)
														 target:self
														 action:@selector(cancel:)];
	NSArray			*columns		= @[@[@"number", NSLocalizedString(@"Number", nil), @80],
										@[@"name", NSLocalizedString(@"Name", nil), @230],
										@[@"year", NSLocalizedString(@"Year", nil), @50],
										@[@"parts", NSLocalizedString(@"Parts", nil), @60]];

	searchField = [[NSSearchField alloc] init];
	[searchField setPlaceholderString:NSLocalizedString(@"Set number or name", nil)];
	[searchField setDelegate:self];
	[searchField setTarget:self];
	[searchField setAction:@selector(search:)];

	table = [[NSTableView alloc] init];
	for(NSArray *spec in columns)
	{
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
		[[column headerCell] setStringValue:spec[1]];
		[column setWidth:[spec[2] doubleValue]];
		[table addTableColumn:column];
	}
	[table setUsesAlternatingRowBackgroundColors:YES];
	[table setDataSource:self];
	[table setDelegate:self];
	[table setTarget:self];
	[table setDoubleAction:@selector(import:)];

	[scrollView setDocumentView:table];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setBorderType:NSBezelBorder];
	[[scrollView heightAnchor] constraintEqualToConstant:240].active = YES;
	[[scrollView widthAnchor] constraintEqualToConstant:480].active = YES;

	statusLabel = [NSTextField labelWithString:@""];
	[statusLabel setTextColor:[NSColor secondaryLabelColor]];
	[statusLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];

	spinner = [[NSProgressIndicator alloc] init];
	[spinner setStyle:NSProgressIndicatorStyleSpinning];
	[spinner setControlSize:NSControlSizeSmall];
	[spinner setDisplayedWhenStopped:NO];

	useAsLimitCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Use as the parts limit", nil)
											  target:nil
											  action:NULL];
	[useAsLimitCheckbox setState:NSControlStateValueOn];

	importButton = [NSButton buttonWithTitle:NSLocalizedString(@"Import", nil) target:self action:@selector(import:)];
	[importButton setKeyEquivalent:@"\r"];
	[cancelButton setKeyEquivalent:@"\e"];

	NSStackView *status		= [NSStackView stackViewWithViews:@[spinner, statusLabel]];
	NSStackView *buttons	= [[NSStackView alloc] init];
	NSStackView *stack		= [NSStackView stackViewWithViews:@[searchField, scrollView, status, buttons]];

	// The checkbox on the left, Cancel and Import on the right.
	[buttons addView:useAsLimitCheckbox inGravity:NSStackViewGravityLeading];
	[buttons addView:cancelButton inGravity:NSStackViewGravityTrailing];
	[buttons addView:importButton inGravity:NSStackViewGravityTrailing];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:10];
	[[searchField widthAnchor] constraintEqualToAnchor:[scrollView widthAnchor]].active = YES;
	[[buttons widthAnchor] constraintEqualToAnchor:[scrollView widthAnchor]].active = YES;

	NSView *content = [PreferencesForm containerForView:stack margins:NSEdgeInsetsMake(20, 20, 20, 20)];

	panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 400)
									   styleMask:NSWindowStyleMaskTitled
										 backing:NSBackingStoreBuffered
										   defer:YES];
	[panel setTitle:NSLocalizedString(@"Import Set Parts", nil)];
	[panel setContentView:content];
	[panel setContentSize:[content fittingSize]];
	[panel setInitialFirstResponder:searchField];

	if(parent != nil)
		[parent beginSheet:panel completionHandler:nil];
	else
	{
		[panel center];
		[panel makeKeyAndOrderFront:nil];
	}

	[self loadSetList];
	[self updateControls];

}//end show


//========== loadSetList =======================================================
//
// Purpose:		Reads the set list from the downloads, which takes a moment the
//				first time.
//
//==============================================================================
- (void) loadSetList
{
	LDrawRebrickableUpdater *updater = [[PartsLimitManager sharedManager] updater];

	[spinner startAnimation:nil];
	[statusLabel setStringValue:NSLocalizedString(@"Reading the set list…", nil)];

	[updater loadSetListWithCompletion:^(LDrawRebrickableSetList *list, NSError *error) {
		[self->spinner stopAnimation:nil];
		self->setList = list;
		[self->statusLabel setStringValue:(list != nil) ? @"" : [error localizedDescription] ?: @""];
		[self search:nil];
	}];

}//end loadSetList


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== search: ===========================================================
//
// Purpose:		Lists the sets matching what is typed.
//
//==============================================================================
- (void) search:(id)sender
{
	NSString *text = [[searchField stringValue] stringByTrimmingCharactersInSet:
					  [NSCharacterSet whitespaceCharacterSet]];

	matches = ([text length] > 0) ? [setList setsMatching:text limit:ImportSetMatchLimit] : @[];
	[table reloadData];

	if([matches count] > 0)
		[table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

	[self updateControls];

}//end search:


//========== import: ===========================================================
//
// Purpose:		Imports the selected set, or the typed number when there is no
//				set list, and makes it the limit when asked.
//
//==============================================================================
- (void) import:(id)sender
{
	PartsLimitManager	*manager	= [PartsLimitManager sharedManager];
	NSString			*number		= [self chosenSetNumber];
	BOOL				 useAsLimit	= ([useAsLimitCheckbox state] == NSControlStateValueOn);

	if(number == nil || isImporting)
		return;

	isImporting = YES;
	[spinner startAnimation:nil];
	[statusLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Importing %@…", nil), number]];
	[self updateControls];

	[[manager updater] importSetNumber:number
							completion:^(LDrawSetInventory *set, NSError *error) {
		self->isImporting = NO;

		// After Cancel, the import still saves the set, but leaves the limit.
		if(self->isClosed)
			return;
		[self->spinner stopAnimation:nil];

		if(set == nil)
		{
			[self->statusLabel setStringValue:@""];
			[self updateControls];
			[[NSAlert alertWithError:error] beginSheetModalForWindow:self->panel completionHandler:nil];
			return;
		}

		if(useAsLimit)
		{
			LDrawPartLimit *limit = [[[manager session] limit] limitWithKind:LDrawPartLimitKindInventory
														 inventoryIdentifier:set.setNumber];
			[manager setLimit:limit window:self->parent];
		}
		[self close];
	}];

}//end import:


//========== cancel: ===========================================================
//==============================================================================
- (void) cancel:(id)sender
{
	[self close];
}


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//**** NSSearchFieldDelegate ****
//========== controlTextDidChange: =============================================
//
// Purpose:		Searches as the user types.
//
//==============================================================================
- (void) controlTextDidChange:(NSNotification *)notification
{
	[self search:nil];
}


//**** NSTableViewDataSource ****
//========== numberOfRowsInTableView: ==========================================
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	return [matches count];
}


//**** NSTableViewDelegate ****
//========== tableView:viewForTableColumn:row: =================================
//==============================================================================
- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	LDrawRebrickableSet	*set		= matches[row];
	NSString			*identifier	= [column identifier];
	NSTableCellView		*cell		= [tableView makeViewWithIdentifier:identifier owner:self];
	NSString			*text		= @"";

	if(cell == nil)
	{
		NSTextField *field = [NSTextField labelWithString:@""];

		[field setLineBreakMode:NSLineBreakByTruncatingTail];
		cell = [PreferencesForm tableCellWithField:field];
		[cell setIdentifier:identifier];
	}

	if([identifier isEqualToString:@"number"])
		text = set.setNumber;
	else if([identifier isEqualToString:@"name"])
		text = (set.themeName != nil) ? [NSString stringWithFormat:@"%@ (%@)", set.name, set.themeName] : set.name;
	else if([identifier isEqualToString:@"year"])
		text = [NSString stringWithFormat:@"%ld", (long)set.year];
	else if([identifier isEqualToString:@"parts"])
		text = [NSString stringWithFormat:@"%lu", (unsigned long)set.partCount];

	[[cell textField] setStringValue:text];
	return cell;

}//end tableView:viewForTableColumn:row:


//**** NSTableViewDelegate ****
//========== tableViewSelectionDidChange: ======================================
//==============================================================================
- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateControls];
}


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== chosenSetNumber ===================================================
//
// Purpose:		The selected set's number. With no set list, the typed text.
//
//==============================================================================
- (NSString *) chosenSetNumber
{
	NSInteger row = [table selectedRow];

	if(setList == nil)
	{
		NSString *typed = [LDrawSetInventory normalizedSetNumber:[searchField stringValue]];
		return ([typed length] > 0) ? typed : nil;
	}

	return (row >= 0 && row < (NSInteger)[matches count]) ? matches[row].setNumber : nil;

}//end chosenSetNumber


//========== updateControls ====================================================
//==============================================================================
- (void) updateControls
{
	[importButton setEnabled:(isImporting == NO && [self chosenSetNumber] != nil)];
	[searchField setEnabled:(isImporting == NO)];
}


//========== close =============================================================
//
// Purpose:		Takes the sheet down, once.
//
//==============================================================================
- (void) close
{
	if(isClosed)
		return;
	isClosed = YES;

	if(parent != nil)
		[parent endSheet:panel];
	[panel orderOut:nil];

	// Last, since this may drop the last strong reference to self.
	runningController = nil;

}//end close

@end
