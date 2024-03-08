//==============================================================================
//
//	LDrawDocumentGPU.m
//	Bricksmith
//
//	Purpose:	Document controller for an LDraw document.
//
//				Opens the document and manages its editor and viewer. This is
//				the central class of the application's user interface.
//
//	Threading:	The LDrawFile encapsulated in this class is a shared resource.
//				We must take care not to edit it while it is being drawn in
//				another thread. As such, all the calls in the "Undoable
//				Activities" section are bracketed with the appropriate locking
//				calls. (ANY edit of the document should be undoable.)
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawDocumentGPU.h"

#import "Inspector.h"
#import "LDrawApplicationMTL.h"
#import "LDrawColorPanelController.h"
#import "LDrawFile.h"
#import "LDrawLSynth.h"
#import "LDrawMPDModel.h"
#import "LDrawPart.h"
#import "SearchPanelController.h"


@implementation LDrawDocument (Metal)


- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block
{
    block();
}


#pragma mark -
#pragma mark Delegate

#pragma mark -
#pragma mark NSOutlineView

//========== outlineViewSelectionDidChange: ====================================
//
// Purpose:		We have selected a different something in the file contents.
//				We need to show it as selected in the OpenGL viewing area.
//				This means we may have to change the active model or step in
//				order to display the selection.
//
//==============================================================================
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSOutlineView   *outlineView        = [notification object];
	NSArray         *selectedObjects    = [self selectedObjects];
	id              lastSelectedItem    = [outlineView itemAtRow:[outlineView selectedRow]];
	LDrawMPDModel   *selectedModel      = [self selectedModel];
	LDrawStep       *selectedStep       = [self selectedStep];
	NSInteger		selectedStepIndex	= 0;
	NSInteger       counter             = 0;
	
//	// This method can be called from LDrawOpenGLView (in which case we already
//	// have a context we want to use) or it might be called on its own. Since
//	// selecting parts can trigger OpenGL commands, we should make sure we have
//	// a context active, but we should also restore the current context when
//	// we're done.
//	NSOpenGLContext *originalContext = [NSOpenGLContext currentContext];
//	[[LDrawApplication sharedOpenGLContext] makeCurrentContext];
//
//	//Deselect all the previously-selected directives
//	// (clears the internal directive flag used for drawing)
//	for(counter = 0; counter < [self->selectedDirectives count]; counter++)
//		[[selectedDirectives objectAtIndex:counter] setSelected:NO];
//
//	//Tell the newly-selected directives that they just got selected.
//	selectedDirectives = selectedObjects;
//	for(counter = 0; counter < [self->selectedDirectives count]; counter++)
//		[[selectedDirectives objectAtIndex:counter] setSelected:YES];
//
//	// Update things which need to take into account the entire selection.
//	// The order matters: the search panel unregisters itself as the active colorwell
//	// before the inspector or color panel do their thing.
//	if([SearchPanelController isVisible])
//	{
//		[[SearchPanelController searchPanel] updateInterfaceForSelection:selectedObjects];
//	}
//	[[LDrawApplication sharedInspector] inspectObjects:selectedObjects];
//	[[LDrawColorPanelController sharedColorPanel] updateSelectionWithObjects:selectedObjects];
//
//	if(selectedModel != nil)
//	{
//		// Put the selection on screen (if we need to)
//		[self setActiveModel:selectedModel];
//
//		// Advance to the current step (if we need to)
//		if(selectedStep != nil)
//		{
//			selectedStepIndex = [selectedModel indexOfDirective:selectedStep];
//
//			if(selectedStepIndex > [selectedModel maxStepIndexToOutput])
//			{
//				[self setCurrentStep:selectedStepIndex]; // update document UI
//			}
//		}
//	}
//	[[self documentContents] noteNeedsDisplay];
//
//	//See if we just selected a new part; if so, we must remember it.
//	if ([lastSelectedItem isKindOfClass:[LDrawPart class]] ||
//		[lastSelectedItem isKindOfClass:[LDrawLSynth class]])
//		[self setLastSelectedPart:lastSelectedItem];
//
//	[self buildRelatedPartsMenus];
//	[originalContext makeCurrentContext];
	
}//end outlineViewSelectionDidChange:


@end
