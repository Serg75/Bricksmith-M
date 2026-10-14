//==============================================================================
//
//  File:       LDrawStepCalloutArrangementInternal.h
//  Package:    LDrawFeatures
//
//  Purpose:    What an arrangement keeps for each box, for the code that
//              moves the boxes.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawCore/MatrixMath.h>
#import <LDrawFeatures/LDrawStepCalloutArrangement.h>

@class LDrawStepCalloutBox;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutSeat
///
/// @abstract   What an arrangement keeps for one box. Lengths are page
///             inches, and places are measured from the page's corner, so
///             they hold through a pan and a zoom.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutSeat : NSObject

/// Which side of its submodel the box is on: 0 for the file's, 1 to 3 for
/// the mirrored ones. For a box that is put by itself, which of its eight
/// places it is in.
@property (nonatomic) NSUInteger		side;

/// The rectangles the box's sides are read from: where it was to go, and the
/// box around each placement its arrows went to as Box2 values, when it took
/// its side. Not read while the arrangement uses the file's sides.
@property (nonatomic) Box2				reference;
@property (nonatomic, copy, nullable) NSData *referenceTargets;

/// How far the box was from its place at `lagTime`. It closes that distance
/// over the time a move takes.
@property (nonatomic) Point2			lag;
@property (nonatomic) NSTimeInterval	lagTime;

/// Where the box's corner was drawn in the last layout.
@property (nonatomic) BOOL				hasShown;
@property (nonatomic) Point2			shown;

@end


@interface LDrawStepCalloutArrangement ()

/// YES while the boxes keep to the sides the file's layout puts them on. NO
/// once they have taken sides of their own, which their seats keep. Setting
/// it leaves the moves under way alone.
@property (nonatomic) BOOL usesFileSides;

/// Says which boxes the next layout is for: ones that are put by themselves,
/// or ones the file places. The two number their sides differently, so when
/// this changes, everything is forgotten first.
- (void) useSidesPlacedAutomatically:(BOOL)isAutomatic;

/// YES from the first layout at the angle the step was laid out at until the
/// camera is turned again. The boxes set out for the file's places once, at
/// the first.
@property (nonatomic) BOOL isAtRest;

/// YES while a box is held by a drag in a turned view. The other boxes stay
/// where they are until it is let go, and are arranged again then.
@property (nonatomic) BOOL isHolding;

/// The seat of each box, in order, made when it has none. When the callouts
/// are others than in the last layout, everything is forgotten first.
- (NSArray<LDrawStepCalloutSeat *> *) seatsOfBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes;

/// How far a box still is from its place at `time`.
- (Point2) lagOfSeat:(LDrawStepCalloutSeat *)seat;

/// Has a box start a move from this far off its place, at `time`.
- (void) setLag:(Point2)lag ofSeat:(LDrawStepCalloutSeat *)seat;

@end

NS_ASSUME_NONNULL_END
