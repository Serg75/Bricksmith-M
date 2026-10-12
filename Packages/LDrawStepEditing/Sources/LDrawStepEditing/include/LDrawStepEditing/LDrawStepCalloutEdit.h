//==============================================================================
//
//  File:       LDrawStepCalloutEdit.h
//  Package:    LDrawStepEditing
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawContainer;
@class LDrawDirective;
@class LDrawModel;
@class LDrawStep;
@class LDrawStepCallout;
@class LDrawStepCalloutBox;
@class LDrawStepPartListEntry;
@class LPubCommand;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepCalloutEditKind
///
/// @abstract   What a change to a callout means for the document.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepCalloutEditKind) {
	/// The document already says this, so nothing is changed.
	LDrawStepCalloutEditKindNone	= 0,
	LDrawStepCalloutEditKindInsert	= 1,
	LDrawStepCalloutEditKindUpdate	= 2,
	/// Lines are taken out of the step and put into it. For adding and for
	/// removing a callout or a divider.
	LDrawStepCalloutEditKindRewrite	= 3
};


//------------------------------------------------------------------------------
///
/// @protocol   LDrawStepCalloutEditHost
///
/// @abstract   The three changes an edit is made of. The host makes each of
///             them in a way that can be undone.
///
//------------------------------------------------------------------------------
@protocol LDrawStepCalloutEditHost <NSObject>

/// Puts a directive into a container, at an index.
- (void) addDirective:(LDrawDirective *)newDirective toParent:(LDrawContainer *)parent atIndex:(NSInteger)index;

/// Takes a directive out of the file.
- (void) deleteDirective:(LDrawDirective *)doomedDirective;

/// A directive is about to be changed: keeps what it says now, for undo.
- (void) preserveDirectiveState:(LDrawDirective *)directive;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutEdit
///
/// @abstract   Decides what a change to a callout writes to the document,
///             without writing it.
///
/// @discussion The host owns the undo manager and makes the change. A dragged
///             box changes the offset of its PLACEMENT line, or gets a line
///             when it has none. Calling a submodel out puts its placements
///             between a BEGIN and an END line, and removing a callout takes
///             those lines out again. A divider is a line in the called-out
///             submodel, at the top of the step that starts a column or row.
///             The way a callout's steps run is an ALLOC line of its own.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutEdit : NSObject

- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly) LDrawStepCalloutEditKind	kind;

/// The line to insert, for `Insert`, and where in the step it goes: just
/// before the callout's END line.
@property (nonatomic, readonly, nullable) LPubCommand		*directiveToInsert;
@property (nonatomic, readonly) NSUInteger					insertIndex;

/// The line to change, for `Update`, and the text to give it.
@property (nonatomic, readonly, nullable) LPubCommand		*existingDirective;
@property (nonatomic, readonly, copy, nullable) NSString	*commandString;

/// For `Rewrite`: the directives to take out first, in this order, and then
/// the directives to put into the step, each at its index, in this order. A
/// directive in both lists is moved.
@property (nonatomic, readonly) NSArray<LDrawDirective *>	*directivesToRemove;
@property (nonatomic, readonly) NSArray<LDrawDirective *>	*directivesToInsert;
@property (nonatomic, readonly) NSArray<NSNumber *>			*insertIndexes;

/// The step the lines of a `Rewrite` go into, when that is not the step the
/// callout is in. A divider goes into a step of the called-out submodel. Nil
/// for the callout's own step.
@property (nonatomic, readonly, nullable) LDrawStep			*targetStep;

/// Undo action key. The host localizes it.
@property (nonatomic, readonly, copy) NSString				*undoActionKey;

/// Makes the change through a host. `step` is the step the callout is in.
/// Returns NO when nothing was changed.
- (BOOL) applyToStep:(nullable LDrawStep *)step host:(id<LDrawStepCalloutEditHost>)host
	NS_SWIFT_NAME(apply(to:host:));

/// The edit that leaves a callout's box with its corner at `origin`, a point
/// of the view. `step` is the step the callout is in.
+ (instancetype) editMovingBox:(LDrawStepCalloutBox *)box
					  toOrigin:(Point2)origin
						inStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(edit(movingBox:toOrigin:inStep:));

/// The edit that calls out the submodel a row of the parts list shows, in the
/// model's visible step. Every placement the row counts goes between one BEGIN
/// and one END line, followed by an arrow for each. Placements with other
/// lines between them are brought together. Nothing to do when the row is no
/// submodel with steps, or the step places it only inside callouts.
+ (instancetype) editCallingOutEntry:(LDrawStepPartListEntry *)entry inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(callingOut:inModel:));

/// The edit that removes a callout: its two lines, its arrows, its PLACEMENT,
/// and the lines between the two that hold for it alone. The parts stay, and
/// so does a styling line with no LOCAL, which later callouts go by.
+ (instancetype) editRemovingCallout:(LDrawStepCallout *)callout NS_SWIFT_NAME(edit(removing:));

/// The edit that puts a divider before a step of a called-out submodel: one
/// DIVIDER line at the top of the step, where LPub3D writes it. The step then
/// starts a column or row in every callout that shows the submodel. Nothing to
/// do for the first step shown, a step that builds nothing, or a step that has
/// a divider.
+ (instancetype) editAddingDividerBeforeStep:(LDrawStep *)step NS_SWIFT_NAME(edit(addingDividerBefore:));

/// The edit that takes the divider before a step out: its DIVIDER lines and
/// the lines of its arrows. Nothing to do for a step with no divider.
+ (instancetype) editRemovingDividerBeforeStep:(LDrawStep *)step NS_SWIFT_NAME(edit(removingDividerBefore:));

/// The edit that makes the steps in a callout's box run down, or across. It
/// is for this callout alone: the line it writes says LOCAL, which LPub3D
/// drops at the end of the step, where a line with no LOCAL is followed by the
/// callouts of every later step. A callout that has such a line of its own
/// gets it changed, or taken out when the callout then runs the way wanted
/// without it. Where later steps go by an ALLOC line further down the step,
/// the line written has no LOCAL: LOCAL would end that line with the step
/// too. Nothing to do for a callout that runs that way already.
+ (instancetype) editArrangingStepsOfCallout:(LDrawStepCallout *)callout vertically:(BOOL)isVertical
	NS_SWIFT_NAME(edit(arrangingStepsOf:vertically:));

/// Where an arrow to a model point points, as LPub3D writes a tip: a share of
/// the box around these outline points, from its top left, with the points
/// seen straight on from `view`. The middle when there is nothing to measure.
+ (Point2) tipForModelPoint:(Point3)point inOutline:(nullable NSData *)outlinePoints view:(Matrix4)view
	NS_SWIFT_NAME(tip(forModelPoint:inOutline:view:));

@end

NS_ASSUME_NONNULL_END
