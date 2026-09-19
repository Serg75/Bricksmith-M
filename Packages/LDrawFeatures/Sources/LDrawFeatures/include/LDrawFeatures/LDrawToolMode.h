//==============================================================================
//
//  File:       LDrawToolMode.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only tool-mode enum extracted from ToolPalette.
//
//  Info:       Hotkey matching lives here so any host can drive the same
//              tool-mode state without the AppKit NSPanel palette. Modifier
//              bits match NSEventModifierFlags so AppKit hosts can pass
//              event.modifierFlags through unchanged.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LDrawToolMode) {
	LDrawToolModeRotateSelect = 0,   // click to select, drag to rotate
	LDrawToolModePanScroll    = 2,   // "grabber" scroll while dragging
	LDrawToolModeSmoothZoom   = 3,   // zoom in / out from drag direction
	LDrawToolModeZoomIn       = 4,   // click to zoom in
	LDrawToolModeZoomOut      = 5,   // click to zoom out
	LDrawToolModeSpin         = 6,   // spin model in space
	LDrawToolModeEraser       = 7    // delete clicked parts
};

// Numeric values match NSEventModifierFlags (AppKit / UIKit).
typedef NS_OPTIONS(NSUInteger, LDrawKeyModifier) {
	LDrawKeyModifierNone    = 0,
	LDrawKeyModifierShift   = 1UL << 17,
	LDrawKeyModifierOption  = 1UL << 19,
	LDrawKeyModifierCommand = 1UL << 20
};

NSString *LDrawToolModeCharacters(LDrawToolMode mode, NSUInteger * _Nullable modifiersOut);
BOOL LDrawToolModeMatches(LDrawToolMode mode, NSString *characters, NSUInteger modifiers);

/// Effective tool from the palette base mode plus currently pressed keys.
/// Mouse-button 3 forces spin; a tablet eraser forces eraser. Zoom-out,
/// zoom-in, smooth-zoom, and pan are checked first so they win over spin.
LDrawToolMode LDrawToolModeResolved(LDrawToolMode baseMode,
									NSString *pressedCharacters,
									NSUInteger pressedModifiers,
									BOOL mouseButton3IsDown,
									BOOL eraserPointingDevice);

/// Kill Cmd-Space before Cocoa beeps when ZoomIn isn’t first responder.
/// Pass device-independent modifier flags (host strips the device mask).
BOOL LDrawToolModeShouldSuppressResponderChain(NSString *characters,
											   NSUInteger deviceIndependentModifiers);

NS_ASSUME_NONNULL_END
