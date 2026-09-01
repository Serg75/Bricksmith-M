//==============================================================================
//
//  File:       LSynthConfiguration.h
//  Package:    LDrawFeatures
//
//  Purpose:    Parsed LSynth configuration (lsynth.ldr / lsynth.mpd): types,
//              constraints, and quick-reference menus.
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

/// Enablement of the LSynth selection-tinting controls in preferences.
typedef struct {
	BOOL transparencyEnabled;
	BOOL colorWellEnabled;
} LSynthSelectionControlEnablement;

/// Model → LSynth submenu contents. Used by +applicationMenuSpecs instead of
/// getter-selector name strings.
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
///             quick-reference menus for hoses, bands, and parts.
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

/// Return the default config path in the main bundle.
- (NSString *)defaultConfigPath;

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

/// Inspector type-popup caption: "Part Type:", "Hose Type:", or "Band Type:".
/// Nil if the class is unrecognized.
+ (nullable NSString *)typeLabelForClass:(LDrawLSynthClass)classType;

/// Transparency slider/text vs color well. Transparent = slider only,
/// Colored = well only, both = both. The host still sets NSControl enabled.
+ (LSynthSelectionControlEnablement)selectionControlEnablementForMode:(LDrawLSynthSelectionMode)mode;

/// Parts / hose / band types or constraints for a Model → LSynth submenu.
/// Empty array if unrecognized.
- (NSArray *)entriesForMenuKind:(LDrawLSynthMenuKind)kind;

/// Declarative encoding of the application Model → LSynth menus: tag, kind,
/// entry_key, action selector name, and shouldFilter. The host still builds
/// NSMenuItems.
+ (NSArray *)applicationMenuSpecs;

/// Insert INSIDE / OUTSIDE / CROSS items: title, action selector name, tag.
/// The host still builds NSMenuItems.
+ (NSArray *)insideOutsideInsertMenuSpecs;

/// The MLCad.ini file lists semi-official LSynth types; lsynth.mpd also has
/// legacy entries. Filter non-official types unless shouldFilter is NO or
/// the user turned off “basic parts only”. Constraints should not filter.
+ (BOOL)shouldIncludeMenuEntry:(NSDictionary *)entry
				  shouldFilter:(BOOL)shouldFilter
				  visibleTypes:(NSArray *)visibleTypes
			  showOnlyOfficial:(BOOL)showOnlyOfficial;

/// For a complete Part the constraints depend on the part’s LSYNTH_CLASS.
/// Hose/band classes pass through. The host still reads the type popup.
+ (LDrawLSynthClass)constraintClassForSynthClass:(LDrawLSynthClass)classTag
                                    selectedType:(nullable NSDictionary *)selectedType;

/// Band or hose constraint dictionaries; nil if the class has none.
- (nullable NSArray *)constraintsForClass:(LDrawLSynthClass)classType;

/// Case-insensitive match on `partName`. NSNotFound if none.
+ (NSUInteger)indexOfConstraintNamed:(NSString *)name inConstraints:(NSArray *)constraints;

/// First type whose LSYNTH_TYPE equals typeName. NSNotFound if none.
+ (NSUInteger)indexOfTypeNamed:(NSString *)typeName inTypes:(NSArray *)types;

/// Titles for the inspector type popup (valueForKey:@"title").
+ (NSArray<NSString *> *)typePopupTitlesFromTypes:(NSArray *)types;

/// Descriptions for the inspector default-constraint popup.
+ (NSArray<NSString *> *)constraintPopupDescriptionsFromConstraints:(NSArray *)constraints;

/// LSYNTH_TYPE at index, or nil if the index is out of range.
+ (nullable NSString *)typeNameAtIndex:(NSInteger)index inTypes:(NSArray *)types;

/// Dictionary at index, or nil if the index is out of range.
+ (nullable NSDictionary *)entryAtIndex:(NSInteger)index inEntries:(NSArray *)entries;

/// For a complete Part, the type at the popup index. Hose/band classes return
/// nil (constraints do not depend on the type popup). The host still reads
/// the popup index.
+ (nullable NSDictionary *)selectedTypeForClass:(LDrawLSynthClass)classTag
										atIndex:(NSInteger)index;

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

/// Inspector: “(approx. %i pieces)” format. The host still localizes.
+ (NSString *)approximatePieceCountFormatKey;

@end

NS_ASSUME_NONNULL_END
