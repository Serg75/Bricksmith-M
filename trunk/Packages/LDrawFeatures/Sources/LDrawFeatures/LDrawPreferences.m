//==============================================================================
//
//  File:       LDrawPreferences.m
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only preferences accessor used by portable clients.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawPreferences.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawFeatures/LDrawGrid.h>
#import <LDrawFeatures/LDrawPartBrowserModel.h>


@implementation LDrawPreferences

//---------- sharedPreferences --------------------------------------[static]--
//
// Purpose:		Return the process-wide preferences accessor.
//
//------------------------------------------------------------------------------
+ (instancetype)sharedPreferences
{
	static LDrawPreferences *shared = nil;
	static dispatch_once_t   onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[LDrawPreferences alloc] init];
	});
	return shared;
}


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
- (void)ensureDefaults
{
	NSMutableDictionary *initialDefaults = [NSMutableDictionary dictionary];

	//
	// General
	//
	[initialDefaults setObject:@(LDrawMouseDraggingBeginImmediately)	forKey:MOUSE_DRAGGING_BEHAVIOR_KEY];
	[initialDefaults setObject:@(LDrawRightButtonContextual)	forKey:RIGHT_BUTTON_BEHAVIOR_KEY];
	[initialDefaults setObject:@(LDrawRotateStyleTrackball)		forKey:ROTATE_MODE_KEY];
	[initialDefaults setObject:@(LDrawMouseWheelScrolls)		forKey:MOUSE_WHEEL_BEHAVIOR_KEY];

	[initialDefaults setObject:@YES								forKey:PART_BROWSER_PANEL_SHOW_AT_LAUNCH];
	[initialDefaults setObject:@YES								forKey:VIEWPORTS_EXPAND_TO_AVAILABLE_SIZE];
	[initialDefaults setObject:@NO								forKey:COLUMNIZE_OUTPUT_KEY]; // appease LDraw traditionalists

	//
	// Grid Spacing
	//
	[initialDefaults setObject:@1.0f							forKey:GRID_SPACING_FINE];
	[initialDefaults setObject:@10.0f							forKey:GRID_SPACING_MEDIUM];
	[initialDefaults setObject:@20.0f							forKey:GRID_SPACING_COARSE];

	//
	// Initial Window State
	//

	// GPU viewer settings -- see -restoreConfiguration in LDrawView.
	// LDrawProjectionMode lives in LDrawRenderCore; values are 0=perspective, 1=orthographic.
	[initialDefaults setObject:@(LDrawViewOrientation3D)		forKey:[LDRAW_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_0"]];
	[initialDefaults setObject:@0								forKey:[LDRAW_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_0"]];
	[initialDefaults setObject:@(LDrawViewOrientationFront)		forKey:[LDRAW_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_1"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_1"]];
	[initialDefaults setObject:@(LDrawViewOrientationLeft)		forKey:[LDRAW_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_2"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_2"]];
	[initialDefaults setObject:@(LDrawViewOrientationTop)		forKey:[LDRAW_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_3"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_3"]];

	//
	// Part Browser
	//
	[initialDefaults setObject:@(LDrawPartBrowserSearchAllCategories)	forKey:PART_BROWSER_SEARCH_MODE];
	[initialDefaults setObject:NSLocalizedString(@"Brick", nil)	forKey:PART_BROWSER_PREVIOUS_CATEGORY];
	[initialDefaults setObject:@0								forKey:PART_BROWSER_PREVIOUS_SELECTED_ROW];
	[initialDefaults setObject:@[]								forKey:FAVORITE_PARTS_KEY];

	//
	// Tool Palette
	//
	[initialDefaults setObject:@NO								forKey:TOOL_PALETTE_HIDDEN];

	//
	// LSynth Palette
	//
	[initialDefaults setObject:@""								forKey:LSYNTH_EXECUTABLE_PATH_KEY];
	[initialDefaults setObject:@""								forKey:LSYNTH_CONFIGURATION_PATH_KEY];
	[initialDefaults setObject:@20								forKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
	[initialDefaults setObject:@0								forKey:LSYNTH_SELECTION_MODE_KEY];
	[initialDefaults setObject:@[@1.0f, @0.0f, @0.0f, @1.0f]	forKey:LSYNTH_SELECTION_COLOR_RGBA_KEY];
	[initialDefaults setObject:@YES								forKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];
	[initialDefaults setObject:@YES								forKey:LSYNTH_SHOW_BASIC_PARTS_LIST_KEY];

	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HAT];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HEAD];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_NECK];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_TORSO];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_ARM_RIGHT];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_ARM_LEFT];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HAND_RIGHT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HAND_LEFT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HIPS];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_LEG_RIGHT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_LEG_LEFT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_LEG_LEFT_ACCESSORY];

	[initialDefaults setObject:@"4485.dat"						forKey:MINIFIGURE_PARTNAME_HAT];
	[initialDefaults setObject:@"3626bp01.dat"					forKey:MINIFIGURE_PARTNAME_HEAD];
	[initialDefaults setObject:@"3838.dat"						forKey:MINIFIGURE_PARTNAME_NECK];
	[initialDefaults setObject:@"973p1b.dat"					forKey:MINIFIGURE_PARTNAME_TORSO];
	[initialDefaults setObject:@"982.dat"						forKey:MINIFIGURE_PARTNAME_ARM_RIGHT];
	[initialDefaults setObject:@"981.dat"						forKey:MINIFIGURE_PARTNAME_ARM_LEFT];
	[initialDefaults setObject:@"983.dat"						forKey:MINIFIGURE_PARTNAME_HAND_RIGHT];
	[initialDefaults setObject:@"3837.dat"						forKey:MINIFIGURE_PARTNAME_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@"983.dat"						forKey:MINIFIGURE_PARTNAME_HAND_LEFT];
	[initialDefaults setObject:@"4006.dat"						forKey:MINIFIGURE_PARTNAME_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@"970.dat"						forKey:MINIFIGURE_PARTNAME_HIPS];
	[initialDefaults setObject:@"971.dat"						forKey:MINIFIGURE_PARTNAME_LEG_RIGHT];
	[initialDefaults setObject:@"6120.dat"						forKey:MINIFIGURE_PARTNAME_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@"972.dat"						forKey:MINIFIGURE_PARTNAME_LEG_LEFT];
	[initialDefaults setObject:@"6120.dat"						forKey:MINIFIGURE_PARTNAME_LEG_LEFT_ACCESSORY];

	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HEAD];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_NECK];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_TORSO];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_ARM_RIGHT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_ARM_LEFT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_RIGHT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_LEFT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HIPS];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_RIGHT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_LEFT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_LEFT_ACCESSORY];

	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_HAT];
	[initialDefaults setObject:@(LDrawYellow)					forKey:MINIFIGURE_COLOR_HEAD];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_NECK];
	[initialDefaults setObject:@(LDrawWhite)					forKey:MINIFIGURE_COLOR_TORSO];
	[initialDefaults setObject:@(LDrawWhite)					forKey:MINIFIGURE_COLOR_ARM_RIGHT];
	[initialDefaults setObject:@(LDrawWhite)					forKey:MINIFIGURE_COLOR_ARM_LEFT];
	[initialDefaults setObject:@(LDrawYellow)					forKey:MINIFIGURE_COLOR_HAND_RIGHT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@(LDrawYellow)					forKey:MINIFIGURE_COLOR_HAND_LEFT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_HIPS];
	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_LEG_RIGHT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_LEG_LEFT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_LEG_LEFT_ACCESSORY];
	[initialDefaults setObject:@4.0f							forKey:MINIFIGURE_HEAD_ELEVATION];

	[initialDefaults setObject:@(LDrawViewOrientationFront)		forKey:[LDRAW_VIEW_ANGLE stringByAppendingString:@" MinifigureGeneratorView"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_VIEW_PROJECTION stringByAppendingString:@" MinifigureGeneratorView"]];

	[[NSUserDefaults standardUserDefaults] registerDefaults:initialDefaults];
}


//---------- viewingAnglePreferenceKeyForAutosaveName: ---------------[static]--
//
// Purpose:		Preference keys for a named LDrawView autosave slot.
//
//------------------------------------------------------------------------------
+ (NSString *)viewingAnglePreferenceKeyForAutosaveName:(NSString *)autosaveName
{
	return [NSString stringWithFormat:@"%@ %@", LDRAW_VIEW_ANGLE, autosaveName];
}


//---------- projectionModePreferenceKeyForAutosaveName: ------------[static]--
//
// Purpose:		User-defaults key for an LDrawView's saved projection mode.
//
//------------------------------------------------------------------------------
+ (NSString *)projectionModePreferenceKeyForAutosaveName:(NSString *)autosaveName
{
	return [NSString stringWithFormat:@"%@ %@", LDRAW_VIEW_PROJECTION, autosaveName];
}


//---------- documentViewportAutosaveNameAtIndex: --------------------[static]--
//
// Purpose:		Document 3D viewport autosave name at index. Matches the
//				fileGraphicView_N slots seeded by -ensureDefaults.
//
//------------------------------------------------------------------------------
+ (NSString *)documentViewportAutosaveNameAtIndex:(NSUInteger)index
{
	return [NSString stringWithFormat:@"fileGraphicView_%ld", (long)index];
}

@end
