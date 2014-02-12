//
//  SearchPanel.h
//  Bricksmith
//
//  Created by Robin Macharg on 06/02/2014.
//

#import <Cocoa/Cocoa.h>
#import "LDrawColorWell.h"

// UI radio buttons are tagged:
// Where to search
typedef enum {
    ScopeFile  = 1,
    ScopeModel = 2,
    ScopeStep  = 3,
    ScopeSelection = 4
} ScopeT;

// How to search for colors
typedef enum {
    ColorNoFilter = 1,
    ColorSelectionFilter = 2,
    ColorFilter = 3
} ColorFilterT;

// What to search for
typedef enum {
    SearchAllParts = 1,
    SearchSpecificPart = 2,
    SearchSelectedParts = 3
} SearchPartCriteriaT;

@interface SearchPanel : NSPanel <NSWindowDelegate, NSDraggingDestination>
{
    IBOutlet SearchPanel *searchPanel;
    IBOutlet NSMatrix *scopeMatrix;
    IBOutlet NSMatrix *colorMatrix;
    IBOutlet LDrawColorWell *colorWell;
    IBOutlet NSMatrix *findTypeMatrix;
    IBOutlet NSButton *searchInsideLSynthContainers;
    IBOutlet NSTextField *partName;
}

- (IBAction)doSearchAndSelect:(id)sender;
- (void) updateInterfaceForSelection:(NSArray *)selectedObjects;

//Initialization
+ (SearchPanel *) sharedSearchPanel;

@end