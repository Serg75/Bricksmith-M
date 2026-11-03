//==============================================================================
//
// File:		LDrawColorPanelController.h
//
// Purpose:		Color-picker for Bricksmith.
//
//  Created by Allen Smith on 2/26/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawCore/LDrawColorLibrary.h>

@class LDrawColorBar;

////////////////////////////////////////////////////////////////////////////////
//
// Class:		LDrawColorPanelController
//
////////////////////////////////////////////////////////////////////////////////
@interface LDrawColorPanelController : NSWindowController <LDrawColorable, NSTableViewDelegate>
{
	__weak IBOutlet	LDrawColorBar		*colorBar;
	__weak IBOutlet	NSPopUpButton		*materialPopUpButton;
	__weak IBOutlet	NSTableView			*colorTable;
	__weak IBOutlet	NSSearchField		*searchField;
				
	__weak IBOutlet	NSArrayController	*colorListController;
	
				//YES if we are in the middle of updating the color panel to 
				// reflect the current selection, NO any other time.
				BOOL				 updatingToReflectFile;

				// Parts limit
				NSArray				*selectedPartNames;	// parts selected in the document
				NSString			*browserPartName;	// the Part Browser's part, for when none are
				BOOL				 hasSelection;		// the document's selection holds anything
				NSArray				*allowedColorCodes;	// the colors those parts may take, or nil for any
				NSTextField			*footerField;		// says why the list is short
				CGFloat				 footerSpace;		// the height the list gives up for it
				BOOL				 isRefiltering;		// the limit changes the list; no color is applied
}

//Initialization
+ (LDrawColorPanelController *) sharedColorPanel;

//Actions
- (void) focusSearchField:(id)sender;
- (IBAction) materialPopUpButtonChanged:(id)sender;
- (void) sendAction;
- (IBAction) searchFieldChanged:(id)sender;
- (void) updateSelectionWithObjects:(NSArray *)selectedObjects;

//Utilities
- (NSInteger) indexOfColor:(LDrawColor *)colorSought;
- (void) loadInitialSortDescriptors;

@end
