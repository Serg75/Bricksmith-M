//==============================================================================
//
//  File:       LDrawHostKeys.h
//  Package:    LDrawFeatures
//
//  Purpose:    User-defaults keys for Bricksmith host chrome: windows,
//              donation nag, part browser, tool palette, viewport layout,
//              minifigure generator, and AppKit-only LSynth prefs.
//
//  Info:       Core/RenderCore/Editing cannot import this header. Keys those
//              packages read (LDraw path, LSynth executable, syntax colors,
//              mouse/rotate) stay in LDrawCore/MacLDraw.h. Grid spacing keys
//              live next to LDrawGrid.
//
//  Created by Sergey Slobodenyuk on 2026-08-30.
//
//==============================================================================

#import <Foundation/Foundation.h>

////////////////////////////////////////////////////////////////////////////////
//
#pragma mark		Preferences Keys
//
////////////////////////////////////////////////////////////////////////////////

#define DOCUMENT_WINDOW_SIZE						@"Document Window Size"
#define DONATION_SCREEN_LAST_VERSION_DISPLAYED		@"DonationRequestLastVersion"
#define DONATION_SCREEN_SUPPRESS_THIS_VERSION		@"DonationRequestSuppressThisVersion"
#define FAVORITE_PARTS_KEY							@"FavoriteParts"
#define LDRAW_GL_VIEW_ANGLE							@"LDrawGLView Viewing Angle"
#define LDRAW_GL_VIEW_PROJECTION					@"LDrawGLView Viewing Projection"
#define LDRAW_VIEWER_BACKGROUND_COLOR_KEY			@"LDraw Viewer Background Color"
#define PART_BROWSER_PANEL_SHOW_AT_LAUNCH			@"Part Browser Panel Show at Launch"
#define PART_BROWSER_PREVIOUS_CATEGORY				@"Part Browser Previous Category"
#define PART_BROWSER_PREVIOUS_SELECTED_ROW			@"Part Browser Previous Selected Row"
#define PART_BROWSER_SEARCH_MODE					@"Part Browser Search Mode"
#define PREFERENCES_LAST_TAB_DISPLAYED				@"Preferences Tab"
#define TOOL_PALETTE_HIDDEN							@"Tool Palette Hidden"
#define VIEWPORTS_EXPAND_TO_AVAILABLE_SIZE			@"ViewportsExpandToAvailableSize"

// AppKit color well for LSynth selection; Core reads LSYNTH_SELECTION_COLOR_RGBA_KEY.
#define LSYNTH_SELECTION_COLOR_KEY                  @"LSynth Selection Color"
#define LSYNTH_SHOW_BASIC_PARTS_LIST_KEY            @"LSynth Show Basic Parts List"

#define MINIFIGURE_HAS_HAT							@"Minifigure Has Hat"
#define MINIFIGURE_HAS_HEAD							@"Minifigure Has Head"
#define MINIFIGURE_HAS_NECK							@"Minifigure Has Neck"
#define MINIFIGURE_HAS_TORSO						@"Minifigure Has Torso"
#define MINIFIGURE_HAS_ARM_RIGHT					@"Minifigure Has Arm Right"
#define MINIFIGURE_HAS_ARM_LEFT						@"Minifigure Has Arm Left"
#define MINIFIGURE_HAS_HAND_RIGHT					@"Minifigure Has Hand Right"
#define MINIFIGURE_HAS_HAND_RIGHT_ACCESSORY			@"Minifigure Has Hand Right Accessory"
#define MINIFIGURE_HAS_HAND_LEFT					@"Minifigure Has Hand Left"
#define MINIFIGURE_HAS_HAND_LEFT_ACCESSORY			@"Minifigure Has Hand Left Accessory"
#define MINIFIGURE_HAS_HIPS							@"Minifigure Has Hips"
#define MINIFIGURE_HAS_LEG_RIGHT					@"Minifigure Has Leg Right"
#define MINIFIGURE_HAS_LEG_RIGHT_ACCESSORY			@"Minifigure Has Leg Right Accessory"
#define MINIFIGURE_HAS_LEG_LEFT						@"Minifigure Has Leg Left"
#define MINIFIGURE_HAS_LEG_LEFT_ACCESSORY			@"Minifigure Has Leg Left Accessory"

#define MINIFIGURE_PARTNAME_HAT						@"Minifigure Partname Hat"
#define MINIFIGURE_PARTNAME_HEAD					@"Minifigure Partname Head"
#define MINIFIGURE_PARTNAME_NECK					@"Minifigure Partname Neck"
#define MINIFIGURE_PARTNAME_TORSO					@"Minifigure Partname Torso"
#define MINIFIGURE_PARTNAME_ARM_RIGHT				@"Minifigure Partname Arm Right"
#define MINIFIGURE_PARTNAME_ARM_LEFT				@"Minifigure Partname Arm Left"
#define MINIFIGURE_PARTNAME_HAND_RIGHT				@"Minifigure Partname Hand Right"
#define MINIFIGURE_PARTNAME_HAND_RIGHT_ACCESSORY	@"Minifigure Partname Hand Right Accessory"
#define MINIFIGURE_PARTNAME_HAND_LEFT				@"Minifigure Partname Hand Left"
#define MINIFIGURE_PARTNAME_HAND_LEFT_ACCESSORY		@"Minifigure Partname Hand Left Accessory"
#define MINIFIGURE_PARTNAME_HIPS					@"Minifigure Partname Hips"
#define MINIFIGURE_PARTNAME_LEG_RIGHT				@"Minifigure Partname Leg Right"
#define MINIFIGURE_PARTNAME_LEG_RIGHT_ACCESSORY		@"Minifigure Partname Leg Right Accessory"
#define MINIFIGURE_PARTNAME_LEG_LEFT				@"Minifigure Partname Leg Left"
#define MINIFIGURE_PARTNAME_LEG_LEFT_ACCESSORY		@"Minifigure Partname Leg Left Accessory"

#define MINIFIGURE_ANGLE_HAT						@"Minifigure Angle Hat"
#define MINIFIGURE_ANGLE_HEAD						@"Minifigure Angle Head"
#define MINIFIGURE_ANGLE_NECK						@"Minifigure Angle Neck"
#define MINIFIGURE_ANGLE_TORSO						@"Minifigure Angle Torso"
#define MINIFIGURE_ANGLE_ARM_RIGHT					@"Minifigure Angle Arm Right"
#define MINIFIGURE_ANGLE_ARM_LEFT					@"Minifigure Angle Arm Left"
#define MINIFIGURE_ANGLE_HAND_RIGHT					@"Minifigure Angle Hand Right"
#define MINIFIGURE_ANGLE_HAND_RIGHT_ACCESSORY		@"Minifigure Angle Hand Right Accessory"
#define MINIFIGURE_ANGLE_HAND_LEFT					@"Minifigure Angle Hand Left"
#define MINIFIGURE_ANGLE_HAND_LEFT_ACCESSORY			@"Minifigure Angle Hand Left Accessory"
#define MINIFIGURE_ANGLE_HIPS						@"Minifigure Angle Hips"
#define MINIFIGURE_ANGLE_LEG_RIGHT					@"Minifigure Angle Leg Right"
#define MINIFIGURE_ANGLE_LEG_RIGHT_ACCESSORY		@"Minifigure Angle Leg Right Accessory"
#define MINIFIGURE_ANGLE_LEG_LEFT					@"Minifigure Angle Leg Left"
#define MINIFIGURE_ANGLE_LEG_LEFT_ACCESSORY			@"Minifigure Angle Leg Left Accessory"

#define MINIFIGURE_COLOR_HAT						@"Minifigure Color Hat"
#define MINIFIGURE_COLOR_HEAD						@"Minifigure Color Head"
#define MINIFIGURE_COLOR_NECK						@"Minifigure Color Neck"
#define MINIFIGURE_COLOR_TORSO						@"Minifigure Color Torso"
#define MINIFIGURE_COLOR_ARM_RIGHT					@"Minifigure Color Arm Right"
#define MINIFIGURE_COLOR_ARM_LEFT					@"Minifigure Color Arm Left"
#define MINIFIGURE_COLOR_HAND_RIGHT					@"Minifigure Color Hand Right"
#define MINIFIGURE_COLOR_HAND_RIGHT_ACCESSORY		@"Minifigure Color Hand Right Accessory"
#define MINIFIGURE_COLOR_HAND_LEFT					@"Minifigure Color Hand Left"
#define MINIFIGURE_COLOR_HAND_LEFT_ACCESSORY			@"Minifigure Color Hand Left Accessory"
#define MINIFIGURE_COLOR_HIPS						@"Minifigure Color Hips"
#define MINIFIGURE_COLOR_LEG_RIGHT					@"Minifigure Color Leg Right"
#define MINIFIGURE_COLOR_LEG_RIGHT_ACCESSORY		@"Minifigure Color Leg Right Accessory"
#define MINIFIGURE_COLOR_LEG_LEFT					@"Minifigure Color Leg Left"
#define MINIFIGURE_COLOR_LEG_LEFT_ACCESSORY			@"Minifigure Color Leg Left Accessory"

#define MINIFIGURE_HEAD_ELEVATION					@"Minifigure Head Elevation"
