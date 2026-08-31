//==============================================================================
//
//  File:       LDrawKeys.h
//  Package:    LDrawCore
//
//  Purpose:    Keys, enumerations, and notifications shared by LDrawCore,
//              LDrawRenderCore, and LDrawEditing.
//
//  Info:       Host chrome (minifigure, donation, part browser, tool
//              palette, viewport layout) lives in LDrawFeatures/LDrawHostKeys.h.
//              Pasteboard type names live in LDrawEditing/LDrawPasteboard.h.
//              Grid spacing/rotation constants live in LDrawFeatures/LDrawGrid.h.
//
//  Modified:   2/14/05 Allen Smith.
//
//==============================================================================

////////////////////////////////////////////////////////////////////////////////
//
#pragma mark		Preferences Keys
//
////////////////////////////////////////////////////////////////////////////////

#define COLUMNIZE_OUTPUT_KEY						@"ColumnizeOutput"
#define LDRAW_PATH_KEY								@"LDraw Path"
#define MOUSE_DRAGGING_BEHAVIOR_KEY					@"Mouse Dragging Behavior"
#define RIGHT_BUTTON_BEHAVIOR_KEY					@"Right Button Behavior"
#define ROTATE_MODE_KEY								@"Rotate Mode"
#define MOUSE_WHEEL_BEHAVIOR_KEY					@"Mouse Wheel Behavior"
#define SYNTAX_COLOR_COLORS_KEY						@"Syntax Color Colors"
#define SYNTAX_COLOR_COMMENTS_KEY					@"Syntax Color Comments"
#define SYNTAX_COLOR_MODELS_KEY						@"Syntax Color Models"
#define SYNTAX_COLOR_PARTS_KEY						@"Syntax Color Parts"
#define SYNTAX_COLOR_PRIMITIVES_KEY					@"Syntax Color Primitives"
#define SYNTAX_COLOR_STEPS_KEY						@"Syntax Color Steps"
#define SYNTAX_COLOR_REMOVE_GROUP_KEY				@"Syntax Color Remove Group"
#define SYNTAX_COLOR_UNKNOWN_KEY					@"Syntax Color Unknown"

// LSynth — keys LDrawCore reads from NSUserDefaults (and LDrawFeatures seeds).
#define LSYNTH_EXECUTABLE_PATH_KEY                  @"LSynth Executable Path"
#define LSYNTH_CONFIGURATION_PATH_KEY               @"LSynth Configuration Path"
#define LSYNTH_SELECTION_TRANSPARENCY_KEY           @"LSynth Selection Transparency"
// Foundation-only mirror of the AppKit LSYNTH_SELECTION_COLOR_KEY storing an
// NSArray of four NSNumber floats in 0..1 RGBA order. LDrawCore reads this;
// the AppKit preferences pane in BricksmithMac keeps both in sync.
#define LSYNTH_SELECTION_COLOR_RGBA_KEY             @"LSynth Selection Color RGBA"
#define LSYNTH_SELECTION_MODE_KEY                   @"LSynth Selection Mode"
#define LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY           @"LSynth Save Synthesized Parts"


////////////////////////////////////////////////////////////////////////////////
//
#pragma mark		Notifications
//
////////////////////////////////////////////////////////////////////////////////

//The color which will be assigned to new parts has changed.
// Object is the new LDrawColorT, as an NSNumber. No userInfo.
#define LDrawColorDidChangeNotification					@"LDrawColorDidChangeNotification"

//the keys on the keyboard which were depressed just changed.
// Object is an NSEvent: keyUp, keyDown, or flagsChanged.
#define LDrawKeyboardDidChangeNotification				@"LDrawKeyboardDidChangeNotification"

//tool mode changed.
// Object is an NSNumber containing the new LDrawToolMode.
#define LDrawMouseToolDidChangeNotification				@"LDrawMouseToolDidChangeNotification"

//tablet pointing device changed.
// Object is an NSEvent: NSTabletProximity.
#define LDrawPointingDeviceDidChangeNotification		@"LDrawPointingDeviceDidChangeNotification"

//Syntax coloring changed in preferences.
// Object is the application. No userInfo.
#define LDrawSyntaxColorsDidChangeNotification			@"LDrawSyntaxColorsDidChangeNotification"

//Syntax coloring changed in preferences.
// Object is the new color. No userInfo.
#define LDrawViewBackgroundColorDidChangeNotification	@"LDrawViewBackgroundColorDidChangeNotification"

//A model was added to a document.  Note that the object
// for this notification is the LDrawFile that was edited!
#define LDrawMPDSubModelAdded							@"LDrawMPDSubModelAdded"

//The library was reloaded.  Documents need to tell their parts
// to re-resolve their references.
#define LDrawPartLibraryReloaded						@"LDrawPartLibraryReloaded"

// The LSynth selection appearance changed.  Selected LSynth
// parts need to update to reflect this
#define LSynthSelectionDisplayDidChangeNotification    @"LSynthSelectionDisplayDidChangeNotification"

// The LSynth parts need to resynthesize for some reason - maybe config or exe changes
#define LSynthResynthesisRequiredNotification          @"LSynthResynthesisRequiredNotification"

////////////////////////////////////////////////////////////////////////////////
//
#pragma mark		Menu Tags
//
// Tags to look up menus with.
//
////////////////////////////////////////////////////////////////////////////////

typedef NS_ENUM(NSInteger, LDrawMenuTag)
{
	// Application Menu
	LDrawApplicationMenuTag				= 0,

	// File Menu
	LDrawFileMenuTag					= 1,
    LDrawRevealInFinderTag				= 101,

	// Edit Menu
	LDrawEditMenuTag					= 2,
	LDrawCutMenuTag						= 202,
	LDrawCopyMenuTag					= 203,
	LDrawPasteMenuTag					= 204,
	LDrawDeleteMenuTag					= 205,
	LDrawSelectAllMenuTag				= 206,
	LDrawDuplicateMenuTag				= 207,
	LDrawSplitStepMenuTag				= 208,
	LDrawChangeOriginMenuTag			= 209,
	LDrawSplitModelMenuTag				= 210,
	LDrawRotatePositiveXTag				= 220,
	LDrawRotateNegativeXTag				= 221,
	LDrawRotatePositiveYTag				= 222,
	LDrawRotateNegativeYTag				= 223,
	LDrawRotatePositiveZTag				= 224,
	LDrawRotateNegativeZTag				= 225,
	LDrawChangeOriginByRotationMenuTag	= 226,
	LDrawAxesByPartRotationMenuTag		= 227,
	LDrawMoveToParentMenuTag			= 228,

	// Tools Menu
	LDrawToolsMenuTag					= 3,
	LDrawFileContentsMenuTag			= 302,
	LDrawShowMouseToolsMenuTag			= 303,
	LDrawHideMouseToolsMenuTag			= 304,
	LDrawGridFineMenuTag				= 305,
	LDrawGridMediumMenuTag				= 306,
	LDrawGridCoarseMenuTag				= 307,
	LDrawCoordModelMenuTag				= 308,
	LDrawCoordPartMenuTag				= 309,	

	// Views Menu
	LDrawViewsMenuTag					= 4,
	LDrawStepDisplayMenuTag				= 404,
	LDrawNextStepMenuTag				= 405,
	LDrawPreviousStepMenuTag			= 406,
	LDrawOrientationMenuTag				= 407,
	LDrawUseSelectionForSpinCenterMenuTag = 408,
	LDrawResetSpinCenterMenuTag			= 409,

	// Piece Menu
	LDrawPieceMenuTag					= 5,
	LDrawHidePieceMenuTag				= 501,
	LDrawShowPieceMenuTag				= 502,
	LDrawSnapToGridMenuTag				= 503,
	LDrawGotoModelMenuTag				= 504,
	LDrawSetGroupMenuTag				= 510,

	// Models Menu
	LDrawModelsMenuTag					= 6,
	LDrawAddModelMenuTag				= 601,
	LDrawModelsSeparatorMenuTag			= 602,
	LDrawInsertReferenceMenuTag			= 603,
	LDrawSubmodelReferenceMenuTag		= 604, //used for all items in the Insert Reference menu.
	LDrawRawCommandMenuTag				= 605,
	LDrawAddModelSelectionMenuTag		= 606,
	LDrawRelatedPartMenuTag				= 610, //used to add related parts dynamically.

    LDrawLSynthMenuTag					= 630,
    LDrawLSynthPartMenuTag				= 631, // LSynth parts
    LDrawLSynthHoseMenuTag				= 632, // LSynth synthesizable part: hose
    LDrawLSynthHoseConstraintMenuTag	= 633, // LSynth constraint items: hose
	LDrawLSynthBandMenuTag				= 634, // LSynth synthesizable part: band
	LDrawLSynthBandConstraintMenuTag	= 635, // LSynth constraint items: band
	LDrawLSynthInsideOutsideMenuTag		= 636,
    LDrawLSynthSurroundInsideOutsideTag	= 637,
    LDrawLSynthInvertInsideOutsideTag	= 638,
    LDrawLSynthInsertInsideTag			= 639,
    LDrawLSynthInsertOutsideTag			= 640,
    LDrawLSynthInsertCrossTag			= 641,

	// Window Menu
	LDrawWindowMenuTag					= 7,

	// Contextual Menus
	LDrawPartBrowserAddFavoriteTag		= 4001,
	LDrawPartBrowserRemoveFavoriteTag	= 4002

};


////////////////////////////////////////////////////////////////////////////////
//
#pragma mark		Shared Datatypes
//
// Data types which would otherwise be homeless. LDrawSelectionMode is on
// LDrawRenderer's delegate (RenderCore cannot depend on Editing). LDrawRotateStyle
// is read by LDrawCamera. Mouse-drag enums are read by LDrawViewPolicy.
//
////////////////////////////////////////////////////////////////////////////////

typedef NS_ENUM(NSInteger, LDrawMouseDragBehavior)
{
	LDrawMouseDraggingOff									= 0,
	LDrawMouseDraggingBeginImmediately						= 1,
	LDrawMouseDraggingBeginAfterDelay						= 2,
	LDrawMouseDraggingImmediatelyInOrthoNeverInPerspective	= 3
};

typedef NS_ENUM(NSInteger, LDrawRightButtonBehavior)
{
	LDrawRightButtonContextual								= 0,
	LDrawRightButtonRotates									= 1
};

typedef NS_ENUM(NSInteger, LDrawRotateStyle) {
	LDrawRotateStyleTrackball								= 0,
	LDrawRotateStyleTurntable								= 1
};

typedef NS_ENUM(NSInteger, LDrawMouseWheelBehavior) {
	LDrawMouseWheelScrolls									= 0,
	LDrawMouseWheelZooms									= 1
};

typedef NS_ENUM(NSInteger, LDrawSelectionMode) {
	LDrawSelectionReplace		= 0,	// Normal drag - take new
	LDrawSelectionExtend		= 1,	// Shift drag - take old | new
	LDrawSelectionSubtract		= 2,	// Option drag - take old - new
	LDrawSelectionIntersection	= 3		// Option-shift drag - take old & new
};
