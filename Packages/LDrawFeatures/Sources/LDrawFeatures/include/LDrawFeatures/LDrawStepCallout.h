//==============================================================================
//
//  File:       LDrawStepCallout.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubCallout.h>

@class LDrawDirective;
@class LDrawModel;
@class LDrawPart;
@class LDrawStep;
@class LDrawStepPartListEntry;
@class LPubPlacement;
@class LPubCalloutPointer;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCallout
///
/// @abstract   One callout of a step: the submodels placed between a
///             `0 !LPUB CALLOUT BEGIN` and its END, and the lines that go with
///             them.
///
/// @discussion A callout takes a submodel out of its parent step and shows it
///             in a box of its own. A part between the two lines that places
///             no submodel is an ordinary part of the step.
///
///             Immutable. Collect again when the file changes.
///
//------------------------------------------------------------------------------
@interface LDrawStepCallout : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// The callouts of a step that place at least one submodel, in file order.
/// Empty when `step` is nil.
+ (NSArray<LDrawStepCallout *> *) calloutsForStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(callouts(forStep:));

/// The callouts of the step the model has on display.
+ (NSArray<LDrawStepCallout *> *) calloutsForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(callouts(forVisibleStepOf:));

/// The parts of a step that a submodel's row of the parts list counts, in file
/// order: each places that submodel, in that color. A placement inside a
/// callout or an ignored range is no part of the row, and neither is one
/// inside a group. Empty for a row that is no submodel.
+ (NSArray<LDrawPart *> *) placementsOfEntry:(LDrawStepPartListEntry *)entry inStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(placements(of:inStep:));

/// Whether a step holds a part, a hose or a band that no REMOVE GROUP in force
/// drops. A callout shows only the
/// steps of a submodel that do.
+ (BOOL) stepBuildsSomething:(LDrawStep *)step NS_SWIFT_NAME(stepBuildsSomething(_:));

/// The step of a called-out submodel a callout shows before another: the
/// nearest earlier step that builds something. Nil for the first one shown.
+ (nullable LDrawStep *) stepShownBeforeStep:(LDrawStep *)step NS_SWIFT_NAME(stepShown(before:));

/// The lines that put a divider before a step of a called-out submodel, in
/// file order. They are the DIVIDER lines between the first thing built in the
/// step shown before it and the first thing built in this one, and with them
/// the DIVIDER_POINTER lines there, which give the divider its arrows. Empty
/// when no DIVIDER line is there, and for the first step shown, which starts a
/// column or row anyway.
+ (NSArray<LDrawDirective *> *) dividerLinesBeforeStep:(LDrawStep *)step NS_SWIFT_NAME(dividerLines(before:));

/// The step the callout is in. Nil once the step is gone.
@property (nonatomic, readonly, weak, nullable) LDrawStep *step;

/// The BEGIN line, and the END line when the callout is closed.
@property (nonatomic, readonly) LPubCallout				*beginDirective;
@property (nonatomic, readonly, nullable) LPubCallout	*endDirective;

/// What the box shows of its submodels: their steps, or one finished picture.
@property (nonatomic, readonly) LPubCalloutMode			mode;

/// One row per submodel and color, with how many times it is placed, in the
/// order placed. Each row carries the submodel's outline.
@property (nonatomic, readonly) NSArray<LDrawStepPartListEntry *> *entries;

/// The submodel each entry shows, in the same order.
@property (nonatomic, readonly) NSArray<LDrawModel *>	*submodels;

/// The parts that place those submodels, in file order. An arrow goes to each.
@property (nonatomic, readonly) NSArray<LDrawPart *>	*placements;

/// The arrows the file gives the box, in file order. May be empty.
@property (nonatomic, readonly) NSArray<LPubCalloutPointer *> *pointers;

/// The callout's own PLACEMENT line, or nil when it has none.
@property (nonatomic, readonly, nullable) LPubPlacement *placement;

/// Every LPub line between the callout's two lines, in file order.
@property (nonatomic, readonly) NSArray<LDrawDirective *> *ownLines;

/// How many steps of the submodels build something.
@property (nonatomic, readonly) NSUInteger				stepCount;

/// Whether the steps in the box run down. NO when they run across. Down is
/// LPub3D's choice for a file that says nothing.
@property (nonatomic, readonly) BOOL					isVertical;

/// Whether the steps in the box are numbered. NO when the file turns step
/// numbers off.
@property (nonatomic, readonly) BOOL					showsStepNumbers;

/// Whether the box lists its submodels' parts itself. NO when the step's own
/// list has them, and for a callout that shows its submodels finished.
@property (nonatomic, readonly) BOOL					listsOwnParts;

/// The parts the box lists itself: every step of each submodel, once for each
/// placement. Empty unless `listsOwnParts`.
@property (nonatomic, readonly) NSArray<LDrawStepPartListEntry *> *partEntries;

/// The line of one kind in force for this callout, read as LPub3D reads it,
/// or nil. A line between the callout's own two lines wins. After that come
/// the step's lines before the callout, then what earlier steps carry. A line
/// inside another callout of the same step does not count.
- (nullable __kindof LDrawDirective *) directiveInForceMatching:(BOOL (NS_NOESCAPE ^)(LDrawDirective *))predicate
	NS_SWIFT_NAME(directiveInForce(matching:));

@end

NS_ASSUME_NONNULL_END
