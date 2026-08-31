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
// Object is an NSNumber containing the new ToolModeT.
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

typedef enum MenuTags
{
	// Application Menu
	applicationMenuTag				= 0,

	// File Menu
	fileMenuTag						= 1,
    revealInFinderTag               = 101,

	// Edit Menu
	editMenuTag						= 2,
	cutMenuTag						= 202,
	copyMenuTag						= 203,
	pasteMenuTag					= 204,
	deleteMenuTag					= 205,
	selectAllMenuTag				= 206,
	duplicateMenuTag				= 207,
	splitStepMenuTag				= 208,
	changeOriginMenuTag				= 209,
	splitModelMenuTag				= 210,
	rotatePositiveXTag				= 220,
	rotateNegativeXTag				= 221,
	rotatePositiveYTag				= 222,
	rotateNegativeYTag				= 223,
	rotatePositiveZTag				= 224,
	rotateNegativeZTag				= 225,
	changeOriginByRotationMenuTag	= 226,
	axesByPartRotationMenuTag		= 227,
	moveToParentMenuTag				= 228,

	// Tools Menu
	toolsMenuTag					= 3,
	fileContentsMenuTag				= 302,
	showMouseToolsMenuTag			= 303,
	hideMouseToolsMenuTag			= 304,
	gridFineMenuTag					= 305,
	gridMediumMenuTag				= 306,
	gridCoarseMenuTag				= 307,
	coordModelMenuTag				= 308,
	coordPartMenuTag				= 309,	

	// Views Menu
	viewsMenuTag					= 4,
	stepDisplayMenuTag				= 404,
	nextStepMenuTag					= 405,
	previousStepMenuTag				= 406,
	orientationMenuTag				= 407,
	useSelectionForSpinCenterMenuTag= 408,
	resetSpinCenterMenuTag			= 409,

	// Piece Menu
	pieceMenuTag					= 5,
	hidePieceMenuTag				= 501,
	showPieceMenuTag				= 502,
	snapToGridMenuTag				= 503,
	gotoModelMenuTag				= 504,
	setGroupMenuTag					= 510,

	// Models Menu
	modelsMenuTag					= 6,
	addModelMenuTag					= 601,
	modelsSeparatorMenuTag			= 602,
	insertReferenceMenuTag			= 603,
	submodelReferenceMenuTag		= 604, //used for all items in the Insert Reference menu.
	rawCommandMenuTag               = 605,
	addModelSelectionMenuTag		= 606,
	relatedPartMenuTag				= 610, //used to add related parts dynamically.

    lsynthMenuTag                   = 630,
    lsynthPartMenuTag               = 631, // LSynth parts
    lsynthHoseMenuTag				= 632, // LSynth synthesizable part: hose
    lsynthHoseConstraintMenuTag     = 633, // LSynth constraint items: hose
	lsynthBandMenuTag				= 634, // LSynth synthesizable part: band
	lsynthBandConstraintMenuTag		= 635, // LSynth constraint items: band
	lsynthInsideOutsideMenuTag		= 636,
    lsynthSurroundINSIDEOUTSIDETag  = 637,
    lsynthInvertINSIDEOUTSIDETag    = 638,
    lsynthInsertINSIDETag           = 639,
    lsynthInsertOUTSIDETag          = 640,
    lsynthInsertCROSSTag            = 641,

	// Window Menu
	windowMenuTag					= 7,

	// Contextual Menus
	partBrowserAddFavoriteTag		= 4001,
	partBrowserRemoveFavoriteTag	= 4002

} menuTagsT;


////////////////////////////////////////////////////////////////////////////////
//
#pragma mark		Shared Datatypes
//
// Data types which would otherwise be homeless. LDrawSelectionMode is on
// LDrawRenderer's delegate (RenderCore cannot depend on Editing). RotateModeT
// is read by LDrawCamera. Mouse-drag enums are read by LDrawViewPolicy.
//
////////////////////////////////////////////////////////////////////////////////

typedef enum MouseDragBehavior
{
	MouseDraggingOff									= 0,
	MouseDraggingBeginImmediately						= 1,
	MouseDraggingBeginAfterDelay						= 2,
	MouseDraggingImmediatelyInOrthoNeverInPerspective	= 3


} MouseDragBehaviorT;

typedef enum RightButtonBehavior
{
	RightButtonContextual								= 0,
	RightButtonRotates									= 1

} RightButtonBehaviorT;

typedef enum RotateMode {
	RotateModeTrackball									= 0,
	RotateModeTurntable									= 1

} RotateModeT;

typedef enum MouseWheelBehavior {
	MouseWheelScrolls									= 0,
	MouseWheelZooms										= 1

} MouseWheelBehaviorT;


typedef enum SelectionMode {

	LDrawSelectionReplace		= 0,	// Normal drag - take new
	LDrawSelectionExtend		= 1,	// Shift drag - take old | new
	LDrawSelectionSubtract		= 2,	// Option drag - take old - new
	LDrawSelectionIntersection	= 3		// Option-shift drag - take old & new

} LDrawSelectionMode;
