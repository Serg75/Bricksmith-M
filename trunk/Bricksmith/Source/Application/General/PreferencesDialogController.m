//==============================================================================
//
// File:		PreferencesDialogController.m
//
// Purpose:		Handles the user interface between the application and its 
//				preferences file.
//
// Notes:
//
// To add a new Preferences pane the following steps are required:
//
// Preferences.xib
//   - Add a skeleton NSView, named appropriately.  Change the Document Label for
//     the view and set its dimensions to e.g. 486 x height
// 
// Create an appropriate .tiff icon for the preference panel 'tab' in e.g.
// Resources/Icon
// 
// PreferencesDialogController.h:
//   - #define a constant for the new panel
//   - Add an IBOutlet for the new view and connect it to the view.
//   - Add a declaration for a new -(void)setNewPanelTabValues method.
//
// PreferencesDialogController.m:
//   - In -(void)setDialogValues add setNewPanelTabValues
//   - Add the -(void)setNewPanelTabValues method
//   - Update -(NSArray *)toolbarAllowedItemIdentifiers:
//   - Update -(void)selectPanelWithIdentifier:
//   - Update -(NSToolbarItem *)toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
//
// Add pref panel title to Resources/Localizable.strings in the Preferences section.
//
// Run it up and check it's there.  Hopefully you're good to go.  So, flesh out your .xib:
//   - Add controls
//   - Hook up Actions and Outlets in PreferencesDialogController.h as you build up your .xib
//   - Flesh-out the Actions defined in the header in PreferencesDialogController.m
//   - Add preference key #defines to LDrawKeys.h
//   - Make sure that your controls have sensible initial defaults set in
//     PreferencesDialogController.m/+(void)ensureDefaults
//
// File open dialogs:  Add code to e.g. a button action to open a file selection system
// dialog.  Search for 'folderChooser' for examples.  You'll also need to update
// Localizable.strings.  Accessory views can be added to the .xib to inform the user.  These
// need to be linked up as outlets.
//
//  Created by Allen Smith on 2/14/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "PreferencesDialogController.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawRegex.h>

#import <LDrawFeatures/LDrawGrid.h>
#import <LDrawFeatures/LDrawLSynthPanelModel.h>
#import <LDrawFeatures/LDrawPreferences.h>
#import <LDrawFeatures/LSynthConfiguration.h>

#import "LDrawApplication.h"
#import "LDrawHostChrome.h"
#import "LDrawView.h"				//for LDrawViewOrientation
#import "PartLibraryController.h"
#import "UserDefaultsCategory.h"
#import "WindowCategory.h"

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

@interface PreferencesDialogController ()

// General Tab
@property (nonatomic, weak) IBOutlet NSTextField*			gridSpacingFineField;
@property (nonatomic, weak) IBOutlet NSTextField*			gridSpacingMediumField;
@property (nonatomic, weak) IBOutlet NSTextField*			gridSpacingCoarseField;


@end


@implementation PreferencesDialogController

#define PREFERENCES_WINDOW_AUTOSAVE_NAME	@"PreferencesWindow"

//The shared preferences window. We need to store this reference here so that 
// we can simply bring the window to the front when it is already onscreen, 
// rather than accidentally creating a whole new one.
PreferencesDialogController *preferencesDialog = nil;


//========== awakeFromNib ======================================================
//
// Purpose:		Show the preferences window.
//
//==============================================================================
- (void) awakeFromNib
{
	//Grab the current window content from the Nib (it should be blank). 
	// We will display this while changing panes.
	blankContent = [preferencesWindow contentView];

	NSToolbar *tabToolbar = [[NSToolbar alloc] initWithIdentifier:@"Preferences"];
	[tabToolbar setDelegate:self];
	[preferencesWindow setToolbar:tabToolbar];
	
	//Restore the last-seen tab.
	NSUserDefaults	*userDefaults = [NSUserDefaults standardUserDefaults];
	NSString		*lastIdentifier = [userDefaults stringForKey:PREFERENCES_LAST_TAB_DISPLAYED];
	if(lastIdentifier == nil)
		lastIdentifier = PREFS_LDRAW_TAB_IDENTIFIER;
	[self selectPanelWithIdentifier:lastIdentifier];
	
	// After the window has been resized for the tab, *then* restore the size.
	[self->preferencesWindow setFrameUsingName:PREFERENCES_WINDOW_AUTOSAVE_NAME];
	
}//end awakeFromNib


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
// Purpose:		Make us an object. Load us our window.
//
//==============================================================================
- (id) init
{
	self = [super init];
	
	NSArray *nibObjects = nil;
	[[NSBundle mainBundle] loadNibNamed:@"Preferences" owner:self topLevelObjects:&nibObjects];
	topLevelObjects = nibObjects;
	
	return self;
	
}//end init


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
// Purpose:		Brings the window on screen.
//
//==============================================================================
- (void) setDialogValues
{
	//Make sure there are actually preferences to read before attempting to 
	// retrieve them.
	[PreferencesDialogController ensureDefaults];

	[self setGeneralTabValues];
	[self setStylesTabValues];
	[self setLDrawTabValues];
    [self setLSynthTabValues];
	
}//end setDialogValues


//========== setGeneralTabValues ===============================================
//
// Purpose:		Updates the data in the General tab to match what is on the 
//			    disk.  
//
//==============================================================================
- (void) setGeneralTabValues
{
	NSUserDefaults		*userDefaults		= [NSUserDefaults standardUserDefaults];
	
	//Grid Spacing.
	float gridFine		= [userDefaults floatForKey:GRID_SPACING_FINE];
	float gridMedium	= [userDefaults floatForKey:GRID_SPACING_MEDIUM];
	float gridCoarse	= [userDefaults floatForKey:GRID_SPACING_COARSE];
	[_gridSpacingFineField setFloatValue:gridFine];
	[_gridSpacingMediumField setFloatValue:gridMedium];
	[_gridSpacingCoarseField setFloatValue:gridCoarse];
	
	// Mouse Dragging
	LDrawMouseDragBehavior	mouseBehavior	= (LDrawMouseDragBehavior)[userDefaults integerForKey:MOUSE_DRAGGING_BEHAVIOR_KEY];
	[self->mouseDraggingRadioButtons selectCellWithTag:mouseBehavior];
	
	LDrawRightButtonBehavior	rbBehavior = (LDrawRightButtonBehavior)[userDefaults integerForKey:RIGHT_BUTTON_BEHAVIOR_KEY];
	[self->rightButtonRadioButtons selectCellWithTag:rbBehavior];
	
	LDrawRotateStyle			rBehavior = (LDrawRotateStyle)[userDefaults integerForKey:ROTATE_MODE_KEY];
	[self->rotateModeRadioButtons selectCellWithTag:rBehavior];
	
	LDrawMouseWheelBehavior	wBehavior = (LDrawMouseWheelBehavior)[userDefaults integerForKey:MOUSE_WHEEL_BEHAVIOR_KEY];
	[self->mouseWheelRadioButtons selectCellWithTag:wBehavior];
	
	
	
}//end setGeneralTabValues


//========== setStylesTabValues ================================================
//
// Purpose:		Updates the data in the Styles tab to match what is on the disk.
//
//==============================================================================
- (void) setStylesTabValues
{
	NSUserDefaults	*userDefaults		= [NSUserDefaults standardUserDefaults];
	
	// Get colors from preferences, with fallback defaults if unarchiving fails
	NSColor			*backgroundColor	= [userDefaults colorForKey:LDRAW_VIEWER_BACKGROUND_COLOR_KEY] ?: FallbackColorForPreferenceKey(LDRAW_VIEWER_BACKGROUND_COLOR_KEY);
	NSColor			*modelsColor		= [userDefaults colorForKey:SYNTAX_COLOR_MODELS_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_MODELS_KEY);
	NSColor			*stepsColor			= [userDefaults colorForKey:SYNTAX_COLOR_STEPS_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_STEPS_KEY);
	NSColor			*partsColor			= [userDefaults colorForKey:SYNTAX_COLOR_PARTS_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_PARTS_KEY);
	NSColor			*primitivesColor	= [userDefaults colorForKey:SYNTAX_COLOR_PRIMITIVES_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_PRIMITIVES_KEY);
	NSColor			*colorsColor		= [userDefaults colorForKey:SYNTAX_COLOR_COLORS_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_COLORS_KEY);
	NSColor			*commentsColor		= [userDefaults colorForKey:SYNTAX_COLOR_COMMENTS_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_COMMENTS_KEY);
	NSColor			*unknownColor		= [userDefaults colorForKey:SYNTAX_COLOR_UNKNOWN_KEY] ?: FallbackColorForPreferenceKey(SYNTAX_COLOR_UNKNOWN_KEY);
	
	[backgroundColorWell	setColor:backgroundColor];

	[modelsColorWell		setColor:modelsColor];
	[stepsColorWell			setColor:stepsColor];
	[partsColorWell			setColor:partsColor];
	[primitivesColorWell	setColor:primitivesColor];
	[commentsColorWell		setColor:commentsColor];
	[colorsColorWell		setColor:colorsColor];
	[unknownColorWell		setColor:unknownColor];

}//end setStylesTabValues


//========== setLDrawTabValues =================================================
//
// Purpose:		Updates the data in the LDraw tab to match what is on the disk.
//
//==============================================================================
- (void) setLDrawTabValues
{
	NSUserDefaults		*userDefaults		= [NSUserDefaults standardUserDefaults];
	NSString			*ldrawPath			= [userDefaults stringForKey:LDRAW_PATH_KEY];
	
	if(ldrawPath != nil){
		[LDrawPathTextField setStringValue:ldrawPath];
	}//end if we have a folder.
	//No folder selected yet.
	else
		[self chooseLDrawFolder:self];
	
}//end showPreferencesWindow

//========== setLDrawTabValues =================================================
//
// Purpose:		Updates the data in the LSynth tab to match what is on the disk.
//
//==============================================================================
- (void) setLSynthTabValues
{
    // Get preference values
    NSUserDefaults *userDefaults          = [NSUserDefaults standardUserDefaults];
    NSString       *executablePath        = [userDefaults stringForKey:LSYNTH_EXECUTABLE_PATH_KEY];
    NSString       *configurationPath     = [userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];
	NSInteger       selectionTransparency = [userDefaults integerForKey:LSYNTH_SELECTION_TRANSPARENCY_KEY]; // Stored as an int but interpreted as a percentage
    NSColor        *selectionColor        = [userDefaults colorForKey:LSYNTH_SELECTION_COLOR_KEY] ?: FallbackColorForPreferenceKey(LSYNTH_SELECTION_COLOR_KEY);
    BOOL            saveSynthesizedParts  = [userDefaults boolForKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];
    BOOL            showBasicPartsList    = [userDefaults boolForKey:LSYNTH_SHOW_BASIC_PARTS_LIST_KEY];
    LDrawLSynthSelectionMode selectionMode = (LDrawLSynthSelectionMode)[userDefaults integerForKey:LSYNTH_SELECTION_MODE_KEY];

    // Set control values
    [lsynthExecutablePath       setStringValue:executablePath];
    [lsynthConfigurationPath    setStringValue:configurationPath];
    [lsynthSelectionModeMatrix  selectCellWithTag:selectionMode];
    [lsynthSelectionColorWell   setColor:selectionColor];
    [lsynthTransparencySlider   setIntegerValue:selectionTransparency];
	[lsynthTransparencyText     setStringValue:[NSString stringWithFormat:@"%li", (long)selectionTransparency]];
    [lsynthSaveSynthesizedParts setState:saveSynthesizedParts];
    [lsynthShowBasicPartsList   setState:showBasicPartsList];
    
    LSynthSelectionControlEnablement enablement =
		[LDrawLSynthPanelModel selectionControlEnablementForMode:selectionMode];
    [lsynthTransparencySlider setEnabled:enablement.transparencyEnabled];
    [lsynthTransparencyText setEnabled:enablement.transparencyEnabled];
    [lsynthSelectionColorWell setEnabled:enablement.colorWellEnabled];
}

#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== changeTab: ========================================================
//
// Purpose:		Sent by the toolbar "tabs" to indicate the preferences pane 
//				should change.
//
//==============================================================================
- (void) changeTab:(id)sender
{	
	NSString	*itemIdentifier	= [sender itemIdentifier];
	
	[self selectPanelWithIdentifier:itemIdentifier];
	
}//end changeTab:


#pragma mark -
#pragma mark General Tab

//========== gridSpacingChanged: ===============================================
//
// Purpose:		User updated the amounts by which parts are shifted in different 
//				grid modes.
//
//==============================================================================
- (IBAction) gridSpacingChanged:(id)sender
{
	NSUserDefaults	*userDefaults		= [NSUserDefaults standardUserDefaults];

	//Grid Spacing.
	float gridFine		= [_gridSpacingFineField floatValue];
	float gridMedium	= [_gridSpacingMediumField floatValue];
	float gridCoarse	= [_gridSpacingCoarseField floatValue];
	
	[userDefaults setFloat:gridFine		forKey:GRID_SPACING_FINE];
	[userDefaults setFloat:gridMedium	forKey:GRID_SPACING_MEDIUM];
	[userDefaults setFloat:gridCoarse	forKey:GRID_SPACING_COARSE];

}//end gridSpacingChanged:


//========== mouseDraggingChanged: =============================================
//
// Purpose:		Mouse drag-and-drop behavior was changed.
//
//==============================================================================
- (IBAction) mouseDraggingChanged:(id)sender
{
	NSUserDefaults		   *userDefaults	= [NSUserDefaults standardUserDefaults];
	LDrawMouseDragBehavior mouseBehavior	= (LDrawMouseDragBehavior)[self->mouseDraggingRadioButtons selectedTag];
	
	[userDefaults setInteger:mouseBehavior
					  forKey:MOUSE_DRAGGING_BEHAVIOR_KEY];
	
}//end mouseDraggingChanged:

//========== rightButtonChanged: ===============================================
//
// Purpose:		Right-button behavior in the 3D view was changed.
//
//==============================================================================
- (IBAction) rightButtonChanged:(id)sender
{
	NSUserDefaults			 *userDefaults	= [NSUserDefaults standardUserDefaults];
	LDrawRightButtonBehavior rbBehavior 	= (LDrawRightButtonBehavior)[self->rightButtonRadioButtons selectedTag];
	[userDefaults setInteger:rbBehavior
					  forKey:RIGHT_BUTTON_BEHAVIOR_KEY];
}

//========== rotateModeChanged: ================================================
//
// Purpose:		Rotation mode (trackball vs turntable) was changed.
//
//==============================================================================
- (IBAction) rotateModeChanged:(id)sender
{
	NSUserDefaults		*userDefaults	= [NSUserDefaults standardUserDefaults];
	LDrawRotateStyle	rBehavior 		= (LDrawRotateStyle)[self->rotateModeRadioButtons selectedTag];
	[userDefaults setInteger:rBehavior
					  forKey:ROTATE_MODE_KEY];
}

//========== mouseWheelChanged: ================================================
//
// Purpose:		Mouse-wheel behavior (scroll vs zoom) was changed.
//
//==============================================================================
- (IBAction) mouseWheelChanged:(id)sender
{
	NSUserDefaults			*userDefaults	= [NSUserDefaults standardUserDefaults];
	LDrawMouseWheelBehavior wBehavior		= (LDrawMouseWheelBehavior)[self->mouseWheelRadioButtons selectedTag];
	[userDefaults setInteger:wBehavior
					  forKey:MOUSE_WHEEL_BEHAVIOR_KEY];
}

#pragma mark -
#pragma mark Parts Tab

//========== chooseLDrawFolder =================================================
//
// Purpose:		Present a folder choose dialog to find the LDraw folder.
//
//==============================================================================
- (IBAction)chooseLDrawFolder:(id)sender
{
	//Create a standard "Choose" dialog.
	NSOpenPanel *folderChooser = [NSOpenPanel openPanel];
	[folderChooser setCanChooseFiles:NO];
	[folderChooser setCanChooseDirectories:YES];
	
	//Tell the poor user what this dialog does!
	[folderChooser setTitle:NSLocalizedString([LDrawHostChrome chooseLDrawFolderTitleKey], nil)];
	[folderChooser setMessage:NSLocalizedString([LDrawHostChrome ldrawFolderChooserMessageKey], nil)];
	[folderChooser setAccessoryView:folderChooserAccessoryView];
	[folderChooser setPrompt:NSLocalizedString([LDrawHostChrome choosePromptKey], nil)];
	
	//Run the dialog.
	if([folderChooser runModal] == NSModalResponseOK)
	{
		// Get the folder selected.
		NSURL	*folderURL	= [[folderChooser URLs] objectAtIndex:0];
		
		if([folderURL isFileURL])
			[self changeLDrawFolderPath:[folderURL path]];
		else
			NSBeep(); // sanity check
	}
	
}//end chooseLDrawFolder:


//========== pathTextFieldChanged: =============================================
//
// Purpose:		The user has gone all geek on us and manually typed in a new 
//				LDraw folder path.
//
//==============================================================================
- (IBAction) pathTextFieldChanged:(id)sender
{
	NSString *newPath = [LDrawPathTextField stringValue];
	
	[self changeLDrawFolderPath:newPath];
	
}//end pathTextFieldChanged:


//========== reloadParts: ======================================================
//
// Purpose:		Scans the contents of the LDraw/Parts folder and produces a 
//				Mac-friendly index of parts.
//
//				Is it fast? No. Is it easy to code? Yes.
//
//==============================================================================
- (IBAction) reloadParts:(id)sender
{
	PartLibraryController   *libraryController	= [LDrawApplication sharedPartLibraryController];
	
	[libraryController reloadPartCatalog:^(BOOL success) {}];
	
}//end reloadParts:


#pragma mark -
#pragma mark Styles Tab

//========== backgroundColorWellChanged: =======================================
//
// Purpose:		The color for the LDraw views' background has been changed. 
//				Update the value in the preferences.
//
//==============================================================================
- (IBAction) backgroundColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:LDRAW_VIEWER_BACKGROUND_COLOR_KEY];
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawViewBackgroundColorDidChangeNotification
						  object:newColor ];
						  
}//end backgroundColorWellChanged:


//========== modelsColorWellChanged: ===========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) modelsColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_MODELS_KEY];
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
						  
}//end modelsColorWellChanged:


//========== stepsColorWellChanged: ============================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) stepsColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_STEPS_KEY];
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
						  
}//end stepsColorWellChanged:


//========== partsColorWellChanged: ============================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) partsColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_PARTS_KEY];

	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
						  
}//end partsColorWellChanged:


//========== primitivesColorWellChanged: =======================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) primitivesColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_PRIMITIVES_KEY];
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
						  
}//end primitivesColorWellChanged:


//========== colorsColorWellChanged: ===========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) colorsColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_COLORS_KEY];
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
	
}//end colorsColorWellChanged:


//========== commentsColorWellChanged: =========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) commentsColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_COMMENTS_KEY];
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
						  
}//end commentsColorWellChanged:


//========== unknownColorWellChanged: ==========================================
//
// Purpose:		This syntax-color well changed. Update the value in preferences.
//
//==============================================================================
- (IBAction) unknownColorWellChanged:(NSColorWell *)sender
{
	NSColor			*newColor		= [sender color];
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	
	[userDefaults setColor:newColor forKey:SYNTAX_COLOR_UNKNOWN_KEY];
	
	[[NSNotificationCenter defaultCenter]
			postNotificationName:LDrawSyntaxColorsDidChangeNotification
						  object:NSApp ];
						  
}//end unknownColorWellChanged:

#pragma mark -
#pragma mark LSynth Tab

//========== lsynthChooseExecutable: ==========================================
//
// Purpose:		The user wishes to choose their own LSynth executable.
//
//==============================================================================
- (IBAction)lsynthChooseExecutable:(id)sender
{
    //Create a standard "Choose" dialog.
    NSOpenPanel *lsynthExecutableChooser = [NSOpenPanel openPanel];
    [lsynthExecutableChooser setCanChooseFiles:YES];
    [lsynthExecutableChooser setCanChooseDirectories:NO];

    //Tell the poor user what this dialog does!
    [lsynthExecutableChooser setTitle:NSLocalizedString([LDrawHostChrome chooseLSynthExecutableTitleKey], nil)];
    [lsynthExecutableChooser setMessage:NSLocalizedString([LDrawHostChrome lsynthExecutableChooserMessageKey], nil)];
    [lsynthExecutableChooser setAccessoryView:lsynthExecutableChooserAccessoryView];
    [lsynthExecutableChooser setPrompt:NSLocalizedString([LDrawHostChrome choosePromptKey], nil)];

    //Run the dialog.
    if([lsynthExecutableChooser runModal] == NSModalResponseOK)
    {
        // Get the file selected.
        NSURL	*lsynthExecutableURL = [[lsynthExecutableChooser URLs] objectAtIndex:0];

        // TODO: validation?
        if([lsynthExecutableURL isFileURL]) {
            [lsynthExecutablePath setStringValue:[lsynthExecutableURL path]];
            NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
            [userDefaults setObject:[lsynthExecutableURL path] forKey:LSYNTH_EXECUTABLE_PATH_KEY];
        }
        else
            NSBeep(); // sanity check
    }
} // end lsynthChooseExecutable:

//========== lsynthChooseConfiguration: ==========================================
//
// Purpose:		The user wishes to choose their own LSynth configuration file.
//
//==============================================================================
- (IBAction)lsynthChooseConfiguration:(id)sender
{
    NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
    NSString *currentConfiguration  = [userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];
    
    //Create a standard "Choose" dialog.
    NSOpenPanel *lsynthConfigurationChooser = [NSOpenPanel openPanel];
    [lsynthConfigurationChooser setCanChooseFiles:YES];
    [lsynthConfigurationChooser setCanChooseDirectories:NO];
    
    //Tell the poor user what this dialog does!
    [lsynthConfigurationChooser setTitle:NSLocalizedString([LDrawHostChrome chooseLSynthConfigurationTitleKey], nil)];
    [lsynthConfigurationChooser setMessage:NSLocalizedString([LDrawHostChrome lsynthConfigurationChooserMessageKey], nil)];
    [lsynthConfigurationChooser setAccessoryView:lsynthConfigurationChooserAccessoryView];
    [lsynthConfigurationChooser setPrompt:NSLocalizedString([LDrawHostChrome choosePromptKey], nil)];
    
    //Run the dialog.
    if([lsynthConfigurationChooser runModal] == NSModalResponseOK)
    {
        // Get the file selected.
        NSURL	*lsynthConfigurationURL = [[lsynthConfigurationChooser URLs] objectAtIndex:0];
        
        // TODO: validation?
        if([lsynthConfigurationURL isFileURL]) {
            [lsynthConfigurationPath setStringValue:[lsynthConfigurationURL path]];
            [userDefaults setObject:[lsynthConfigurationURL path] forKey:LSYNTH_CONFIGURATION_PATH_KEY];

            // reload config if changed
            if ([currentConfiguration isEqualToString:[lsynthConfigurationURL path]]) {
                [[LSynthConfiguration sharedInstance] parseLsynthConfig:[lsynthConfigurationURL path]];
            }
        }
        else
            NSBeep(); // sanity check
    }
} // end lsynthChooseConfiguration:

//========== lsynthTransparencySliderChanged: ==================================
//
// Purpose:		The user has changed the LSynth selection transparency
//
//==============================================================================
- (IBAction)lsynthTransparencySliderChanged:(id)sender
{
    NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:[sender integerValue] forKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
    [lsynthTransparencyText setIntegerValue:[sender integerValue]];
    [self lsynthRequiresRedisplay];
} // end lsynthTransparencySliderChanged:

//========== lsynthTransparencyTextChanged: ====================================
//
// Purpose:		The user has changed the LSynth selection transparency
//
//==============================================================================
- (IBAction)lsynthTransparencyTextChanged:(id)sender
{
    NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:[sender integerValue] forKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
    [lsynthTransparencySlider setIntegerValue:[sender integerValue]];
    [self lsynthRequiresRedisplay];
} // end lsynthTransparencyTextChanged:

//========== lsynthSelectionColorWellClicked: ==================================
//
// Purpose:		The user has changed the LSynth selection color
//
//==============================================================================
- (IBAction)lsynthSelectionColorWellClicked:(NSColorWell *)sender
{
    NSColor			*newColor		= [sender color];
    NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];

    [userDefaults setColor:newColor forKey:LSYNTH_SELECTION_COLOR_KEY];

    // Mirror into the Foundation-only RGBA key so LDrawCore can read the
    // current selection color without depending on NSColor.
    NSColor *rgba = [newColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: newColor;
    [userDefaults setObject:@[ @([rgba redComponent]),
                               @([rgba greenComponent]),
                               @([rgba blueComponent]),
                               @([rgba alphaComponent]) ]
                     forKey:LSYNTH_SELECTION_COLOR_RGBA_KEY];
    [self lsynthRequiresRedisplay];
} // end lsynthSelectionColorWellClicked:

//========== lsynthSelectionModeChanged: =======================================
//
// Purpose:		User has chosen between transparency, color or both
//
//==============================================================================
- (IBAction)lsynthSelectionModeChanged:(id)sender
{
    NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];

    [userDefaults setInteger:[[sender selectedCell] tag] forKey:LSYNTH_SELECTION_MODE_KEY];

    [self setLSynthTabValues];
    [self lsynthRequiresRedisplay];
} // end lsynthSelectionModeChanged:

//========== lsynthSaveSynthesizedPartsChanged: ================================
//
// Purpose:		User has toggled the 'Save synthesized parts' checkbox
//
//==============================================================================
- (IBAction)lsynthSaveSynthesizedPartsChanged:(id)sender {
    NSUserDefaults	*userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:[lsynthSaveSynthesizedParts state] forKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];
} // end lsynthSaveSynthesizedPartsChanged:

//========== lsynthShowBasicPartsListChanged: ==================================
//
// Purpose:		User has toggled the 'Show simple parts list' checkbox
//
//==============================================================================
- (IBAction)lsynthShowBasicPartsListChanged:(id)sender
{
    NSUserDefaults	*userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:[lsynthShowBasicPartsList state] forKey:LSYNTH_SHOW_BASIC_PARTS_LIST_KEY];

    // Regenerate LSynth part menus
    [[LDrawApplication shared] populateLSynthModelMenus];
} // end lsynthShowBasicPartsListChanged:

//========== lsynthRequiresRedisplay ===========================================
//
// Purpose:		Convenience method to notify LSynth parts that they may need
//              redisplay if the selection highlighting has changed, or executable
//              or config files have changed.
//
//==============================================================================
- (void) lsynthRequiresRedisplay
{
    [[NSNotificationCenter defaultCenter]
            postNotificationName:LSynthSelectionDisplayDidChangeNotification
                          object:NSApp ];
} // end lsynthRequiresRedisplay

//========== lsynthRequiresResynthesis =========================================
//
// Purpose:		Convenience method to notify LSynth parts that they need to
//              resyntheisze if the  executable or config files have changed.
//
//==============================================================================
- (void) lsynthRequiresResynthesis
{
    [[NSNotificationCenter defaultCenter]
            postNotificationName:LSynthResynthesisRequiredNotification
                          object:NSApp ];
} // end lsynthRequiresResynthesis

#pragma mark -
#pragma mark TOOLBAR DELEGATE
#pragma mark -

//**** NSToolbar ****
//========== toolbarAllowedItemIdentifiers: ====================================
//
// Purpose:		The tabs allowed in the preferences window.
//
//==============================================================================
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [NSArray arrayWithObjects:
						PREFS_GENERAL_TAB_IDENTIFIER,
						PREFS_LDRAW_TAB_IDENTIFIER,
						PREFS_STYLE_TAB_IDENTIFIER,
                        PREFS_LSYNTH_TAB_IDENTIFIER,
						nil ];
}//end toolbarAllowedItemIdentifiers:


//**** NSToolbar ****
//========== toolbarDefaultItemIdentifiers: ====================================
//
// Purpose:		The tabs shown by default in the preferences window.
//
//==============================================================================
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarAllowedItemIdentifiers:toolbar];
	
}//end toolbarDefaultItemIdentifiers:


//**** NSToolbar ****
//========== toolbarSelectableItemIdentifiers: =================================
//
// Purpose:		The tabs selectable in the preferences window.
//
//==============================================================================
- (NSArray *) toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarAllowedItemIdentifiers:toolbar];
	
}//end toolbarSelectableItemIdentifiers:


//**** NSToolbar ****
//========== toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: ==========
//
// Purpose:		Creates the "tabs" used in the preferences window.
//
//==============================================================================
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	 itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *newItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	
	[newItem setLabel:NSLocalizedString(itemIdentifier, nil)];
	
	if([itemIdentifier isEqualToString:PREFS_GENERAL_TAB_IDENTIFIER])
		[newItem setImage:[NSImage imageNamed:NSImageNamePreferencesGeneral]];
	
	else if([itemIdentifier isEqualToString:PREFS_LDRAW_TAB_IDENTIFIER])
		[newItem setImage:[NSImage imageNamed:@"LDrawLogo"]];
	
	else if([itemIdentifier isEqualToString:PREFS_STYLE_TAB_IDENTIFIER])
		[newItem setImage:[NSImage imageNamed:@"SyntaxColoring"]];
    
    else if([itemIdentifier isEqualToString:PREFS_LSYNTH_TAB_IDENTIFIER])
		[newItem setImage:[NSImage imageNamed:@"LSynthIcon"]];
	
	[newItem setTarget:self];
	[newItem setAction:@selector(changeTab:)];
	
	return newItem;
	
}//end toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:


#pragma mark -
#pragma mark WINDOW DELEGATE
#pragma mark -

//**** NSWindow ****
//========== windowShouldClose: ================================================
//
// Purpose:		Used to release the preferences controller.
//
//==============================================================================
- (BOOL) windowShouldClose:(id)sender
{
	//Save out the last tab view.
	NSUserDefaults	*userDefaults = [NSUserDefaults standardUserDefaults];
	NSString		*lastIdentifier = [[preferencesWindow toolbar] selectedItemIdentifier];
	
	[userDefaults setObject:lastIdentifier
					 forKey:PREFERENCES_LAST_TAB_DISPLAYED];
	
	// Cocoa autosaving doesn't necessarily get restored when we need it to, so 
	// we have to track in manually.  
	[self->preferencesWindow saveFrameUsingName:PREFERENCES_WINDOW_AUTOSAVE_NAME];
	
	return YES;
	
}//end windowShouldClose:


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


//========== changeLDrawFolderPath: ============================================
//
// Purpose:		A new folder path has been chose as the LDraw folder. We need to 
//				check it out and reload the parts from it.
//
//==============================================================================
- (void) changeLDrawFolderPath:(NSString *) folderPath
{
	PartLibraryController   *libraryController  = [LDrawApplication sharedPartLibraryController];
	NSUserDefaults          *userDefaults       = [NSUserDefaults standardUserDefaults];
	
	[LDrawPathTextField setStringValue:folderPath];
	
	// Record this new folder in preferences whether it's right or not. We'll 
	// let them sink their own ship here. 
	[userDefaults setObject:folderPath forKey:LDRAW_PATH_KEY];
	[[LDrawPaths sharedPaths] setPreferredLDrawPath:folderPath];
	
	if([libraryController validateLDrawFolderWithMessage:folderPath] == YES)
	{
		[self reloadParts:self];
	}
	//else we displayed an error message already.
	
}//end changeLDrawFolderPath:


//========== selectPanelWithIdentifier: ========================================
//
// Purpose:		Changes the the preferences dialog to display the panel/tab 
//				represented by itemIdentifier.
//
//==============================================================================
- (void) selectPanelWithIdentifier:(NSString *)itemIdentifier
{
	NSView		*newContentView	= nil;
	NSRect		 newFrameRect	= NSZeroRect;
	
	//Make sure the corresponding toolbar tab is selected too.
	[[preferencesWindow toolbar] setSelectedItemIdentifier:itemIdentifier];
	
	if([itemIdentifier isEqualToString:PREFS_GENERAL_TAB_IDENTIFIER])
		newContentView = self->generalTabContentView;
	
	else if([itemIdentifier isEqualToString:PREFS_LDRAW_TAB_IDENTIFIER])
		newContentView = ldrawContentView;
	
	else if([itemIdentifier isEqualToString:PREFS_STYLE_TAB_IDENTIFIER])
		newContentView = stylesContentView;

    else if([itemIdentifier isEqualToString:PREFS_LSYNTH_TAB_IDENTIFIER])
		newContentView = lsynthContentView;
    
	//need content rect in screen coordinates
	//Need find window frame with new content view.
	newFrameRect = [preferencesWindow frameRectForContentSize:[newContentView frame].size];
	
	//Do a smooth transition to the new panel.
	[preferencesWindow setContentView:blankContent]; //so we don't see artifacts during resize.
	[preferencesWindow setFrame:newFrameRect
						display:YES
						animate:YES ];
	[preferencesWindow setContentView:newContentView];
	
}//end selectPanelWithIdentifier

#pragma mark -
#pragma mark <NSTextFieldDelegate>
#pragma mark -

//========== controlTextDidEndEditing: =========================================
//
// Purpose:		The user finished editing a text field.  Used specifically by
//              the LSynth pane to validate and resynthesize in a timely fashion.
//
//==============================================================================
- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    NSTextField *textField          = [aNotification object];
    NSUserDefaults *userDefaults    = [NSUserDefaults standardUserDefaults];
    NSString *currentExecutable     = [userDefaults stringForKey:LSYNTH_EXECUTABLE_PATH_KEY];
    NSString *currentConfiguration  = [userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];

    // The user manually changed the LSynth executable path
    // TODO: run validating synthesis
    if (textField == lsynthExecutablePath) {
        NSURL *executablePathAsURL = [NSURL fileURLWithPath:[lsynthExecutablePath stringValue]];
        if([executablePathAsURL isFileURL] && ![currentExecutable isEqualToString:[executablePathAsURL path]]) {
            [userDefaults setObject:[executablePathAsURL path] forKey:LSYNTH_EXECUTABLE_PATH_KEY];
            [self lsynthRequiresResynthesis];
        }

        // No path - it's been deleted
        else if (([[executablePathAsURL path] length] == 0 || [[executablePathAsURL path] isMatchedByRegex:@"^\\s+$"])
                && executablePathAsURL
                && ![currentExecutable isEqualToString:[executablePathAsURL path]]) {
            [userDefaults setObject:@"" forKey:LSYNTH_EXECUTABLE_PATH_KEY];
            [self lsynthRequiresResynthesis];
        }

        else if (executablePathAsURL) {
            NSBeep(); // sanity check
        }
    }

    // The user manually changed the LSynth config path
    // TODO: run validating synthesis
    else if (textField == lsynthConfigurationPath) {
        NSURL *configPathAsURL = [NSURL fileURLWithPath:[lsynthConfigurationPath stringValue]];
        if([configPathAsURL isFileURL]) {
            [userDefaults setObject:[configPathAsURL path] forKey:LSYNTH_CONFIGURATION_PATH_KEY];
            
            // reload config if changed
            if (![currentConfiguration isEqualToString:[configPathAsURL path]])
			{
                [[LSynthConfiguration sharedInstance] parseLsynthConfig:[configPathAsURL path]];
                [[LDrawApplication shared] populateLSynthModelMenus];
                [self lsynthRequiresResynthesis];
            }
        }

        // No path - it's been deleted
        else if (!configPathAsURL || [[configPathAsURL path] length] == 0)
		{
            [userDefaults setObject:@"" forKey:LSYNTH_CONFIGURATION_PATH_KEY];
            [[LSynthConfiguration sharedInstance] parseLsynthConfig:[LDrawLSynthPanelModel configPathInBundle:[NSBundle mainBundle]]];
            [[LDrawApplication shared] populateLSynthModelMenus];
            [self lsynthRequiresResynthesis];
        }
        
        else {
            NSBeep(); // sanity check
        }
    }


    
    
    
    
//    NSView *nextKeyView = [textField nextKeyView];
//    NSUInteger whyEnd = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] unsignedIntValue];
//    BOOL returnKeyPressed = (whyEnd == NSReturnTextMovement);
//    BOOL tabOrBacktabToSelf = ((whyEnd == NSTabTextMovement || whyEnd == NSBacktabTextMovement) && (nextKeyView == nil || nextKeyView == textField));
//    if (returnKeyPressed || tabOrBacktabToSelf)
//        NSLog(@"focus stays");
//    else
//        NSLog(@"focus leaves");
}

#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		It's time to get fitted for a halo.
//
//==============================================================================
- (void) dealloc
{
	CFRelease((__bridge CFTypeRef)(preferencesDialog));
	topLevelObjects = nil;
	
	//clear out our global preferences controller. 
	// It will be reinitialized when needed.
	preferencesDialog = nil;
	
}//end dealloc

@end
