//==============================================================================
//
//  File:       LDrawLSynthPanelModel.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only packing for Model → LSynth menus, the LSynth
//              inspector popups, and selection-tint control enablement. Parse
//              and type/constraint lookup stay on LSynthConfiguration.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawLSynthConfigSource.h>

NS_ASSUME_NONNULL_BEGIN

/// Enablement of the LSynth selection-tinting controls in preferences.
typedef struct {
	BOOL transparencyEnabled;
	BOOL colorWellEnabled;
} LSynthSelectionControlEnablement;


//------------------------------------------------------------------------------
///
/// @class      LDrawLSynthPanelModel
///
/// @abstract   Foundation-only packing for LSynth menus and inspector popups.
///             The host still builds NSMenuItems and NSPopUpButtons.
///
//------------------------------------------------------------------------------
@interface LDrawLSynthPanelModel : NSObject

/// Bundled lsynth.mpd, or nil if the bundle has no such resource.
+ (nullable NSString *)configPathInBundle:(NSBundle *)bundle;

/// Inspector type-popup caption: "Part Type:", "Hose Type:", or "Band Type:".
/// Nil if the class is unrecognized.
+ (nullable NSString *)typeLabelForClass:(LDrawLSynthClass)classType;

/// Transparency slider/text vs color well. Transparent = slider only,
/// Colored = well only, both = both. The host still sets NSControl enabled.
+ (LSynthSelectionControlEnablement)selectionControlEnablementForMode:(LDrawLSynthSelectionMode)mode;

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
/// the popup index and supplies typesForLSynthClass:.
+ (nullable NSDictionary *)selectedTypeForClass:(LDrawLSynthClass)classTag
										atIndex:(NSInteger)index
										inTypes:(nullable NSArray *)types;

/// Inspector: “(approx. %i pieces)” format. The host still localizes.
+ (NSString *)approximatePieceCountFormatKey;

@end

NS_ASSUME_NONNULL_END
