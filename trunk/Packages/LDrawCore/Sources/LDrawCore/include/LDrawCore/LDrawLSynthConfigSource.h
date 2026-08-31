//==============================================================================
//
//  File:       LDrawLSynthConfigSource.h
//  Package:    LDrawCore
//
//  Purpose:    GPU/AppKit-free abstraction that supplies the LSynth
//              configuration look-ups used by LDrawLSynth at parse time.
//
//  Info:       Each host app installs a concrete adapter at launch. LDrawCore
//              must not depend on LSynthConfiguration (LDrawFeatures); this
//              protocol keeps the model layer free of feature-package types.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawLSynth;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

// Hose, band, or part class for a synthesis directive. Defined here so
// LDrawCore can use it without depending on LDrawFeatures.
typedef NS_ENUM(NSInteger, LDrawLSynthClass) {
    LDrawLSynthClassPart = 1,
    LDrawLSynthClassHose = 2,
    LDrawLSynthClassBand = 3,
    LDrawLSynthClassCount
};

// LSynth "selection mode" — how synthesized parts are tinted when the
// directive is selected. Mirrored from BricksmithMac's
// PreferencesDialogController.h so LDrawCore can read the user's choice
// directly from NSUserDefaults under LSYNTH_SELECTION_MODE_KEY without
// pulling in the AppKit preferences UI.
typedef NS_ENUM(NSInteger, LDrawLSynthSelectionMode) {
    LDrawLSynthSelectionTransparent         = 0,
    LDrawLSynthSelectionColored             = 1,
    LDrawLSynthSelectionTransparentColored  = 2
};


//------------------------------------------------------------------------------
///
/// @protocol   LDrawLSynthConfigSource
///
/// @abstract   GPU/AppKit-free abstraction that supplies the LSynth
///             configuration look-ups used by LDrawLSynth at parse time.
///
//------------------------------------------------------------------------------
@protocol LDrawLSynthConfigSource <NSObject>

// Resolves the LSynth class (hose/band/part) for the given directive based on
// the textual type name parsed from the file. Implementations typically
// delegate to LSynthConfiguration in LDrawFeatures.
- (void)setLSynthClassForDirective:(LDrawLSynth *)directive
						  withType:(NSString *)type;

// Look up a configured LSynth type by its textual name (e.g. @"RUBBER_BAND").
// Returns nil if no such type is registered.
- (nullable NSDictionary *)typeForTypeName:(NSString *)typeName;

// True when the given part is registered as a hose/band constraint in the
// active configuration.
- (BOOL)isLSynthConstraint:(LDrawPart *)part;

// Returns all configured "PART"-class LSynth definitions. Each element is a
// dictionary describing one part; the LSYNTH_CLASS key holds an
// integer-valued NSNumber compatible with LDrawLSynthClass.
- (NSArray *)getParts;

// Look up the constraint definition (radius / orientation) for a given
// constraint part. Returns nil if the part is not a registered constraint.
- (nullable NSDictionary *)constraintDefinitionForPart:(LDrawPart *)directive;

@end

NS_ASSUME_NONNULL_END
