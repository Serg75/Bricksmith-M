//==============================================================================
//
// File:		PartBrowserDataSource.m
//
// Purpose:		Provides a standardized data source for part browser interface.
//
//				A part browser consists of a table which displays part numbers 
//				and descriptions, and a combo box to choose part categories. If 
//				you wish to make a part browser, you must lay out the UI in a 
//				manner appropriate to its setting, and then connect all the 
//				outlets specified by this class. 
//
// Usage:		An instance of this class should exist in each Nib file which 
//				contains a part browser, and the browser widgets and actions 
//				should be connected to it. This class will then take care of 
//				managing those widgets.
//
//				Clients wishing to know about part insertions should implement 
//				the action -insertLDrawPart:.
//
//  Created by Allen Smith on 2/17/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "PartBrowserDataSource.h"

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/NSString+LDraw.h>

#import <LDrawEditing/LDrawClipboard.h>
#import <LDrawEditing/LDrawInsertion.h>
#import <LDrawFeatures/LDrawHostKeys.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

#import "IconTextCell.h"
#import "LDrawApplication.h"
#import "LDrawColorPanelController.h"
#import "LDrawDocument.h"
#import "LDrawViewerContainer.h"
#import "PartBrowserLimitViews.h"
#import "PartsLimitController.h"
#import "PartsLimitManager.h"
#import "TableViewCategory.h"

NSString * const PartBrowserSelectionDidChangeNotification = @"PartBrowserSelectionDidChangeNotification";

// Columns added for an inventory's rows.
static NSString * const LimitColorColumn	= @"LimitColor";
static NSString * const LimitCountColumn	= @"LimitCount";

static const CGFloat LimitBarHeight			= 22.0;
static const CGFloat SwatchSize				= 14.0;


@implementation PartBrowserDataSource


//========== awakeFromNib ======================================================
//
// Purpose:		This class is just about always initialized in a Nib file.
//				So when awaking, we grab the actual data source for the class.
//
//==============================================================================
- (void) awakeFromNib
{
	NSUserDefaults  *userDefaults       = [NSUserDefaults standardUserDefaults];
	NSString        *startingCategory   = [userDefaults stringForKey:PART_BROWSER_PREVIOUS_CATEGORY];
	NSInteger       startingRow         = [userDefaults integerForKey:PART_BROWSER_PREVIOUS_SELECTED_ROW];
	NSMenu          *searchMenuTemplate = nil;
	NSMenuItem      *recentsItem        = nil;
	NSMenuItem      *noRecentsItem      = nil;
	
	// Loading main nib (the one in which this helper controller was allocated)
	// By the time this is called, our accessory nib has already been loaded in 
	// -init.
	if(self->partsTable != nil)
	{
		//---------- Widget Setup ----------------------------------------------
		
		if(partPreview == nil)
		{
			partPreview = partPreviewViewport.glView;
		}
		
		// - Category Table
		
		[self->categoryTable setStyle:NSTableViewStyleSourceList];
		[self->categoryTable setAllowsTypeSelect:YES];
		[self->categoryTable setFocusRingType:NSFocusRingTypeNone];
		[self->categoryTable setDelegate:self];
		[self->categoryTable setDataSource:self];
		self->categoryTable.floatsGroupRows = NO;
		self->categoryTable.rowSizeStyle = NSTableViewRowSizeStyleSmall;
		[[self->categoryTable window] makeFirstResponder:self->categoryTable];
		
		// - Parts Table
		
		[self->partsTable setTarget:self];
		[self->partsTable setDoubleAction:@selector(doubleClickedInPartTable:)];
		[self->partsTable setFocusRingType:NSFocusRingTypeNone];
		
		// - Part preview
		
		[self->partPreview setAcceptsFirstResponder:NO];
		[self->partPreview setLDrawDelegate:self];

		[self->zoomInButton setTarget:self->partPreview];
		[self->zoomInButton setAction:@selector(zoomIn:)];
		[self->zoomInButton setToolTip:NSLocalizedString([LDrawPartBrowserModel zoomInTooltipLocalizationKey], nil)];
		
		[self->zoomOutButton setTarget:self->partPreview];
		[self->zoomOutButton setAction:@selector(zoomOut:)];
		[self->zoomOutButton setToolTip:NSLocalizedString([LDrawPartBrowserModel zoomOutTooltipLocalizationKey], nil)];

		[self->addRemoveFavoriteButton setTarget:self];
		[self->addRemoveFavoriteButton setToolTip:NSLocalizedString([LDrawPartBrowserModel addRemoveFavoritesTooltipLocalizationKey], nil)];
		
		[self->insertButton setTarget:self];
		[self->insertButton setAction:@selector(addPartClicked:)];
		
		// Scope bar
		[searchAllCategoriesButton setTarget:self];
		[searchAllCategoriesButton setAction:@selector(searchAllCategoriesButtonClicked:)];
		
		[searchSelectedCategoryButton setTarget:self];
		[searchSelectedCategoryButton setAction:@selector(searchSelectedCategoryButtonClicked:)];
		
		[searchField setTarget:self];
		[searchField setAction:@selector(searchFieldChanged:)];
		
		// Configure the search field's menu
		searchMenuTemplate = [[NSMenu alloc] initWithTitle:@"Search template"];
		
		noRecentsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString([LDrawPartBrowserModel noRecentSearchesLocalizationKey], nil)
												   action:NULL
											keyEquivalent:@"" ];
		[noRecentsItem setTag:NSSearchFieldNoRecentsMenuItemTag];
		
		recentsItem = [[NSMenuItem alloc] initWithTitle:@"recent items placeholder"
												 action:NULL
										  keyEquivalent:@"" ];
		[recentsItem setTag:NSSearchFieldRecentsMenuItemTag];
		
		[searchMenuTemplate insertItem:noRecentsItem atIndex:0];
		[searchMenuTemplate insertItem:recentsItem atIndex:1];
		
		[[self->searchField cell] setSearchMenuTemplate:searchMenuTemplate];
		
		// If there is no sort order yet, define one.
		if([[self->partsTable sortDescriptors] count] == 0)
		{
			NSTableColumn		*descriptionColumn	= [self->partsTable tableColumnWithIdentifier:PART_NAME_KEY];
			NSSortDescriptor	*sortDescriptor		= [descriptionColumn sortDescriptorPrototype];
			
			if(sortDescriptor != nil)
				[self->partsTable setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
		}
		
		[self->partsTable setMenu:self->contextualMenu];
		
		
		//---------- Parts limit -----------------------------------------------

		self->showsAllParts = [userDefaults boolForKey:PARTS_LIMIT_BROWSER_SHOWS_ALL_KEY];
		[self installLimitControls];


		//---------- Set Data --------------------------------------------------
		
		[self setPartLibrary:[LDrawPartLibrary sharedPartLibrary]];
		[self loadCategory:startingCategory];
		
		[partsTable scrollRowToVisible:startingRow];
		[partsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:startingRow]
				byExtendingSelection:NO];
		[self syncSelectionAndPartDisplayed];
		[self->partPreview scrollCenterToModelPoint:ZeroPoint3];
		
		
		//---------- Notifications ---------------------------------------------
		
		//We also want to know if the part catalog changes while the program is running.
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(sharedPartCatalogDidChange:)
													 name: LDrawPartLibraryDidChangeNotification
												   object: nil ];

		[self observeLimit];
	}
	// Loading "PartBrowserAccessories.nib"
	else
	{
	}

}//end awakeFromNib


//========== init ==============================================================
//
// Purpose:		This is very basic; it's not where the action is.
//
//==============================================================================
- (id) init
{
	self = [super init];
	
	// Load the accessories from our private nib file.
	NSArray *nibObjects = nil;
	[[NSBundle mainBundle] loadNibNamed:@"PartBrowserAccessories" owner:self topLevelObjects:&nibObjects];
	topLevelObjects = nibObjects;
	
	// Not displaying anything yet.
	categoryList	= [NSArray array];
	tableDataSource	= [NSMutableArray array];
	searchMode		= (LDrawPartBrowserSearchMode)[[NSUserDefaults standardUserDefaults] integerForKey:PART_BROWSER_SEARCH_MODE];
	
	return self;
	
}//end init


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== category ==========================================================
//
// Purpose:		Returns the currently-selected category.
//
//==============================================================================
- (NSString *) category
{
	return self->selectedCategory;
	
}//end category


//========== selectedPartName ==================================================
//
// Purpose:		Returns the name of the selected part file.
//				i.e., "3001.dat"
//
//==============================================================================
- (NSString *) selectedPartName
{
	NSInteger       rowIndex    = [partsTable selectedRow];
	NSDictionary    *partRecord = nil;
	NSString        *partName   = nil;
	
	if(rowIndex >= 0)
	{
		partRecord	= [tableDataSource objectAtIndex:rowIndex];
		partName	= [partRecord objectForKey:PART_NUMBER_KEY];
	}
	
	return partName;
	
}//end selectedPartName


//========== selectedRecord ====================================================
//
// Purpose:		The selected row's record, or nil.
//
//==============================================================================
- (NSDictionary *) selectedRecord
{
	NSInteger rowIndex = [partsTable selectedRow];

	if(rowIndex < 0 || rowIndex >= (NSInteger)[tableDataSource count])
		return nil;
	return [tableDataSource objectAtIndex:rowIndex];

}//end selectedRecord


//========== insertionColor ====================================================
//
// Purpose:		The color a part is inserted in: an inventory row's own, else
//				the Colors window's.
//
//==============================================================================
- (LDrawColor *) insertionColor
{
	NSNumber *colorCode = [[self selectedRecord] objectForKey:LDrawPartBrowserColorCodeKey];

	if(colorCode != nil)
		return [[LDrawColorLibrary sharedColorLibrary] colorForCode:(LDrawColorT)[colorCode intValue]];
	return [[LDrawColorPanelController sharedColorPanel] LDrawColor];

}//end insertionColor


#pragma mark -

//========== loadCategory: =====================================================
//
// Purpose:		Causes the parts browser to display all the parts in 
//				newCategory. 
//
//==============================================================================
- (BOOL) loadCategory:(NSString *)newCategory
{
	BOOL success = [self->browserModel hasCategory:newCategory];
	
	// Assign instance variable
	self->selectedCategory = newCategory;
	[self->searchField setStringValue:@""];
	
	if(success == YES)
	{
		[self reloadRows];
		[self syncSelectionAndCategoryDisplayed];
	}
	else
	{	// The user entered an invalid category; display no list.
		[self setTableDataSource:[NSMutableArray array]];
		[self updateLimitControls];
	}
	
	[self setConstraints];
	
	return success;
	
}//end loadCategory:


//========== setPartCatalog: ===================================================
//
// Purpose:		A new part catalog has been read out of the LDraw folder. Now we 
//				set up the data sources to reflect it.
//
//==============================================================================
- (void) setPartLibrary:(LDrawPartLibrary *)partLibraryIn
{
	NSArray         *categories         = nil;
	
	// Assign ivar
	self->partLibrary = partLibraryIn;
	if(self->browserModel == nil)
	{
		self->browserModel = [[LDrawPartBrowserModel alloc] initWithPartLibrary:partLibraryIn];
		self->browserModel.limitSession = [[PartsLimitManager sharedManager] session];
	}
	else
	{
		self->browserModel.partLibrary = partLibraryIn;
	}
	
	// Get all the categories, and the sets.
	categories = [self->browserModel categoryHierarchy];
	[self setCategoryList:categories];
	
	//And set the current category to show everything
	[self loadCategory:Category_All];
	
}//end setPartCatalog:


//========== setCategoryList: ==================================================
//
// Purpose:		Sets the complete list of all the categories avaibaled; used as 
//				the category combo box's data source.
//
//==============================================================================
- (void) setCategoryList:(NSArray *)newCategoryList
{
	//swap the variable
	categoryList = newCategoryList;
	
	//Update the category chooser
	[categoryTable reloadData];
	
	// Source lists should be presented expanded
	for(id item in categoryList)
	{
		[categoryTable expandItem:item];
	}

}//end setCategoryList


//========== setTableDataSource: ===============================================
//
// Purpose:		The table displays a list of the parts in a category. The array
//				here is an array of part records containg names and 
//				descriptions.
//
//				The new parts are then displayed in the table.
//
//==============================================================================
- (void) setTableDataSource:(NSMutableArray *)allPartRecords
{
	NSString        *originalSelectedPartName   = [self selectedPartName];
	NSUInteger      newSelectedIndex            = NSNotFound;

	[allPartRecords sortUsingDescriptors:[partsTable sortDescriptors]];
	
	// Swap out the variable
	self->tableDataSource = allPartRecords;
	[partsTable reloadData];
	
	// Attempt to restore the original selection (happens especially if clearing 
	// the search field) 
	newSelectedIndex = [LDrawPartBrowserModel indexOfPartNamed:originalSelectedPartName
													 inRecords:self->tableDataSource];
	newSelectedIndex = [LDrawPartBrowserModel tableSelectionIndexPreferring:newSelectedIndex];
	
	// Scroll to the new selection
	[partsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:newSelectedIndex] byExtendingSelection:NO];
	[partsTable scrollRowToVisible:newSelectedIndex];
	
}//end setTableDataSource


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== searchAllCategoriesButtonClicked: =================================
//
// Purpose:		The search should be performed on all the parts in the catalog.
//
//==============================================================================
- (IBAction) searchAllCategoriesButtonClicked:(id)sender
{
	self->searchMode = LDrawPartBrowserSearchAllCategories;
	[[NSUserDefaults standardUserDefaults] setInteger:LDrawPartBrowserSearchAllCategories forKey:PART_BROWSER_SEARCH_MODE];

	[self performSearch];
}


//========== searchSelectedCategoryButtonClicked: ==============================
//
// Purpose:		The search should be limited to the selected category only.
//
//==============================================================================
- (IBAction) searchSelectedCategoryButtonClicked:(id)sender
{
	self->searchMode = LDrawPartBrowserSearchSelectedCategory;
	[[NSUserDefaults standardUserDefaults] setInteger:LDrawPartBrowserSearchSelectedCategory forKey:PART_BROWSER_SEARCH_MODE];
	
	[self performSearch];
}


//========== addPartClicked: ===================================================
//
// Purpose:		Need to add the selected part to whoever is interested in that. 
//				This is dispatched as a nil-targeted action, and will most 
//				likely be picked up by the foremost document.
//
//==============================================================================
- (IBAction) addPartClicked:(id)sender
{
	if([self colorProblemForSelectedPart] != nil)
	{
		NSBeep();
		return;
	}

	//anyone who implements this message will know what to do.
	[NSApp sendAction:@selector(insertLDrawPart:) to:nil from:self];

}//end addPartClicked:


//========== addFavoriteClicked: ===============================================
//
// Purpose:		Adds the currently-selected part to the library's list of 
//				"favorite" parts. It seems users like to have a list like this. 
//
//==============================================================================
- (IBAction) addFavoriteClicked:(id)sender
{
	NSString *selectedPartName = [self selectedPartName];
	
	[self->partLibrary addPartNameToFavorites:selectedPartName];
	
	[self setConstraints];

}//end addFavoriteClicked:


//========== doubleClickedInPartTable: =========================================
//
// Purpose:		We mean this to insert a part.
//
//==============================================================================
- (void) doubleClickedInPartTable:(id)sender
{
	[self addPartClicked:sender];
	
}//end doubleClickedInPartTable:


//========== removeFavoriteClicked: ============================================
//
// Purpose:		Removes the currently-selected part from the library's 
//				"favorites" list, if it happens to be in it. 
//
//==============================================================================
- (IBAction) removeFavoriteClicked:(id)sender
{
	NSString *selectedPartName = [self selectedPartName];
	
	[self->partLibrary removePartNameFromFavorites:selectedPartName];
	
	[self setConstraints];
	
}//end removeFavoriteClicked:


//========== searchFieldChanged: ===============================================
//
// Purpose:		The search string has been changed. We do a search on the entire 
//				part library.
//
//==============================================================================
- (IBAction) searchFieldChanged:(id)sender
{
	[self performSearch];
	
}//end searchFieldChanged:


#pragma mark -
#pragma mark DATA SOURCES

#pragma mark -
#pragma mark NSOutlineView

//========== outlineView:numberOfChildrenOfItem: ===============================
//==============================================================================
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return [[LDrawPartBrowserModel categoryChildrenOfItem:item inHierarchy:categoryList] count];
}


//========== outlineView:child:ofItem: =========================================
//==============================================================================
- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return [[LDrawPartBrowserModel categoryChildrenOfItem:item inHierarchy:categoryList] objectAtIndex:index];
}


//========== outlineView:isItemExpandable: =====================================
//==============================================================================
- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	NSUInteger childCount = [self outlineView:outlineView numberOfChildrenOfItem:item];
	return (childCount != 0);
}


#pragma mark -
#pragma mark Table

//**** NSTableDataSource ****
//========== numberOfRowsInTableView: ==========================================
//
// Purpose:		Should return the number of parts in the category currently 
//				being browsed.
//
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	return [tableDataSource count];
	
}//end numberOfRowsInTableView


//**** NSTableDataSource ****
//========== tableView:objectValueForTableColumn:row: ===============================
//
// Purpose:		Displays information for the part in the record.
//
//==============================================================================
- (id)				tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
						  row:(NSInteger)rowIndex
{
	NSDictionary	*partRecord			= [self->tableDataSource objectAtIndex:rowIndex];
	NSString		*columnIdentifier	= [tableColumn identifier];
	NSNumber		*colorCode			= [partRecord objectForKey:LDrawPartBrowserColorCodeKey];
	
	NSString		*cellValue			= [partRecord objectForKey:columnIdentifier];
	
	if([columnIdentifier isEqualToString:LimitColorColumn])
		return (colorCode != nil) ? [self swatchForColorCode:(LDrawColorT)[colorCode intValue]] : nil;
	
	if([columnIdentifier isEqualToString:LimitCountColumn])
		return [partRecord objectForKey:LDrawPartBrowserCountTextKey];
	
	//If it's a part, get rid of the file extension on its name. A row of an
	// inventory with no LDraw part shows its LEGO number.
	if([columnIdentifier isEqualToString:PART_NUMBER_KEY])
		cellValue = [cellValue stringByDeletingPathExtension] ?: [partRecord objectForKey:LDrawPartBrowserLEGONumberKey];
	
	return cellValue;
	
}//end tableView:objectValueForTableColumn:row:


//**** NSTableDataSource ****
//========== tableView:sortDescriptorsDidChange: ===============================
//
// Purpose:		Resort the table elements.
//
//==============================================================================
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	NSArray			*newDescriptors	= [tableView sortDescriptors];
	NSDictionary	*selected		= [self selectedRecord];
	NSUInteger		 row			= NSNotFound;

	[tableDataSource sortUsingDescriptors:newDescriptors];
	[tableView reloadData];

	// The selected part stays selected where it moved to.
	row = (selected != nil) ? [tableDataSource indexOfObjectIdenticalTo:selected] : NSNotFound;
	if(row != NSNotFound)
	{
		[tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		[tableView scrollRowToVisible:row];
	}
	
}//end tableView:sortDescriptorsDidChange:


//**** NSTableDataSource ****
//========== tableView:writeRowsWithIndexes:toPasteboard: ======================
//
// Purpose:		It's time for drag-and-drop parts!
//
//				This method adds LDraw parts to the pasteboard.
//
// Notes:		We can have but one part selected in the browser, so the rows 
//				parameter is irrelevant. 
//
//==============================================================================
- (BOOL)     tableView:(NSTableView *)aTableView
  writeRowsWithIndexes:(NSIndexSet *)rowIndexes
		  toPasteboard:(NSPasteboard *)pasteboard
{
	BOOL	success = NO;
	
	// Select the dragged row (it may not have been selected), then write it to 
	// the pasteboard. 
	[self->partsTable selectRowIndexes:rowIndexes byExtendingSelection:NO];
	success = [self writeSelectedPartToPasteboard:pasteboard];
	
	return success;
		
}//end tableView:writeRowsWithIndexes:toPasteboard:


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

#pragma mark LDrawGLView

//========== LDrawView:writeDirectivesToPasteboard:asCopy: =====================
//
// Purpose:		Begin a drag-and-drop part insertion initiated in the directive 
//				view. 
//
//==============================================================================
- (BOOL)           LDrawView:(LDrawView *)glView
 writeDirectivesToPasteboard:(NSPasteboard *)pasteboard
					  asCopy:(BOOL)copyFlag
{
	BOOL	success = [self writeSelectedPartToPasteboard:pasteboard];
	
	return success;
	
}//end LDrawView:writeDirectivesToPasteboard:asCopy:


#pragma mark -
#pragma mark NSOutlineView

//========== outlineView:isGroupItem: ==========================================
//
// Purpose:		Get the Apple-defined group heading style by magic.
//
//				Source lists automatically get a different color font. (You are 
//				then responsible for capitalizing the text elsewhere.) 
//
//				Regular outline views get a gray bar across the cell.
//
//==============================================================================
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	NSUInteger childCount = [self outlineView:outlineView numberOfChildrenOfItem:item];
	
	return (childCount > 0);
}


//========== outlineView:shouldSelectItem: =====================================
//==============================================================================
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	BOOL isGroupHeading = [self outlineView:outlineView isGroupItem:item];
	
	return (isGroupHeading == NO);
}


//========== outlineView:shouldShowOutlineCellForItem: =========================
//
// Purpose:		Hide the disclosure triangle.
//
//==============================================================================
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item
{
	return NO;
}


//========== outlineViewSelectionDidChange: ====================================
//
// Purpose:		Select a new category.
//
//==============================================================================
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSDictionary	*categoryRecord	= [self->categoryTable itemAtRow:[categoryTable selectedRow]];
	NSString		*newCategory	= [categoryRecord objectForKey:CategoryNameKey];
	BOOL			 success		= NO;
	
	//Clear the search field
	[self->searchField setStringValue:@""];
	
	success = [self loadCategory:newCategory];
	[self syncSelectionAndPartDisplayed];
	
	if(success == YES)
		[userDefaults setObject:newCategory forKey:PART_BROWSER_PREVIOUS_CATEGORY];
}


//========== outlineView:viewForTableColumn:item: ==============================
///
/// @abstract	Returns the correct cell for the row.
///
/// 			Cell prototypes are defined in the nib file.
///
//==============================================================================
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BOOL				isGroupHeading	= [self outlineView:outlineView isGroupItem:item];
	NSTableCellView*	view			= nil;
	NSString*			name			= [item objectForKey:CategoryDisplayNameKey];
	NSString*			displayName 	= nil;

	if(isGroupHeading)
	{
		view = [outlineView makeViewWithIdentifier:@"HeaderCell" owner:nil];

		// Must manually capitalize the header title for source lists; Apple
		// doesn't do this magically for us.
		displayName = [name uppercaseString];
	}
	else
	{
		view = [outlineView makeViewWithIdentifier:@"CategoryCell" owner:nil];
		displayName = name;
	}
	view.textField.stringValue = displayName;

	return view;
}


#pragma mark -
#pragma mark NSTableView

//**** NSTableView ****
//========== tableViewSelectionDidChange: ======================================
//
// Purpose:		A new part has been selected.
//
//==============================================================================
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSUserDefaults  *userDefaults   = [NSUserDefaults standardUserDefaults];
	NSInteger       newRow          = [self->partsTable selectedRow];
	
	//Redisplay preview.
	[self syncSelectionAndPartDisplayed];
	[self setConstraints];

	// The Colors window lists the colors of the part the next insert makes.
	[[NSNotificationCenter defaultCenter] postNotificationName:PartBrowserSelectionDidChangeNotification
														object:self];
	
	//save for posterity.
	if(newRow != -1)
	{
		[userDefaults setInteger:newRow forKey:PART_BROWSER_PREVIOUS_SELECTED_ROW];
	}
	
}//end tableViewSelectionDidChange


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== sharedPartCatalogDidChange: =======================================
//
// Purpose:		The application has loaded a new part catalog from the LDraw 
//				folder. Data sources must be updated accordingly.
//
//==============================================================================
- (void) sharedPartCatalogDidChange:(NSNotification *)notification
{
	LDrawPartLibrary *newLibrary 			= [notification object];
	NSString	*originalSelectedCategory	= self->selectedCategory;
	NSString	*originalSearch				= [self->searchField stringValue];
	NSInteger	selectedRow 				= [self->partsTable selectedRow];
	
	[self setPartLibrary:newLibrary];
	
	// Restore the original selection (setting the part library wipes it out)
	
	[self loadCategory:originalSelectedCategory];
	
	if([originalSearch length] > 0)
	{
		[self->searchField setStringValue:originalSearch];
		[self performSearch];
	}
	
	[partsTable scrollRowToVisible:selectedRow];
	[partsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow]
			byExtendingSelection:NO];
	[self syncSelectionAndPartDisplayed];
	
}//end sharedPartCatalogDidChange:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== indexOfPartNamed: =================================================
//
// Purpose:		Returns the index of the part with the given name in the current 
//				found set. 
//
//==============================================================================
- (NSUInteger) indexOfPartNamed:(NSString *)searchName
{
	return [LDrawPartBrowserModel indexOfPartNamed:searchName inRecords:self->tableDataSource];
}//end indexOfPartNamed:


//========== performSearch =====================================================
//
// Purpose:		Executes the search based on the current search settings.
//
//==============================================================================
- (void) performSearch
{
	[self reloadRows];

	[self syncSelectionAndPartDisplayed];
	[self setConstraints];
}


//========== reloadRows ========================================================
//
// Purpose:		Lists the category, or the search, as the parts limit allows.
//
//==============================================================================
- (void) reloadRows
{
	[self prepareModel];
	[self->browserModel reloadFilter];
	[self updateLimitColumns];
	[self setTableDataSource:[self->browserModel.filteredParts mutableCopy]];
	[self updateLimitControls];
}


//========== prepareModel ======================================================
//
// Purpose:		Gives the model what is typed and chosen, and what the model in
//				the document uses when an inventory's rows need counts.
//
//==============================================================================
- (void) prepareModel
{
	LDrawPartBrowserModel	*model		= self->browserModel;
	NSString				*inventory	= [LDrawPartBrowserModel inventoryIdentifierForCategory:self->selectedCategory];
	LDrawPartLimitTable		*table		= [[[PartsLimitManager sharedManager] session] table];

	model.searchString			= [self->searchField stringValue];
	model.currentCategory		= self->selectedCategory ?: Category_All;
	model.searchMode			= self->searchMode;
	model.hidesDisallowedParts	= (self->showsAllParts == NO);

	if(self->filtersByCurrentColor)
		model.colorFilter = @([[[LDrawColorPanelController sharedColorPanel] LDrawColor] colorCode]);

	// The walk is kept per edit, so asking for it costs little.
	if(inventory != nil || table.limit.kind == LDrawPartLimitKindInventory)
		model.partUsage = [[[self countedDocument] partsLimitController] usage];
	else
		model.partUsage = nil;
}


//========== setConstraints ====================================================
//
// Purpose:		Sets the enabled or disabled state of controls in the part 
//				browser. 
//
//==============================================================================
- (void) setConstraints
{
	NSString    *selectedPart       = [self selectedPartName];
	NSArray     *favorites          = [self->partLibrary favoritePartNames];
	BOOL        partIsInFavorites   = [LDrawPartBrowserModel partNamed:selectedPart isInFavorites:favorites];
	BOOL		showSearchScopeButtons	= [LDrawPartBrowserModel shouldShowSearchScopeButtonsForSearchString:[searchField stringValue]
																									category:self->selectedCategory];
	BOOL		partActionsEnabled	= (selectedPart != nil);
	BOOL		showAddFavorite		= (partIsInFavorites == NO);
	BOOL		showRemoveFavorite	= (partIsInFavorites == YES);
	
	//---------- Set constraints -----------------------------------------------
	
	[self->searchAllCategoriesButton	setHidden:(showSearchScopeButtons == NO)];
	[self->searchSelectedCategoryButton	setHidden:(showSearchScopeButtons == NO)];
	
	[self->searchAllCategoriesButton	setState:(self->searchMode == LDrawPartBrowserSearchAllCategories)];
	[self->searchSelectedCategoryButton	setState:(self->searchMode == LDrawPartBrowserSearchSelectedCategory)];
	
	[self->searchSelectedCategoryButton setTitle:[self->browserModel displayNameForCategory:self->selectedCategory]];
	[self->searchSelectedCategoryButton sizeToFit];

	// A part not made in the current color waits for another color.
	NSString	*colorProblem		= [self colorProblemForSelectedPart];

	[self->insertButton				setEnabled:(partActionsEnabled && colorProblem == nil)];
	[self->insertButton				setToolTip:colorProblem];
	
	// Favorites Add/Remove button
	[self->addRemoveFavoriteButton	setEnabled:partActionsEnabled];
	
	if(showAddFavorite == NO)
	{
		[self->addRemoveFavoriteButton	setAction:@selector(removeFavoriteClicked:)];
		[self->addRemoveFavoriteButton	setImage:[NSImage imageNamed:[LDrawPartBrowserModel favoriteButtonImageNameWhenShowingAdd:NO]]];
	}
	else
	{
		[self->addRemoveFavoriteButton	setAction:@selector(addFavoriteClicked:)];
		[self->addRemoveFavoriteButton	setImage:[NSImage imageNamed:[LDrawPartBrowserModel favoriteButtonImageNameWhenShowingAdd:YES]]];
	}
	
	// Hide inapplicable menu items.
	[[self->contextualMenu itemWithTag:LDrawPartBrowserAddFavoriteTag]		setHidden:(showAddFavorite == NO)];
	[[self->contextualMenu itemWithTag:LDrawPartBrowserRemoveFavoriteTag]	setHidden:(showRemoveFavorite == NO)];
	
}//end setConstraints


//========== scrollSelectedCategoryToCenter ====================================
//
// Purpose:		Scroll the current category selection to the center of the 
//				table. This only works if the enclosing window/split view has 
//				been already been resized to its final height. 
//
//==============================================================================
- (void) scrollSelectedCategoryToCenter
{
	NSInteger selectedRow = [self->categoryTable selectedRow];
	
	[categoryTable scrollRowToCenter:selectedRow];
}


//========== syncSelectionAndCategoryDisplayed =================================
//
// Purpose:		Selects the current category in the category table.
//
//==============================================================================
- (void) syncSelectionAndCategoryDisplayed
{
	id			categoryItem	= [LDrawPartBrowserModel categoryItemNamed:self->selectedCategory
															   inHierarchy:self->categoryList];
	NSInteger	categoryRow 	= [categoryTable rowForItem:categoryItem];
	[categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:categoryRow] byExtendingSelection:NO];
}


//========== syncSelectionAndPartDisplayed =====================================
//
// Purpose:		Makes the current part displayed match the part selected in the 
//				table.
//
//==============================================================================
- (void) syncSelectionAndPartDisplayed
{
	NSString    *selectedPartName   = [self selectedPartName];
	LDrawPart   *newPart            = nil;
		
	if(selectedPartName != nil)
	{
		// Not this simple anymore. We have to make sure to draw the optimized
		// vertexes. The easiest way to do that is to create a part referencing
		// the model.
//		modelToView = [self->partLibrary modelForName:selectedPartName];

		NSNumber	*rowColor	= [[self selectedRecord] objectForKey:LDrawPartBrowserColorCodeKey];
		LDrawColorT	 colorCode	= (rowColor != nil) ? (LDrawColorT)[rowColor intValue] : LDrawCurrentColor;

		newPart = [LDrawInsertion partNamed:selectedPartName
									  color:[[LDrawColorLibrary sharedColorLibrary] colorForCode:colorCode]
					   copyingTransformFrom:nil];
		[LDrawApplication makeCurrentSharedContext];
	}
	[partPreview setLDrawDirective:newPart];
	[self updateColorStrip];
	
}//end syncSelectionAndPartDisplayed


//========== writeSelectedPartToPasteboard: ====================================
//
// Purpose:		Writes the current part-browser selection onto the pasteboard.
//
//==============================================================================
- (BOOL) writeSelectedPartToPasteboard:(NSPasteboard *)pasteboard
{
	NSString   *partName      = [self selectedPartName];
	LDrawColor *selectedColor = [self insertionColor];
	NSArray    *archivedParts = nil;

	if([self colorProblemForSelectedPart] != nil)
		return NO;

	archivedParts = [LDrawClipboard archivedDraggingDataForPartNamed:partName color:selectedColor];

	if(archivedParts != nil)
	{
		// Set up pasteboard
		[pasteboard declareTypes:[LDrawClipboard partBrowserDeclaredDragTypes] owner:self];

		[pasteboard setPropertyList:archivedParts
							forType:LDrawDraggingPboardType];

		[pasteboard setPropertyList:[NSNumber numberWithBool:YES]
							forType:LDrawDraggingIsUninitializedPboardType];

		return YES;
	}

	return NO;
	
}//end writeSelectedPartToPasteboard:


#pragma mark -
#pragma mark PARTS LIMIT
#pragma mark -

//========== installLimitControls ==============================================
//
// Purpose:		Adds the bar over the parts list, the color strip under the
//				preview and the color filter button after Favorites. All stay
//				hidden until a limit needs them.
//
//==============================================================================
- (void) installLimitControls
{
	NSScrollView	*scrollView	= [self->partsTable enclosingScrollView];
	NSView			*listView	= [scrollView superview];
	NSRect			 favorite	= [self->addRemoveFavoriteButton frame];
	NSRect			 filter		= NSMakeRect(NSMaxX(favorite) + 2, NSMinY(favorite), 30, NSHeight(favorite));

	self->limitBar = [[PartBrowserLimitBar alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([scrollView frame]),
																			LimitBarHeight)];
	[self->limitBar setAutoresizingMask:NSViewWidthSizable | ([listView isFlipped] ? NSViewMaxYMargin
																				   : NSViewMinYMargin)];
	[[self->limitBar button] setTarget:self];
	[[self->limitBar button] setAction:@selector(toggleShowsAllParts:)];
	[self->limitBar setHidden:YES];
	[listView addSubview:self->limitBar];

	self->colorStrip = [[PartColorStripView alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
	[self->colorStrip setTarget:self];
	[self->colorStrip setAction:@selector(colorChipClicked:)];
	[self->colorStrip setHidden:YES];
	[self->partPreviewViewport setBottomAccessory:self->colorStrip];

	// The insert button may sit close after Favorites.
	if([self->insertButton superview] == [self->addRemoveFavoriteButton superview])
		filter.size.width = MAX(MIN(NSWidth(filter), NSMinX([self->insertButton frame]) - NSMinX(filter)), 20);

	self->colorFilterButton = [[NSPopUpButton alloc] initWithFrame:filter pullsDown:YES];
	[self->colorFilterButton setBordered:NO];
	[[self->colorFilterButton cell] setArrowPosition:NSPopUpNoArrow];
	[[self->colorFilterButton cell] setImagePosition:NSImageOnly];
	[self->colorFilterButton addItemWithTitle:@""];
	[[self->colorFilterButton menu] setDelegate:self];
	[self->colorFilterButton setToolTip:NSLocalizedString(@"Show only the parts in a color", nil)];
	[self->colorFilterButton setAutoresizingMask:[self->addRemoveFavoriteButton autoresizingMask]];
	[self->colorFilterButton setHidden:YES];
	[[self->addRemoveFavoriteButton superview] addSubview:self->colorFilterButton];
	[self updateColorFilterButton];

}//end installLimitControls


//========== observeLimit ======================================================
//
// Purpose:		The list follows the limit, the counted document's edits, the
//				Colors window and the setting in Settings.
//
//==============================================================================
- (void) observeLimit
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

	[center addObserver:self
			   selector:@selector(partsLimitDidChange:)
				   name:LDrawPartLimitDidChangeNotification
				 object:[[PartsLimitManager sharedManager] session]];
	[center addObserver:self
			   selector:@selector(documentDidCheck:)
				   name:PartsLimitDidCheckNotification
				 object:nil];
	[center addObserver:self
			   selector:@selector(mainWindowDidChange:)
				   name:NSWindowDidBecomeMainNotification
				 object:nil];
	[center addObserver:self
			   selector:@selector(currentColorDidChange:)
				   name:LDrawColorDidChangeNotification
				 object:nil];
	[center addObserver:self
			   selector:@selector(browserSettingDidChange:)
				   name:PartsLimitBrowserSettingDidChangeNotification
				 object:nil];

}//end observeLimit


//========== updateLimitColumns ================================================
//
// Purpose:		An inventory's rows get a swatch column first and a Count column
//				last. Other rows go without them.
//
//==============================================================================
- (void) updateLimitColumns
{
	BOOL			 wantsColumns	= self->browserModel.showsInventoryRows;
	NSTableColumn	*colorColumn	= [self->partsTable tableColumnWithIdentifier:LimitColorColumn];
	NSTableColumn	*countColumn	= [self->partsTable tableColumnWithIdentifier:LimitCountColumn];
	NSTableColumn	*nameColumn		= [self->partsTable tableColumnWithIdentifier:PART_NAME_KEY];

	if(wantsColumns && colorColumn == nil)
	{
		colorColumn = [[NSTableColumn alloc] initWithIdentifier:LimitColorColumn];
		[colorColumn setDataCell:[[NSImageCell alloc] init]];
		[colorColumn setWidth:SwatchSize + 6];
		[colorColumn setMinWidth:SwatchSize + 6];
		[colorColumn setMaxWidth:SwatchSize + 6];
		[colorColumn setResizingMask:NSTableColumnNoResizing];
		[[colorColumn headerCell] setStringValue:@""];
		[self->partsTable addTableColumn:colorColumn];
		[self->partsTable moveColumn:[self->partsTable numberOfColumns] - 1 toColumn:0];

		countColumn = [[NSTableColumn alloc] initWithIdentifier:LimitCountColumn];
		[[countColumn headerCell] setStringValue:NSLocalizedString(@"Count", nil)];
		[[countColumn dataCell] setAlignment:NSTextAlignmentRight];
		[[countColumn dataCell] setFont:[[nameColumn dataCell] font]];
		[countColumn setWidth:64];
		[countColumn setMinWidth:44];
		[countColumn setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:LDrawPartBrowserLeftKey
																			   ascending:YES]];
		[self->partsTable addTableColumn:countColumn];
	}
	else if(wantsColumns == NO && colorColumn != nil)
	{
		NSSortDescriptor *sort = [[self->partsTable sortDescriptors] firstObject];

		[self->partsTable removeTableColumn:colorColumn];
		[self->partsTable removeTableColumn:countColumn];

		// What is left means nothing without counts.
		if([[sort key] isEqualToString:LDrawPartBrowserLeftKey] && [nameColumn sortDescriptorPrototype] != nil)
			[self->partsTable setSortDescriptors:@[[nameColumn sortDescriptorPrototype]]];
	}

}//end updateLimitColumns


//========== updateLimitControls ===============================================
//
// Purpose:		Shows the bar while something limits the list, and the color
//				filter while the limit restricts colors.
//
//==============================================================================
- (void) updateLimitControls
{
	NSString	*buttonTitle	= nil;
	NSString	*text			= [self limitBarTextWithButtonTitle:&buttonTitle];

	[self setLimitBarShown:(text != nil)];
	if(text != nil)
		[self->limitBar setText:text buttonTitle:buttonTitle];

	[self->colorFilterButton setHidden:([self->browserModel filterColorCodes] == nil)];
	[self updateColorFilterButton];

}//end updateLimitControls


//========== setLimitBarShown: =================================================
//
// Purpose:		Puts the bar over the parts list, which gives up the room, or
//				takes it away.
//
//==============================================================================
- (void) setLimitBarShown:(BOOL)shown
{
	NSScrollView	*scrollView	= [self->partsTable enclosingScrollView];
	BOOL			 isFlipped	= [[scrollView superview] isFlipped];
	NSRect			 list		= [scrollView frame];
	NSRect			 bar		= [self->limitBar frame];

	if(shown == ([self->limitBar isHidden] == NO))
		return;

	if(shown)
	{
		list.size.height -= LimitBarHeight;
		if(isFlipped)
			list.origin.y += LimitBarHeight;
	}
	else
	{
		list.size.height += LimitBarHeight;
		if(isFlipped)
			list.origin.y -= LimitBarHeight;
	}

	bar.origin.x	= NSMinX(list);
	bar.origin.y	= isFlipped ? NSMinY(list) - LimitBarHeight : NSMaxY(list);
	bar.size.width	= NSWidth(list);

	[scrollView setFrame:list];
	[self->limitBar setFrame:bar];
	[self->limitBar setHidden:(shown == NO)];

}//end setLimitBarShown:


//========== limitBarTextWithButtonTitle: ======================================
//
// Purpose:		What the bar says, or nil for no bar. A limit gets a button to
//				list every part, or to hide the others again.
//
//==============================================================================
- (NSString *) limitBarTextWithButtonTitle:(NSString **)buttonTitle
{
	LDrawPartBrowserModel	*model		= self->browserModel;
	LDrawPartLimitTable		*table		= model.activeTable;
	LDrawPartLimit			*limit		= table.limit;
	NSString				*inventory	= [LDrawPartBrowserModel inventoryIdentifierForCategory:self->selectedCategory];
	NSInteger				 year		= [[[PartsLimitManager sharedManager] session] currentYear];
	NSString				*text		= nil;

	*buttonTitle = nil;

	if(table == nil)
		return nil;

	if(inventory != nil && model.showsInventoryRows)
		return [NSString stringWithFormat:NSLocalizedString(@"Parts of %@", nil),
				[model displayNameForCategory:self->selectedCategory]];

	if(limit.kind == LDrawPartLimitKindAvailableNow)
	{
		if(limit.yearsBack <= 0)
			text = NSLocalizedString(@"Parts in the colors they were made in", nil);
		else if(limit.yearsBack == 1)
			text = [NSString stringWithFormat:NSLocalizedString(@"Parts made in %ld", nil), (long)year];
		else
			text = [NSString stringWithFormat:NSLocalizedString(@"Parts made in %ld–%ld", nil),
					(long)(year - limit.yearsBack + 1), (long)year];
	}
	else
	{
		text = [NSString stringWithFormat:NSLocalizedString(@"Parts of %@", nil),
				[[PartsLimitManager sharedManager] titleForLimit:limit] ?: @""];
	}

	*buttonTitle = self->showsAllParts ? NSLocalizedString(@"Hide Others", nil) : NSLocalizedString(@"Show All", nil);
	return text;

}//end limitBarTextWithButtonTitle:


//========== updateColorStrip ==================================================
//
// Purpose:		Shows the selected part's colors under the preview. When the
//				current color is not among them, it comes first, crossed out.
//
//==============================================================================
- (void) updateColorStrip
{
	NSDictionary	*record			= [self selectedRecord];
	NSNumber		*rowColor		= [record objectForKey:LDrawPartBrowserColorCodeKey];
	LDrawColorT		 panelColor		= [[[LDrawColorPanelController sharedColorPanel] LDrawColor] colorCode];
	NSArray			*chips			= [self->browserModel colorChipsForPartNamed:[record objectForKey:PART_NUMBER_KEY]];
	NSString		*colorProblem	= [self colorProblemForSelectedPart];

	[self->colorStrip setChips:chips
				  currentColor:(rowColor != nil) ? (LDrawColorT)[rowColor intValue] : panelColor
				   struckColor:(colorProblem != nil) ? @(panelColor) : nil
				 struckTooltip:colorProblem];

}//end updateColorStrip


//========== colorProblemForSelectedPart =======================================
//
// Purpose:		Why the selected part cannot go in in the current color, or nil
//				when it can. An inventory row brings its own color, and Warn
//				Only lets any color through.
//
//==============================================================================
- (NSString *) colorProblemForSelectedPart
{
	NSDictionary		*record		= [self selectedRecord];
	NSString			*partName	= [record objectForKey:PART_NUMBER_KEY];
	LDrawPartLimitTable	*table		= self->browserModel.activeTable;
	LDrawColor			*color		= [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawPartLimitStatus status		= LDrawPartLimitStatusAllowed;

	if(		partName == nil
	   ||	[record objectForKey:LDrawPartBrowserColorCodeKey] != nil
	   ||	table == nil
	   ||	table.limit.warnsOnly )
		return nil;

	status = [self->browserModel statusForPartNamed:partName colorCode:[color colorCode]];
	if(status != LDrawPartLimitStatusNotInColor)
		return nil;

	if(table.limit.kind == LDrawPartLimitKindAvailableNow)
		return [NSString stringWithFormat:NSLocalizedString(@"Not made in %@ now. Pick a color below.", nil),
				[color localizedName]];
	return [NSString stringWithFormat:NSLocalizedString(@"The inventory has none in %@. Pick a color below.", nil),
			[color localizedName]];

}//end colorProblemForSelectedPart


//========== colorChipClicked: =================================================
//
// Purpose:		An inventory's chip selects its row; any other chip makes its
//				color the current one, as a click in the Colors window does.
//
//==============================================================================
- (void) colorChipClicked:(id)sender
{
	LDrawPartBrowserColorChip	*chip	= [self->colorStrip clickedChip];
	NSUInteger					 row	= NSNotFound;

	if(chip == nil)
		return;

	if(chip.record != nil)
	{
		row = [self->tableDataSource indexOfObjectIdenticalTo:chip.record];
		if(row == NSNotFound)
		{
			NSBeep();
			return;
		}
		[self->partsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		[self->partsTable scrollRowToVisible:row];
	}
	else
	{
		[[LDrawColorPanelController sharedColorPanel] setLDrawColor:
		 [[LDrawColorLibrary sharedColorLibrary] colorForCode:chip.colorCode]];
	}

}//end colorChipClicked:


//========== toggleShowsAllParts: ==============================================
//==============================================================================
- (IBAction) toggleShowsAllParts:(id)sender
{
	self->showsAllParts = (self->showsAllParts == NO);
	[self performSearch];
}


//**** NSMenuDelegate ****
//========== menuNeedsUpdate: ==================================================
//
// Purpose:		The color filter's menu: any color, the current color, then
//				every color the list can be filtered by.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	LDrawColor	*current	= [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	NSNumber	*filter		= self->browserModel.colorFilter;
	NSMenuItem	*item		= nil;

	if(menu != [self->colorFilterButton menu])
		return;

	[menu removeAllItems];
	[menu addItemWithTitle:@"" action:NULL keyEquivalent:@""];

	item = [menu addItemWithTitle:NSLocalizedString(@"Any Color", nil)
						   action:@selector(chooseColorFilter:)
					keyEquivalent:@""];
	[item setState:(filter == nil) ? NSControlStateValueOn : NSControlStateValueOff];

	item = [menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Current Color (%@)", nil),
								   [current localizedName]]
						   action:@selector(chooseColorFilter:)
					keyEquivalent:@""];
	[item setTag:1];
	[item setState:self->filtersByCurrentColor ? NSControlStateValueOn : NSControlStateValueOff];

	[menu addItem:[NSMenuItem separatorItem]];

	for(NSNumber *colorCode in [self->browserModel filterColorCodes])
	{
		LDrawColorT code = (LDrawColorT)[colorCode intValue];

		item = [menu addItemWithTitle:[[[LDrawColorLibrary sharedColorLibrary] colorForCode:code] localizedName]
							   action:@selector(chooseColorFilter:)
						keyEquivalent:@""];
		[item setImage:[self swatchForColorCode:code]];
		[item setRepresentedObject:colorCode];
		[item setState:(self->filtersByCurrentColor == NO && [filter isEqual:colorCode])
					   ? NSControlStateValueOn : NSControlStateValueOff];
	}

	for(NSMenuItem *each in [menu itemArray])
		[each setTarget:self];

}//end menuNeedsUpdate:


//========== chooseColorFilter: ================================================
//==============================================================================
- (IBAction) chooseColorFilter:(id)sender
{
	self->filtersByCurrentColor			= ([sender tag] == 1);
	self->browserModel.colorFilter		= [sender representedObject];
	[self performSearch];
}


//========== updateColorFilterButton ===========================================
//
// Purpose:		The button shows the filter's color while one is on.
//
//==============================================================================
- (void) updateColorFilterButton
{
	NSNumber	*filter	= self->browserModel.colorFilter;
	NSImage		*image	= nil;

	if(filter != nil)
		image = PartBrowserSwatchImage((LDrawColorT)[filter intValue], NSMakeSize(18, 18), YES, NO);
	else
		image = [NSImage imageWithSystemSymbolName:@"line.3.horizontal.decrease.circle"
						  accessibilityDescription:NSLocalizedString(@"Color filter", nil)];

	[[self->colorFilterButton itemAtIndex:0] setImage:image];

}//end updateColorFilterButton


//========== swatchForColorCode: ===============================================
//==============================================================================
- (NSImage *) swatchForColorCode:(LDrawColorT)colorCode
{
	NSImage *swatch = [self->swatches objectForKey:@(colorCode)];

	if(swatch == nil)
	{
		swatch = PartBrowserSwatchImage(colorCode, NSMakeSize(SwatchSize, SwatchSize), NO, NO);
		if(self->swatches == nil)
			self->swatches = [NSMutableDictionary dictionary];
		[self->swatches setObject:swatch forKey:@(colorCode)];
	}
	return swatch;

}//end swatchForColorCode:


//========== countedDocument ===================================================
//
// Purpose:		The document whose model the counts are for: the window's own,
//				or for the shared panel, the main window's. With the app in the
//				background there is no main window, so the frontmost document.
//
//==============================================================================
- (LDrawDocument *) countedDocument
{
	id document = [[[self->partsTable window] windowController] document];

	if([document isKindOfClass:[LDrawDocument class]] == NO)
		document = [[NSDocumentController sharedDocumentController] currentDocument];
	if(document == nil)
		document = [[NSApp orderedDocuments] firstObject];

	return [document isKindOfClass:[LDrawDocument class]] ? document : nil;

}//end countedDocument


//**** NSTableViewDelegate ****
//========== tableView:willDisplayCell:forTableColumn:row: =====================
//
// Purpose:		Grays parts the limit does not allow and rows with nothing
//				left, and makes rows past their count red.
//
//==============================================================================
- (void) tableView:(NSTableView *)tableView
   willDisplayCell:(id)cell
	forTableColumn:(NSTableColumn *)tableColumn
			   row:(NSInteger)row
{
	NSColor *color = [NSColor controlTextColor];

	if(tableView != self->partsTable || [cell isKindOfClass:[NSTextFieldCell class]] == NO)
		return;

	// A selected row keeps the selection's colors.
	if([tableView isRowSelected:row] == NO && row < (NSInteger)[self->tableDataSource count])
	{
		switch([self->browserModel stateForRecord:[self->tableDataSource objectAtIndex:row]])
		{
			case LDrawPartBrowserRowDimmed:
			case LDrawPartBrowserRowAllUsed:
			case LDrawPartBrowserRowNoPart:
				color = [NSColor secondaryLabelColor];
				break;
			case LDrawPartBrowserRowOver:
				color = [NSColor systemRedColor];
				break;
			case LDrawPartBrowserRowNormal:
				break;
		}
	}
	[cell setTextColor:color];

}//end tableView:willDisplayCell:forTableColumn:row:


//**** NSTableViewDelegate ****
//========== tableView:toolTipForCell:rect:tableColumn:row:mouseLocation: ======
//
// Purpose:		The spares in a count, and why a row cannot be inserted.
//
//==============================================================================
- (NSString *) tableView:(NSTableView *)tableView
		  toolTipForCell:(NSCell *)cell
					rect:(NSRectPointer)rect
			 tableColumn:(NSTableColumn *)tableColumn
					 row:(NSInteger)row
		   mouseLocation:(NSPoint)mouseLocation
{
	NSDictionary	*record	= (row < (NSInteger)[self->tableDataSource count])
							  ? [self->tableDataSource objectAtIndex:row] : nil;
	NSUInteger		 spares	= [[record objectForKey:LDrawPartBrowserSparesKey] unsignedIntegerValue];
	NSUInteger		 owned	= [[record objectForKey:LDrawPartBrowserOwnedKey] unsignedIntegerValue];

	if([self->browserModel stateForRecord:record] == LDrawPartBrowserRowNoPart)
		return [NSString stringWithFormat:NSLocalizedString(@"No LDraw part matches LEGO %@.", nil),
				[record objectForKey:LDrawPartBrowserLEGONumberKey]];

	if([[tableColumn identifier] isEqualToString:LimitCountColumn] && spares > 0)
		return [NSString stringWithFormat:NSLocalizedString(@"%lu + %lu spare", nil),
				(unsigned long)(owned - spares), (unsigned long)spares];

	return nil;

}//end tableView:toolTipForCell:rect:tableColumn:row:mouseLocation:


#pragma mark -
#pragma mark Limit notifications

//========== partsLimitDidChange: ==============================================
//
// Purpose:		The limit, or the sets the store has, changed. The Sets group
//				is listed again, and the list reloaded where it was.
//
//==============================================================================
- (void) partsLimitDidChange:(NSNotification *)notification
{
	NSString	*category	= self->selectedCategory;
	NSString	*search		= [self->searchField stringValue];

	// A filter color makes no sense once the limit offers none.
	if(self->browserModel.colorFilter != nil)
	{
		[self prepareModel];
		[self->browserModel reloadFilter];
		if([[self->browserModel filterColorCodes] containsObject:self->browserModel.colorFilter] == NO)
		{
			self->browserModel.colorFilter	= nil;
			self->filtersByCurrentColor		= NO;
		}
	}

	[self setCategoryList:[self->browserModel categoryHierarchy]];
	if([self->browserModel hasCategory:category] == NO)
		category = Category_All;

	[self loadCategory:category];
	if([search length] > 0)
	{
		[self->searchField setStringValue:search];
		[self performSearch];
	}
	[self syncSelectionAndPartDisplayed];

}//end partsLimitDidChange:


//========== documentDidCheck: =================================================
//
// Purpose:		The counted model changed, so an inventory's counts do too.
//
//==============================================================================
- (void) documentDidCheck:(NSNotification *)notification
{
	if(self->browserModel.showsInventoryRows && [notification object] == [self countedDocument])
		[self performSearch];
}


//========== mainWindowDidChange: ==============================================
//
// Purpose:		The shared panel counts the main window's model.
//
//==============================================================================
- (void) mainWindowDidChange:(NSNotification *)notification
{
	BOOL isPanel = ([[[[self->partsTable window] windowController] document] isKindOfClass:[LDrawDocument class]]
					== NO);

	if(isPanel && self->browserModel.showsInventoryRows && [notification object] != [self->partsTable window])
		[self performSearch];
}


//========== currentColorDidChange: ============================================
//
// Purpose:		The Colors window's color decides what can be inserted, and
//				what the Current Color filter keeps.
//
//==============================================================================
- (void) currentColorDidChange:(NSNotification *)notification
{
	if(self->filtersByCurrentColor)
		[self performSearch];
	else
	{
		[self updateColorStrip];
		[self setConstraints];
	}
}


//========== browserSettingDidChange: ==========================================
//==============================================================================
- (void) browserSettingDidChange:(NSNotification *)notification
{
	self->showsAllParts = [[NSUserDefaults standardUserDefaults] boolForKey:PARTS_LIMIT_BROWSER_SHOWS_ALL_KEY];
	[self performSearch];
}


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		It's AppKit, in the Library, with the Lead Pipe!!!
//
//==============================================================================
- (void) dealloc
{
	//Remove notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	topLevelObjects = nil;
	
}//end dealloc


@end
