//==============================================================================
//
//  File:       LSynthConfiguration.h
//  Package:    LDrawFeatures
//
//  Purpose:    Parsed LSynth configuration (lsynth.ldr / lsynth.mpd): types,
//              constraints, and model mutation. Menu and inspector packing
//              live in LDrawLSynthPanelModel.
//
//  Created by Robin Macharg on 24/09/2012.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawLSynthConfigSource.h>

@class LDrawPart;
@class LDrawLSynth;
@class LDrawColor;

NS_ASSUME_NONNULL_BEGIN

/// Model → LSynth submenu contents. Used by LDrawLSynthPanelModel
/// +applicationMenuSpecs instead of getter-selector name strings.
typedef NS_ENUM(NSInteger, LDrawLSynthMenuKind) {
	LDrawLSynthMenuParts            = 0,
	LDrawLSynthMenuHoseTypes        = 1,
	LDrawLSynthMenuHoseConstraints  = 2,
	LDrawLSynthMenuBandTypes        = 3,
	LDrawLSynthMenuBandConstraints  = 4
};

//------------------------------------------------------------------------------
///
/// @class      LSynthConfiguration
///
/// @abstract   Parsed lsynth.ldr configuration: types, constraints, and
///             lookup used when synthesizing hoses, bands, and parts.
///
//------------------------------------------------------------------------------
@interface LSynthConfiguration : NSObject <LDrawLSynthConfigSource>
{
    NSMutableArray *parts;
    NSMutableArray *hose_constraints;
    NSMutableArray *band_constraints;
    NSMutableArray *hose_types;
    NSMutableArray *band_types;

    NSMutableArray *quickRefHoses;
    NSMutableArray *quickRefBands;
    NSMutableArray *quickRefParts;
    NSMutableArray *quickRefHoseConstraints;
    NSMutableArray *quickRefBandConstraints;
}

#pragma mark -
#pragma mark Class Methods
#pragma mark -

/// Return the singleton LSynthConfiguration instance.
+ (LSynthConfiguration*)sharedInstance;

#pragma mark -
#pragma mark Instance Methods
#pragma mark -

/// Parse an LSynth lsynth.mpd configuration file in order that we can a)
/// validate incoming ldraw files if required and b) populate parts menus
/// appropriately. We only need to parse the file enough to satisfy these
/// requirements; LSynth has a better understanding of this config file.
- (void)parseLsynthConfig:(NSString *)lsynthConfigurationPath;

/// Determine if a given part is an "official" LSynth constraint, i.e. defined
/// in lsynth.ldr, and parsed into the LSynthConfiguration object.
- (BOOL)isLSynthConstraint:(LDrawPart *)part;

#pragma mark -
#pragma mark CONSTANT ACCESSORS
#pragma mark -


/// Default constraint part name for a hose or band class; nil otherwise.
+ (nullable NSString *)defaultConstraintForClass:(LDrawLSynthClass)classType;

/// Default type name for a hose or band class; nil otherwise.
+ (nullable NSString *)defaultTypeNameForClass:(LDrawLSynthClass)classType;

#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

/// Configured synthesizable parts.
- (NSArray *)parts;

/// Look up a constraint by part type. Not especially performant.
- (nullable NSDictionary *)constraintDefinitionForPart:(LDrawPart *)directive;

/// Look up a band or hose definition by name. Used when the class is changed.
/// Not especially performant.
- (nullable NSDictionary *)typeForTypeName:(NSString *)typeName;

/// Parts, hose types, or band types for the class; nil if unrelated.
- (nullable NSArray *)typesForLSynthClass:(LDrawLSynthClass)classTag;

/// Parts / hose / band types or constraints for a Model → LSynth submenu.
/// Empty array if unrecognized.
- (NSArray *)entriesForMenuKind:(LDrawLSynthMenuKind)kind;

/// For a complete Part the constraints depend on the part’s LSYNTH_CLASS.
/// Hose/band classes pass through. The host still reads the type popup.
+ (LDrawLSynthClass)constraintClassForSynthClass:(LDrawLSynthClass)classTag
                                    selectedType:(nullable NSDictionary *)selectedType;

/// Band or hose constraint dictionaries; nil if the class has none.
- (nullable NSArray *)constraintsForClass:(LDrawLSynthClass)classType;

/// Sets each constraint part’s display name. Hoses only work with hose
/// constraints, bands similarly. The host still finishes editing.
- (void)applyConstraintPartName:(NSString *)partName toLSynth:(LDrawLSynth *)lsynth;

/// Sets each constraint part to the class default and refreshes its icon.
- (void)applyDefaultConstraintsToLSynth:(LDrawLSynth *)lsynth
							  classType:(LDrawLSynthClass)classType;

/// Set the class of an LSynthDirective based on the part type name.
- (void)setLSynthClassForDirective:(LDrawLSynth *)directive withType:(NSString *)type;

/// Hose, band, or part class for a type name; 0 if unknown.
- (LDrawLSynthClass)classForType:(NSString *)type;

/// New LDrawLSynth with type, class, and color set. The host still inserts it.
- (LDrawLSynth *)synthesizableDirectiveWithType:(NSString *)type color:(LDrawColor *)color;

@end

NS_ASSUME_NONNULL_END
