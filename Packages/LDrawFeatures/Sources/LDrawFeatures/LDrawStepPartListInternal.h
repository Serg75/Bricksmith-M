//==============================================================================
//
//  File:       LDrawStepPartListInternal.h
//  Package:    LDrawFeatures
//
//  Purpose:    The parts of the collector that the callout code shares.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartList.h>

@class LDrawColor;
@class LDrawDirective;
@class LDrawPart;
@class LDrawPartLibrary;

NS_ASSUME_NONNULL_BEGIN

@interface LDrawStepPartList (Internal)

/// The directives in order, with every container opened in place except a hose
/// or band.
+ (NSArray<LDrawDirective *> *) flattenedDirectives:(NSArray<LDrawDirective *> *)directives;

/// Whether a directive is built in this step. NO when a REMOVE GROUP in force
/// drops it.
+ (BOOL) isBuiltDirective:(LDrawDirective *)directive;

/// The submodel or peer file a part places, or nil.
+ (nullable LDrawModel *) submodelForPart:(LDrawPart *)part library:(nullable LDrawPartLibrary *)library;

/// The submodel a part places, or nil when it places none or one that is
/// really a part.
+ (nullable LDrawModel *) assemblyPlacedByPart:(LDrawPart *)part;

/// The key of the row a part that places a submodel is counted in. Nothing is
/// measured for it.
+ (NSString *) rowKeyOfPlacement:(LDrawPart *)part;

/// The rows the submodels these parts place would add to a list: every step of
/// each submodel, once for each part. `model` is the model the parts are in.
+ (NSArray<LDrawStepPartListEntry *> *) entriesForSubmodelsPlacedByParts:(NSArray<LDrawPart *> *)parts
																 inModel:(nullable LDrawModel *)model;

/// Entries for one step of a submodel, in display order. Its parts in the main
/// color take `color`, the color the submodel is placed in.
+ (NSArray<LDrawStepPartListEntry *> *) entriesForStep:(LDrawStep *)step
									   inheritingColor:(nullable LDrawColor *)color;

/// The points every part of one step reaches furthest out to, as Point3 values
/// in its model's own coordinates. Empty with no catalog.
+ (NSData *) outlinePointsOfStep:(LDrawStep *)step;

/// The points every part inside a model reaches furthest out to, or nil with
/// no model or no catalog.
+ (nullable NSData *) outlinePointsOfModel:(nullable LDrawModel *)submodel;

/// A part's color, or `inheritedColor` when the part is in the main color.
+ (nullable LDrawColor *) colorOfPart:(LDrawPart *)part inheriting:(nullable LDrawColor *)inheritedColor;

/// A one-instance row that shows a whole submodel as one part, with its
/// outline. Listed whatever the submodel preference says.
+ (LDrawStepPartListEntry *) entryForSubmodel:(LDrawModel *)submodel
										named:(NSString *)name
										color:(nullable LDrawColor *)color;

@end

NS_ASSUME_NONNULL_END
