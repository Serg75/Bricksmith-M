//==============================================================================
//
//  File:       LDrawPreferences.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only schema and accessor wrapper around
//              NSUserDefaults for Bricksmith preference keys.
//
//  Info:       Seeds factory defaults that do not require AppKit (NSColor) into
//              a host-provided NSUserDefaults. The macOS preferences pane still
//              registers archived-color defaults for its own UI. Donation nag,
//              split-view geometry, toolbar identifier, and open-panel strings
//              live in the Bricksmith app (LDrawHostChrome).
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawFeatures/LDrawHostKeys.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPreferences
///
/// @abstract   Foundation-only schema and accessor wrapper around
///             NSUserDefaults for Bricksmith preference keys.
///
//------------------------------------------------------------------------------
@interface LDrawPreferences : NSObject

/// Seeds the given store with Bricksmith's factory settings (numeric, boolean,
/// and string keys). Safe to call repeatedly. The host still registers
/// AppKit-only archived-color defaults.
+ (void)ensureDefaults:(NSUserDefaults *)userDefaults;

/// Preference keys for a named LDrawView autosave slot.
+ (NSString *)viewingAnglePreferenceKeyForAutosaveName:(NSString *)autosaveName;
+ (NSString *)projectionModePreferenceKeyForAutosaveName:(NSString *)autosaveName;

/// Document 3D viewport autosave name at index (fileGraphicView_N).
+ (NSString *)documentViewportAutosaveNameAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
