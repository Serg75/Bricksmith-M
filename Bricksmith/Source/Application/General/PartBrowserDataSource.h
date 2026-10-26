//==============================================================================
//
// File:		PartBrowserDataSource.h
//
// Purpose:		Provides a standardized data source for part browser interface.
//
//  Created by Allen Smith on 2/17/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawFeatures/LDrawPartBrowserModel.h>

#import "LDrawView.h"

@class LDrawColor;
@class LDrawViewerContainer;
@class LDrawPartLibrary;
@class PartBrowserLimitBar;
@class PartColorStripView;

////////////////////////////////////////////////////////////////////////////////
//
// class PartBrowserDataSource
//
////////////////////////////////////////////////////////////////////////////////
@interface PartBrowserDataSource : NSObject <NSOutlineViewDelegate, NSOutlineViewDataSource, NSTableViewDelegate,
											 NSMenuDelegate>
{
	__weak IBOutlet NSButton		*searchAllCategoriesButton;
	__weak IBOutlet NSButton		*searchSelectedCategoryButton;
	__weak IBOutlet NSSearchField	*searchField;
	
	__weak IBOutlet NSOutlineView	*categoryTable;
	__weak IBOutlet NSTableView		*partsTable;
	__weak IBOutlet LDrawView		*partPreview;
	__weak IBOutlet LDrawViewerContainer	*partPreviewViewport;
	__weak IBOutlet NSButton		*zoomInButton;
	__weak IBOutlet NSButton		*zoomOutButton;
	__weak IBOutlet NSButton		*addRemoveFavoriteButton;
	__weak IBOutlet NSButton		*insertButton;
	__weak IBOutlet NSMenu			*contextualMenu;

	NSArray				*topLevelObjects;	// holds NIB objects

	__weak LDrawPartLibrary	*partLibrary; //weak reference to the shared part catalog.
	NSString				*selectedCategory;
	NSArray 				*categoryList;
	NSMutableArray  		*tableDataSource;
	LDrawPartBrowserSearchMode	searchMode;
	LDrawPartBrowserModel	*browserModel;

	// Parts limit
	PartBrowserLimitBar		*limitBar;			// over the list while a limit or a set is shown
	PartColorStripView		*colorStrip;		// under the preview
	NSPopUpButton			*colorFilterButton;	// in the bottom bar
	BOOL					 showsAllParts;		// the bar's Show All
	BOOL					 filtersByCurrentColor;	// the color filter follows the Colors window
	NSMutableDictionary		*swatches;			// images by color code
}

//Accessors
- (NSString *) category;
- (NSString *) selectedPartName;
- (LDrawColor *) insertionColor;

- (void) setPartLibrary:(LDrawPartLibrary *)partLibraryIn;
- (BOOL) loadCategory:(NSString *)newCategory;
- (void) setCategoryList:(NSArray *)categoryList;
- (void) setTableDataSource:(NSMutableArray *) partsInCategory;

//Actions
- (IBAction) searchAllCategoriesButtonClicked:(id)sender;
- (IBAction) searchSelectedCategoryButtonClicked:(id)sender;
- (IBAction) addPartClicked:(id)sender;
- (IBAction) addFavoriteClicked:(id)sender;
- (void) doubleClickedInPartTable:(id)sender;
- (IBAction) removeFavoriteClicked:(id)sender;
- (IBAction) searchFieldChanged:(id)sender;

//Notifications
- (void) sharedPartCatalogDidChange:(NSNotification *)notification;

//Utilities
- (NSUInteger) indexOfPartNamed:(NSString *)searchName;
- (void) performSearch;
- (void) setConstraints;
- (void) scrollSelectedCategoryToCenter;
- (void) syncSelectionAndCategoryDisplayed;
- (void) syncSelectionAndPartDisplayed;
- (BOOL) writeSelectedPartToPasteboard:(NSPasteboard *)pasteboard;

@end
