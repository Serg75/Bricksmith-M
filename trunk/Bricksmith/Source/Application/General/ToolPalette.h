//==============================================================================
//
// File:		ToolPalette.h
//
// Purpose:		Manages the current tool mode in effect when the mouse is used 
//				in an LDrawView.
//
//  Created by Allen Smith on 1/20/06.
//  Copyright 2006. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>
#import <LDrawFeatures/LDrawToolMode.h>

@class LDrawColorWell;

////////////////////////////////////////////////////////////////////////////////
//
//		Types and Constants
//
////////////////////////////////////////////////////////////////////////////////

typedef LDrawToolMode ToolModeT;

#define RotateSelectTool	LDrawToolModeRotateSelect
#define PanScrollTool		LDrawToolModePanScroll
#define SmoothZoomTool		LDrawToolModeSmoothZoom
#define ZoomInTool			LDrawToolModeZoomIn
#define ZoomOutTool			LDrawToolModeZoomOut
#define SpinTool			LDrawToolModeSpin
#define EraserTool			LDrawToolModeEraser



////////////////////////////////////////////////////////////////////////////////
//
//		ToolPalette
//
////////////////////////////////////////////////////////////////////////////////
@interface ToolPalette : NSObject
{
	ToolModeT				 baseToolMode;			//as selected in the palette
	ToolModeT				 effectiveToolMode;		//accounting for modifiers.

	NSArray					*topLevelObjects;		// holds NIB objects

	//Event Tracking
	NSString				*currentKeyCharacters;	//identifies the current keys down, independent of modifiers (empty string if no keys down)
	NSUInteger				 currentKeyModifiers;	//identifiers the current modifiers down (including device-dependent)
	BOOL					 mouseButton3IsDown;
	NSPointingDeviceType	 tabletPointingDevice;	// current pen-tablet device currently in proximity

	NSPanel					*palettePanel;

	//Nib connections
	__weak IBOutlet NSView			*paletteContents;
	__weak IBOutlet NSMatrix		*toolButtons;
	__weak IBOutlet LDrawColorWell	*colorWell;
}


//Initialization
+ (ToolPalette *) sharedToolPalette;

//Accessors
+ (ToolModeT) toolMode;
- (BOOL) isVisible;
- (ToolModeT) toolMode;
- (void) setToolMode:(ToolModeT)newToolMode;

//Actions
- (void) hideToolPalette:(id)sender;
- (void) showToolPalette:(id)sender;
- (IBAction) toolButtonClicked:(id)sender;

// Event notifiers
- (void) mouseButton3DidChange:(NSEvent *)theEvent;

//Utilities
- (void) resolveCurrentToolMode;
+ (NSString *) keysForToolMode:(ToolModeT)toolMode modifiers:(NSUInteger*)modifiersOut;
+ (BOOL) toolMode:(ToolModeT)toolMode matchesCharacters:(NSString *)characters modifiers:(NSUInteger)modifiers;

@end
