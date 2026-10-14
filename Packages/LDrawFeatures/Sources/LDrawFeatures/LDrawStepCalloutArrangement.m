//==============================================================================
//
//  File:       LDrawStepCalloutArrangement.m
//  Package:    LDrawFeatures
//
//  Purpose:    Keeps the sides the callouts' boxes have taken in a turn, and
//              the moves that are under way.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import "LDrawStepCalloutArrangementInternal.h"

#import <LDrawCore/LPubCallout.h>
#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>


/// How long a box takes to move to a new place, in seconds.
static const NSTimeInterval MOVE_SECONDS = 0.3;

/// A box nearer its place than this, in page inches, has arrived.
static const double ARRIVED_INCHES = 0.001;


@implementation LDrawStepCalloutSeat
@end


@implementation LDrawStepCalloutArrangement
{
	/// The seat of each callout, by its BEGIN line, and those lines in the
	/// order of the boxes of the last layout.
	NSMapTable<LPubCallout *, LDrawStepCalloutSeat *>	*seats;
	NSArray<LPubCallout *>								*seated;

	/// YES when the sides kept are those of boxes that are put by
	/// themselves, which are numbered differently.
	BOOL												 hasAutomaticSides;
}

//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		NSPointerFunctionsOptions weakObjects = NSPointerFunctionsWeakMemory
											  | NSPointerFunctionsObjectPointerPersonality;

		self->seats				= [NSMapTable mapTableWithKeyOptions:weakObjects
														valueOptions:NSPointerFunctionsStrongMemory];
		self->seated			= @[];
		self->_usesFileSides	= YES;
	}
	return self;

}//end init


//========== reset =============================================================
- (void) reset
{
	[self->seats removeAllObjects];

	self->seated			= @[];
	self->_usesFileSides	= YES;
	self->_isAtRest			= NO;
	self->_isHolding		= NO;

}//end reset


//========== isMoving ==========================================================
- (BOOL) isMoving
{
	for (LDrawStepCalloutSeat *seat in [self->seats objectEnumerator]) {
		Point2 lag = [self lagOfSeat:seat];

		if (hypot(lag.x, lag.y) > ARRIVED_INCHES) {
			return YES;
		}
	}

	return NO;

}//end isMoving


//========== useSidesPlacedAutomatically: ======================================
- (void) useSidesPlacedAutomatically:(BOOL)isAutomatic
{
	if (isAutomatic != self->hasAutomaticSides) {
		[self reset];

		self->hasAutomaticSides = isAutomatic;
	}

}//end useSidesPlacedAutomatically:


//========== seatsOfBoxes: =====================================================
- (NSArray<LDrawStepCalloutSeat *> *) seatsOfBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
{
	NSMutableArray<LPubCallout *>			*lines	= [NSMutableArray arrayWithCapacity:boxes.count];
	NSMutableArray<LDrawStepCalloutSeat *>	*found	= [NSMutableArray arrayWithCapacity:boxes.count];

	for (LDrawStepCalloutBox *box in boxes) {
		[lines addObject:box.callout.beginDirective];
	}

	// Compared by identity: two BEGIN lines read the same.
	BOOL isSame = (lines.count == self->seated.count);

	for (NSUInteger index = 0; isSame && index < lines.count; index++) {
		isSame = (lines[index] == self->seated[index]);
	}

	if (isSame == NO) {
		[self reset];
		self->seated = lines;
	}

	for (LPubCallout *line in lines) {
		LDrawStepCalloutSeat *seat = [self->seats objectForKey:line];

		if (seat == nil) {
			seat = [[LDrawStepCalloutSeat alloc] init];
			[self->seats setObject:seat forKey:line];
		}
		[found addObject:seat];
	}

	return found;

}//end seatsOfBoxes:


//========== lagOfSeat: ========================================================
///
/// @abstract	How far a box still is from its place. It starts slowly and
///				arrives slowly.
///
//==============================================================================
- (Point2) lagOfSeat:(LDrawStepCalloutSeat *)seat
{
	double share	= MAX(0.0, MIN(1.0, (self.time - seat.lagTime) / MOVE_SECONDS));
	double left		= 1.0 - share * share * (3.0 - 2.0 * share);

	return V2Make(seat.lag.x * left, seat.lag.y * left);

}//end lagOfSeat:


//========== setLag:ofSeat: ====================================================
- (void) setLag:(Point2)lag ofSeat:(LDrawStepCalloutSeat *)seat
{
	seat.lag		= lag;
	seat.lagTime	= self.time;

}//end setLag:ofSeat:

@end
