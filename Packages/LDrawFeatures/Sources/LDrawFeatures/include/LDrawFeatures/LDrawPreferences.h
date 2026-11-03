//==============================================================================
//
//  File:       LDrawPreferences.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only schema and accessor wrapper around
//              NSUserDefaults for the host's preference keys.
//
//  Info:       Seeds factory defaults that do not require AppKit (NSColor) into
//              a host-provided NSUserDefaults. The default part-browser
//              category string comes from the host (localized “Brick”, for
//              instance). The macOS preferences pane still registers
//              archived-color defaults for its own UI. Donation nag,
//              split-view geometry, toolbar identifier, and open-panel strings
//              live in the host app (LDrawHostChrome).
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawFeatures/LDrawHostKeys.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPreferences
///
/// @abstract   Foundation-only schema and accessor wrapper around
///             NSUserDefaults for the host's preference keys.
///
//------------------------------------------------------------------------------
@interface LDrawPreferences : NSObject

/// Seeds the given store with the host's factory settings (numeric, boolean,
/// and string keys). Safe to call repeatedly. The host still registers
/// AppKit-only archived-color defaults.
///
/// previousPartCategory is stored under PART_BROWSER_PREVIOUS_CATEGORY
/// (unchanged key). Pass a localized category name; nil or empty falls back
/// to unlocalized @"Brick".
+ (void)ensureDefaults:(NSUserDefaults *)userDefaults
 previousPartCategory:(nullable NSString *)previousPartCategory;

/// Preference keys for a named LDrawView autosave slot.
+ (NSString *)viewingAnglePreferenceKeyForAutosaveName:(NSString *)autosaveName;
+ (NSString *)projectionModePreferenceKeyForAutosaveName:(NSString *)autosaveName;

/// Document 3D viewport autosave name at index (fileGraphicView_N).
+ (NSString *)documentViewportAutosaveNameAtIndex:(NSUInteger)index;

/// The parts limit's mark style: stripes, a tint or an outline. Any other
/// stored value reads as stripes.
+ (LDrawRenderMarkStyle)partsLimitMarkStyleInDefaults:(NSUserDefaults *)userDefaults;

/// A parts limit mark color as red, green and blue, for
/// PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY or PARTS_LIMIT_TOO_MANY_COLOR_KEY. A
/// stored value that is not three numbers reads as the factory color.
+ (void)getPartsLimitMarkColor:(float[_Nonnull 3])rgb
						forKey:(NSString *)key
					inDefaults:(NSUserDefaults *)userDefaults;

/// Gives the drawing code the marks the settings ask for: whether parts are
/// marked and how, the colors, and whether other parts dim. The host redraws.
+ (void)applyPartsLimitMarksFromDefaults:(NSUserDefaults *)userDefaults;

@end

NS_ASSUME_NONNULL_END
