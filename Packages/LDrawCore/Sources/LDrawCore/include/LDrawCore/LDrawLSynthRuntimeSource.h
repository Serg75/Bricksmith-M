//==============================================================================
//
//  File:       LDrawLSynthRuntimeSource.h
//  Package:    LDrawCore
//
//  Purpose:    Host-injected LSynth process paths and selection-tint settings
//              used when synthesizing, writing, and previewing LSynth
//              directives.
//
//  Info:       Each host app installs a concrete adapter at launch. LDrawCore
//              must not look up the app main bundle or standardUserDefaults
//              for lsynthcp, the custom config file, or selection prefs.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/LDrawLSynthConfigSource.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @protocol   LDrawLSynthRuntimeSource
///
/// @abstract   Host-injected LSynth executable/config paths and selection-tint
///             settings. Implementations typically read NSUserDefaults keys
///             (LSYNTH_* in LDrawKeys.h) plus a bundled lsynthcp path.
///
//------------------------------------------------------------------------------
@protocol LDrawLSynthRuntimeSource <NSObject>

/// Resolved lsynthcp: user-chosen path if non-empty, otherwise the bundled
/// auxiliary executable. Nil if neither is available.
- (nullable NSString *)executablePath;

/// Custom lsynth.mpd for the `-c` flag. Empty or nil skips `-c`.
- (nullable NSString *)configurationPath;

/// When YES, write emits SYNTHESIZED BEGIN/END blocks.
- (BOOL)saveSynthesizedParts;

/// How synthesized parts are tinted while the directive is selected.
- (LDrawLSynthSelectionMode)selectionMode;

/// Selection transparency as a 0–100 percentage (factory default 20).
- (NSInteger)selectionTransparencyPercent;

/// Writes four RGBA floats. Falls back to opaque red if the preference is
/// missing or malformed. outRGBA must be non-NULL.
- (void)getSelectionColorRGBA:(float *)outRGBA;

@end

NS_ASSUME_NONNULL_END
