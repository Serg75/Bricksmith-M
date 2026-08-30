//==============================================================================
//
// File:		SearchPanel.m
//
// Purpose:		Search for parts in a file.  Structure copied from ColorPanel.
//
//==============================================================================
#import "SearchPanelController.h"

#import "LDrawDocument.h"
#import <LDrawCore/LDrawFile.h>
#import "LDrawColorPanelController.h"
#import "LDrawFileOutlineView.h"
#import "PartBrowserTableView.h"
#import <LDrawCore/MacLDraw.h>
#import <LDrawEditing/LDrawClipboard.h>

@implementation SearchPanelController

SearchPanelController *sharedSearchPanel = nil;

//========== awakeFromNib ======================================================
//
// Purpose:		Brings the Search panel to life.
//
// Note:		Please note that this method is called BEFORE most class
//				initialization code.
//
//==============================================================================
- (void) awakeFromNib
{
    // Register for dragging operations - we want to be able to drag parts into the search box
    [[self window] registerForDraggedTypes:[LDrawClipboard searchPanelRegisteredDragTypes]];
    
	// Set the initial state of the UI
	NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
	LDrawDocument        *currentDocument    = [documentController currentDocument];
	NSArray              *selectedObjects    = [currentDocument selectedObjects];
	[self updateInterfaceForSelection:selectedObjects];
	
}//end awakeFromNib

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- sharedSearchPanel ---------------------------------------[static]--
//
// Purpose:		Returns the global instance of the search panel.
//
//------------------------------------------------------------------------------
+ (SearchPanelController *) searchPanel
{
    if(sharedSearchPanel == nil)
        sharedSearchPanel = [[SearchPanelController alloc] init];

    return sharedSearchPanel;

}//end sharedSearchPanel

//========== init ==============================================================
//
// Purpose:		Brings the LDraw search panel to life.
//
//==============================================================================
- (id) init
{
	self = [super initWithWindowNibName:@"SearchPanel"];
	if(self)
	{
	}
    return self;
}// end init

#pragma mark - ACCESSORS -

//---------- isVisible -----------------------------------------------[static]--
//
// Purpose:		Returns whether the shared search panel object is visible or 
//				not.
//
//------------------------------------------------------------------------------
+ (BOOL) isVisible
{
	return (sharedSearchPanel != nil);
}

#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== doSearchAndSelect: ================================================
//
// Purpose:		The main search method.  This operates as follows:
//
//              - Determine where to search (the scope): File, Model, Step or within
//                the current selection
//              - Collect all potential matches up
//              - Filter out parts that don't match our criteria, based on part
//                type and colour
//              - Select the remaining matching parts
//
//==============================================================================
- (IBAction)doSearchAndSelect:(id)sender
{
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    LDrawDocument        *currentDocument    = [documentController currentDocument];
    NSArray              *selectedObjects    = [self selectedObjects];
    ScopeT                scope              = (ScopeT)[[scopeMatrix selectedCell] tag];
    SearchPartCriteriaT   criterion          = (SearchPartCriteriaT)[[findTypeMatrix selectedCell] tag];
    ColorFilterT          colorCriterion     = (ColorFilterT)[[colorMatrix selectedCell] tag];

    if ([selectedObjects count] == 0) {
        [LDrawSearch normalizeEmptySelectionScope:&scope
                                      colorFilter:&colorCriterion
                                    partCriterion:&criterion];
    }

    NSArray *searchableObjects = [LDrawSearch searchableObjectsForScope:scope
                                                              selection:selectedObjects
                                                            activeModel:[[currentDocument documentContents] activeModel]
                                                                   file:[currentDocument documentContents]];

    NSArray *colorFilter = [LDrawSearch colorFilterForCriterion:colorCriterion
                                                      wellColor:[colorWell LDrawColor]
                                                      selection:selectedObjects];

    NSArray *partFilter = [LDrawSearch partFilterForCriterion:criterion
                                                specificNames:[partName stringValue]
                                                    selection:selectedObjects];

    NSArray *matchables = [LDrawSearch matchablesInSearchableObjects:searchableObjects
                                               includeLSynthContents:([searchInsideLSynthContainers state] == NSControlStateValueOn)];

    matchables = [LDrawSearch filterMatchables:matchables
                                   colorFilter:colorFilter
                                    partFilter:partFilter
                            excludeHiddenParts:([searchHiddenParts state] == NSControlStateValueOn)];

    [currentDocument selectDirectives:matchables];
} // end doSearchAndSelect:

//========== scopeChanged: =====================================================
//
// Purpose:		Update the UI in response to the user changing the search scope
//
//==============================================================================
- (IBAction)scopeChanged:(id)sender {
    [self updateInterfaceForSelection:[self selectedObjects]];
} // end scopeChanged:

//========== colorOptionChanged: ===============================================
//
// Purpose:		Update the UI in response to the user changing the search color option
//
//==============================================================================
- (IBAction)colorOptionChanged:(id)sender {
    [self updateInterfaceForSelection:[self selectedObjects]];
} // end colorOptionChanged:

//========== findTypeOptionChanged: ============================================
//
// Purpose:		Update the UI in response to the user changing the search part option
//
//==============================================================================
- (IBAction)findTypeOptionChanged:(id)sender {
    [self updateInterfaceForSelection:[self selectedObjects]];
} // end findTypeOptionChanged:

#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//**** NSWindow ****
//========== windowWillClose: ==================================================
//
// Purpose:		Window is closing; clean up.
//
//==============================================================================
- (void) windowWillClose:(NSNotification *)notification
{
	sharedSearchPanel = nil;
}


//**** NSWindow ****
//========== windowWillReturnUndoManager: ======================================
//
// Purpose:		Allows Undo to keep working transparently through this window by
//				allowing the undo request to forward on to the active document.
//
//==============================================================================
- (NSUndoManager *) windowWillReturnUndoManager:(NSWindow *)sender
{
    NSDocument *currentDocument = [[NSDocumentController sharedDocumentController] currentDocument];

    return [currentDocument undoManager];

}//end windowWillReturnUndoManager:


#pragma mark - UTILITIES -

//========== updateInterfaceForSelection: ======================================
//
// Purpose:		The Document lets us know when the selection changes.  We can in
//              turn update the UI appropriately.  We don't change the user's
//              options, merely warn them what we'll do.
//
//==============================================================================
- (void) updateInterfaceForSelection:(NSArray *)selectedObjects
{
    // The selection's changed which means we shouldn't be the active color well anymore
    [LDrawColorWell setActiveColorWell:nil];

    NSArray *keys = [LDrawSearch emptySelectionWarningKeysWithCount:[selectedObjects count]
                                                              scope:(ScopeT)[scopeMatrix selectedTag]
                                                        colorFilter:(ColorFilterT)[colorMatrix selectedTag]
                                                      partCriterion:(SearchPartCriteriaT)[findTypeMatrix selectedTag]];
    if(keys != nil)
    {
        NSMutableArray *localized = [NSMutableArray array];
        for(NSString *key in keys)
        {
            [localized addObject:NSLocalizedString(key, @"")];
        }
        [warningText setStringValue:[LDrawSearch emptySelectionWarningFromLocalizedParts:localized]];
        [warningText setHidden:NO];
    }
    else
    {
        [warningText setHidden:YES];
    }
} // end updateInterfaceForSelection:

//========== selectedObjects ===================================================
//
// Purpose:		Convenience method to return all selected objects in the document
//
//==============================================================================
-(NSArray *)selectedObjects
{
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    LDrawDocument        *currentDocument    = [documentController currentDocument];

    return [currentDocument selectedObjects];
} // end selectedObjects

#pragma mark -
#pragma mark <NSDraggingDestination>
#pragma mark -

//========== draggingEntered: ==================================================
//
// Purpose:		Return the drag type.  We don't want to move or copy the data.
//              The Link type gives us a nice indicative arrow with our cursor.
//
//==============================================================================
-(NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    // We want to intercept drops on the part name text field and handle them ourselves
    [partName setEditable:NO];
    return NSDragOperationLink;
} // end draggingEntered:

//========== draggingExited: ==================================================
//
// Purpose:		The user has dragged the part back out of the window.
//
//==============================================================================
-(void)draggingExited:(id < NSDraggingInfo >)sender
{
    // Reenable normal editing of the part name text field
    [partName setEditable:YES];
} // end draggingExited:

//========== prepareForDragOperation: ==========================================
//
// Purpose:		Someone wants to drop something on us.  We don't want to accept
//              the drop, but we do want to know what parts they wanted to drop
//              on us.
//
//==============================================================================
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    NSString *partNames = nil;
    BOOL fromOutline     = [[sender draggingSource] isKindOfClass:[LDrawFileOutlineView class]];
    BOOL fromPartBrowser = [[sender draggingSource] isKindOfClass:[PartBrowserTableView class]];
    NSString *pasteboardType = [LDrawSearch searchDropPasteboardTypeFromOutline:fromOutline
                                                                fromPartBrowser:fromPartBrowser];

    if(pasteboardType != nil)
    {
        NSPasteboard *pasteboard = [sender draggingPasteboard];
        NSArray *archivedDirectives = [pasteboard propertyListForType:pasteboardType];

        partNames = [LDrawSearch commaSeparatedPartNamesFromArchivedDirectivesData:archivedDirectives];
    }

    [partName setStringValue:partNames];
    
    // We don't actually want to do a drag, but we do want to reenable the text field
    [partName setEditable:YES];
    return YES;
} // end prepareForDragOperation:

@end
