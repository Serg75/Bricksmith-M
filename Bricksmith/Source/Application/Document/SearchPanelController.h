//
//  SearchPanel.h
//  Bricksmith
//
//  Created by Robin Macharg on 06/02/2014.
//

#import <Cocoa/Cocoa.h>
#import "LDrawColorWell.h"
#import <LDrawEditing/LDrawSearch.h>

@interface SearchPanelController : NSWindowController <NSWindowDelegate, NSDraggingDestination>
{
	__weak IBOutlet NSMatrix		*scopeMatrix;
	__weak IBOutlet NSMatrix		*colorMatrix;
	__weak IBOutlet LDrawColorWell	*colorWell;
	__weak IBOutlet NSMatrix		*findTypeMatrix;
	__weak IBOutlet NSButton		*searchInsideLSynthContainers;
	__weak IBOutlet NSButton		*searchHiddenParts;
	__weak IBOutlet NSTextField		*partName;
	__weak IBOutlet NSTextField		*warningText;
}

//Initialization
+ (SearchPanelController *) searchPanel;

// Accessors
+ (BOOL) isVisible;

// Actions
- (IBAction)doSearchAndSelect:(id)sender;
- (IBAction)scopeChanged:(id)sender;
- (IBAction)colorOptionChanged:(id)sender;
- (IBAction)findTypeOptionChanged:(id)sender;

// Utility
- (void) updateInterfaceForSelection:(NSArray *)selectedObjects;

@end
