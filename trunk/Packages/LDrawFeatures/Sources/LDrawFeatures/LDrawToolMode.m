//==============================================================================
//
//  File:       LDrawToolMode.m
//  Package:    LDrawFeatures
//
//  Purpose:    Hotkey mapping for LDrawToolMode, independent of AppKit.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawToolMode.h>

#import <LDrawCore/StringCategory.h>

NSString *LDrawToolModeCharacters(LDrawToolMode mode, NSUInteger *modifiersOut)
{
	NSString   *characters = @"";
	NSUInteger  modifiers  = LDrawKeyModifierNone;

	switch (mode)
	{
		case LDrawToolModeRotateSelect:
		case LDrawToolModeEraser:
			characters = @"";
			modifiers  = LDrawKeyModifierNone;
			break;

		case LDrawToolModePanScroll:
			characters = @" ";
			modifiers  = LDrawKeyModifierNone;
			break;

		case LDrawToolModeSmoothZoom:
			characters = @"";
			modifiers  = (LDrawKeyModifierCommand | LDrawKeyModifierOption);
			break;

		case LDrawToolModeZoomIn:
			characters = @" ";
			modifiers  = LDrawKeyModifierCommand;
			break;

		case LDrawToolModeZoomOut:
			characters = @" ";
			modifiers  = LDrawKeyModifierOption;
			break;

		case LDrawToolModeSpin:
			characters = @"";
			modifiers  = LDrawKeyModifierCommand;
			break;
	}

	if (modifiersOut != NULL)
	{
		*modifiersOut = modifiers;
	}
	return characters;
}

BOOL LDrawToolModeMatches(LDrawToolMode mode, NSString *characters, NSUInteger modifiers)
{
	NSUInteger  testModifiers   = 0;
	NSString   *testCharacters  = LDrawToolModeCharacters(mode, &testModifiers);

	return [characters ams_containsString:testCharacters options:0]
		&& (modifiers & testModifiers) == testModifiers;
}


LDrawToolMode LDrawToolModeResolved(LDrawToolMode baseMode,
									NSString *pressedCharacters,
									NSUInteger pressedModifiers,
									BOOL mouseButton3IsDown,
									BOOL eraserPointingDevice)
{
	NSUInteger  baseModifiers        = 0;
	NSString   *baseCharacters       = LDrawToolModeCharacters(baseMode, &baseModifiers);
	NSString   *effectiveCharacters  = [baseCharacters stringByAppendingString:pressedCharacters ?: @""];
	NSUInteger  effectiveModifiers   = baseModifiers | pressedModifiers;

	// Assess the current state of the keyboard and set the effective tool mode
	// based on it. The "effective keys" are the result of what we *would be
	// pressing* to get the currently-selected tool, plus the keys we *actually
	// are pressing*.
	if (LDrawToolModeMatches(LDrawToolModeZoomOut, effectiveCharacters, effectiveModifiers))
	{
		return LDrawToolModeZoomOut;
	}
	if (LDrawToolModeMatches(LDrawToolModeZoomIn, effectiveCharacters, effectiveModifiers))
	{
		return LDrawToolModeZoomIn;
	}
	if (LDrawToolModeMatches(LDrawToolModeSmoothZoom, effectiveCharacters, effectiveModifiers))
	{
		return LDrawToolModeSmoothZoom;
	}
	if (LDrawToolModeMatches(LDrawToolModePanScroll, effectiveCharacters, effectiveModifiers))
	{
		return LDrawToolModePanScroll;
	}
	if (LDrawToolModeMatches(LDrawToolModeSpin, effectiveCharacters, effectiveModifiers)
	   || mouseButton3IsDown)
	{
		return LDrawToolModeSpin;
	}
	if (eraserPointingDevice)
	{
		return LDrawToolModeEraser;
	}
	// Rotate/select (no hot key; normal behavior)
	return LDrawToolModeRotateSelect;
}


//---------- LDrawToolModeShouldSuppressResponderChain -----------------------
//
// Purpose:		Kill Cmd-Space before Cocoa beeps when ZoomIn isn’t first
//				responder. Matches ZoomIn hotkey characters/modifiers exactly.
//
//------------------------------------------------------------------------------
BOOL LDrawToolModeShouldSuppressResponderChain(NSString *characters,
											   NSUInteger deviceIndependentModifiers)
{
	NSUInteger  zoomInModifiers  = 0;
	NSString   *zoomInCharacters = LDrawToolModeCharacters(LDrawToolModeZoomIn, &zoomInModifiers);

	return [characters isEqualToString:zoomInCharacters]
		&& deviceIndependentModifiers == zoomInModifiers;
}
