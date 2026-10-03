//==============================================================================
//
// File:		PreferencesDialogController.m
//
// Purpose:		Handles the user interface between the application and its
//				preferences file.
//
// Notes:		The window lists its panes in a sidebar on the left and shows
//				the selected pane on the right. Each pane is built in code by a
//				make...Pane method. To add a pane, add its identifier to
//				-init and build it there, give it an icon in SymbolNameForPane,
//				and name it in Localizable.strings under its identifier.
//
//				Preference keys live in LDrawKeys.h. Give a new key a default
//				in +ensureDefaults or in LDrawPreferences.
//
//  Created by Allen Smith on 2/14/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "PreferencesDialogController.h"

#import <LDrawCore/LDrawGroupable.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawLSynthConfigSource.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawRegex.h>

#import <LDrawFeatures/LDrawGrid.h>
#import <LDrawFeatures/LDrawLSynthPanelModel.h>
#import <LDrawFeatures/LDrawPartListOrientations.h>
#import <LDrawFeatures/LDrawPreferences.h>
#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LSynthConfiguration.h>

#import "LDrawApplication.h"
#import "LDrawHostChrome.h"
#import "PartLibraryController.h"
#import "PreferencesForm.h"
#import "UserDefaultsCategory.h"

// Pane identifiers. They are also the Localizable.strings keys of the pane
// names, and the value saved under PREFERENCES_LAST_TAB_DISPLAYED.
static NSString * const PreferencesPaneGeneral	= @"PreferencesTabGeneral";
static NSString * const PreferencesPaneMouse	= @"PreferencesTabMouse";
static NSString * const PreferencesPaneSteps	= @"PreferencesTabSteps";
static NSString * const PreferencesPaneColors	= @"PreferencesTabStyles";
static NSString * const PreferencesPaneLSynth	= @"PreferencesTabLSynth";

#define PREFERENCES_WINDOW_AUTOSAVE_NAME	@"PreferencesWindow"

static const CGFloat kSidebarWidth		= 180;
static const CGFloat kMinWindowHeight	= 320;

static inline NSData *archivedData(id object) {
    return [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:nil];
}

/// Maps LDrawHostChrome colorFallbackForPreferenceKey: to NSColor.
static NSColor *FallbackColorForPreferenceKey(NSString *key)
{
	switch([LDrawHostChrome colorFallbackForPreferenceKey:key])
	{
		case LDrawHostColorFallbackControlBackground:
			return [NSColor controlBackgroundColor];
		case LDrawHostColorFallbackText:
			return [NSColor textColor];
		case LDrawHostColorFallbackSystemBlue:
			return [NSColor systemBlueColor];
		case LDrawHostColorFallbackTeal:
		{
			float rgba[4];
			[LDrawHostChrome getTealSyntaxColorRGBA:rgba];
			return [NSColor colorWithDeviceRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
		}
		case LDrawHostColorFallbackSystemGreen:
			return [NSColor systemGreenColor];
		case LDrawHostColorFallbackSystemGray:
			return [NSColor systemGrayColor];
		case LDrawHostColorFallbackSystemRed:
			return [NSColor systemRedColor];
	}
	return [NSColor textColor];
}


//========== SymbolNameForPane =================================================
//
// Purpose:		The small sidebar icon of a pane.
//
//==============================================================================
static NSString *SymbolNameForPane(NSString *identifier)
{
	NSDictionary<NSString *, NSString *> *names = @{
		PreferencesPaneGeneral	: @"gearshape",
		PreferencesPaneMouse	: @"computermouse",
		PreferencesPaneSteps	: @"square.stack.3d.up",
		PreferencesPaneColors	: @"paintpalette",
		PreferencesPaneLSynth	: @"scribble.variable",
	};

	return names[identifier];

}//end SymbolNameForPane


//========== GhostTransparencyMinPercent =======================================
//
// Purpose:		The lowest ghost transparency LDrawModel accepts.
//
//==============================================================================
static NSInteger GhostTransparencyMinPercent(void)
{
	return lroundf((1.0f - LDRAW_MAX_GHOST_ALPHA) * 100.0f);

}//end GhostTransparencyMinPercent


//========== GhostTransparencyMaxPercent =======================================
//
// Purpose:		The highest ghost transparency LDrawModel accepts.
//
//==============================================================================
static NSInteger GhostTransparencyMaxPercent(void)
{
	return lroundf((1.0f - LDRAW_MIN_GHOST_ALPHA) * 100.0f);

}//end GhostTransparencyMaxPercent


//========== PercentFormatter ==================================================
//
// Purpose:		Accepts whole numbers in a percentage field.
//
//==============================================================================
static NSNumberFormatter *PercentFormatter(void)
{
	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];

	[formatter setNumberStyle:NSNumberFormatterDecimalStyle];
	[formatter setMaximumFractionDigits:0];

	return formatter;

}//end PercentFormatter


//========== MouseDraggingNote =================================================
//
// Purpose:		Explains a choice of when parts start to drag.
//
//==============================================================================
static NSString *MouseDraggingNote(LDrawMouseDragBehavior behavior)
{
	switch(behavior)
	{
		case LDrawMouseDraggingOff:
			return NSLocalizedString(@"Parts move only with the keyboard. Dragging spins the model.", nil);
		case LDrawMouseDraggingBeginImmediately:
			return NSLocalizedString(@"To spin the model instead, hold ⌘ and drag.", nil);
		case LDrawMouseDraggingBeginAfterDelay:
			return NSLocalizedString(@"To spin the model, drag right away. Works like Bricksmith 1.x.", nil);
		case LDrawMouseDraggingImmediatelyInOrthoNeverInPerspective:
			return NSLocalizedString(@"Parts never drag in the 3D perspective view. Works like MLCad.", nil);
	}
	return @"";

}//end MouseDraggingNote


//========== RightButtonNote ===================================================
//
// Purpose:		Explains a choice of what the right mouse button does.
//
//==============================================================================
static NSString *RightButtonNote(LDrawRightButtonBehavior behavior)
{
	switch(behavior)
	{
		case LDrawRightButtonContextual:
			return NSLocalizedString(@"Hold ⌘ and drag to rotate the view.", nil);
		case LDrawRightButtonRotates:
			return NSLocalizedString(@"The context menu is not available.", nil);
	}
	return @"";

}//end RightButtonNote


//========== MouseWheelNote ====================================================
//
// Purpose:		Explains a choice of what the scroll wheel does.
//
//==============================================================================
static NSString *MouseWheelNote(LDrawMouseWheelBehavior behavior)
{
	switch(behavior)
	{
		case LDrawMouseWheelScrolls:
			return NSLocalizedString(@"Hold Option to zoom.", nil);
		case LDrawMouseWheelZooms:
			return NSLocalizedString(@"The wheel always zooms instead of scrolling.", nil);
	}
	return @"";

}//end MouseWheelNote


//========== RotateStyleNote ===================================================
//
// Purpose:		Explains a choice of how dragging rotates the camera.
//
//==============================================================================
static NSString *RotateStyleNote(LDrawRotateStyle style)
{
	switch(style)
	{
		case LDrawRotateStyleTrackball:
			return NSLocalizedString(@"Dragging spins the model like a trackball. "
									 @"The model can turn to any angle.", nil);
		case LDrawRotateStyleTurntable:
			return NSLocalizedString(@"The model's base never turns to face left or right, "
									 @"as if the model stood on a turntable.", nil);
	}
	return @"";

}//end RotateStyleNote


@interface PreferencesDialogController () <NSWindowDelegate, NSToolbarDelegate,
										   NSTableViewDataSource, NSTableViewDelegate,
										   NSTextFieldDelegate>
{
	NSWindow										*preferencesWindow;
	NSTableView										*sidebarTable;
	NSView											*detailView;
	NSArray<NSString *>								*paneIdentifiers;
	NSDictionary<NSString *, NSScrollView *>		*panes;
	NSString										*selectedPaneIdentifier;

	// General Pane
	NSTextField		*LDrawPathTextField;
	NSTextField		*gridSpacingFineField;
	NSTextField		*gridSpacingMediumField;
	NSTextField		*gridSpacingCoarseField;

	// Mouse Pane
	NSPopUpButton	*mouseDraggingPopUp;
	NSPopUpButton	*rightButtonPopUp;
	NSPopUpButton	*mouseWheelPopUp;
	NSPopUpButton	*rotateModePopUp;
	NSTextField		*mouseDraggingNote;
	NSTextField		*rightButtonNote;
	NSTextField		*mouseWheelNote;
	NSTextField		*rotateModeNote;

	// Steps Pane
	NSSwitch		*stepSelectionGoesBackSwitch;
	NSSwitch		*hideRemovedGroupsInStepsSwitch;
	NSSwitch		*ghostRemovedGroupsSwitch;
	NSSwitch		*ghostPreviousStepsSwitch;
	NSSlider		*ghostTransparencySlider;
	NSTextField		*ghostTransparencyText;
	NSSwitch		*stepPartListShowSwitch;
	NSSwitch		*stepPartListSubmodelsSwitch;
	NSSwitch		*stepPartListFollowsStepSwitch;
	NSSwitch		*stepPartListLPubScaleSwitch;
	NSTextField		*stepPartListOrientationsField;

	// Colors Pane
	NSColorWell		*backgroundColorWell;
	NSColorWell		*modelsColorWell;
	NSColorWell		*stepsColorWell;
	NSColorWell		*partsColorWell;
	NSColorWell		*primitivesColorWell;
	NSColorWell		*colorsColorWell;
	NSColorWell		*commentsColorWell;
	NSColorWell		*unknownColorWell;

	// LSynth Pane
	NSTextField		*lsynthExecutablePath;
	NSTextField		*lsynthConfigurationPath;
	NSSwitch		*lsynthShowBasicPartsList;
	NSPopUpButton	*lsynthSelectionModePopUp;
	NSSlider		*lsynthTransparencySlider;
	NSTextField		*lsynthTransparencyText;
	NSColorWell		*lsynthSelectionColorWell;
	NSSwitch		*lsynthSaveSynthesizedParts;
}

@end


@implementation PreferencesDialogController

//The shared preferences window. We need to store this reference here so that
// we can simply bring the window to the front when it is already onscreen,
// rather than accidentally creating a whole new one.
PreferencesDialogController *preferencesDialog = nil;


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- doPreferences -------------------------------------------[static]--
//
// Purpose:		Show the preferences window.
//
//------------------------------------------------------------------------------
+ (void) doPreferences
{
	if(preferencesDialog == nil)
		preferencesDialog = [[PreferencesDialogController alloc] init];

	[preferencesDialog showPreferencesWindow];

}//end doPreferences


//========== init ==============================================================
//
// Purpose:		Builds the panes and the window, and shows the pane last seen.
//
//==============================================================================
- (id) init
{
	self = [super init];
	if(self == nil)
		return nil;

	NSString *lastIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:PREFERENCES_LAST_TAB_DISPLAYED];

	paneIdentifiers = @[PreferencesPaneGeneral,
						PreferencesPaneMouse,
						PreferencesPaneSteps,
						PreferencesPaneColors,
						PreferencesPaneLSynth];

	panes = @{
		PreferencesPaneGeneral	: [self makeGeneralPane],
		PreferencesPaneMouse	: [self makeMousePane],
		PreferencesPaneSteps	: [self makeStepsPane],
		PreferencesPaneColors	: [self makeColorsPane],
		PreferencesPaneLSynth	: [self makeLSynthPane],
	};

	[self makeWindow];

	if([paneIdentifiers containsObject:lastIdentifier] == NO)
		lastIdentifier = PreferencesPaneGeneral;

	if([preferencesWindow setFrameUsingName:PREFERENCES_WINDOW_AUTOSAVE_NAME] == NO)
		[preferencesWindow center];

	[self selectPaneWithIdentifier:lastIdentifier];

	return self;

}//end init


//========== makeWindow ========================================================
//
// Purpose:		Makes the window: the pane list on the left, the pane on the
//				right.
//
// Notes:		The empty toolbar puts the pane name in the title bar, to the
//				right of the sidebar.
//
//==============================================================================
- (void) makeWindow
{
	NSSplitViewController	*splitController	= [[NSSplitViewController alloc] init];
	NSViewController		*sidebarController	= [[NSViewController alloc] init];
	NSViewController		*detailController	= [[NSViewController alloc] init];
	NSSplitViewItem			*sidebarItem		= nil;
	NSSplitViewItem			*detailItem			= nil;
	NSToolbar				*toolbar			= [[NSToolbar alloc] initWithIdentifier:@"Preferences"];
	NSWindowStyleMask		 styleMask			= (  NSWindowStyleMaskTitled
												   | NSWindowStyleMaskClosable
												   | NSWindowStyleMaskFullSizeContentView);
	CGFloat					 windowWidth		= 0;

	detailView = [[NSView alloc] init];
	[sidebarController setView:[self makeSidebar]];
	[detailController setView:detailView];

	sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
	[sidebarItem setCanCollapse:NO];
	[sidebarItem setMinimumThickness:kSidebarWidth];
	[sidebarItem setMaximumThickness:kSidebarWidth];

	detailItem = [NSSplitViewItem splitViewItemWithViewController:detailController];
	[detailItem setMinimumThickness:PreferencesFormPaneWidth];

	[splitController addSplitViewItem:sidebarItem];
	[splitController addSplitViewItem:detailItem];
	windowWidth = kSidebarWidth + [[splitController splitView] dividerThickness] + PreferencesFormPaneWidth;

	preferencesWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, windowWidth, 480)
													styleMask:styleMask
													  backing:NSBackingStoreBuffered
														defer:YES];
	[preferencesWindow setReleasedWhenClosed:NO];
	[preferencesWindow setTabbingMode:NSWindowTabbingModeDisallowed];
	[preferencesWindow setDelegate:self];
	[preferencesWindow setContentViewController:splitController];
	[preferencesWindow setContentSize:NSMakeSize(windowWidth, 480)];
	[preferencesWindow setAutorecalculatesKeyViewLoop:YES];

	[toolbar setDelegate:self];
	[toolbar setAllowsUserCustomization:NO];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[preferencesWindow setToolbar:toolbar];
	[preferencesWindow setToolbarStyle:NSWindowToolbarStyleUnified];

}//end makeWindow


//========== makeSidebar =======================================================
//
// Purpose:		Makes the list of panes.
//
//==============================================================================
- (NSView *) makeSidebar
{
	NSScrollView	*scrollView	= [[NSScrollView alloc] init];
	NSTableColumn	*column		= [[NSTableColumn alloc] initWithIdentifier:@"Pane"];

	sidebarTable = [[NSTableView alloc] init];
	[sidebarTable setStyle:NSTableViewStyleSourceList];
	[sidebarTable setRowSizeStyle:NSTableViewRowSizeStyleMedium];
	[sidebarTable setHeaderView:nil];
	[sidebarTable addTableColumn:column];
	[sidebarTable setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
	[sidebarTable setAllowsEmptySelection:NO];
	[sidebarTable setDataSource:self];
	[sidebarTable setDelegate:self];

	[scrollView setDocumentView:sidebarTable];
	[scrollView setDrawsBackground:NO];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setAutohidesScrollers:YES];

	return scrollView;

}//end makeSidebar


//========== makeGeneralPane ===================================================
//
// Purpose:		The LDraw folder and the grid spacing.
//
//==============================================================================
- (NSScrollView *) makeGeneralPane
{
	NSString	*folderNote		= NSLocalizedString(@"The folder holds the LDraw part definitions in its \"p\" "
													@"and \"parts\" folders. Download it from www.ldraw.org.", nil);
	NSString	*reloadNote		= NSLocalizedString(@"Read the folder again after you add parts to it.", nil);
	NSString	*gridNote		= NSLocalizedString(@"How far parts move along the studs. A 1 × 1 brick is "
													@"20 units wide and 24 units tall.", nil);
	SEL			 gridAction		= @selector(gridSpacingChanged:);
	NSButton	*chooseButton	= nil;
	NSButton	*reloadButton	= nil;
	NSView		*folderRow		= nil;
	NSView		*reloadRow		= nil;
	NSView		*folderSection	= nil;
	NSView		*gridSection	= nil;

	LDrawPathTextField = [PreferencesForm pathFieldWithPlaceholder:nil];
	[LDrawPathTextField setTarget:self];
	[LDrawPathTextField setAction:@selector(pathTextFieldChanged:)];

	// Only Return sets a typed path, since that reloads every part.
	[[LDrawPathTextField cell] setSendsActionOnEndEditing:NO];

	chooseButton = [PreferencesForm buttonWithTitle:NSLocalizedString(@"Choose…", nil)
											 target:self
											 action:@selector(chooseLDrawFolder:)];
	reloadButton = [PreferencesForm buttonWithTitle:NSLocalizedString(@"Reload Parts", nil)
											 target:self
											 action:@selector(reloadParts:)];

	folderRow = [PreferencesForm rowWithContent:[PreferencesForm controlGroup:@[LDrawPathTextField, chooseButton]]];
	reloadRow = [PreferencesForm rowWithTitle:NSLocalizedString(@"Part catalog", nil)
										 note:reloadNote
									  control:reloadButton
									noteField:NULL];

	folderSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"LDraw Folder", nil)
												 rows:@[folderRow, reloadRow]
											   footer:folderNote];

	gridSpacingFineField	= [PreferencesForm numberFieldWithWidth:60 target:self action:gridAction];
	gridSpacingMediumField	= [PreferencesForm numberFieldWithWidth:60 target:self action:gridAction];
	gridSpacingCoarseField	= [PreferencesForm numberFieldWithWidth:60 target:self action:gridAction];

	gridSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Grid Spacing", nil)
											   rows:@[[self gridRowWithTitle:NSLocalizedString(@"Fine", nil)
																	   field:gridSpacingFineField],
													  [self gridRowWithTitle:NSLocalizedString(@"Medium", nil)
																	   field:gridSpacingMediumField],
													  [self gridRowWithTitle:NSLocalizedString(@"Coarse", nil)
																	   field:gridSpacingCoarseField]]
											 footer:gridNote];

	return [PreferencesForm paneWithSections:@[folderSection, gridSection]];

}//end makeGeneralPane


//========== gridRowWithTitle:field: ===========================================
//
// Purpose:		A grid spacing row: the field and its unit.
//
//==============================================================================
- (NSView *) gridRowWithTitle:(NSString *)title field:(NSTextField *)field
{
	NSTextField *unit = [PreferencesForm unitLabelWithString:NSLocalizedString(@"LDU", nil)];

	return [PreferencesForm rowWithTitle:title control:[PreferencesForm controlGroup:@[field, unit]]];

}//end gridRowWithTitle:field:


//========== makeMousePane =====================================================
//
// Purpose:		How the mouse drags parts and moves the view.
//
//==============================================================================
- (NSScrollView *) makeMousePane
{
	NSString	*orthoNote		= NSLocalizedString(@"Front, Top and the other flat views are orthographic.", nil);
	NSTextField	*draggingNote	= nil;
	NSTextField	*buttonNote		= nil;
	NSTextField	*wheelNote		= nil;
	NSTextField	*rotateNote		= nil;
	NSView		*draggingRow	= nil;
	NSView		*buttonRow		= nil;
	NSView		*wheelRow		= nil;
	NSView		*rotateRow		= nil;
	NSView		*partsSection	= nil;
	NSView		*viewSection	= nil;

	mouseDraggingPopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"Immediately", nil),
															NSLocalizedString(@"After a short delay", nil),
															NSLocalizedString(@"In orthographic views only", nil),
															NSLocalizedString(@"Never", nil)]
													 tags:@[@(LDrawMouseDraggingBeginImmediately),
															@(LDrawMouseDraggingBeginAfterDelay),
															@(LDrawMouseDraggingImmediatelyInOrthoNeverInPerspective),
															@(LDrawMouseDraggingOff)]
												   target:self
												   action:@selector(mouseDraggingChanged:)];

	rightButtonPopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"Shows the context menu", nil),
														  NSLocalizedString(@"Rotates the view", nil)]
												   tags:@[@(LDrawRightButtonContextual),
														  @(LDrawRightButtonRotates)]
												 target:self
												 action:@selector(rightButtonChanged:)];

	mouseWheelPopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"Scrolls", nil),
														 NSLocalizedString(@"Zooms", nil)]
												  tags:@[@(LDrawMouseWheelScrolls),
														 @(LDrawMouseWheelZooms)]
												target:self
												action:@selector(mouseWheelChanged:)];

	rotateModePopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"Turntable", nil),
														 NSLocalizedString(@"Trackball", nil)]
												  tags:@[@(LDrawRotateStyleTurntable),
														 @(LDrawRotateStyleTrackball)]
												target:self
												action:@selector(rotateModeChanged:)];

	draggingRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Start dragging parts", nil)
										   note:nil
										control:mouseDraggingPopUp
									  noteField:&draggingNote];
	buttonRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Right button", nil)
										   note:nil
										control:rightButtonPopUp
									  noteField:&buttonNote];
	wheelRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Scroll wheel", nil)
										   note:nil
										control:mouseWheelPopUp
									  noteField:&wheelNote];
	rotateRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Camera rotation", nil)
										   note:nil
										control:rotateModePopUp
									  noteField:&rotateNote];

	mouseDraggingNote	= draggingNote;
	rightButtonNote		= buttonNote;
	mouseWheelNote		= wheelNote;
	rotateModeNote		= rotateNote;

	partsSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Parts", nil)
												rows:@[draggingRow]
											  footer:orthoNote];
	viewSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"3D View", nil)
											   rows:@[buttonRow, wheelRow, rotateRow]
											 footer:nil];

	return [PreferencesForm paneWithSections:@[partsSection, viewSection]];

}//end makeMousePane


//========== makeStepsPane =====================================================
//
// Purpose:		Step selection, removed groups, ghosts and the step parts list.
//
//==============================================================================
- (NSScrollView *) makeStepsPane
{
	NSString	*selectionNote		= NSLocalizedString(@"Selecting a later step in the file contents always moves "
														@"forward to it. With this off, selecting an earlier step "
														@"leaves the step on display as it is.", nil);
	NSString	*goesBackTitle		= NSLocalizedString(@"Go back to an earlier step when it is selected", nil);
	NSString	*groupsNote			= NSLocalizedString(@"Parts in an MLCAD group disappear once you reach a step "
														@"that removes the group. The All view always applies every "
														@"removal; a ghost draws the group see-through there instead "
														@"of dropping it, and you can still select it.", nil);
	NSString	*previousNote		= NSLocalizedString(@"Only the current step draws solid. Everything built before "
														@"it stays on screen see-through, so the new parts stand out. "
														@"You can still select the ghosts.", nil);
	NSString	*ghostsNote			= NSLocalizedString(@"How see-through a ghost draws, whether it is a removed "
														@"group or a previous step. Higher is fainter.", nil);
	NSString	*partListNote		= NSLocalizedString(@"A framed list of the parts the current step adds. With "
														@"Draw on LPub3D's page on, it is packed like LPub3D, and "
														@"dragging its edge sizes it for each step.", nil);
	NSString	*showListTitle		= NSLocalizedString(@"Show the step's parts list in Steps view mode", nil);
	NSTextField	*percentLabel		= [PreferencesForm unitLabelWithString:@"%"];
	NSTextField	*orientationsNote	= nil;
	NSButton	*chooseButton		= nil;
	NSButton	*defaultButton		= nil;
	NSView		*transparencyGroup	= nil;
	NSView		*orientationsGroup	= nil;
	NSView		*goesBackRow		= nil;
	NSView		*hideRow			= nil;
	NSView		*ghostGroupsRow		= nil;
	NSView		*ghostStepsRow		= nil;
	NSView		*transparencyRow	= nil;
	NSView		*showListRow		= nil;
	NSView		*submodelsRow		= nil;
	NSView		*followsStepRow		= nil;
	NSView		*lpubScaleRow		= nil;
	NSView		*orientationsRow	= nil;
	NSView		*selectionSection	= nil;
	NSView		*groupsSection		= nil;
	NSView		*previousSection	= nil;
	NSView		*ghostsSection		= nil;
	NSView		*partListSection	= nil;

	stepSelectionGoesBackSwitch = [PreferencesForm switchWithTarget:self
															 action:@selector(stepSelectionGoesBackChanged:)];
	hideRemovedGroupsInStepsSwitch = [PreferencesForm switchWithTarget:self
															   action:@selector(hideRemovedGroupsInStepsChanged:)];
	ghostRemovedGroupsSwitch = [PreferencesForm switchWithTarget:self
														 action:@selector(ghostRemovedGroupsChanged:)];
	ghostPreviousStepsSwitch = [PreferencesForm switchWithTarget:self
														 action:@selector(ghostPreviousStepsChanged:)];

	ghostTransparencySlider = [PreferencesForm sliderWithMinValue:GhostTransparencyMinPercent()
														 maxValue:GhostTransparencyMaxPercent()
														   target:self
														   action:@selector(ghostTransparencySliderChanged:)];
	ghostTransparencyText = [PreferencesForm numberFieldWithWidth:44
														   target:self
														   action:@selector(ghostTransparencyTextChanged:)];
	[ghostTransparencyText setFormatter:PercentFormatter()];
	transparencyGroup = [PreferencesForm controlGroup:@[ghostTransparencySlider, ghostTransparencyText, percentLabel]];

	stepPartListShowSwitch = [PreferencesForm switchWithTarget:self
													   action:@selector(stepPartListShowChanged:)];
	stepPartListSubmodelsSwitch = [PreferencesForm switchWithTarget:self
															action:@selector(stepPartListSubmodelsChanged:)];
	stepPartListFollowsStepSwitch = [PreferencesForm switchWithTarget:self
															  action:@selector(stepPartListFollowsStepChanged:)];
	stepPartListLPubScaleSwitch = [PreferencesForm switchWithTarget:self
															action:@selector(stepPartListLPubScaleChanged:)];

	chooseButton = [PreferencesForm buttonWithTitle:NSLocalizedString(@"Choose…", nil)
											 target:self
											 action:@selector(chooseStepPartListOrientations:)];
	defaultButton = [PreferencesForm buttonWithTitle:NSLocalizedString(@"Default", nil)
											  target:self
											  action:@selector(useDefaultStepPartListOrientations:)];
	orientationsGroup = [PreferencesForm controlGroup:@[chooseButton, defaultButton]];
	orientationsRow = [PreferencesForm rowWithTitle:NSLocalizedString(@"Part orientations", nil)
											   note:nil
											control:orientationsGroup
										  noteField:&orientationsNote];
	stepPartListOrientationsField = orientationsNote;

	goesBackRow		= [PreferencesForm rowWithTitle:goesBackTitle control:stepSelectionGoesBackSwitch];
	hideRow			= [PreferencesForm rowWithTitle:NSLocalizedString(@"Hide in Steps view mode", nil)
											control:hideRemovedGroupsInStepsSwitch];
	ghostGroupsRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Show as ghosts in All view mode", nil)
											control:ghostRemovedGroupsSwitch];
	ghostStepsRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Show as ghosts in Steps view mode", nil)
											control:ghostPreviousStepsSwitch];
	transparencyRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Transparency", nil)
											control:transparencyGroup];
	showListRow		= [PreferencesForm rowWithTitle:showListTitle control:stepPartListShowSwitch];
	submodelsRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Include submodel references", nil)
											control:stepPartListSubmodelsSwitch];
	followsStepRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Draw the icons at the step's own rotation", nil)
											control:stepPartListFollowsStepSwitch];
	lpubScaleRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Draw on LPub3D's page", nil)
											control:stepPartListLPubScaleSwitch];

	selectionSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Step Selection", nil)
													rows:@[goesBackRow]
												  footer:selectionNote];
	groupsSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Removed Groups", nil)
												 rows:@[hideRow, ghostGroupsRow]
											   footer:groupsNote];
	previousSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Previous Steps", nil)
												   rows:@[ghostStepsRow]
												 footer:previousNote];
	ghostsSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Ghosts", nil)
												 rows:@[transparencyRow]
											   footer:ghostsNote];
	partListSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Parts List", nil)
												   rows:@[showListRow, submodelsRow, followsStepRow,
														  lpubScaleRow, orientationsRow]
												 footer:partListNote];

	return [PreferencesForm paneWithSections:@[selectionSection, groupsSection, previousSection, ghostsSection,
											   partListSection]];

}//end makeStepsPane


//========== makeColorsPane ====================================================
//
// Purpose:		The view background and the file contents colors.
//
//==============================================================================
- (NSScrollView *) makeColorsPane
{
	NSString					*contentsNote		= NSLocalizedString(@"The text color of each kind of line in "
																		@"the file contents list.", nil);
	NSArray<NSString *>			*contentsTitles		= @[NSLocalizedString(@"Models", nil),
														NSLocalizedString(@"Steps", nil),
														NSLocalizedString(@"Parts", nil),
														NSLocalizedString(@"Primitives", nil),
														NSLocalizedString(@"Colors", nil),
														NSLocalizedString(@"Comments", nil),
														NSLocalizedString(@"Unknown", nil)];
	NSMutableArray<NSView *>	*contentsRows		= [NSMutableArray array];
	NSArray<NSColorWell *>		*contentsWells		= nil;
	NSView						*backgroundRow		= nil;
	NSView						*viewSection		= nil;
	NSView						*contentsSection	= nil;

	backgroundColorWell	= [PreferencesForm colorWellWithTarget:self action:@selector(backgroundColorWellChanged:)];
	modelsColorWell		= [PreferencesForm colorWellWithTarget:self action:@selector(modelsColorWellChanged:)];
	stepsColorWell		= [PreferencesForm colorWellWithTarget:self action:@selector(stepsColorWellChanged:)];
	partsColorWell		= [PreferencesForm colorWellWithTarget:self action:@selector(partsColorWellChanged:)];
	primitivesColorWell	= [PreferencesForm colorWellWithTarget:self action:@selector(primitivesColorWellChanged:)];
	colorsColorWell		= [PreferencesForm colorWellWithTarget:self action:@selector(colorsColorWellChanged:)];
	commentsColorWell	= [PreferencesForm colorWellWithTarget:self action:@selector(commentsColorWellChanged:)];
	unknownColorWell	= [PreferencesForm colorWellWithTarget:self action:@selector(unknownColorWellChanged:)];

	contentsWells = @[modelsColorWell, stepsColorWell, partsColorWell, primitivesColorWell,
					  colorsColorWell, commentsColorWell, unknownColorWell];

	for(NSUInteger index = 0; index < [contentsWells count]; index++)
	{
		[contentsRows addObject:[PreferencesForm rowWithTitle:contentsTitles[index]
													  control:contentsWells[index]]];
	}

	backgroundRow = [PreferencesForm rowWithTitle:NSLocalizedString(@"Background", nil)
										  control:backgroundColorWell];

	viewSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"3D View", nil)
											   rows:@[backgroundRow]
											 footer:nil];
	contentsSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"File Contents", nil)
												   rows:contentsRows
												 footer:contentsNote];

	return [PreferencesForm paneWithSections:@[viewSection, contentsSection]];

}//end makeColorsPane


//========== makeLSynthPane ====================================================
//
// Purpose:		The LSynth program, its configuration, and how synthesized
//				parts are selected and saved.
//
//==============================================================================
- (NSScrollView *) makeLSynthPane
{
	NSString	*programNote			= NSLocalizedString(@"Leave blank to use the built-in version, or choose your "
															@"own. LSynth must take a \"-\" argument to mean \"use "
															@"STDIN/OUT\".", nil);
	NSString	*configurationNote		= NSLocalizedString(@"Leave blank to use the built-in configuration, or choose "
															@"your own. LSynth must take a \"-c <CONFIG FILE>\" "
															@"argument.", nil);
	NSString	*simpleListNote			= NSLocalizedString(@"Leave out nonstandard and old part types from the LSynth "
															@"menus. Turn this off if you use your own configuration "
															@"file.", nil);
	NSString	*selectionNote			= NSLocalizedString(@"How a selected LSynth part or constraint is drawn. 0% is "
															@"fully transparent and 100% is fully opaque.", nil);
	NSString	*saveNote				= NSLocalizedString(@"Synthesis can add many parts to a file. Bricksmith makes "
															@"them again when it opens the file, so you may turn this "
															@"off for big models. Other LDraw programs probably need "
															@"them saved.", nil);
	NSString	*builtIn				= NSLocalizedString(@"Built-in", nil);
	NSTextField	*percentLabel			= [PreferencesForm unitLabelWithString:@"%"];
	NSButton	*chooseExecutable		= nil;
	NSButton	*chooseConfiguration	= nil;
	NSView		*executableGroup		= nil;
	NSView		*configurationGroup		= nil;
	NSView		*transparencyGroup		= nil;
	NSView		*simpleListRow			= nil;
	NSView		*modeRow				= nil;
	NSView		*transparencyRow		= nil;
	NSView		*colorRow				= nil;
	NSView		*saveRow				= nil;
	NSView		*programSection			= nil;
	NSView		*configurationSection	= nil;
	NSView		*selectionSection		= nil;
	NSView		*savingSection			= nil;

	lsynthExecutablePath	= [PreferencesForm pathFieldWithPlaceholder:builtIn];
	lsynthConfigurationPath	= [PreferencesForm pathFieldWithPlaceholder:builtIn];
	[lsynthExecutablePath setDelegate:self];
	[lsynthConfigurationPath setDelegate:self];

	chooseExecutable = [PreferencesForm buttonWithTitle:NSLocalizedString(@"Choose…", nil)
												 target:self
												 action:@selector(lsynthChooseExecutable:)];
	chooseConfiguration = [PreferencesForm buttonWithTitle:NSLocalizedString(@"Choose…", nil)
													target:self
													action:@selector(lsynthChooseConfiguration:)];
	executableGroup		= [PreferencesForm controlGroup:@[lsynthExecutablePath, chooseExecutable]];
	configurationGroup	= [PreferencesForm controlGroup:@[lsynthConfigurationPath, chooseConfiguration]];

	lsynthShowBasicPartsList = [PreferencesForm switchWithTarget:self
														 action:@selector(lsynthShowBasicPartsListChanged:)];
	lsynthSaveSynthesizedParts = [PreferencesForm switchWithTarget:self
														   action:@selector(lsynthSaveSynthesizedPartsChanged:)];

	lsynthSelectionModePopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"Transparency", nil),
																  NSLocalizedString(@"Custom color", nil),
																  NSLocalizedString(@"Transparency and color", nil)]
														   tags:@[@(LDrawLSynthSelectionTransparent),
																  @(LDrawLSynthSelectionColored),
																  @(LDrawLSynthSelectionTransparentColored)]
														 target:self
														 action:@selector(lsynthSelectionModeChanged:)];

	lsynthTransparencySlider = [PreferencesForm sliderWithMinValue:0
														  maxValue:100
															target:self
															action:@selector(lsynthTransparencySliderChanged:)];
	[lsynthTransparencySlider setContinuous:NO];
	lsynthTransparencyText = [PreferencesForm numberFieldWithWidth:44
														   target:self
														   action:@selector(lsynthTransparencyTextChanged:)];
	[lsynthTransparencyText setFormatter:PercentFormatter()];
	transparencyGroup = [PreferencesForm controlGroup:@[lsynthTransparencySlider,
														lsynthTransparencyText,
														percentLabel]];

	lsynthSelectionColorWell = [PreferencesForm colorWellWithTarget:self
															 action:@selector(lsynthSelectionColorWellClicked:)];

	simpleListRow = [PreferencesForm rowWithTitle:NSLocalizedString(@"Show simple parts list", nil)
											 note:simpleListNote
										  control:lsynthShowBasicPartsList
										noteField:NULL];
	modeRow			= [PreferencesForm rowWithTitle:NSLocalizedString(@"Highlight with", nil)
											control:lsynthSelectionModePopUp];
	transparencyRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Transparency", nil)
											control:transparencyGroup];
	colorRow		= [PreferencesForm rowWithTitle:NSLocalizedString(@"Color", nil)
											control:lsynthSelectionColorWell];
	saveRow = [PreferencesForm rowWithTitle:NSLocalizedString(@"Save synthesized parts", nil)
									   note:saveNote
									control:lsynthSaveSynthesizedParts
								  noteField:NULL];

	programSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"LSynth Program", nil)
												  rows:@[[PreferencesForm rowWithContent:executableGroup]]
												footer:programNote];

	configurationSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Configuration File", nil)
														rows:@[[PreferencesForm rowWithContent:configurationGroup],
															   simpleListRow]
													  footer:configurationNote];

	selectionSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Selection", nil)
													rows:@[modeRow, transparencyRow, colorRow]
												  footer:selectionNote];

	savingSection = [PreferencesForm sectionWithTitle:NSLocalizedString(@"Synthesized Parts", nil)
												 rows:@[saveRow]
											   footer:nil];

	return [PreferencesForm paneWithSections:@[programSection, configurationSection, selectionSection, savingSection]];

}//end makeLSynthPane


//========== showPreferencesWindow =============================================
//
// Purpose:		Brings the window on screen.
//
//==============================================================================
- (void) showPreferencesWindow
{
	[self setDialogValues];
	[preferencesWindow makeKeyAndOrderFront:nil];

}//end showPreferencesWindow


#pragma mark -

//========== setDialogValues ===================================================
//
// Purpose:		Makes every pane show what is stored in preferences.
//
//==============================================================================
- (void) setDialogValues
{
	//Make sure there are actually preferences to read before attempting to
	// retrieve them.
	[PreferencesDialogController ensureDefaults];

	[self setGeneralPaneValues];
	[self setMousePaneValues];
	[self setStepsPaneValues];
	[self setColorsPaneValues];
	[self setLSynthPaneValues];

}//end setDialogValues


//========== setGeneralPaneValues ==============================================
//
// Purpose:		Updates the General pane to match what is on the disk.
//
// Notes:		With no LDraw folder set yet, asks for one.
//
//==============================================================================
- (void) setGeneralPaneValues
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSString		*ldrawPath		= [userDefaults stringForKey:LDRAW_PATH_KEY];

	[gridSpacingFineField	setFloatValue:[userDefaults floatForKey:GRID_SPACING_FINE]];
	[gridSpacingMediumField	setFloatValue:[userDefaults floatForKey:GRID_SPACING_MEDIUM]];
	[gridSpacingCoarseField	setFloatValue:[userDefaults floatForKey:GRID_SPACING_COARSE]];

	if(ldrawPath != nil)
		[LDrawPathTextField setStringValue:ldrawPath];
	else
		[self chooseLDrawFolder:self];

}//end setGeneralPaneValues


//========== setMousePaneValues ================================================
//
// Purpose:		Updates the Mouse pane to match what is on the disk.
//
//==============================================================================
- (void) setMousePaneValues
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

	[mouseDraggingPopUp	selectItemWithTag:[userDefaults integerForKey:MOUSE_DRAGGING_BEHAVIOR_KEY]];
	[rightButtonPopUp	selectItemWithTag:[userDefaults integerForKey:RIGHT_BUTTON_BEHAVIOR_KEY]];
	[mouseWheelPopUp	selectItemWithTag:[userDefaults integerForKey:MOUSE_WHEEL_BEHAVIOR_KEY]];
	[rotateModePopUp	selectItemWithTag:[userDefaults integerForKey:ROTATE_MODE_KEY]];

	[self showMouseNotes];

}//end setMousePaneValues


//========== showMouseNotes ====================================================
//
// Purpose:		Explains each mouse choice under its pop-up menu.
//
//==============================================================================
- (void) showMouseNotes
{
	[mouseDraggingNote	setStringValue:MouseDraggingNote([mouseDraggingPopUp selectedTag])];
	[rightButtonNote	setStringValue:RightButtonNote([rightButtonPopUp selectedTag])];
	[mouseWheelNote		setStringValue:MouseWheelNote([mouseWheelPopUp selectedTag])];
	[rotateModeNote		setStringValue:RotateStyleNote([rotateModePopUp selectedTag])];

}//end showMouseNotes


//========== setStepsPaneValues ================================================
//
// Purpose:		Updates the Steps pane to match what is on the disk.
//
//==============================================================================
- (void) setStepsPaneValues
{
	NSUserDefaults	*userDefaults		= [NSUserDefaults standardUserDefaults];
	BOOL			 selectionGoesBack	= [userDefaults boolForKey:STEP_SELECTION_GOES_BACK_KEY];
	BOOL			 hideRemovedGroups	= [userDefaults boolForKey:HIDE_REMOVED_GROUPS_IN_STEPS_KEY];
	BOOL			 ghostRemovedGroups	= [userDefaults boolForKey:GHOST_REMOVED_GROUPS_KEY];
	BOOL			 ghostPreviousSteps	= [userDefaults boolForKey:GHOST_PREVIOUS_STEPS_KEY];
	NSInteger		 ghostTransparency	= [userDefaults integerForKey:GHOST_TRANSPARENCY_KEY];

	[stepSelectionGoesBackSwitch setState:(selectionGoesBack ? NSControlStateValueOn : NSControlStateValueOff)];
	[hideRemovedGroupsInStepsSwitch setState:(hideRemovedGroups ? NSControlStateValueOn : NSControlStateValueOff)];
	[ghostRemovedGroupsSwitch setState:(ghostRemovedGroups ? NSControlStateValueOn : NSControlStateValueOff)];
	[ghostPreviousStepsSwitch setState:(ghostPreviousSteps ? NSControlStateValueOn : NSControlStateValueOff)];

	// Routed through the setter rather than pushed into the two controls, so a
	// stored value outside the slider's travel is pulled into range instead of
	// leaving the slider and the field disagreeing. Re-pushing an unchanged
	// value to LDrawModel is free -- it only notifies on a change.
	[self setGhostTransparency:ghostTransparency];

	[self setStepPartListSwitch:stepPartListShowSwitch			fromKey:SHOW_STEP_PART_LIST_KEY];
	[self setStepPartListSwitch:stepPartListSubmodelsSwitch		fromKey:STEP_PART_LIST_SUBMODELS_KEY];
	[self setStepPartListSwitch:stepPartListFollowsStepSwitch	fromKey:STEP_PART_LIST_FOLLOWS_STEP_KEY];
	[self setStepPartListSwitch:stepPartListLPubScaleSwitch		fromKey:STEP_PART_LIST_LPUB_SCALE_KEY];

	[self showStepPartListOrientations];

}//end setStepsPaneValues


//========== setColorsPaneValues ===============================================
//
// Purpose:		Updates the Colors pane to match what is on the disk.
//
//==============================================================================
- (void) setColorsPaneValues
{
	[self setColorWell:backgroundColorWell	fromKey:LDRAW_VIEWER_BACKGROUND_COLOR_KEY];
	[self setColorWell:modelsColorWell		fromKey:SYNTAX_COLOR_MODELS_KEY];
	[self setColorWell:stepsColorWell		fromKey:SYNTAX_COLOR_STEPS_KEY];
	[self setColorWell:partsColorWell		fromKey:SYNTAX_COLOR_PARTS_KEY];
	[self setColorWell:primitivesColorWell	fromKey:SYNTAX_COLOR_PRIMITIVES_KEY];
	[self setColorWell:colorsColorWell		fromKey:SYNTAX_COLOR_COLORS_KEY];
	[self setColorWell:commentsColorWell	fromKey:SYNTAX_COLOR_COMMENTS_KEY];
	[self setColorWell:unknownColorWell		fromKey:SYNTAX_COLOR_UNKNOWN_KEY];

}//end setColorsPaneValues


//========== setColorWell:fromKey: =============================================
//
// Purpose:		Shows a stored color, or its default if it cannot be read.
//
//==============================================================================
- (void) setColorWell:(NSColorWell *)colorWell fromKey:(NSString *)key
{
	NSColor *color = [[NSUserDefaults standardUserDefaults] colorForKey:key] ?: FallbackColorForPreferenceKey(key);

	[colorWell setColor:color];

}//end setColorWell:fromKey:


//========== setLSynthPaneValues ===============================================
//
// Purpose:		Updates the LSynth pane to match what is on the disk.
//
//==============================================================================
- (void) setLSynthPaneValues
{
	NSUserDefaults		*userDefaults			= [NSUserDefaults standardUserDefaults];
	NSString			*executablePath			= [userDefaults stringForKey:LSYNTH_EXECUTABLE_PATH_KEY];
	NSString			*configurationPath		= [userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];
	NSInteger			 selectionTransparency	= [userDefaults integerForKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
	BOOL				 saveSynthesizedParts	= [userDefaults boolForKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];
	BOOL				 showBasicPartsList		= [userDefaults boolForKey:LSYNTH_SHOW_BASIC_PARTS_LIST_KEY];
	NSInteger			 selectionMode			= [userDefaults integerForKey:LSYNTH_SELECTION_MODE_KEY];
	LSynthSelectionControlEnablement enablement;

	enablement = [LDrawLSynthPanelModel selectionControlEnablementForMode:selectionMode];

	[lsynthExecutablePath		setStringValue:executablePath ?: @""];
	[lsynthConfigurationPath	setStringValue:configurationPath ?: @""];
	[lsynthSelectionModePopUp	selectItemWithTag:selectionMode];
	[lsynthTransparencySlider	setIntegerValue:selectionTransparency];
	[lsynthTransparencyText		setIntegerValue:selectionTransparency];
	[self setColorWell:lsynthSelectionColorWell fromKey:LSYNTH_SELECTION_COLOR_KEY];
	[lsynthSaveSynthesizedParts	setState:(saveSynthesizedParts ? NSControlStateValueOn : NSControlStateValueOff)];
	[lsynthShowBasicPartsList	setState:(showBasicPartsList ? NSControlStateValueOn : NSControlStateValueOff)];

	[lsynthTransparencySlider	setEnabled:enablement.transparencyEnabled];
	[lsynthTransparencyText		setEnabled:enablement.transparencyEnabled];
	[lsynthSelectionColorWell	setEnabled:enablement.colorWellEnabled];

}//end setLSynthPaneValues


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

#pragma mark -
#pragma mark General Pane

//========== gridSpacingChanged: ===============================================
//
// Purpose:		User updated the amounts by which parts are shifted in different
//				grid modes.
//
//==============================================================================
- (IBAction) gridSpacingChanged:(id)sender
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

	[userDefaults setFloat:[gridSpacingFineField floatValue]	forKey:GRID_SPACING_FINE];
	[userDefaults setFloat:[gridSpacingMediumField floatValue]	forKey:GRID_SPACING_MEDIUM];
	[userDefaults setFloat:[gridSpacingCoarseField floatValue]	forKey:GRID_SPACING_COARSE];

}//end gridSpacingChanged:


//========== chooseLDrawFolder =================================================
//
// Purpose:		Present a folder choose dialog to find the LDraw folder.
//
//==============================================================================
- (IBAction) chooseLDrawFolder:(id)sender
{
	NSOpenPanel	*folderChooser	= [NSOpenPanel openPanel];
	NSString	*accessoryText	= NSLocalizedString(@"Download the LDraw parts library from www.ldraw.org. "
												   @"The LDraw folder holds the \"p\" and \"parts\" folders.", nil);

	[folderChooser setCanChooseFiles:NO];
	[folderChooser setCanChooseDirectories:YES];
	[folderChooser setTitle:NSLocalizedString([LDrawHostChrome chooseLDrawFolderTitleKey], nil)];
	[folderChooser setMessage:NSLocalizedString([LDrawHostChrome ldrawFolderChooserMessageKey], nil)];
	[folderChooser setAccessoryView:[PreferencesForm chooserAccessoryViewWithText:accessoryText]];
	[folderChooser setAccessoryViewDisclosed:YES];
	[folderChooser setPrompt:NSLocalizedString([LDrawHostChrome choosePromptKey], nil)];

	if([folderChooser runModal] == NSModalResponseOK)
	{
		NSURL *folderURL = [[folderChooser URLs] objectAtIndex:0];

		if([folderURL isFileURL])
			[self changeLDrawFolderPath:[folderURL path]];
		else
			NSBeep(); // sanity check
	}

}//end chooseLDrawFolder:


//========== pathTextFieldChanged: =============================================
//
// Purpose:		The user typed a new LDraw folder path.
//
//==============================================================================
- (IBAction) pathTextFieldChanged:(id)sender
{
	[self changeLDrawFolderPath:[LDrawPathTextField stringValue]];

}//end pathTextFieldChanged:


//========== reloadParts: ======================================================
//
// Purpose:		Scans the contents of the LDraw/Parts folder and produces a
//				Mac-friendly index of parts.
//
//==============================================================================
- (IBAction) reloadParts:(id)sender
{
	PartLibraryController *libraryController = [LDrawApplication sharedPartLibraryController];

	[libraryController reloadPartCatalog:^(BOOL success) {}];

}//end reloadParts:


#pragma mark -
#pragma mark Mouse Pane

//========== mouseDraggingChanged: =============================================
//
// Purpose:		Mouse drag-and-drop behavior was changed.
//
//==============================================================================
- (IBAction) mouseDraggingChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[mouseDraggingPopUp selectedTag]
											   forKey:MOUSE_DRAGGING_BEHAVIOR_KEY];
	[self showMouseNotes];

}//end mouseDraggingChanged:


//========== rightButtonChanged: ===============================================
//
// Purpose:		Right-button behavior in the 3D view was changed.
//
//==============================================================================
- (IBAction) rightButtonChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[rightButtonPopUp selectedTag]
											   forKey:RIGHT_BUTTON_BEHAVIOR_KEY];
	[self showMouseNotes];

}//end rightButtonChanged:


//========== rotateModeChanged: ================================================
//
// Purpose:		Rotation mode (trackball vs turntable) was changed.
//
//==============================================================================
- (IBAction) rotateModeChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[rotateModePopUp selectedTag]
											   forKey:ROTATE_MODE_KEY];
	[self showMouseNotes];

}//end rotateModeChanged:


//========== mouseWheelChanged: ================================================
//
// Purpose:		Mouse-wheel behavior (scroll vs zoom) was changed.
//
//==============================================================================
- (IBAction) mouseWheelChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[mouseWheelPopUp selectedTag]
											   forKey:MOUSE_WHEEL_BEHAVIOR_KEY];
	[self showMouseNotes];

}//end mouseWheelChanged:


#pragma mark -
#pragma mark Steps Pane

//========== stepSelectionGoesBackChanged: =====================================
//
// Purpose:		The user toggled whether selecting an earlier step goes back to
//				it.
//
//==============================================================================
- (IBAction) stepSelectionGoesBackChanged:(id)sender
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	BOOL			 goesBack		= ([stepSelectionGoesBackSwitch state] == NSControlStateValueOn);

	[userDefaults setBool:goesBack forKey:STEP_SELECTION_GOES_BACK_KEY];

}//end stepSelectionGoesBackChanged:


//========== hideRemovedGroupsInStepsChanged: ==================================
//
// Purpose:		The user toggled whether the Steps view mode honors
//				0 !LPUB REMOVE GROUP commands.
//
//				Turning it off keeps a removed group on screen while stepping
//				through the build, which is what you want when the group is
//				what you are editing. The All view mode always honors removals.
//
//==============================================================================
- (IBAction) hideRemovedGroupsInStepsChanged:(id)sender
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	BOOL			 hideThem		= ([hideRemovedGroupsInStepsSwitch state] == NSControlStateValueOn);

	[userDefaults setBool:hideThem forKey:HIDE_REMOVED_GROUPS_IN_STEPS_KEY];

	// LDrawCore is defaults-free, so push the value; the setter notifies open
	// documents for us.
	[LDrawModel setHidesRemovedGroupsInStepDisplay:hideThem];

}//end hideRemovedGroupsInStepsChanged:


//========== ghostRemovedGroupsChanged: ========================================
//
// Purpose:		The user toggled whether the All view mode draws a removed group
//				translucent instead of dropping it.
//
//				A ghost stays selectable, so it can be clicked and edited while
//				the rest of the model reads normally. The Steps view mode is
//				unaffected -- there a group is either fully drawn or gone.
//
//==============================================================================
- (IBAction) ghostRemovedGroupsChanged:(id)sender
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	BOOL			 ghostThem		= ([ghostRemovedGroupsSwitch state] == NSControlStateValueOn);

	[userDefaults setBool:ghostThem forKey:GHOST_REMOVED_GROUPS_KEY];

	// LDrawCore is defaults-free, so push the value; the setter notifies open
	// documents for us.
	[LDrawModel setShowsRemovedGroupsAsGhosts:ghostThem];

}//end ghostRemovedGroupsChanged:


//========== ghostPreviousStepsChanged: ========================================
//
// Purpose:		The user toggled whether the Steps view mode draws everything
//				built before the current step as translucent ghosts.
//
//				It makes the parts a step adds stand out against the assembly
//				they go onto, which stays on screen for context. The ghosts stay
//				selectable, and the All view mode is unaffected.
//
//==============================================================================
- (IBAction) ghostPreviousStepsChanged:(id)sender
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	BOOL			 ghostThem		= ([ghostPreviousStepsSwitch state] == NSControlStateValueOn);

	[userDefaults setBool:ghostThem forKey:GHOST_PREVIOUS_STEPS_KEY];

	// LDrawCore is defaults-free, so push the value; the setter notifies open
	// documents for us.
	[LDrawModel setGhostsPreviousSteps:ghostThem];

}//end ghostPreviousStepsChanged:


//========== ghostTransparencySliderChanged: ===================================
//
// Purpose:		The user dragged the ghost transparency slider.
//
//==============================================================================
- (IBAction) ghostTransparencySliderChanged:(id)sender
{
	[self setGhostTransparency:[sender integerValue]];

}//end ghostTransparencySliderChanged:


//========== ghostTransparencyTextChanged: =====================================
//
// Purpose:		The user typed a ghost transparency.
//
//==============================================================================
- (IBAction) ghostTransparencyTextChanged:(id)sender
{
	[self setGhostTransparency:[sender integerValue]];

}//end ghostTransparencyTextChanged:


//========== setGhostTransparency: =============================================
//
// Purpose:		Stores how see-through a ghost draws and gets it onto the
//				screen.
//
//				One value covers both kinds of ghost -- a removed MLCAD group
//				and, in the Steps view mode, a step already built.
//
// Notes:		Shared by the slider and the text field, which are two ways of
//				saying the same thing and have to agree afterwards.
//
//==============================================================================
- (void) setGhostTransparency:(NSInteger)percent
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];

	// LDrawModel clamps the alpha it is handed, so clamp to the same band here:
	// what the controls show then always matches what took effect.
	NSInteger		 clamped		= MAX(GhostTransparencyMinPercent(), MIN(GhostTransparencyMaxPercent(), percent));

	[userDefaults setInteger:clamped forKey:GHOST_TRANSPARENCY_KEY];
	[ghostTransparencySlider setIntegerValue:clamped];
	[ghostTransparencyText setIntegerValue:clamped];

	// LDrawCore is defaults-free, so push the value; the setter notifies open
	// documents for us.
	[LDrawModel setGhostAlpha:LDrawGhostAlphaForTransparencyPercent(clamped)];

}//end setGhostTransparency:


//========== stepPartListShowChanged: ==========================================
//
// Purpose:		The user toggled the step parts list.
//
// Notes:		Off by default. The list only shows in Steps view mode.
//
//==============================================================================
- (IBAction) stepPartListShowChanged:(id)sender
{
	[self storeStepPartListFlagFromSwitch:stepPartListShowSwitch forKey:SHOW_STEP_PART_LIST_KEY];

}//end stepPartListShowChanged:


//========== stepPartListSubmodelsChanged: =====================================
//
// Purpose:		The user chose whether submodel references get a row.
//
//==============================================================================
- (IBAction) stepPartListSubmodelsChanged:(id)sender
{
	[self storeStepPartListFlagFromSwitch:stepPartListSubmodelsSwitch forKey:STEP_PART_LIST_SUBMODELS_KEY];

}//end stepPartListSubmodelsChanged:


//========== stepPartListFollowsStepChanged: ===================================
//
// Purpose:		The user chose whether the icons follow the step's rotation.
//
// Notes:		Following the step draws the icons at the same angle as the
//				assembly next to them. The other choice is LPub3D's way: one
//				fixed angle for the whole document.
//
//==============================================================================
- (IBAction) stepPartListFollowsStepChanged:(id)sender
{
	[self storeStepPartListFlagFromSwitch:stepPartListFollowsStepSwitch
								   forKey:STEP_PART_LIST_FOLLOWS_STEP_KEY];

}//end stepPartListFollowsStepChanged:


//========== stepPartListLPubScaleChanged: =====================================
//
// Purpose:		The user chose whether the list is drawn on LPub3D's page, at
//				the size LPub3D would print it.
//
//==============================================================================
- (IBAction) stepPartListLPubScaleChanged:(id)sender
{
	[self storeStepPartListFlagFromSwitch:stepPartListLPubScaleSwitch forKey:STEP_PART_LIST_LPUB_SCALE_KEY];

}//end stepPartListLPubScaleChanged:


//========== chooseStepPartListOrientations: ===================================
//
// Purpose:		Picks the PLI control file the parts list orients its parts by.
//
//==============================================================================
- (IBAction) chooseStepPartListOrientations:(id)sender
{
	NSOpenPanel	*chooser	= [NSOpenPanel openPanel];
	NSString	*current	= [[self class] stepPartListOrientationsPath];

	[chooser setCanChooseFiles:YES];
	[chooser setCanChooseDirectories:NO];
	[chooser setAllowsMultipleSelection:NO];
	[chooser setMessage:NSLocalizedString(@"StepPartListOrientationsChooserMessage", nil)];

	if(current != nil)
		[chooser setDirectoryURL:[NSURL fileURLWithPath:[current stringByDeletingLastPathComponent]]];

	if([chooser runModal] != NSModalResponseOK || [[chooser URLs] count] == 0)
		return;

	[[NSUserDefaults standardUserDefaults] setObject:[[[chooser URLs] objectAtIndex:0] path]
											  forKey:STEP_PART_LIST_ORIENTATIONS_FILE_KEY];

	[[self class] loadStepPartListOrientations];
	[self showStepPartListOrientations];
	[self postStepPartListDidChange];

}//end chooseStepPartListOrientations:


//========== useDefaultStepPartListOrientations: ===============================
//
// Purpose:		Goes back to LPub3D's own control file, if it is installed.
//
//==============================================================================
- (IBAction) useDefaultStepPartListOrientations:(id)sender
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:STEP_PART_LIST_ORIENTATIONS_FILE_KEY];

	[[self class] loadStepPartListOrientations];
	[self showStepPartListOrientations];
	[self postStepPartListDidChange];

}//end useDefaultStepPartListOrientations:


//========== showStepPartListOrientations ======================================
//
// Purpose:		Says which control file is in use, and whether it was read.
//
//==============================================================================
- (void) showStepPartListOrientations
{
	NSUserDefaults				*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSString					*path			= [[self class] stepPartListOrientationsPath];
	LDrawPartListOrientations	*orientations	= [LDrawStepPartList partOrientations];
	BOOL						 fileWasChosen	= ([[userDefaults stringForKey:STEP_PART_LIST_ORIENTATIONS_FILE_KEY] length] > 0);
	NSString					*text			= nil;

	if(path == nil)
		text = NSLocalizedString(@"StepPartListOrientationsNone", nil);
	else if(orientations == nil)
		text = [NSString stringWithFormat:NSLocalizedString(@"StepPartListOrientationsUnreadableFormat", nil),
				[path lastPathComponent]];
	else
	{
		NSString *format = fileWasChosen ? NSLocalizedString(@"StepPartListOrientationsChosenFormat", nil)
										 : NSLocalizedString(@"StepPartListOrientationsDefaultFormat", nil);

		text = [NSString stringWithFormat:format, [path lastPathComponent],
				(unsigned long)[orientations count]];
	}

	[stepPartListOrientationsField setStringValue:text];
	[stepPartListOrientationsField setToolTip:path];

}//end showStepPartListOrientations


//========== storeStepPartListFlagFromSwitch:forKey: ===========================
//
// Purpose:		Stores a parts list switch and tells the open documents.
//
//==============================================================================
- (void) storeStepPartListFlagFromSwitch:(NSSwitch *)toggle forKey:(NSString *)key
{
	BOOL on = ([toggle state] == NSControlStateValueOn);

	[[NSUserDefaults standardUserDefaults] setBool:on forKey:key];

	[[self class] pushStepPartListDefaults];
	[self postStepPartListDidChange];

}//end storeStepPartListFlagFromSwitch:forKey:


//========== setStepPartListSwitch:fromKey: ====================================
//
// Purpose:		Shows what a stored parts list flag says.
//
//==============================================================================
- (void) setStepPartListSwitch:(NSSwitch *)toggle fromKey:(NSString *)key
{
	BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:key];

	[toggle setState:(on ? NSControlStateValueOn : NSControlStateValueOff)];

}//end setStepPartListSwitch:fromKey:


//========== postStepPartListDidChange =========================================
//
// Purpose:		Tells the open documents to re-evaluate their overlays.
//
//==============================================================================
- (void) postStepPartListDidChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawStepPartListDidChangeNotification
														object:nil];

}//end postStepPartListDidChange


#pragma mark -
#pragma mark Colors Pane

//========== backgroundColorWellChanged: =======================================
//
// Purpose:		The color for the LDraw views' background has been changed.
//				Update the value in the preferences.
//
//==============================================================================
- (IBAction) backgroundColorWellChanged:(NSColorWell *)sender
{
	NSColor *newColor = [sender color];

	[[NSUserDefaults standardUserDefaults] setColor:newColor forKey:LDRAW_VIEWER_BACKGROUND_COLOR_KEY];

	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawViewBackgroundColorDidChangeNotification
														object:newColor];

}//end backgroundColorWellChanged:


//========== modelsColorWellChanged: ===========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) modelsColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_MODELS_KEY];

}//end modelsColorWellChanged:


//========== stepsColorWellChanged: ============================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) stepsColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_STEPS_KEY];

}//end stepsColorWellChanged:


//========== partsColorWellChanged: ============================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) partsColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_PARTS_KEY];

}//end partsColorWellChanged:


//========== primitivesColorWellChanged: =======================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) primitivesColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_PRIMITIVES_KEY];

}//end primitivesColorWellChanged:


//========== colorsColorWellChanged: ===========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) colorsColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_COLORS_KEY];

}//end colorsColorWellChanged:


//========== commentsColorWellChanged: =========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) commentsColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_COMMENTS_KEY];

}//end commentsColorWellChanged:


//========== unknownColorWellChanged: ==========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) unknownColorWellChanged:(NSColorWell *)sender
{
	[self storeSyntaxColor:[sender color] forKey:SYNTAX_COLOR_UNKNOWN_KEY];

}//end unknownColorWellChanged:


//========== storeSyntaxColor:forKey: ==========================================
//
// Purpose:		Stores a file contents color and tells the open documents.
//
//==============================================================================
- (void) storeSyntaxColor:(NSColor *)color forKey:(NSString *)key
{
	[[NSUserDefaults standardUserDefaults] setColor:color forKey:key];

	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawSyntaxColorsDidChangeNotification
														object:NSApp];

}//end storeSyntaxColor:forKey:


#pragma mark -
#pragma mark LSynth Pane

//========== lsynthChooseExecutable: ===========================================
//
// Purpose:		The user wishes to choose their own LSynth executable.
//
//==============================================================================
- (IBAction) lsynthChooseExecutable:(id)sender
{
	NSOpenPanel	*chooser		= [NSOpenPanel openPanel];
	NSString	*accessoryText	= NSLocalizedString(@"LSynth source and ready-built programs are at "
												   @"http://lsynth.sourceforge.net/. The Bricksmith sources "
												   @"also hold a version changed to work with Bricksmith.", nil);

	[chooser setCanChooseFiles:YES];
	[chooser setCanChooseDirectories:NO];
	[chooser setTitle:NSLocalizedString([LDrawHostChrome chooseLSynthExecutableTitleKey], nil)];
	[chooser setMessage:NSLocalizedString([LDrawHostChrome lsynthExecutableChooserMessageKey], nil)];
	[chooser setAccessoryView:[PreferencesForm chooserAccessoryViewWithText:accessoryText]];
	[chooser setAccessoryViewDisclosed:YES];
	[chooser setPrompt:NSLocalizedString([LDrawHostChrome choosePromptKey], nil)];

	if([chooser runModal] == NSModalResponseOK)
	{
		NSURL *executableURL = [[chooser URLs] objectAtIndex:0];

		// TODO: validation?
		if([executableURL isFileURL])
		{
			[lsynthExecutablePath setStringValue:[executableURL path]];
			[[NSUserDefaults standardUserDefaults] setObject:[executableURL path] forKey:LSYNTH_EXECUTABLE_PATH_KEY];
		}
		else
			NSBeep(); // sanity check
	}

}//end lsynthChooseExecutable:


//========== lsynthChooseConfiguration: ========================================
//
// Purpose:		The user wishes to choose their own LSynth configuration file.
//
//==============================================================================
- (IBAction) lsynthChooseConfiguration:(id)sender
{
	NSUserDefaults	*userDefaults			= [NSUserDefaults standardUserDefaults];
	NSString		*currentConfiguration	= [userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];
	NSOpenPanel		*chooser				= [NSOpenPanel openPanel];
	NSString		*accessoryText			= NSLocalizedString(@"Bricksmith comes with a default LSynth configuration "
															   @"file. It defines the common flexible parts such as "
															   @"bands, chains and tubes. You may use your own "
															   @"version of the file to customize them.", nil);

	[chooser setCanChooseFiles:YES];
	[chooser setCanChooseDirectories:NO];
	[chooser setTitle:NSLocalizedString([LDrawHostChrome chooseLSynthConfigurationTitleKey], nil)];
	[chooser setMessage:NSLocalizedString([LDrawHostChrome lsynthConfigurationChooserMessageKey], nil)];
	[chooser setAccessoryView:[PreferencesForm chooserAccessoryViewWithText:accessoryText]];
	[chooser setAccessoryViewDisclosed:YES];
	[chooser setPrompt:NSLocalizedString([LDrawHostChrome choosePromptKey], nil)];

	if([chooser runModal] == NSModalResponseOK)
	{
		NSURL *configurationURL = [[chooser URLs] objectAtIndex:0];

		// TODO: validation?
		if([configurationURL isFileURL])
		{
			[lsynthConfigurationPath setStringValue:[configurationURL path]];
			[userDefaults setObject:[configurationURL path] forKey:LSYNTH_CONFIGURATION_PATH_KEY];

			// reload config if changed
			if([currentConfiguration isEqualToString:[configurationURL path]])
				[[LSynthConfiguration sharedInstance] parseLsynthConfig:[configurationURL path]];
		}
		else
			NSBeep(); // sanity check
	}

}//end lsynthChooseConfiguration:


//========== lsynthTransparencySliderChanged: ==================================
//
// Purpose:		The user has changed the LSynth selection transparency
//
//==============================================================================
- (IBAction) lsynthTransparencySliderChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[sender integerValue] forKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
	[lsynthTransparencyText setIntegerValue:[sender integerValue]];
	[self lsynthRequiresRedisplay];

}//end lsynthTransparencySliderChanged:


//========== lsynthTransparencyTextChanged: ====================================
//
// Purpose:		The user has changed the LSynth selection transparency
//
//==============================================================================
- (IBAction) lsynthTransparencyTextChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[sender integerValue] forKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
	[lsynthTransparencySlider setIntegerValue:[sender integerValue]];
	[self lsynthRequiresRedisplay];

}//end lsynthTransparencyTextChanged:


//========== lsynthSelectionColorWellClicked: ==================================
//
// Purpose:		The user has changed the LSynth selection color
//
//==============================================================================
- (IBAction) lsynthSelectionColorWellClicked:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSColor			*rgba			= [newColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: newColor;

	[userDefaults setColor:newColor forKey:LSYNTH_SELECTION_COLOR_KEY];

	// Mirror into the Foundation-only RGBA key so LDrawCore can read the
	// current selection color without depending on NSColor.
	[userDefaults setObject:@[ @([rgba redComponent]),
							   @([rgba greenComponent]),
							   @([rgba blueComponent]),
							   @([rgba alphaComponent]) ]
					 forKey:LSYNTH_SELECTION_COLOR_RGBA_KEY];
	[self lsynthRequiresRedisplay];

}//end lsynthSelectionColorWellClicked:


//========== lsynthSelectionModeChanged: =======================================
//
// Purpose:		User has chosen between transparency, color or both
//
//==============================================================================
- (IBAction) lsynthSelectionModeChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[lsynthSelectionModePopUp selectedTag]
											   forKey:LSYNTH_SELECTION_MODE_KEY];

	[self setLSynthPaneValues];
	[self lsynthRequiresRedisplay];

}//end lsynthSelectionModeChanged:


//========== lsynthSaveSynthesizedPartsChanged: ================================
//
// Purpose:		User has toggled the 'Save synthesized parts' switch
//
//==============================================================================
- (IBAction) lsynthSaveSynthesizedPartsChanged:(id)sender
{
	BOOL on = ([lsynthSaveSynthesizedParts state] == NSControlStateValueOn);

	[[NSUserDefaults standardUserDefaults] setBool:on forKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];

}//end lsynthSaveSynthesizedPartsChanged:


//========== lsynthShowBasicPartsListChanged: ==================================
//
// Purpose:		User has toggled the 'Show simple parts list' switch
//
//==============================================================================
- (IBAction) lsynthShowBasicPartsListChanged:(id)sender
{
	BOOL on = ([lsynthShowBasicPartsList state] == NSControlStateValueOn);

	[[NSUserDefaults standardUserDefaults] setBool:on forKey:LSYNTH_SHOW_BASIC_PARTS_LIST_KEY];

	// Regenerate LSynth part menus
	[[LDrawApplication shared] populateLSynthModelMenus];

}//end lsynthShowBasicPartsListChanged:


//========== lsynthRequiresRedisplay ===========================================
//
// Purpose:		Tells LSynth parts to redraw, since the selection highlight
//				changed.
//
//==============================================================================
- (void) lsynthRequiresRedisplay
{
	[[NSNotificationCenter defaultCenter] postNotificationName:LSynthSelectionDisplayDidChangeNotification
														object:NSApp];

}//end lsynthRequiresRedisplay


//========== lsynthRequiresResynthesis =========================================
//
// Purpose:		Tells LSynth parts to synthesize again, since the executable or
//				the configuration file changed.
//
//==============================================================================
- (void) lsynthRequiresResynthesis
{
	[[NSNotificationCenter defaultCenter] postNotificationName:LSynthResynthesisRequiredNotification
														object:NSApp];

}//end lsynthRequiresResynthesis


#pragma mark -
#pragma mark SIDEBAR
#pragma mark -

//**** NSTableViewDataSource ****
//========== numberOfRowsInTableView: ==========================================
//
// Purpose:		One row per pane.
//
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	return [paneIdentifiers count];

}//end numberOfRowsInTableView:


//**** NSTableViewDelegate ****
//========== tableView:viewForTableColumn:row: =================================
//
// Purpose:		A pane's small icon and name.
//
//==============================================================================
- (NSView *) tableView:(NSTableView *)tableView
	viewForTableColumn:(NSTableColumn *)tableColumn
				   row:(NSInteger)row
{
	NSString		*identifier	= paneIdentifiers[row];
	NSTableCellView	*cell		= [tableView makeViewWithIdentifier:@"PaneCell" owner:self];

	if(cell == nil)
	{
		NSImageView	*imageView	= [[NSImageView alloc] init];
		NSTextField	*textField	= [NSTextField labelWithString:@""];

		cell = [[NSTableCellView alloc] init];
		[cell setIdentifier:@"PaneCell"];

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
			[[imageView widthAnchor] constraintEqualToConstant:20],
			[[textField leadingAnchor] constraintEqualToAnchor:[imageView trailingAnchor] constant:6],
			[[textField trailingAnchor] constraintLessThanOrEqualToAnchor:[cell trailingAnchor] constant:-2],
			[[textField centerYAnchor] constraintEqualToAnchor:[cell centerYAnchor]],
		]];
	}

	[[cell textField] setStringValue:NSLocalizedString(identifier, nil)];
	[[cell imageView] setImage:[NSImage imageWithSystemSymbolName:SymbolNameForPane(identifier)
										 accessibilityDescription:nil]];

	return cell;

}//end tableView:viewForTableColumn:row:


//**** NSTableViewDelegate ****
//========== tableViewSelectionDidChange: ======================================
//
// Purpose:		Shows the pane picked in the sidebar.
//
//==============================================================================
- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [sidebarTable selectedRow];

	if(row >= 0)
		[self showPaneWithIdentifier:paneIdentifiers[row]];

}//end tableViewSelectionDidChange:


//========== selectPaneWithIdentifier: =========================================
//
// Purpose:		Selects a pane in the sidebar and shows it.
//
//==============================================================================
- (void) selectPaneWithIdentifier:(NSString *)identifier
{
	NSUInteger row = [paneIdentifiers indexOfObject:identifier];

	if(row == NSNotFound)
		return;

	[sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[self showPaneWithIdentifier:identifier];

}//end selectPaneWithIdentifier:


//========== showPaneWithIdentifier: ===========================================
//
// Purpose:		Puts a pane on the right and fits the window to it.
//
//==============================================================================
- (void) showPaneWithIdentifier:(NSString *)identifier
{
	NSScrollView *pane = panes[identifier];

	if(pane == nil || [identifier isEqualToString:selectedPaneIdentifier])
		return;

	[[detailView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	[detailView addSubview:pane];
	[NSLayoutConstraint activateConstraints:@[
		[[pane leadingAnchor] constraintEqualToAnchor:[detailView leadingAnchor]],
		[[pane trailingAnchor] constraintEqualToAnchor:[detailView trailingAnchor]],
		[[pane topAnchor] constraintEqualToAnchor:[detailView topAnchor]],
		[[pane bottomAnchor] constraintEqualToAnchor:[detailView bottomAnchor]],
	]];

	selectedPaneIdentifier = identifier;
	[preferencesWindow setTitle:NSLocalizedString(identifier, nil)];
	[self fitWindowToPane:pane];

}//end showPaneWithIdentifier:


//========== fitWindowToPane: ==================================================
//
// Purpose:		Makes the window as tall as the pane, keeping its top edge in
//				place. A pane taller than the screen scrolls.
//
//==============================================================================
- (void) fitWindowToPane:(NSScrollView *)pane
{
	NSScreen	*screen			= [preferencesWindow screen] ?: [NSScreen mainScreen];
	NSRect		 frame			= [preferencesWindow frame];
	CGFloat		 barsHeight		= NSHeight(frame) - NSHeight([preferencesWindow contentLayoutRect]);
	CGFloat		 paneHeight		= [[pane documentView] fittingSize].height;
	CGFloat		 newHeight		= MAX(kMinWindowHeight, paneHeight + barsHeight);

	newHeight			= MIN(newHeight, NSHeight([screen visibleFrame]));
	frame.origin.y		+= NSHeight(frame) - newHeight;
	frame.size.height	= newHeight;

	[preferencesWindow setFrame:frame display:YES animate:[preferencesWindow isVisible]];

}//end fitWindowToPane:


#pragma mark -
#pragma mark TOOLBAR DELEGATE
#pragma mark -

//**** NSToolbarDelegate ****
//========== toolbarAllowedItemIdentifiers: ====================================
//
// Purpose:		Only a separator that follows the sidebar edge.
//
//==============================================================================
- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[NSToolbarSidebarTrackingSeparatorItemIdentifier];

}//end toolbarAllowedItemIdentifiers:


//**** NSToolbarDelegate ****
//========== toolbarDefaultItemIdentifiers: ====================================
//
// Purpose:		Only a separator that follows the sidebar edge.
//
//==============================================================================
- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarAllowedItemIdentifiers:toolbar];

}//end toolbarDefaultItemIdentifiers:


//**** NSToolbarDelegate ****
//========== toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: ==========
//
// Purpose:		The toolbar has no items of its own.
//
//==============================================================================
- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar
	  itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
  willBeInsertedIntoToolbar:(BOOL)flag
{
	return nil;

}//end toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:


#pragma mark -
#pragma mark WINDOW DELEGATE
#pragma mark -

//**** NSWindowDelegate ****
//========== windowWillClose: ==================================================
//
// Purpose:		Remembers the pane and the window position for next time.
//
//==============================================================================
- (void) windowWillClose:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults] setObject:selectedPaneIdentifier
											  forKey:PREFERENCES_LAST_TAB_DISPLAYED];

	// Cocoa autosaving doesn't necessarily get restored when we need it to, so
	// we have to track in manually.
	[preferencesWindow saveFrameUsingName:PREFERENCES_WINDOW_AUTOSAVE_NAME];

}//end windowWillClose:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//---------- ensureDefaults ------------------------------------------[static]--
//
// Purpose:		Verifies that all expected settings exist in preferences. If a
//				setting is not found, it is restored to its default value.
//
//				This method should be called upon program launch, so that the
//				rest of the program need not worry about preference
//				error-checking.
//
//------------------------------------------------------------------------------
+ (void) ensureDefaults
{
	[LDrawPreferences ensureDefaults:[NSUserDefaults standardUserDefaults]
				previousPartCategory:NSLocalizedString(@"Brick", nil)];

	NSUserDefaults		*userDefaults		= [NSUserDefaults standardUserDefaults];
	NSMutableDictionary	*initialDefaults	= [NSMutableDictionary dictionary];

	NSColor				*backgroundColor	= FallbackColorForPreferenceKey(LDRAW_VIEWER_BACKGROUND_COLOR_KEY);
	NSColor				*modelsColor		= FallbackColorForPreferenceKey(SYNTAX_COLOR_MODELS_KEY);
	NSColor				*stepsColor			= FallbackColorForPreferenceKey(SYNTAX_COLOR_STEPS_KEY);
	NSColor				*partsColor			= FallbackColorForPreferenceKey(SYNTAX_COLOR_PARTS_KEY);
	NSColor				*primitivesColor	= FallbackColorForPreferenceKey(SYNTAX_COLOR_PRIMITIVES_KEY);
	NSColor				*colorsColor		= FallbackColorForPreferenceKey(SYNTAX_COLOR_COLORS_KEY);
	NSColor				*commentsColor		= FallbackColorForPreferenceKey(SYNTAX_COLOR_COMMENTS_KEY);
	NSColor				*removeGroupColor	= FallbackColorForPreferenceKey(SYNTAX_COLOR_REMOVE_GROUP_KEY);
	NSColor				*unknownColor		= FallbackColorForPreferenceKey(SYNTAX_COLOR_UNKNOWN_KEY);

	// AppKit-only color defaults. Numeric/string keys are registered by
	// LDrawPreferences so other hosts can seed them without NSColor.
	[initialDefaults setObject:archivedData(backgroundColor)	forKey:LDRAW_VIEWER_BACKGROUND_COLOR_KEY];
	[initialDefaults setObject:archivedData(modelsColor)		forKey:SYNTAX_COLOR_MODELS_KEY];
	[initialDefaults setObject:archivedData(stepsColor)			forKey:SYNTAX_COLOR_STEPS_KEY];
	[initialDefaults setObject:archivedData(partsColor)			forKey:SYNTAX_COLOR_PARTS_KEY];
	[initialDefaults setObject:archivedData(primitivesColor)	forKey:SYNTAX_COLOR_PRIMITIVES_KEY];
	[initialDefaults setObject:archivedData(commentsColor)		forKey:SYNTAX_COLOR_COMMENTS_KEY];
	[initialDefaults setObject:archivedData(removeGroupColor)	forKey:SYNTAX_COLOR_REMOVE_GROUP_KEY];
	[initialDefaults setObject:archivedData(colorsColor)		forKey:SYNTAX_COLOR_COLORS_KEY];
	[initialDefaults setObject:archivedData(unknownColor)		forKey:SYNTAX_COLOR_UNKNOWN_KEY];

	NSColor *lsynthSelectionColor = FallbackColorForPreferenceKey(LSYNTH_SELECTION_COLOR_KEY);
	[initialDefaults setObject:archivedData(lsynthSelectionColor) forKey:LSYNTH_SELECTION_COLOR_KEY];
	{
		NSColor *rgbaColor = [lsynthSelectionColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: lsynthSelectionColor;
		[initialDefaults setObject:@[ @([rgbaColor redComponent]),
									  @([rgbaColor greenComponent]),
									  @([rgbaColor blueComponent]),
									  @([rgbaColor alphaComponent]) ]
							forKey:LSYNTH_SELECTION_COLOR_RGBA_KEY];
	}

	[userDefaults registerDefaults:initialDefaults];

}//end ensureDefaults


//---------- stepPartListOrientationsPath ----------------------------[static]--
//
// Purpose:		The control file in use: the one chosen, else LPub3D's own.
//
//------------------------------------------------------------------------------
+ (NSString *) stepPartListOrientationsPath
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSString		*chosenPath		= [userDefaults stringForKey:STEP_PART_LIST_ORIENTATIONS_FILE_KEY];

	if([chosenPath length] > 0)
		return chosenPath;

	return [LDrawPartListOrientations lpubDefaultFilePath];

}//end stepPartListOrientationsPath


//---------- loadStepPartListOrientations ----------------------------[static]--
//
// Purpose:		Reads the control file into the parts list, or clears it.
//
// Notes:		Read once here, not every time a list is packed, because the
//				file is large and rarely changes.
//
//------------------------------------------------------------------------------
+ (void) loadStepPartListOrientations
{
	NSString					*path			= [self stepPartListOrientationsPath];
	LDrawPartListOrientations	*orientations	= nil;

	if(path != nil)
		orientations = [LDrawPartListOrientations orientationsWithContentsOfFile:path error:NULL];

	[LDrawStepPartList setPartOrientations:orientations];

}//end loadStepPartListOrientations


//---------- pushStepPartListDefaults --------------------------------[static]--
//
// Purpose:		Copies the parts list preferences into LDrawStepPartList, which
//				does not read user defaults.
//
//------------------------------------------------------------------------------
+ (void) pushStepPartListDefaults
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

	[LDrawStepPartList setEnabled:[userDefaults boolForKey:SHOW_STEP_PART_LIST_KEY]];
	[LDrawStepPartList setIncludesSubmodels:[userDefaults boolForKey:STEP_PART_LIST_SUBMODELS_KEY]];
	[LDrawStepPartList setFollowsStepRotation:[userDefaults boolForKey:STEP_PART_LIST_FOLLOWS_STEP_KEY]];
	[LDrawStepPartList setUsesLPubScale:[userDefaults boolForKey:STEP_PART_LIST_LPUB_SCALE_KEY]];

}//end pushStepPartListDefaults


//========== changeLDrawFolderPath: ============================================
//
// Purpose:		A new folder path has been chose as the LDraw folder. We need to
//				check it out and reload the parts from it.
//
//==============================================================================
- (void) changeLDrawFolderPath:(NSString *)folderPath
{
	PartLibraryController	*libraryController	= [LDrawApplication sharedPartLibraryController];
	NSUserDefaults			*userDefaults		= [NSUserDefaults standardUserDefaults];

	[LDrawPathTextField setStringValue:folderPath];

	// Record this new folder in preferences whether it's right or not. We'll
	// let them sink their own ship here.
	[userDefaults setObject:folderPath forKey:LDRAW_PATH_KEY];
	[[LDrawPaths sharedPaths] setPreferredLDrawPath:folderPath];

	if([libraryController validateLDrawFolderWithMessage:folderPath] == YES)
		[self reloadParts:self];
	//else we displayed an error message already.

}//end changeLDrawFolderPath:


#pragma mark -
#pragma mark <NSTextFieldDelegate>
#pragma mark -

//========== controlTextDidEndEditing: =========================================
//
// Purpose:		The user finished editing a text field.  Used specifically by
//              the LSynth pane to validate and resynthesize in a timely fashion.
//
//==============================================================================
- (void) controlTextDidEndEditing:(NSNotification *)aNotification
{
	NSTextField		*textField				= [aNotification object];
	NSUserDefaults	*userDefaults			= [NSUserDefaults standardUserDefaults];
	NSString		*currentExecutable		= [userDefaults stringForKey:LSYNTH_EXECUTABLE_PATH_KEY];
	NSString		*currentConfiguration	= [userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];

	// The user manually changed the LSynth executable path
	// TODO: run validating synthesis
	if(textField == lsynthExecutablePath)
	{
		NSURL *executablePathAsURL = [NSURL fileURLWithPath:[lsynthExecutablePath stringValue]];

		if([executablePathAsURL isFileURL] && ![currentExecutable isEqualToString:[executablePathAsURL path]])
		{
			[userDefaults setObject:[executablePathAsURL path] forKey:LSYNTH_EXECUTABLE_PATH_KEY];
			[self lsynthRequiresResynthesis];
		}
		// No path - it's been deleted
		else if(   ([[executablePathAsURL path] length] == 0 || [[executablePathAsURL path] isMatchedByRegex:@"^\\s+$"])
				&& executablePathAsURL
				&& ![currentExecutable isEqualToString:[executablePathAsURL path]])
		{
			[userDefaults setObject:@"" forKey:LSYNTH_EXECUTABLE_PATH_KEY];
			[self lsynthRequiresResynthesis];
		}
		else if(executablePathAsURL)
			NSBeep(); // sanity check
	}

	// The user manually changed the LSynth config path
	// TODO: run validating synthesis
	else if(textField == lsynthConfigurationPath)
	{
		NSURL *configPathAsURL = [NSURL fileURLWithPath:[lsynthConfigurationPath stringValue]];

		if([configPathAsURL isFileURL])
		{
			[userDefaults setObject:[configPathAsURL path] forKey:LSYNTH_CONFIGURATION_PATH_KEY];

			// reload config if changed
			if(![currentConfiguration isEqualToString:[configPathAsURL path]])
			{
				[[LSynthConfiguration sharedInstance] parseLsynthConfig:[configPathAsURL path]];
				[[LDrawApplication shared] populateLSynthModelMenus];
				[self lsynthRequiresResynthesis];
			}
		}
		// No path - it's been deleted
		else if(!configPathAsURL || [[configPathAsURL path] length] == 0)
		{
			[userDefaults setObject:@"" forKey:LSYNTH_CONFIGURATION_PATH_KEY];
			[[LSynthConfiguration sharedInstance] parseLsynthConfig:[LDrawLSynthPanelModel configPathInBundle:[NSBundle mainBundle]]];
			[[LDrawApplication shared] populateLSynthModelMenus];
			[self lsynthRequiresResynthesis];
		}
		else
			NSBeep(); // sanity check
	}

}//end controlTextDidEndEditing:

@end
