//==============================================================================
//
// File:		DocumentToolbarController.m
//
// Purpose:		Repository for methods relating to creating and maintaining the 
//				toolbar for the main document window. This class is conveniently 
//				instantiated in the Nib file of the document, which is also 
//				where all the button's custom views live.
//
//				This class basically exists to sweep any toolbar complexity 
//				under the carpet, so as to keep the LDrawDocument class as 
//				focused as possible.
//
//  Created by Allen Smith on 5/4/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "DocumentToolbarController.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawEditing/LDrawSelection.h>

#import "LDrawToolbarLabels.h"


@implementation DocumentToolbarController

//========== awakeFromNib ======================================================
//
// Purpose:		Creates things!
//
//==============================================================================
- (void) awakeFromNib
{
	[gridSegmentedControl	removeFromSuperview];
	[orientationSegmentedControl removeFromSuperview];
	[nudgeXToolView			removeFromSuperview];
	[nudgeYToolView			removeFromSuperview];
	[nudgeZToolView			removeFromSuperview];
	[zoomToolView			removeFromSuperview];
	
}//end awakeFromNib

#pragma mark -
#pragma mark TOOLBAR DELEGATE
#pragma mark -

//========== toolbarAllowedItemIdentifiers: ====================================
//
// Purpose:		Returns the list of all possible toolbar buttons.
//
//==============================================================================
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [LDrawToolbarLabels documentToolbarAllowedItemIdentifiers];
}//end toolbarAllowedItemIdentifiers:


//========== toolbarDefaultItemIdentifiers: ====================================
//
// Purpose:		Returns the list of toolbar buttons in the default set. These 
//				will appear when the application is opened for the first time.
//
//==============================================================================
- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return [LDrawToolbarLabels documentToolbarDefaultItemIdentifiers];
}//end toolbarDefaultItemIdentifiers:


//========== toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: ==========
//
// Purpose:		The toolbar buttons themselves are created here.
//
//==============================================================================
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	 itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	
	if([itemIdentifier isEqualToString:TOOLBAR_NUDGE_X_IDENTIFIER])
	{
		NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:itemIdentifier];
		[newItem setLabel:NSLocalizedString(labelKey, nil)];
		[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
		[newItem setView:nudgeXToolView];
	}
	
	else if([itemIdentifier isEqualToString:TOOLBAR_NUDGE_Y_IDENTIFIER])
	{
		NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:itemIdentifier];
		[newItem setLabel:NSLocalizedString(labelKey, nil)];
		[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
		[newItem setView:nudgeYToolView];
	}
	
	else if([itemIdentifier isEqualToString:TOOLBAR_NUDGE_Z_IDENTIFIER])
	{
		NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:itemIdentifier];
		[newItem setLabel:NSLocalizedString(labelKey, nil)];
		[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
		[newItem setView:nudgeZToolView];
	}
	else if([itemIdentifier isEqualToString:TOOLBAR_GRID_SPACING_IDENTIFIER]) {
		newItem = [self makeGridSpacingItem];
	}
	else if([itemIdentifier isEqualToString:TOOLBAR_GRID_ORIENTATION_IDENTIFIER]) {
		newItem = [self makeGridOrientationItem];
	}
	else if([itemIdentifier isEqualToString:TOOLBAR_PART_BROWSER]) {
		newItem = [self makePartBrowserItem];
	}
	else if([self makeRotationItemIfIdentifier:itemIdentifier item:&newItem]) {
	}
	else if([itemIdentifier isEqualToString:TOOLBAR_SHOW_COLORS]) {
		newItem = [self makeShowColorsItem];
	}	
	else if([itemIdentifier isEqualToString:TOOLBAR_SHOW_INSPECTOR]) {
		newItem = [self makeShowInspectorItem];
	}
	
	else if([itemIdentifier isEqualToString:TOOLBAR_SNAP_TO_GRID]) {
		newItem = [self makeSnapToGridItem];
	}
	
	else if([itemIdentifier isEqualToString:TOOLBAR_ZOOM_IN]) {
//		newItem = [self makeZoomInItem];
		newItem = nil; // deprecated in Bricksmith 2.5
	}
	else if([itemIdentifier isEqualToString:TOOLBAR_ZOOM_OUT]) {
//		newItem = [self makeZoomOutItem];
		newItem = nil; // deprecated in Bricksmith 2.5
	}
	else if([itemIdentifier isEqualToString:TOOLBAR_ZOOM_SPECIFY]) {
		newItem = [self makeZoomItem];
	}
	
	return newItem;
	
}//end toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -
//Methods to affect toolbar widgets.

//========== setGridSpacingMode: ===============================================
//
// Purpose:		Someone is telling us they changed the current granularity.
//				We need to update our indicator to this new state.
//
//==============================================================================
- (void) setGridSpacingMode:(LDrawGridSpacingMode)newMode
{
	[self->gridSegmentedControl selectSegmentWithTag:newMode];
	
}//end setGridSpacingMode:


//========== setGridOrientationMode: ===========================================
//
// Purpose:		Someone is telling us they changed the current grid orientation.
//				We need to update our indicator to this new state.
//
//==============================================================================
- (void) setGridOrientationMode:(LDrawGridOrientationMode)newMode
{
	[self->orientationSegmentedControl selectSegmentWithTag:newMode];

}//end setGridOrientationMode:



#pragma mark -
#pragma mark BUTTON FACTORIES
#pragma mark -

//========== makeGridSpacingItem ===============================================
//
// Purpose:		Creates the toolbar widget used to toggle the grid mode. 
//				Currently, this is implemented as a segmented control.
//
//==============================================================================
- (NSToolbarItem *) makeGridSpacingItem
{
	NSToolbarItem			*newItem	= [[NSToolbarItem alloc] initWithItemIdentifier:TOOLBAR_GRID_SPACING_IDENTIFIER];
	LDrawGridSpacingMode	gridMode	= [self->document gridSpacingMode];
	
	[self->gridSegmentedControl selectSegmentWithTag:gridMode];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_GRID_SPACING_IDENTIFIER];
	[newItem setView:self->gridSegmentedControl];
	[newItem setLabel:NSLocalizedString(labelKey,nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey,nil)];
	
	return newItem;
	
}//end makeGridSpacingItem


//========== makeGridOrientationItem ===========================================
//
// Purpose:		Creates the toolbar widget used to toggle the grid orientation.
//				Currently, this is implemented as a segmented control.
//
//==============================================================================
- (NSToolbarItem *) makeGridOrientationItem
{
	NSToolbarItem			*newItem		= [[NSToolbarItem alloc] initWithItemIdentifier:TOOLBAR_GRID_ORIENTATION_IDENTIFIER];
	LDrawGridOrientationMode	gridMode	= [self->document gridOrientationMode];
	
	[self->orientationSegmentedControl selectSegmentWithTag:gridMode];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_GRID_ORIENTATION_IDENTIFIER];
	[newItem setView:self->orientationSegmentedControl];
	[newItem setLabel:NSLocalizedString(labelKey,nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey,nil)];
	
	return newItem;
}//end makeGridOrientationItem


//========== makePartBrowserItem ===========================================
//
// Purpose:		Button that shows the Lego Part Browser.
//
//==============================================================================
- (NSToolbarItem *) makePartBrowserItem
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc]
									initWithItemIdentifier:TOOLBAR_PART_BROWSER];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_PART_BROWSER];
	[newItem setLabel:NSLocalizedString(labelKey, nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
	[newItem setImage:[NSImage imageNamed:@"PartBrowser"]];
	
	// Part Browser action lives in LDrawApplication, but it's easiest to just 
	// dispatch it to the responder chain. That's what the menu item does. 
	[newItem setTarget:nil];
	[newItem setAction:@selector(doPartBrowser:)];
	
	return newItem;
	
}//end makePartBrowserItem


//========== makeRotationItemIfIdentifier:item: ================================
//
// Purpose:		Button that rotates around an axis.
//
//==============================================================================
- (BOOL) makeRotationItemIfIdentifier:(NSString *)itemIdentifier
								 item:(NSToolbarItem * __autoreleasing *)outItem
{
	LDrawQuickRotationAxis  axis      = LDrawQuickRotationAxisX;
	BOOL                    positive  = YES;

	if([LDrawSelection quickRotationAxis:&axis
								positive:&positive
					forToolbarIdentifier:itemIdentifier] == NO)
	{
		return NO;
	}

	*outItem = [self makeRotationItemWithIdentifier:itemIdentifier
											   axis:axis
										   positive:positive];
	return YES;
}


//========== makeRotationItemWithIdentifier:axis:positive: =====================
//
// Purpose:		Button that rotates around an axis.
//
//==============================================================================
- (NSToolbarItem *) makeRotationItemWithIdentifier:(NSString *)itemIdentifier
											  axis:(LDrawQuickRotationAxis)axis
										  positive:(BOOL)positive
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:itemIdentifier];
	[newItem setLabel:NSLocalizedString(labelKey, nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
	[newItem setImage:[NSImage imageNamed:itemIdentifier]];

	[newItem setTarget:self->document];
	[newItem setAction:@selector(quickRotateClicked:)];
	[newItem setTag:[LDrawSelection quickRotationMenuTagForAxis:axis
													   positive:positive]];

	return newItem;
}


//========== makeShowColorsItem ================================================
//
// Purpose:		Button that displays the colors panel
//
//==============================================================================
- (NSToolbarItem *) makeShowColorsItem
{
	NSToolbarItem   *newItem    = [[NSToolbarItem alloc]
													initWithItemIdentifier:TOOLBAR_SHOW_COLORS];
	NSImage         *image      = [NSImage imageNamed:NSImageNameColorPanel];
	
	[newItem setLabel:NSLocalizedString([LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_SHOW_COLORS], nil)];
	[newItem setPaletteLabel:NSLocalizedString([LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_SHOW_COLORS], nil)];
	[newItem setImage:image];
	
	[newItem setTarget:nil];
	[newItem setAction:@selector(showColors:)];
	
	return newItem;
	
}//end makeShowColorsItem


//========== makeShowInspectorItem =============================================
//
// Purpose:		Button that displays the inspector (info) window
//
//==============================================================================
- (NSToolbarItem *) makeShowInspectorItem
{
	NSToolbarItem   *newItem    = [[NSToolbarItem alloc]
														initWithItemIdentifier:TOOLBAR_SHOW_INSPECTOR];
	NSImage         *image      = [NSImage imageNamed:NSImageNameInfo];
	
	[newItem setLabel:NSLocalizedString([LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_SHOW_INSPECTOR], nil)];
	[newItem setPaletteLabel:NSLocalizedString([LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_SHOW_INSPECTOR], nil)];
	[newItem setImage:image];
	
	[newItem setTarget:nil];
	[newItem setAction:@selector(showInspector:)];
	
	return newItem;
	
}//end makeShowInspectorItem


//========== makeSnapToGridItem ================================================
//
// Purpose:		Button that aligns a part to the grid.
//
//==============================================================================
- (NSToolbarItem *) makeSnapToGridItem
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc]
									initWithItemIdentifier:TOOLBAR_SNAP_TO_GRID];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_SNAP_TO_GRID];
	[newItem setLabel:NSLocalizedString(labelKey, nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
	[newItem setImage:[NSImage imageNamed:@"Snap To Grid"]];
	
	[newItem setTarget:self->document];
	[newItem setAction:@selector(snapSelectionToGrid:)];
	
	return newItem;
	
}//end makeSnapToGridItem


//========== makeZoomInItem ====================================================
//
// Purpose:		Button that enlarges the object being viewed
//
// Note:		Obsoleted in Bricksmith 2.5 by unified zoom control.
//
//==============================================================================
- (NSToolbarItem *) makeZoomInItem
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc]
									initWithItemIdentifier:TOOLBAR_ZOOM_IN];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_ZOOM_IN];
	[newItem setLabel:NSLocalizedString(labelKey, nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
	[newItem setImage:[NSImage imageNamed:@"ZoomIn"]];
	
	[newItem setTarget:self->document];
	[newItem setAction:@selector(zoomIn:)];
	
	return newItem;
	
}//end makeZoomInItem


//========== makeZoomOutItem ===================================================
//
// Purpose:		Button that shrinks the object being viewed
//
// Note:		Obsoleted in Bricksmith 2.5 by unified zoom control.
//
//==============================================================================
- (NSToolbarItem *) makeZoomOutItem
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc]
									initWithItemIdentifier:TOOLBAR_ZOOM_OUT];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_ZOOM_OUT];
	[newItem setLabel:NSLocalizedString(labelKey, nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
	[newItem setImage:[NSImage imageNamed:@"ZoomOut"]];
	
	[newItem setTarget:self->document];
	[newItem setAction:@selector(zoomOut:)];
	
	return newItem;
	
}//end makeZoomOutItem


//========== makeZoomItem ======================================================
//
// Purpose:		Hooks up the text entry field which is used to specify an 
//				exact zoom percentage.
//
// Notes:		In Bricksmith 2.5, the zoom text/in/out controls were melded 
//				into a single unit, produced by this method. 
//
//==============================================================================
- (NSToolbarItem *) makeZoomItem
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc]
									initWithItemIdentifier:TOOLBAR_ZOOM_SPECIFY];
	
	NSString *labelKey = [LDrawToolbarLabels labelKeyForItemIdentifier:TOOLBAR_ZOOM_SPECIFY];
	[newItem setLabel:NSLocalizedString(labelKey, nil)];
	[newItem setPaletteLabel:NSLocalizedString(labelKey, nil)];
	[newItem setView:zoomToolView];
	
	return newItem;
	
}//end makeZoomItem


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== gridSpacingSegmentedControlClicked: ===============================
//
// Purpose:		We clicked on the toolbar's segmented control for changing the 
//				grid spacing.
//
//==============================================================================
- (void) gridSpacingSegmentedControlClicked:(id)sender
{
	NSInteger           selectedSegment = [sender selectedSegment];
	LDrawGridSpacingMode    newGridMode = (LDrawGridSpacingMode)[[sender cell] tagForSegment:selectedSegment];
//	LDrawGridSpacingMode	newGridMode = [sender selectedTag]; // WHY does this not work!? Sheesh!
	
	[self->document setGridSpacingMode:newGridMode];
	
}//end gridSpacingSegmentedControlClicked:


//========== gridOrientationSegmentedControlClicked: ===========================
//
// Purpose:		We clicked on the toolbar's segmented control for changing the 
//				grid orientation.
//
//==============================================================================
- (IBAction) gridOrientationSegmentedControlClicked:(id)sender
{
	NSInteger                   selectedSegment = [sender selectedSegment];
	LDrawGridOrientationMode    newGridMode     = (LDrawGridOrientationMode)[[sender cell] tagForSegment:selectedSegment];
	
	[self->document setGridOrientationMode:newGridMode];	
	
}//emd gridOrientationSegmentedControlClicked:


//========== nudgeXClicked: ====================================================
//
// Purpose:		The toolbar button indicating movement along the axis has been 
//				clicked. The direction to move can be determined by the tag of 
//				the button clicked: -1 for negative movement; +1 for positive 
//				movement.
//
//==============================================================================
- (IBAction) nudgeXClicked:(id)sender
{
	Vector3	nudgeVector = [LDrawSelection nudgeUnitVectorForAxis:LDrawNudgeAxisX
															sign:[[sender selectedCell] tag]];
	
	[document nudgeSelectionBy:nudgeVector];
	
}//end nudgeXClicked:


//========== nudgeYClicked: ====================================================
//
// Purpose:		The toolbar button indicating movement along the axis has been 
//				clicked. The direction to move can be determined by the tag of 
//				the button clicked: -1 for negative movement; +1 for positive 
//				movement.
//
//==============================================================================
- (IBAction) nudgeYClicked:(id)sender
{
	Vector3	nudgeVector = [LDrawSelection nudgeUnitVectorForAxis:LDrawNudgeAxisY
															sign:[[sender selectedCell] tag]];
	
	[document nudgeSelectionBy:nudgeVector];
	
}//end nudgeYClicked:


//========== nudgeZClicked: ====================================================
//
// Purpose:		The toolbar button indicating movement along the axis has been 
//				clicked. The direction to move can be determined by the tag of 
//				the button clicked: -1 for negative movement; +1 for positive 
//				movement.
//
//==============================================================================
- (IBAction) nudgeZClicked:(id)sender
{
	Vector3	nudgeVector = [LDrawSelection nudgeUnitVectorForAxis:LDrawNudgeAxisZ
															sign:[[sender selectedCell] tag]];
	
	[document nudgeSelectionBy:nudgeVector];
	
}//end nudgeZClicked:


//========== zoomSegmentedControlClicked: ======================================
//
// Purpose:		For nicer modern looks, the zoom control is a segmented cell 
//				which acts like push buttons. 
//
//==============================================================================
- (void) zoomSegmentedControlClicked:(id)sender
{
	switch([LDrawToolbarLabels zoomActionForSegmentIndex:[sender selectedSegment]])
	{
		case LDrawZoomToolbarSegmentOut:
			[document zoomOut:sender];
			break;
		case LDrawZoomToolbarSegmentIn:
			[document zoomIn:sender];
			break;
		case LDrawZoomToolbarSegmentNone:
			break; // center cell is just a spacer hidden behind zoom text field.
	}
	
}//end zoomSegmentedControlClicked:


//========== zoomScaleChanged: =================================================
//
// Purpose:		The user has typed a new percentage into the scaling text field.
//				The document needs to update something with that.
//
//==============================================================================
- (IBAction) zoomScaleChanged:(id)sender
{
	CGFloat newZoom = [sender doubleValue];
	[self->document setZoomPercentage:newZoom];
	
}//end zoomScaleChanged:


#pragma mark -
#pragma mark VALIDATION
#pragma mark -


//========== validateToolbarItem: ==============================================
//
// Purpose:		Toolbar validation: eye candy that probably slows everything to 
//				a crawl.
//
//==============================================================================
- (BOOL) validateToolbarItem:(NSToolbarItem *)item
{
	LDrawPart		*selectedPart	= [self->document selectedPart];
	NSArray			*selectedItems	= [self->document selectedObjects];
	NSString		*identifier		= [item itemIdentifier];
	BOOL			 enabled		= NO;
	
	//Must have something selected.
	if([LDrawToolbarLabels toolbarRequiresNonEmptySelectionForIdentifier:identifier])
	{
		enabled = [selectedItems count] > 0;
	}
	
	//Must have a part selected.
	else if([LDrawToolbarLabels toolbarRequiresSelectedPartForIdentifier:identifier])
	{
		enabled = (selectedPart != nil);
	}
	
	//We don't have special conditions for it; give it a pass.
	else
		enabled = YES;
	
	return enabled;
	
}//end validateToolbarItem:


@end
