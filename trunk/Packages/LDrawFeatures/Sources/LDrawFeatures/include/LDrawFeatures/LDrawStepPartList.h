//==============================================================================
//
//  File:       LDrawStepPartList.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawModel;
@class LDrawStep;
@class LDrawStepPartListEntry;

@class LDrawPartListOrientations;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartList
///
/// @abstract   Collects the parts a single step consumes, grouped by design and
///             color.
///
/// @discussion The list says what the step uses, not what is drawn. A hidden
///             part is listed. A part dropped by `REMOVE GROUP` or inside a
///             `PLI BEGIN IGN` range is not. A reference that does not resolve
///             is listed and flagged `isMissing`. Earlier steps are not walked.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartList : NSObject

/// Entries for the given step, in display order. Empty when `step` is nil.
+ (NSArray<LDrawStepPartListEntry *> *) entriesForStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(entries(forStep:));

/// Entries for the step the model has on display, or for its last step when
/// the model is not in Steps mode. Empty when `model` is nil.
///
/// Works out group suppression first, so a `REMOVE GROUP` that just came into
/// scope is honored.
+ (NSArray<LDrawStepPartListEntry *> *) entriesForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(entries(forVisibleStepOf:));

/// Whether a list should be shown for the model's visible step. The preference
/// must be on. A `PLI SHOW FALSE` in force for the step then hides it, read
/// with the same scope rules as every other LPub meta. Steps view mode is not
/// checked.
+ (BOOL) isShownForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(isShown(forVisibleStepOf:));


// MARK: - Host-injected preferences
//
// LDrawFeatures never reads NSUserDefaults. The host pushes these values in.

/// Whether the parts list is shown at all. Default NO.
+ (BOOL) isEnabled;
+ (void) setEnabled:(BOOL)flag;

/// Whether a reference to a submodel or peer file gets a row of its own, never
/// its contents. Default NO. A part-like submodel always gets a row.
+ (BOOL) includesSubmodels;
+ (void) setIncludesSubmodels:(BOOL)flag;

/// Whether a model is a part rather than an assembly. True when its header
/// says so, or when it holds nothing but primitives, subparts, raw geometry,
/// LSynth hoses and bands, and submodels that are themselves part-like. One
/// catalog part makes it an assembly. An empty model and nil are not parts.
+ (BOOL) isPartLikeModel:(nullable LDrawModel *)model NS_SWIFT_NAME(isPartLike(_:));

/// Whether the icons follow the step's own rotation, so they match the
/// assembly beside them. When NO they hold one fixed angle for the whole
/// document, like LPub3D's `PLI VIEW_ANGLE`. Default YES.
+ (BOOL) followsStepRotation;
+ (void) setFollowsStepRotation:(BOOL)flag;

/// Whether the viewport shows LPub3D's printed page. Default NO. When on, the
/// zoom sets how many points a page inch covers, and the list is sized in
/// those. When off, the icons keep a fixed size.
+ (BOOL) usesLPubScale;
+ (void) setUsesLPubScale:(BOOL)flag;

/// The base orientation of each part, from LPub3D's PLI control file, or nil.
/// Default nil. Used only when the icons do not follow the step's rotation.
+ (nullable LDrawPartListOrientations *) partOrientations;
+ (void) setPartOrientations:(nullable LDrawPartListOrientations *)orientations
	NS_SWIFT_NAME(setPartOrientations(_:));

/// The range a dragged width is clamped to. Below the minimum an icon is too
/// small to read; above the maximum the frame fills the view.
+ (double) minimumWidthInInches;
+ (double) maximumWidthInInches;

/// The least a pinned height may be dragged to. Lower than the width's minimum,
/// because LPub3D files pin heights well under an inch. The most is
/// `maximumWidthInInches`.
+ (double) minimumHeightInInches;

@end

NS_ASSUME_NONNULL_END
