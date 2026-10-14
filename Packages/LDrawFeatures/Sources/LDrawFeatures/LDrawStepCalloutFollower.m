//==============================================================================
//
//  File:       LDrawStepCalloutFollower.m
//  Package:    LDrawFeatures
//
//  Purpose:    Moves the callouts' boxes on a page with their submodels.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import "LDrawStepCalloutFollower.h"

#import <LDrawFeatures/LDrawStepCalloutStyle.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

#import "LDrawStepCalloutArrangementInternal.h"
#import "LDrawStepCalloutContent.h"


/// How far over the page's edge a box may reach and still be on the page, in
/// page inches. A box is not drawn to LPub3D's exact size, so one put at the
/// edge may reach a little over it.
static const double PAGE_EDGE_TOLERANCE_INCHES = 0.1;

/// How far a box stays from the placement its own arrow goes to, in page
/// inches: room for the arrow's head and some of its line.
static const double OWN_ARROW_ROOM_INCHES = 0.5;

/// The least of that a box keeps once it has taken a side of its own, in page
/// inches: the length of an arrow's head. The file may have it nearer.
static const double LEAST_ARROW_ROOM_INCHES = 5.0 / 16.0;

/// How much more than its margin a box keeps to where another box's arrow
/// goes, in page inches: half the width of an arrow's head.
static const double ARROW_HEAD_ROOM_INCHES = 1.0 / 16.0;

/// How many times the boxes are moved off the arrows and apart. Each time
/// halves what is left to move.
static const NSUInteger SEPARATION_ROUNDS = 16;

/// How far limits may cross, in points, and still leave a thing its place.
static const double LIMIT_SLACK = 0.01;

/// What is wrong with a way of putting the boxes, in page inches of cost:
/// for each inch a box is from its place beside its submodel, for each inch
/// of an arrow under a box, for each inch a box reaches over a placement
/// another box's arrow goes to, and for each inch an arrow is short of its
/// room.
static const double AWAY_COST	= 1.0;
static const double OVER_COST	= 4.0;
static const double COVER_COST	= 2.0;
static const double SHORT_COST	= 2.0;

/// The cost of a box that is not on the file's side of its submodel, of an
/// arrow whose placement is under its own box, and of two arrows that cross.
static const double OTHER_SIDE_COST	= 0.75;
static const double HIDDEN_COST		= 4.0;
static const double CROSSING_COST	= 0.5;

/// For boxes that are put by themselves: the cost of each inch a box is from
/// what it calls out, and of each inch it reaches over the step's assembly.
static const double REACH_COST		= 0.5;
static const double ASSEMBLY_COST	= 1.0;

/// Boxes that cost no more than this are left as they are. Others change
/// sides when that takes off this much, and this share of the cost.
static const double SETTLED_COST	= 0.3;
static const double CHANGE_SHARE	= 0.25;

/// The sides of its submodel a box may be on: the file's, and that side
/// mirrored across, up and down, and both.
static const NSUInteger OWN_SIDE_COUNT = 4;

/// The places a box that is put by itself may be in: beside the assembly on
/// each of its four sides, and beside what it calls out on each of four.
static const NSUInteger AUTOMATIC_SIDE_COUNT = 8;

/// With more ways to put the boxes than this, the sides are tried a box at a
/// time, and not every way together.
static const NSUInteger FULL_SEARCH_WAYS = 256;

enum { AxisX, AxisY, AxisCount };


//------------------------------------------------------------------------------
///
/// @struct     Extent
///
/// @abstract   A rectangle, as where it starts and ends along x and y.
///
//------------------------------------------------------------------------------
typedef struct Extent
{
	double	min[AxisCount];
	double	max[AxisCount];

} Extent;


//------------------------------------------------------------------------------
///
/// @struct     Side
///
/// @abstract   The side of another thing that a thing is on: along which
///             axis, whether it comes after the other there, and the gap
///             between the two. The gap is below 0 for two things that
///             overlap.
///
//------------------------------------------------------------------------------
typedef struct Side
{
	NSUInteger	axis;
	BOOL		isAfter;
	double		gap;

} Side;


//------------------------------------------------------------------------------
///
/// @struct     Rooms
///
/// @abstract   The room a box keeps to the arrows, in points: to where its own
///             go, the least of that on a side of its own, and more than its
///             margin to where another's go.
///
//------------------------------------------------------------------------------
typedef struct Rooms
{
	double	own;
	double	least;
	double	head;

} Rooms;


//------------------------------------------------------------------------------
///
/// @struct     Segment
///
/// @abstract   A straight line from one point to another.
///
//------------------------------------------------------------------------------
typedef struct Segment
{
	Point2	from;
	Point2	to;

} Segment;


//------------------------------------------------------------------------------
///
/// @struct     FollowedBox
///
/// @abstract   One thing on the page: a callout's box, or the parts list.
///
//------------------------------------------------------------------------------
typedef struct FollowedBox
{
	/// Where the file puts it, and its size.
	Extent			 placed;
	double			 size[AxisCount];

	/// The room it keeps to other things: its MARGINS, in points.
	double			 margin[AxisCount];

	/// NO for the parts list and for a box off the page, which stay.
	BOOL			 moves;

	/// The box around the step's assembly, for a box that is put beside it
	/// by itself, and the room such a box keeps to where its arrows go. NULL
	/// for a box the file places.
	const Extent	*assembly;
	double			 arrowRoom;

	/// YES for a box a drag holds, which is drawn where it is held.
	BOOL			 isHeld;

	/// How far its corner may go on the page. Both are the placed corner for
	/// a thing that stays.
	double			 pageLow[AxisCount];
	double			 pageHigh[AxisCount];

	/// Where the middle of what it places is drawn, now and as the step was
	/// laid out. `hasMiddle` is NO for a thing that follows nothing.
	BOOL			 hasMiddle;
	Point2			 middle;
	Point2			 laidOutMiddle;

	/// The box around each placement one of its arrows goes to, now and as
	/// the step was laid out.
	const Box2		*targets;
	const Box2		*laidOutTargets;
	NSUInteger		 targetCount;

	// Set for the sides the boxes are tried on:

	/// The rectangles its sides are read from: itself, where its arrows go,
	/// and the box around them all.
	Extent			 reference;
	const Box2		*referenceTargets;
	Extent			 reach;

	/// The side of its submodel it is on, and where that has its corner: its
	/// place beside its submodel, which it sets out from.
	NSUInteger		 side;
	double			 start[AxisCount];

	// Worked out for those sides:

	/// How far its corner may go.
	double			 low[AxisCount];
	double			 high[AxisCount];

	/// How far its corner may go and be clear of the arrows.
	double			 clearLow[AxisCount];
	double			 clearHigh[AxisCount];

	/// Where its corner goes.
	double			 origin[AxisCount];

} FollowedBox;


//------------------------------------------------------------------------------
///
/// @struct     BoxOrder
///
/// @abstract   Two things that are one after the other along x or y, and stay
///             in that order.
///
//------------------------------------------------------------------------------
typedef struct BoxOrder
{
	NSUInteger	axis;
	NSUInteger	first;
	NSUInteger	second;

	/// How far the second corner stays after the first at least.
	double		distance;

} BoxOrder;


//------------------------------------------------------------------------------
///
/// @enum       SidesKind
///
/// @abstract   Which sides the boxes keep to: the ones they have, the file's,
///             or new ones of their own.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSUInteger, SidesKind)
{
	SidesKept,
	SidesOfFile,
	SidesTaken
};


// MARK: - RECTANGLES -


//========== Clamped() =========================================================
static double Clamped(double value, double low, double high)
{
	return MAX(low, MIN(high, value));

}//end Clamped


//========== ExtentOfBox() =====================================================
static Extent ExtentOfBox(Box2 rect)
{
	Extent extent;

	extent.min[AxisX] = V2BoxMinX(rect);
	extent.min[AxisY] = V2BoxMinY(rect);
	extent.max[AxisX] = V2BoxMaxX(rect);
	extent.max[AxisY] = V2BoxMaxY(rect);

	return extent;

}//end ExtentOfBox


//========== ExtentAt() ========================================================
static Extent ExtentAt(const double *corner, const double *size)
{
	Extent extent;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		extent.min[axis] = corner[axis];
		extent.max[axis] = corner[axis] + size[axis];
	}

	return extent;

}//end ExtentAt


//========== FindSide() ========================================================
///
/// @abstract	The side of `other` that `one` is on, where the gap between
/// 			them is widest. NO when they overlap.
///
//==============================================================================
static BOOL FindSide(Extent one, Extent other, Side *outSide)
{
	Side side = { 0, NO, -1.0 };

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		double gapBefore	= other.min[axis] - one.max[axis];
		double gapAfter		= one.min[axis] - other.max[axis];

		if (gapBefore > side.gap) {
			side = (Side){ axis, NO, gapBefore };
		}
		if (gapAfter > side.gap) {
			side = (Side){ axis, YES, gapAfter };
		}
	}

	if (side.gap < 0.0) {
		return NO;
	}

	*outSide = side;
	return YES;

}//end FindSide


//========== SideOfMiddle() ====================================================
///
/// @abstract	The side of `other` that the middle of `one` is on, for two
/// 			things that overlap: along the axis where the middles are
/// 			further apart for the sizes of the two.
///
//==============================================================================
static Side SideOfMiddle(Extent one, Extent other)
{
	Side	side		= { AxisX, NO, -1.0 };
	double	furthest	= -1.0;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		double apart	= (one.min[axis] + one.max[axis] - other.min[axis] - other.max[axis]) / 2.0;
		double span		= (one.max[axis] - one.min[axis]) + (other.max[axis] - other.min[axis]);
		double share	= (span > 0.0) ? fabs(apart) / span : 0.0;

		if (share > furthest) {
			furthest	= share;
			side		= (Side){ axis, (apart > 0.0), -1.0 };
		}
	}

	return side;

}//end SideOfMiddle


//========== FindCrossing() ====================================================
///
/// @abstract	Where a line goes through a rectangle: how far along the line
/// 			it comes in and goes out, as shares of the line. NO when it
/// 			stays outside.
///
//==============================================================================
static BOOL FindCrossing(Segment line, Extent extent, double *outEnter, double *outLeave)
{
	double from[AxisCount]	= { line.from.x, line.from.y };
	double along[AxisCount]	= { line.to.x - line.from.x, line.to.y - line.from.y };
	double enter			= 0.0;
	double leave			= 1.0;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		if (along[axis] == 0.0) {
			if (from[axis] < extent.min[axis] || from[axis] > extent.max[axis]) {
				return NO;
			}
			continue;
		}

		double atMin = (extent.min[axis] - from[axis]) / along[axis];
		double atMax = (extent.max[axis] - from[axis]) / along[axis];

		enter = MAX(enter, MIN(atMin, atMax));
		leave = MIN(leave, MAX(atMin, atMax));
	}

	if (enter >= leave) {
		return NO;
	}

	*outEnter = enter;
	*outLeave = leave;
	return YES;

}//end FindCrossing


//========== Turn() ============================================================
///
/// @abstract	Which way the corner at `middle` turns on the way from `first`
/// 			to `last`: above 0 one way, below 0 the other.
///
//==============================================================================
static double Turn(Point2 first, Point2 middle, Point2 last)
{
	return (middle.x - first.x) * (last.y - first.y) - (middle.y - first.y) * (last.x - first.x);

}//end Turn


//========== Cross() ===========================================================
///
/// @abstract	Whether two lines cross, each with its ends on either side of
/// 			the other.
///
//==============================================================================
static BOOL Cross(Segment one, Segment other)
{
	return Turn(one.from, one.to, other.from) * Turn(one.from, one.to, other.to) < 0.0
		&& Turn(other.from, other.to, one.from) * Turn(other.from, other.to, one.to) < 0.0;

}//end Cross


// MARK: - THE THINGS ON THE PAGE -


//========== MakeFollowedBox() =================================================
///
/// @abstract	A thing on the page that stays where the file puts it, and
/// 			follows nothing.
///
//==============================================================================
static FollowedBox MakeFollowedBox(Box2 rect, Size2 margin)
{
	FollowedBox box = {0};

	box.placed			= ExtentOfBox(rect);
	box.margin[AxisX]	= margin.width;
	box.margin[AxisY]	= margin.height;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		box.size[axis]		= box.placed.max[axis] - box.placed.min[axis];
		box.pageLow[axis]	= box.placed.min[axis];
		box.pageHigh[axis]	= box.placed.min[axis];
	}

	return box;

}//end MakeFollowedBox


//========== GivePlaces() ======================================================
///
/// @abstract	Tells a box where what it places is drawn, now and as the step
/// 			was laid out: the middle first, then where its arrows go.
///
//==============================================================================
static void GivePlaces(FollowedBox *box, NSData *places, NSData *laidOutPlaces)
{
	const Box2	*now	= places.bytes;
	const Box2	*then	= laidOutPlaces.bytes;
	NSUInteger	 count	= MIN(places.length, laidOutPlaces.length) / sizeof(Box2);

	if (count == 0) {
		return;
	}

	box->hasMiddle		= YES;
	box->middle			= now[0].origin;
	box->laidOutMiddle	= then[0].origin;
	box->targets		= now + 1;
	box->laidOutTargets	= then + 1;
	box->targetCount	= count - 1;

}//end GivePlaces


//========== LetMoveOnPage() ===================================================
///
/// @abstract	Lets a box move over the page, the larger of its margin and
/// 			the page's from the edges. A box the file puts more than
/// 			`tolerance` over an edge is left to stay.
///
/// @discussion	A box the file puts nearer an edge, or a little over it, may go
/// 			back there.
///
//==============================================================================
static void LetMoveOnPage(FollowedBox *box, Box2 pageRect, double pageMargin, double tolerance)
{
	Extent page = ExtentOfBox(pageRect);

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		if (box->placed.min[axis] < page.min[axis] - tolerance
			|| box->placed.max[axis] > page.max[axis] + tolerance) {
			return;
		}
	}

	box->moves = YES;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		double room = MAX(box->margin[axis], pageMargin);

		box->pageLow[axis]	= MIN(page.min[axis] + room, box->placed.min[axis]);
		box->pageHigh[axis]	= MAX(page.max[axis] - room - box->size[axis], box->placed.min[axis]);
	}

}//end LetMoveOnPage


//========== LetMoveOverPage() =================================================
///
/// @abstract	Lets a box that is put by itself move over the whole page, the
/// 			larger of its margin and the page's from the edges.
///
//==============================================================================
static void LetMoveOverPage(FollowedBox *box, Box2 pageRect, double pageMargin)
{
	Extent page = ExtentOfBox(pageRect);

	box->moves = YES;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		double room = MAX(box->margin[axis], pageMargin);

		box->pageLow[axis]	= page.min[axis] + room;
		box->pageHigh[axis]	= MAX(box->pageLow[axis], page.max[axis] - room - box->size[axis]);
	}

}//end LetMoveOverPage


//========== AimOfBox() ========================================================
///
/// @abstract	Where a box points: the middle of where its arrows go, or of
/// 			what it places when it has no arrow.
///
//==============================================================================
static Point2 AimOfBox(const FollowedBox *box)
{
	Point2 sum = ZeroPoint2;

	for (NSUInteger index = 0; index < box->targetCount; index++) {
		sum = V2Add(sum, V2BoxMid(box->targets[index]));
	}

	if (box->targetCount > 0) {
		return V2Make(sum.x / box->targetCount, sum.y / box->targetCount);
	}
	if (box->hasMiddle) {
		return box->middle;
	}

	return V2Make((box->placed.min[AxisX] + box->placed.max[AxisX]) / 2.0,
				  (box->placed.min[AxisY] + box->placed.max[AxisY]) / 2.0);

}//end AimOfBox


//========== FindAutomaticCorner() =============================================
///
/// @abstract	Where the corner of a box is that is put by itself, in one of
/// 			its eight places.
///
/// @discussion	The first four are beside the step's assembly: past its side
/// 			to the right, to the left, below and above by the box's margin,
/// 			and level with what the box points at. The box is also as far
/// 			from where its arrows go as an arrow needs, when the assembly's
/// 			side is nearer than that.
///
/// 			The other four are beside what the box points at, that far
/// 			from it, wherever the assembly's sides are. They are for a
/// 			page that leaves no room beside the assembly.
///
//==============================================================================
static void FindAutomaticCorner(const FollowedBox *box, NSUInteger side, double *outCorner)
{
	Point2		aim					= AimOfBox(box);
	double		level[AxisCount]	= { aim.x, aim.y };
	BOOL		isBesideAssembly	= (side < 4);
	NSUInteger	across				= ((side % 4) < 2) ? AxisX : AxisY;
	NSUInteger	along				= (across == AxisX) ? AxisY : AxisX;
	double		nearest				= level[across];
	double		furthest			= level[across];

	for (NSUInteger index = 0; index < box->targetCount; index++) {
		Extent target = ExtentOfBox(box->targets[index]);

		nearest		= MIN(nearest, target.min[across]);
		furthest	= MAX(furthest, target.max[across]);
	}

	if (side % 2 == 0) {
		outCorner[across] = furthest + box->arrowRoom;

		if (isBesideAssembly) {
			outCorner[across] = MAX(outCorner[across], box->assembly->max[across] + box->margin[across]);
		}
	}
	else {
		outCorner[across] = nearest - box->arrowRoom;

		if (isBesideAssembly) {
			outCorner[across] = MIN(outCorner[across], box->assembly->min[across] - box->margin[across]);
		}

		outCorner[across] -= box->size[across];
	}

	outCorner[along] = level[along] - box->size[along] / 2.0;

}//end FindAutomaticCorner


//========== FindWantedCorner() ================================================
///
/// @abstract	Where a box's corner is when the box is beside its submodel:
/// 			as far from the middle of its placements as the file has it.
///
/// @discussion	Side 0 is the file's. The others have the box mirrored about
/// 			that middle: across, up and down, and both.
///
/// 			A box that is put by itself has eight places of its own.
///
//==============================================================================
static void FindWantedCorner(const FollowedBox *box, NSUInteger side, double *outCorner)
{
	if (box->assembly != NULL) {
		FindAutomaticCorner(box, side, outCorner);
		return;
	}

	double middle[AxisCount]	= { box->middle.x, box->middle.y };
	double moved[AxisCount]		= { box->middle.x - box->laidOutMiddle.x, box->middle.y - box->laidOutMiddle.y };

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		outCorner[axis] = box->placed.min[axis];

		if (box->moves == NO || box->hasMiddle == NO) {
			continue;
		}

		outCorner[axis] += moved[axis];

		if ((side >> axis) & 1) {
			outCorner[axis] = 2.0 * middle[axis] - outCorner[axis] - box->size[axis];
		}
	}

}//end FindWantedCorner


//========== OwnArrowRoom() ====================================================
///
/// @abstract	The room a box keeps to where one of its own arrows goes: what
/// 			an arrow needs to show, or what the file leaves it when that
/// 			is less.
///
/// @discussion	On the file's sides that is how the box starts from where the
/// 			file puts it. On a side of its own it keeps the length of an
/// 			arrow's head at least, since the box around a placement is
/// 			another in every view, and may leave an arrow nothing.
///
//==============================================================================
static double OwnArrowRoom(const FollowedBox *box, NSUInteger index, Rooms rooms, BOOL keepsFileGaps)
{
	// The file has no say over a box that is put by itself.
	if (box->assembly != NULL) {
		return rooms.own;
	}

	Side	side		= {0};
	BOOL	isApart		= FindSide(box->placed, ExtentOfBox(box->laidOutTargets[index]), &side);
	double	room		= MIN(rooms.own, isApart ? side.gap : 0.0);

	return keepsFileGaps ? room : MAX(room, rooms.least);

}//end OwnArrowRoom


// MARK: - SIDES -


//========== FindReach() =======================================================
///
/// @abstract	Works out the box around a thing and where its arrows go, as
/// 			its sides are read.
///
//==============================================================================
static void FindReach(FollowedBox *box)
{
	box->reach = box->reference;

	for (NSUInteger index = 0; index < box->targetCount; index++) {
		Extent target = ExtentOfBox(box->referenceTargets[index]);

		for (NSUInteger axis = 0; axis < AxisCount; axis++) {
			box->reach.min[axis] = MIN(box->reach.min[axis], target.min[axis]);
			box->reach.max[axis] = MAX(box->reach.max[axis], target.max[axis]);
		}
	}

}//end FindReach


//========== UseFileSide() =====================================================
///
/// @abstract	Has a thing's sides read from the file's layout: where it puts
/// 			the thing, and where its arrows went when the step was laid
/// 			out.
///
//==============================================================================
static void UseFileSide(FollowedBox *box)
{
	box->side				= 0;
	box->reference			= box->placed;
	box->referenceTargets	= box->laidOutTargets;

	FindWantedCorner(box, 0, box->start);
	FindReach(box);

}//end UseFileSide


//========== UseFileSides() ====================================================
static void UseFileSides(FollowedBox *boxes, NSUInteger count)
{
	for (NSUInteger index = 0; index < count; index++) {
		UseFileSide(&boxes[index]);
	}

}//end UseFileSides


//========== TakeSides() =======================================================
///
/// @abstract	Has each box on a side of its submodel, and the sides read
/// 			from where that puts the boxes and where the arrows go now.
///
//==============================================================================
static void TakeSides(FollowedBox *boxes, NSUInteger count, const NSUInteger *sides)
{
	for (NSUInteger index = 0; index < count; index++) {
		FollowedBox *box = &boxes[index];

		FindWantedCorner(box, sides[index], box->start);

		box->side				= sides[index];
		box->reference			= ExtentAt(box->start, box->size);
		box->referenceTargets	= box->targets;

		FindReach(box);
	}

}//end TakeSides


//========== AddOrder() ========================================================
///
/// @abstract	Has two things stay on the side of each other that `side` says
/// 			`one` is on, the larger of their margins apart.
///
/// @discussion	On the file's sides they keep the gap the file leaves, when
/// 			that is less.
///
//==============================================================================
static void AddOrder(BoxOrder *orders, NSUInteger *orderCount, const FollowedBox *boxes,
					 NSUInteger one, NSUInteger other, Side side, BOOL keepsFileGaps)
{
	NSUInteger			 axis	= side.axis;
	NSUInteger			 first	= side.isAfter ? other : one;
	NSUInteger			 second	= side.isAfter ? one : other;
	const FollowedBox	*before	= &boxes[first];
	const FollowedBox	*after	= &boxes[second];
	double				 room	= MAX(before->margin[axis], after->margin[axis]);

	if (keepsFileGaps) {
		room = MIN(room, after->reference.min[axis] - before->reference.max[axis]);
	}

	// Each of two things may find the same order.
	for (NSUInteger index = 0; index < *orderCount; index++) {
		if (orders[index].axis == axis && orders[index].first == first && orders[index].second == second) {
			return;
		}
	}

	orders[*orderCount] = (BoxOrder){ axis, first, second, before->size[axis] + room };
	*orderCount += 1;

}//end AddOrder


//========== KeepClearOfArrows() ===============================================
///
/// @abstract	Has a box keep to its side of where the arrows of `owner` go.
///
/// @discussion	With a side, the box is on that side of every one of them. The
/// 			owner's box is kept to that side too, so the box is then clear
/// 			of the whole of each arrow. With none, the side is found for
/// 			each of them. One the file has the box over is let be. On other
/// 			sides the box moves off it, to the side its middle is on.
///
/// 			From its own arrows a box keeps the room an arrow needs to
/// 			show. From another's it keeps the larger of the two margins and
/// 			half an arrow's head. On the file's sides it keeps the gap the
/// 			file leaves, when that is less.
///
//==============================================================================
static void KeepClearOfArrows(FollowedBox *box, const FollowedBox *owner, const Side *sideOfAll,
							  Rooms rooms, BOOL keepsFileGaps)
{
	for (NSUInteger index = 0; index < owner->targetCount; index++) {
		Extent	reference	= ExtentOfBox(owner->referenceTargets[index]);
		Extent	target		= ExtentOfBox(owner->targets[index]);
		Side	side		= {0};

		if (sideOfAll != NULL) {
			side = *sideOfAll;
		}
		else if (FindSide(box->reference, reference, &side) == NO) {
			if (keepsFileGaps) {
				continue;
			}

			side = SideOfMiddle(box->reference, reference);
		}

		NSUInteger	axis	= side.axis;
		double		room	= MAX(box->margin[axis], owner->margin[axis]) + rooms.head;

		if (box == owner) {
			room = OwnArrowRoom(box, index, rooms, keepsFileGaps);
		}

		if (keepsFileGaps) {
			double gap = side.isAfter ? box->reference.min[axis] - reference.max[axis]
									  : reference.min[axis] - box->reference.max[axis];

			room = MIN(room, gap);
		}

		if (side.isAfter) {
			box->clearLow[axis] = MAX(box->clearLow[axis], target.max[axis] + room);
		}
		else {
			box->clearHigh[axis] = MIN(box->clearHigh[axis], target.min[axis] - room - box->size[axis]);
		}
	}

}//end KeepClearOfArrows


//========== FindOrders() ======================================================
///
/// @abstract	Reads the side each thing is on of the others and of the
/// 			arrows, and has it keep to them.
///
/// @discussion	A thing that is clear of another and of everything its arrows
/// 			go to keeps to that side of both. Two things that are over each
/// 			other's arrows keep the order their own rectangles are in.
///
/// 			On the file's sides two things the file puts over each other
/// 			are let be. On others they are put in the order of their
/// 			middles, so that no two boxes come to lie over each other.
///
//==============================================================================
static NSUInteger FindOrders(FollowedBox *boxes, NSUInteger count, Rooms rooms, BOOL keepsFileGaps,
							 BoxOrder *orders)
{
	NSUInteger orderCount = 0;

	for (NSUInteger one = 0; one < count; one++) {
		FollowedBox *box = &boxes[one];

		KeepClearOfArrows(box, box, NULL, rooms, keepsFileGaps);

		for (NSUInteger other = one + 1; other < count; other++) {
			FollowedBox	*next			= &boxes[other];
			Side		 side			= {0};
			BOOL		 isClearOfNext	= FindSide(box->reference, next->reach, &side);

			if (box->moves == NO && next->moves == NO) {
				continue;
			}

			if (isClearOfNext) {
				AddOrder(orders, &orderCount, boxes, one, other, side, keepsFileGaps);
			}
			KeepClearOfArrows(box, next, isClearOfNext ? &side : NULL, rooms, keepsFileGaps);

			BOOL isNextClear = FindSide(next->reference, box->reach, &side);

			if (isNextClear) {
				AddOrder(orders, &orderCount, boxes, other, one, side, keepsFileGaps);
			}
			KeepClearOfArrows(next, box, isNextClear ? &side : NULL, rooms, keepsFileGaps);

			if (isClearOfNext || isNextClear) {
				continue;
			}

			if (FindSide(box->reference, next->reference, &side)) {
				AddOrder(orders, &orderCount, boxes, one, other, side, keepsFileGaps);
			}
			else if (keepsFileGaps == NO) {
				side = SideOfMiddle(box->reference, next->reference);

				AddOrder(orders, &orderCount, boxes, one, other, side, keepsFileGaps);
			}
		}
	}

	return orderCount;

}//end FindOrders


// MARK: - PLACES -


//========== MoveWithinLimits() ================================================
///
/// @abstract	Moves a thing along x or y, as far as it may go.
///
//==============================================================================
static void MoveWithinLimits(FollowedBox *box, NSUInteger axis, double distance)
{
	box->origin[axis] = Clamped(box->origin[axis] + distance, box->low[axis], box->high[axis]);

}//end MoveWithinLimits


//========== MoveClearOfArrows() ===============================================
///
/// @abstract	Moves a thing clear of the arrows, then back to where it may go.
///
/// @discussion	Between two arrows that leave it no room it goes half way.
///
//==============================================================================
static void MoveClearOfArrows(FollowedBox *box)
{
	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		double low	= box->clearLow[axis];
		double high	= box->clearHigh[axis];

		if (low > high) {
			low		= (low + high) / 2.0;
			high	= low;
		}

		box->origin[axis] = Clamped(box->origin[axis], low, high);

		MoveWithinLimits(box, axis, 0.0);
	}

}//end MoveClearOfArrows


//========== NarrowLimits() ====================================================
///
/// @abstract	Takes from how far each thing may go the room the things in
/// 			order with it need. NO when that leaves a thing no place, or
/// 			would move one that stays.
///
/// @discussion	An order reaches the thing next to it each time round, so once
/// 			for each thing reaches them all.
///
//==============================================================================
static BOOL NarrowLimits(FollowedBox *boxes, NSUInteger count, const BoxOrder *orders, NSUInteger orderCount)
{
	for (NSUInteger round = 0; round < count; round++) {
		for (NSUInteger index = 0; index < orderCount; index++) {
			BoxOrder	 order	= orders[index];
			FollowedBox	*first	= &boxes[order.first];
			FollowedBox	*second	= &boxes[order.second];

			second->low[order.axis]	= MAX(second->low[order.axis], first->low[order.axis] + order.distance);
			first->high[order.axis]	= MIN(first->high[order.axis], second->high[order.axis] - order.distance);
		}
	}

	for (NSUInteger index = 0; index < count; index++) {
		const FollowedBox *box = &boxes[index];

		for (NSUInteger axis = 0; axis < AxisCount; axis++) {
			if (box->low[axis] > box->high[axis] + LIMIT_SLACK) {
				return NO;
			}
			if (box->moves == NO && (box->low[axis] > box->pageLow[axis] + LIMIT_SLACK
									 || box->high[axis] < box->pageHigh[axis] - LIMIT_SLACK)) {
				return NO;
			}
		}
	}

	return YES;

}//end NarrowLimits


//========== Settle() ==========================================================
///
/// @abstract	Finds each thing its place: clear of the arrows where it can
/// 			be, and in order with the others.
///
/// @discussion	Each round moves the things off the arrows, then moves those
/// 			that are too close for their order apart, each as far as the
/// 			other. The order comes last, so it holds where the two cannot
/// 			both be had.
///
/// 			A last pass moves only the second of each two, so that every
/// 			order holds to the point. The limits leave room for it.
///
//==============================================================================
static void Settle(FollowedBox *boxes, NSUInteger count, const BoxOrder *orders, NSUInteger orderCount)
{
	for (NSUInteger round = 0; round < SEPARATION_ROUNDS; round++) {
		for (NSUInteger index = 0; index < count; index++) {
			MoveClearOfArrows(&boxes[index]);
		}

		for (NSUInteger index = 0; index < orderCount; index++) {
			BoxOrder	 order	= orders[index];
			NSUInteger	 axis	= order.axis;
			FollowedBox	*first	= &boxes[order.first];
			FollowedBox	*second	= &boxes[order.second];
			double		 lack	= order.distance - (second->origin[axis] - first->origin[axis]);

			if (lack > 0.0) {
				MoveWithinLimits(first, axis, -lack / 2.0);
				MoveWithinLimits(second, axis, lack / 2.0);
			}
		}
	}

	for (NSUInteger round = 0; round < count; round++) {
		for (NSUInteger index = 0; index < orderCount; index++) {
			BoxOrder	 order	= orders[index];
			NSUInteger	 axis	= order.axis;
			FollowedBox	*first	= &boxes[order.first];
			FollowedBox	*second	= &boxes[order.second];

			second->origin[axis] = MAX(second->origin[axis], first->origin[axis] + order.distance);
		}
	}

}//end Settle


//========== FindPlaces() ======================================================
///
/// @abstract	Works out where the things go on the sides they have. NO when
/// 			those sides leave a thing no place on the page. The things are
/// 			put as well as can be even then.
///
/// @discussion	The file's sides always leave one, since the file's layout is
/// 			on them.
///
//==============================================================================
static BOOL FindPlaces(FollowedBox *boxes, NSUInteger count, Rooms rooms, BOOL keepsFileGaps, BoxOrder *orders)
{
	for (NSUInteger index = 0; index < count; index++) {
		FollowedBox *box = &boxes[index];

		for (NSUInteger axis = 0; axis < AxisCount; axis++) {
			box->low[axis]			= box->pageLow[axis];
			box->high[axis]			= box->pageHigh[axis];
			box->clearLow[axis]		= -DBL_MAX;
			box->clearHigh[axis]	= DBL_MAX;
			box->origin[axis]		= box->start[axis];
		}
	}

	NSUInteger	orderCount	= FindOrders(boxes, count, rooms, keepsFileGaps, orders);
	BOOL		hasRoom		= NarrowLimits(boxes, count, orders, orderCount);

	Settle(boxes, count, orders, orderCount);

	return hasRoom || keepsFileGaps;

}//end FindPlaces


// MARK: - WHAT A WAY OF PUTTING THE BOXES COSTS -


//========== FindArrow() =======================================================
///
/// @abstract	The line of one of a box's arrows, about as it is drawn: from
/// 			the point of the box nearest the middle of the placement to
/// 			where it meets the box around the placement. NO when that
/// 			middle is under the box, which then has no arrow.
///
//==============================================================================
static BOOL FindArrow(const FollowedBox *box, NSUInteger index, Segment *outArrow)
{
	Extent	target	= ExtentOfBox(box->targets[index]);
	Extent	frame	= ExtentAt(box->origin, box->size);
	Point2	middle	= V2Make((target.min[AxisX] + target.max[AxisX]) / 2.0,
							 (target.min[AxisY] + target.max[AxisY]) / 2.0);
	Point2	from	= V2Make(Clamped(middle.x, frame.min[AxisX], frame.max[AxisX]),
							 Clamped(middle.y, frame.min[AxisY], frame.max[AxisY]));
	Segment	whole	= { from, middle };
	double	enter	= 1.0;
	double	leave	= 1.0;

	if (from.x == middle.x && from.y == middle.y) {
		return NO;
	}

	// To the middle itself when the box around the placement has no size.
	FindCrossing(whole, target, &enter, &leave);

	outArrow->from	= from;
	outArrow->to	= V2Make(from.x + (middle.x - from.x) * enter, from.y + (middle.y - from.y) * enter);

	return YES;

}//end FindArrow


//========== LengthInside() ====================================================
///
/// @abstract	How much of a line is inside a rectangle.
///
//==============================================================================
static double LengthInside(Segment line, Extent extent)
{
	double enter = 0.0;
	double leave = 0.0;

	if (FindCrossing(line, extent, &enter, &leave) == NO) {
		return 0.0;
	}

	return (leave - enter) * hypot(line.to.x - line.from.x, line.to.y - line.from.y);

}//end LengthInside


//========== DepthOver() =======================================================
///
/// @abstract	How far a rectangle reaches over another: the lesser of how
/// 			far across and how far down. 0 when it does not.
///
//==============================================================================
static double DepthOver(Extent one, Extent other, double room)
{
	double depth = DBL_MAX;

	for (NSUInteger axis = 0; axis < AxisCount; axis++) {
		double over = MIN(one.max[axis], other.max[axis] + room) - MAX(one.min[axis], other.min[axis] - room);

		depth = MIN(depth, over);
	}

	return MAX(0.0, depth);

}//end DepthOver


//========== Cost() ============================================================
///
/// @abstract	What is wrong with where the things have been put, in page
/// 			inches. Less is better, and 0 is every box beside its submodel
/// 			on the file's side of it, with every arrow in the clear.
///
/// @discussion	Two things that stay are not counted against each other: no
/// 			way of putting the boxes changes what is between them.
///
/// 			On the file's sides an arrow is as long as it need be when it
/// 			has the room the file leaves it.
///
/// 			A box that is put by itself has no side of the file's. It
/// 			costs more the further it is from what it calls out, and the
/// 			further it reaches over the assembly.
///
//==============================================================================
static double Cost(const FollowedBox *boxes, NSUInteger count, Rooms rooms, BOOL keepsFileGaps,
				   double pointsPerPageInch)
{
	double cost = 0.0;

	for (NSUInteger one = 0; one < count; one++) {
		const FollowedBox	*box	= &boxes[one];
		double				 away	= hypot(box->origin[AxisX] - box->start[AxisX],
											box->origin[AxisY] - box->start[AxisY]);

		if (box->moves && box->assembly != NULL) {
			Extent	own		= ExtentAt(box->origin, box->size);
			Point2	aim		= AimOfBox(box);
			double	across	= MAX(0.0, MAX(own.min[AxisX] - aim.x, aim.x - own.max[AxisX]));
			double	down	= MAX(0.0, MAX(own.min[AxisY] - aim.y, aim.y - own.max[AxisY]));

			cost += AWAY_COST * away;
			cost += REACH_COST * hypot(across, down);
			cost += ASSEMBLY_COST * DepthOver(own, *box->assembly, 0.0);
		}
		else if (box->moves && box->hasMiddle) {
			cost += AWAY_COST * away;
			cost += (box->side != 0) ? OTHER_SIDE_COST * pointsPerPageInch : 0.0;
		}

		for (NSUInteger index = 0; index < box->targetCount; index++) {
			Extent	target		= ExtentOfBox(box->targets[index]);
			Segment	arrow		= {0};
			BOOL	hasArrow	= FindArrow(box, index, &arrow);

			if (box->moves && hasArrow) {
				double length	= hypot(arrow.to.x - arrow.from.x, arrow.to.y - arrow.from.y);
				double room		= OwnArrowRoom(box, index, rooms, keepsFileGaps);

				cost += SHORT_COST * MAX(0.0, room - length);
			}
			else if (box->moves) {
				cost += HIDDEN_COST * pointsPerPageInch;
			}

			for (NSUInteger other = 0; other < count; other++) {
				const FollowedBox	*over	= &boxes[other];
				Extent				 frame	= ExtentAt(over->origin, over->size);

				if (other == one || (box->moves == NO && over->moves == NO)) {
					continue;
				}

				if (hasArrow) {
					cost += OVER_COST * LengthInside(arrow, frame);
				}
				if (over->moves) {
					cost += COVER_COST * DepthOver(frame, target, rooms.head);
				}

				for (NSUInteger crossed = 0; hasArrow && other > one && crossed < over->targetCount; crossed++) {
					Segment line = {0};

					if (FindArrow(over, crossed, &line) && Cross(arrow, line)) {
						cost += CROSSING_COST * pointsPerPageInch;
					}
				}
			}
		}
	}

	return cost / pointsPerPageInch;

}//end Cost


//========== CostOnSides() =====================================================
///
/// @abstract	What the boxes cost with each on a side of its submodel, or
/// 			DBL_MAX when those sides leave a box no place on the page.
///
//==============================================================================
static double CostOnSides(FollowedBox *boxes, NSUInteger count, Rooms rooms, double pointsPerPageInch,
						  BoxOrder *orders, const NSUInteger *sides)
{
	TakeSides(boxes, count, sides);

	if (FindPlaces(boxes, count, rooms, NO, orders) == NO) {
		return DBL_MAX;
	}

	return Cost(boxes, count, rooms, NO, pointsPerPageInch);

}//end CostOnSides


//========== FindBetterSides() =================================================
///
/// @abstract	Looks for sides that cost less than `allowed`, and gives the
/// 			cheapest: the file's when they are to be tried, or each box on
/// 			a side of its submodel. `sides` has the side each box is on,
/// 			and gets the ones found.
///
/// @discussion	A few boxes are tried on every side, every way together. With
/// 			more ways than is worth working out, each box in turn takes
/// 			the side that is cheapest with the others as they are, twice
/// 			round.
///
//==============================================================================
static SidesKind FindBetterSides(FollowedBox *boxes, NSUInteger count, Rooms rooms, double pointsPerPageInch,
								 BoxOrder *orders, BOOL triesFileSides, double allowed, NSUInteger *sides)
{
	SidesKind		 kind		= SidesKept;
	double			 least		= allowed;
	NSMutableData	*trialData	= [NSMutableData dataWithLength:count * sizeof(NSUInteger)];
	NSMutableData	*moverData	= [NSMutableData dataWithLength:count * sizeof(NSUInteger)];
	NSUInteger		*trial		= trialData.mutableBytes;
	NSUInteger		*movers		= moverData.mutableBytes;
	NSUInteger		 moverCount	= 0;

	if (triesFileSides) {
		UseFileSides(boxes, count);
		FindPlaces(boxes, count, rooms, YES, orders);

		double cost = Cost(boxes, count, rooms, YES, pointsPerPageInch);

		if (cost < least) {
			least	= cost;
			kind	= SidesOfFile;
		}
	}

	for (NSUInteger index = 0; index < count; index++) {
		if (boxes[index].moves && (boxes[index].hasMiddle || boxes[index].assembly != NULL)) {
			movers[moverCount++] = index;
		}
	}

	// Boxes that are put by themselves have more places to be in.
	NSUInteger sideCount	= (moverCount > 0 && boxes[movers[0]].assembly != NULL) ? AUTOMATIC_SIDE_COUNT
																					 : OWN_SIDE_COUNT;
	NSUInteger wayCount		= 1;

	for (NSUInteger index = 0; index < moverCount && wayCount <= FULL_SEARCH_WAYS; index++) {
		wayCount *= sideCount;
	}

	if (moverCount > 0 && wayCount <= FULL_SEARCH_WAYS) {
		for (NSUInteger way = 0; way < wayCount; way++) {
			NSUInteger rest = way;

			for (NSUInteger index = 0; index < moverCount; index++) {
				trial[movers[index]] = rest % sideCount;
				rest /= sideCount;
			}

			double cost = CostOnSides(boxes, count, rooms, pointsPerPageInch, orders, trial);

			if (cost < least) {
				least	= cost;
				kind	= SidesTaken;

				memcpy(sides, trial, count * sizeof(NSUInteger));
			}
		}
	}
	else if (moverCount > 0) {
		double leastOfTrial = DBL_MAX;

		memcpy(trial, sides, count * sizeof(NSUInteger));

		for (NSUInteger round = 0; round < 2; round++) {
			for (NSUInteger index = 0; index < moverCount; index++) {
				NSUInteger mover	= movers[index];
				NSUInteger cheapest	= trial[mover];

				for (NSUInteger side = 0; side < sideCount; side++) {
					trial[mover] = side;

					double cost = CostOnSides(boxes, count, rooms, pointsPerPageInch, orders, trial);

					if (cost < leastOfTrial) {
						leastOfTrial	= cost;
						cheapest		= side;
					}
				}

				trial[mover] = cheapest;
			}
		}

		if (leastOfTrial < least) {
			kind = SidesTaken;

			memcpy(sides, trial, count * sizeof(NSUInteger));
		}
	}

	return kind;

}//end FindBetterSides


// MARK: - WHAT AN ARRANGEMENT KEEPS -


//========== BoxOnPage() =======================================================
///
/// @abstract	A box of the view, measured in page inches from the page's
/// 			corner.
///
//==============================================================================
static Box2 BoxOnPage(Box2 box, Box2 pageRect, double pointsPerPageInch)
{
	return V2MakeBox((box.origin.x - pageRect.origin.x) / pointsPerPageInch,
					 (box.origin.y - pageRect.origin.y) / pointsPerPageInch,
					 box.size.width / pointsPerPageInch,
					 box.size.height / pointsPerPageInch);

}//end BoxOnPage


//========== BoxInView() =======================================================
static Box2 BoxInView(Box2 box, Box2 pageRect, double pointsPerPageInch)
{
	return V2MakeBox(box.origin.x * pointsPerPageInch + pageRect.origin.x,
					 box.origin.y * pointsPerPageInch + pageRect.origin.y,
					 box.size.width * pointsPerPageInch,
					 box.size.height * pointsPerPageInch);

}//end BoxInView


//========== OriginOfBox() =====================================================
static Point2 OriginOfBox(const FollowedBox *box)
{
	return V2Make(box->origin[AxisX], box->origin[AxisY]);

}//end OriginOfBox


//========== SubmodelShift() ===================================================
///
/// @abstract	How far a box's submodel has moved in the view since the step
/// 			was laid out. Nothing for a thing that stays.
///
//==============================================================================
static Point2 SubmodelShift(const FollowedBox *box)
{
	if (box->moves == NO || box->hasMiddle == NO) {
		return ZeroPoint2;
	}

	return V2Sub(box->middle, box->laidOutMiddle);

}//end SubmodelShift


//========== PointOnPage() =====================================================
///
/// @abstract	A point of the view, measured in page inches from the page's
/// 			corner.
///
//==============================================================================
static Point2 PointOnPage(Point2 point, Box2 pageRect, double pointsPerPageInch)
{
	return V2Make((point.x - pageRect.origin.x) / pointsPerPageInch,
				  (point.y - pageRect.origin.y) / pointsPerPageInch);

}//end PointOnPage


//========== PointInView() =====================================================
static Point2 PointInView(Point2 point, Box2 pageRect, double pointsPerPageInch)
{
	return V2Make(point.x * pointsPerPageInch + pageRect.origin.x,
				  point.y * pointsPerPageInch + pageRect.origin.y);

}//end PointInView


//========== InchesFrom() ======================================================
///
/// @abstract	How far a point of the view is from a place, in page inches.
///
//==============================================================================
static Point2 InchesFrom(Point2 place, Point2 point, double pointsPerPageInch)
{
	return V2Make((point.x - place.x) / pointsPerPageInch, (point.y - place.y) / pointsPerPageInch);

}//end InchesFrom


//========== KeepSides() =======================================================
///
/// @abstract	Keeps the sides the boxes have just taken in their seats: the
/// 			side of its submodel each is on, and the rectangles the other
/// 			sides are read from.
///
//==============================================================================
static void KeepSides(const FollowedBox *boxes, NSArray<LDrawStepCalloutSeat *> *seats, Box2 pageRect,
					  double pointsPerPageInch)
{
	for (NSUInteger index = 0; index < seats.count; index++) {
		const FollowedBox		*box		= &boxes[index];
		LDrawStepCalloutSeat	*seat		= seats[index];
		NSMutableData			*targets	= [NSMutableData dataWithLength:box->targetCount * sizeof(Box2)];
		Box2					*kept		= targets.mutableBytes;
		Box2					 reference	= V2MakeBox(box->reference.min[AxisX], box->reference.min[AxisY],
														box->size[AxisX], box->size[AxisY]);

		for (NSUInteger target = 0; target < box->targetCount; target++) {
			kept[target] = BoxOnPage(box->referenceTargets[target], pageRect, pointsPerPageInch);
		}

		seat.side				= box->side;
		seat.reference			= BoxOnPage(reference, pageRect, pointsPerPageInch);
		seat.referenceTargets	= targets;
	}

}//end KeepSides


//========== UseKeptSides() ====================================================
///
/// @abstract	Has the sides the boxes took in an earlier layout, as their
/// 			seats keep them. NO when a box has other arrows than it had
/// 			then. `kept` holds what the boxes then point into.
///
//==============================================================================
static BOOL UseKeptSides(FollowedBox *boxes, NSUInteger count, NSArray<LDrawStepCalloutSeat *> *seats,
						 NSMutableArray<NSData *> *kept, Box2 pageRect, double pointsPerPageInch)
{
	for (NSUInteger index = 0; index < count; index++) {
		FollowedBox *box = &boxes[index];

		// The parts list has no seat. It stays where the file puts it.
		if (index >= seats.count) {
			UseFileSide(box);
			continue;
		}

		LDrawStepCalloutSeat	*seat		= seats[index];
		NSMutableData			*targets	= [seat.referenceTargets mutableCopy];
		Box2					*inView		= targets.mutableBytes;

		if (targets.length != box->targetCount * sizeof(Box2)) {
			return NO;
		}

		for (NSUInteger target = 0; target < box->targetCount; target++) {
			inView[target] = BoxInView(inView[target], pageRect, pointsPerPageInch);
		}

		[kept addObject:targets];

		FindWantedCorner(box, seat.side, box->start);

		box->side				= seat.side;
		box->reference			= ExtentOfBox(BoxInView(seat.reference, pageRect, pointsPerPageInch));
		box->referenceTargets	= inView;

		FindReach(box);
	}

	return YES;

}//end UseKeptSides


@implementation LDrawStepCalloutFollower

//---------- moveBoxes:from:to:onPage:listFrame:...:arrangement: -----[static]--
///
/// @abstract	Moves each box with its submodel, as far as there is room.
///
/// @discussion	The parts list is one more thing on the page, which stays, as a
/// 			box off the page does.
///
/// 			While the boxes keep their sides, every step here changes
/// 			little when the camera turns a little, so they move without a
/// 			jump. Boxes that take other sides would jump. They are drawn
/// 			as far from their new places as they were, and close that
/// 			distance over the time a move takes.
///
//------------------------------------------------------------------------------
+ (void) moveBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
			  from:(NSArray<NSData *> *)laidOutPlaces
				to:(NSArray<NSData *> *)places
			onPage:(Box2)pageRect
		 listFrame:(Box2)listFrame
 pointsPerPageInch:(double)pointsPerPageInch
	   arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
{
	[self moveBoxes:boxes
			   from:laidOutPlaces
				 to:places
	 aroundAssembly:NULL
			 onPage:pageRect
		  listFrame:listFrame
  pointsPerPageInch:pointsPerPageInch
		arrangement:arrangement];

}//end moveBoxes:from:to:onPage:listFrame:pointsPerPageInch:arrangement:


//---------- placeBoxes:aroundAssembly:places:onPage:listFrame:... ---[static]--
///
/// @abstract	Puts each box beside the step's assembly by itself, where the
/// 			file is not asked.
///
//------------------------------------------------------------------------------
+ (void) placeBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
	 aroundAssembly:(Box2)assemblyRect
			 places:(NSArray<NSData *> *)places
			 onPage:(Box2)pageRect
		  listFrame:(Box2)listFrame
  pointsPerPageInch:(double)pointsPerPageInch
		arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
{
	[self moveBoxes:boxes
			   from:places
				 to:places
	 aroundAssembly:&assemblyRect
			 onPage:pageRect
		  listFrame:listFrame
  pointsPerPageInch:pointsPerPageInch
		arrangement:arrangement];

}//end placeBoxes:aroundAssembly:places:onPage:listFrame:pointsPerPageInch:arrangement:


//---------- moveBoxes:from:to:aroundAssembly:onPage:listFrame:... ---[static]--
///
/// @abstract	Finds the boxes their places, and draws them there.
///
/// @discussion	With an assembly the boxes are put beside it by themselves:
/// 			the file's places and sides are not read, and every box may
/// 			move. With none they go with their submodels from where the
/// 			file puts them.
///
//------------------------------------------------------------------------------
+ (void) moveBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
			  from:(NSArray<NSData *> *)laidOutPlaces
				to:(NSArray<NSData *> *)places
	aroundAssembly:(nullable const Box2 *)assemblyRect
			onPage:(Box2)pageRect
		 listFrame:(Box2)listFrame
 pointsPerPageInch:(double)pointsPerPageInch
	   arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
{
	BOOL			 isAutomatic	= (assemblyRect != NULL);
	Extent			 assembly		= isAutomatic ? ExtentOfBox(*assemblyRect) : (Extent){0};
	double			 pageMargin		= [LDrawStepPartListPolicy frameInsetForPointsPerPageInch:pointsPerPageInch];
	double			 tolerance		= PAGE_EDGE_TOLERANCE_INCHES * pointsPerPageInch;
	Rooms			 rooms			= { OWN_ARROW_ROOM_INCHES * pointsPerPageInch,
										LEAST_ARROW_ROOM_INCHES * pointsPerPageInch,
										ARROW_HEAD_ROOM_INCHES * pointsPerPageInch };
	NSUInteger		 boxCount		= boxes.count;
	BOOL			 hasList		= (V2BoxWidth(listFrame) > 0.0 && V2BoxHeight(listFrame) > 0.0);
	NSUInteger		 count			= boxCount + (hasList ? 1 : 0);
	NSMutableData	*followedData	= [NSMutableData dataWithLength:count * sizeof(FollowedBox)];
	NSMutableData	*orderData		= [NSMutableData dataWithLength:2 * count * count * sizeof(BoxOrder)];
	NSMutableData	*lagData		= [NSMutableData dataWithLength:count * sizeof(Point2)];
	FollowedBox		*followed		= followedData.mutableBytes;
	BoxOrder		*orders			= orderData.mutableBytes;
	Point2			*lags			= lagData.mutableBytes;
	BOOL			 isHolding		= NO;

	if (boxCount == 0) {
		return;
	}

	for (NSUInteger index = 0; index < boxCount; index++) {
		LDrawStepCalloutStyle	*style		= boxes[index].style;
		Size2					 margins	= V2MakeSize(pageMargin, pageMargin);

		if (style != nil) {
			margins = V2MakeSize(style.margins.width * pointsPerPageInch, style.margins.height * pointsPerPageInch);
		}

		followed[index]			= MakeFollowedBox(boxes[index].placedRect, margins);
		followed[index].isHeld	= boxes[index].isHeld;
		isHolding				= isHolding || boxes[index].isHeld;

		if (index < MIN(places.count, laidOutPlaces.count)) {
			GivePlaces(&followed[index], places[index], laidOutPlaces[index]);
		}

		if (isAutomatic) {
			followed[index].assembly	= &assembly;
			followed[index].arrowRoom	= rooms.own;

			LetMoveOverPage(&followed[index], pageRect, pageMargin);
		}
		else {
			LetMoveOnPage(&followed[index], pageRect, pageMargin, tolerance);
		}
	}

	if (hasList) {
		followed[boxCount] = MakeFollowedBox(listFrame, V2MakeSize(pageMargin, pageMargin));
	}

	// Sides kept from boxes of the other kind mean nothing here.
	[arrangement useSidesPlacedAutomatically:isAutomatic];

	if (arrangement != nil && isHolding && isAutomatic == NO) {
		[self holdBoxes:boxes
			   followed:followed
				  count:count
				  rooms:rooms
				 orders:orders
				 onPage:pageRect
	  pointsPerPageInch:pointsPerPageInch
			arrangement:arrangement];
		return;
	}

	if (arrangement != nil) {
		[self arrangeBoxes:followed
					 count:count
					 seats:[arrangement seatsOfBoxes:boxes]
					 rooms:rooms
					orders:orders
					  lags:lags
			   isAutomatic:isAutomatic
					onPage:pageRect
		 pointsPerPageInch:pointsPerPageInch
			   arrangement:arrangement];
	}
	else if (isAutomatic) {
		NSMutableData *sides = [NSMutableData dataWithLength:count * sizeof(NSUInteger)];

		// The best sides there are, or the first when none leaves room.
		FindBetterSides(followed, count, rooms, pointsPerPageInch, orders, NO, DBL_MAX, sides.mutableBytes);
		TakeSides(followed, count, sides.bytes);
		FindPlaces(followed, count, rooms, NO, orders);
	}
	else {
		UseFileSides(followed, count);
		FindPlaces(followed, count, rooms, YES, orders);
	}

	for (NSUInteger index = 0; index < boxCount; index++) {
		const FollowedBox *box = &followed[index];

		[boxes[index] followTo:V2Add(OriginOfBox(box), lags[index]) submodelShift:SubmodelShift(box)];
	}

}//end moveBoxes:from:to:aroundAssembly:onPage:listFrame:pointsPerPageInch:arrangement:


//---------- holdBoxes:followed:count:rooms:orders:onPage:... --------[static]--
///
/// @abstract	For a layout in which a drag holds a box: the box is under the
/// 			pointer, and every other box is drawn where it was drawn last.
///
/// @discussion	Nothing is arranged while a box is held, so nothing moves but
/// 			the box in hand. The boxes are arranged again once it is let
/// 			go.
///
//------------------------------------------------------------------------------
+ (void) holdBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
		  followed:(FollowedBox *)followed
			 count:(NSUInteger)count
			 rooms:(Rooms)rooms
			orders:(BoxOrder *)orders
			onPage:(Box2)pageRect
 pointsPerPageInch:(double)pointsPerPageInch
	   arrangement:(LDrawStepCalloutArrangement *)arrangement
{
	NSArray<LDrawStepCalloutSeat *> *seats = [arrangement seatsOfBoxes:boxes];

	// The file's places, for a box that has not been drawn before.
	UseFileSides(followed, count);
	FindPlaces(followed, count, rooms, YES, orders);

	arrangement.isHolding = YES;

	for (NSUInteger index = 0; index < boxes.count; index++) {
		const FollowedBox		*box	= &followed[index];
		LDrawStepCalloutSeat	*seat	= seats[index];
		Point2					 drawn	= OriginOfBox(box);
		BOOL					 stays	= (box->isHeld == NO && seat.hasShown);

		if (stays) {
			drawn = PointInView(seat.shown, pageRect, pointsPerPageInch);
		}

		[boxes[index] followTo:drawn submodelShift:SubmodelShift(box)];

		// A box in hand has no move to go on with when it is let go. Where
		// it is held is where it sets out from then.
		if (box->isHeld) {
			[arrangement setLag:ZeroPoint2 ofSeat:seat];

			drawn = boxes[index].frameRect.origin;
		}

		if (stays == NO) {
			seat.hasShown	= YES;
			seat.shown		= PointOnPage(drawn, pageRect, pointsPerPageInch);
		}
	}

}//end holdBoxes:followed:count:rooms:orders:onPage:pointsPerPageInch:arrangement:


//---------- arrangeBoxes:count:seats:rooms:orders:lags:... ----------[static]--
///
/// @abstract	Finds the boxes their places on the sides the arrangement
/// 			keeps, or on better ones. Each `origin` gets the box's place,
/// 			and `lags` how far from it the box is drawn in this layout, in
/// 			points.
///
/// @discussion	Sides are changed only for a gain that is worth a move: boxes
/// 			that cost little are let be, and others change for a share of
/// 			their cost. So two ways that cost about the same do not take
/// 			turns.
///
/// 			Boxes that are put by themselves have no sides of the file's
/// 			to fall back on. Until they have taken sides, the best there
/// 			are are taken whatever they cost.
///
//------------------------------------------------------------------------------
+ (void) arrangeBoxes:(FollowedBox *)followed
				count:(NSUInteger)count
				seats:(NSArray<LDrawStepCalloutSeat *> *)seats
				rooms:(Rooms)rooms
			   orders:(BoxOrder *)orders
				 lags:(Point2 *)lags
		  isAutomatic:(BOOL)isAutomatic
			   onPage:(Box2)pageRect
	pointsPerPageInch:(double)pointsPerPageInch
		  arrangement:(LDrawStepCalloutArrangement *)arrangement
{
	NSMutableArray<NSData *>	*kept		= [NSMutableArray array];
	NSMutableData				*sideData	= [NSMutableData dataWithLength:count * sizeof(NSUInteger)];
	NSMutableData				*placeData	= [NSMutableData dataWithLength:count * sizeof(Point2)];
	NSUInteger					*sides		= sideData.mutableBytes;
	Point2						*places		= placeData.mutableBytes;
	BOOL						 wasHolding	= arrangement.isHolding && isAutomatic == NO;

	// A box that was held has been let go. A drop is written for the file's
	// side of its submodel, so that is where the boxes start from.
	if (wasHolding) {
		arrangement.usesFileSides = YES;
	}

	BOOL hasOwn = (arrangement.usesFileSides == NO);

	arrangement.isAtRest	= NO;
	arrangement.isHolding	= NO;

	// The sides the boxes have. Their own may have gone stale.
	hasOwn = hasOwn && UseKeptSides(followed, count, seats, kept, pageRect, pointsPerPageInch);
	hasOwn = hasOwn && FindPlaces(followed, count, rooms, NO, orders);

	// Boxes that are put by themselves have no places until they take sides.
	BOOL hasPlaces = (hasOwn || isAutomatic == NO);

	// The file's sides, for boxes the file places.
	if (hasOwn == NO && isAutomatic == NO) {
		arrangement.usesFileSides = YES;

		UseFileSides(followed, count);
		FindPlaces(followed, count, rooms, YES, orders);
	}

	for (NSUInteger index = 0; index < count; index++) {
		places[index]	= OriginOfBox(&followed[index]);
		sides[index]	= (hasOwn && index < seats.count) ? seats[index].side : 0;
	}

	// Better ones, when these are not good enough.
	double		cost		= hasPlaces ? Cost(followed, count, rooms, (hasOwn == NO), pointsPerPageInch) : DBL_MAX;
	double		allowed		= hasPlaces ? cost - MAX(SETTLED_COST, CHANGE_SHARE * cost) : DBL_MAX;
	BOOL		triesFile	= (hasOwn && isAutomatic == NO);
	BOOL		hasSearched	= (cost > SETTLED_COST);
	SidesKind	kind		= SidesKept;

	if (hasSearched) {
		kind = FindBetterSides(followed, count, rooms, pointsPerPageInch, orders, triesFile, allowed, sides);
	}

	// With no sides yet, and none that leaves every box room: the first.
	if (hasPlaces == NO && kind == SidesKept) {
		kind = SidesTaken;
	}

	if (kind == SidesOfFile) {
		arrangement.usesFileSides = YES;

		UseFileSides(followed, count);
		FindPlaces(followed, count, rooms, YES, orders);
	}
	else if (kind == SidesTaken) {
		arrangement.usesFileSides = NO;

		TakeSides(followed, count, sides);
		FindPlaces(followed, count, rooms, NO, orders);
		KeepSides(followed, seats, pageRect, pointsPerPageInch);
	}
	else if (hasSearched && hasOwn) {
		// The search has worked other ways out over these.
		[kept removeAllObjects];

		UseKeptSides(followed, count, seats, kept, pageRect, pointsPerPageInch);
		FindPlaces(followed, count, rooms, NO, orders);
	}
	else if (hasSearched) {
		UseFileSides(followed, count);
		FindPlaces(followed, count, rooms, YES, orders);
	}

	for (NSUInteger index = 0; index < seats.count; index++) {
		LDrawStepCalloutSeat	*seat		= seats[index];
		Point2					 place		= OriginOfBox(&followed[index]);
		Point2					 lag		= [arrangement lagOfSeat:seat];
		BOOL					 isChanged	= (kind != SidesKept);

		// After a hold every box starts from where it was drawn: the others
		// have stood still, and the one that was held was under the pointer.
		// So does a box that is put by itself when its sides have gone stale,
		// which leaves no place to measure from.
		BOOL startsWhereShown = seat.hasShown && (wasHolding || (isChanged && hasPlaces == NO));

		if (startsWhereShown) {
			Point2 shown = PointInView(seat.shown, pageRect, pointsPerPageInch);

			lag = InchesFrom(place, shown, pointsPerPageInch);
		}
		else if (isChanged && seat.hasShown == NO) {
			// Never drawn yet, so it has nowhere to come from.
			lag = ZeroPoint2;
		}
		else if (isChanged) {
			// A box that has a new place starts as far from it as it was.
			lag = V2Add(lag, InchesFrom(place, places[index], pointsPerPageInch));
		}

		if (startsWhereShown || isChanged) {
			[arrangement setLag:lag ofSeat:seat];
		}

		lags[index] = V2MulScalar(lag, pointsPerPageInch);

		seat.hasShown	= YES;
		seat.shown		= V2Add(PointOnPage(place, pageRect, pointsPerPageInch), lag);
	}

}//end arrangeBoxes:count:seats:rooms:orders:lags:isAutomatic:onPage:pointsPerPageInch:arrangement:


//---------- restBoxes:onPage:pointsPerPageInch:arrangement: ---------[static]--
///
/// @abstract	Puts each box where the file puts it.
///
/// @discussion	Boxes that had taken sides of their own, or were on their way
/// 			to a place, are drawn where they were, and close the distance
/// 			to the file's place over the time a move takes. They set out
/// 			once, in the first layout here. Setting out again in each
/// 			would never get them there.
///
//------------------------------------------------------------------------------
+ (void) restBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
			onPage:(Box2)pageRect
 pointsPerPageInch:(double)pointsPerPageInch
	   arrangement:(LDrawStepCalloutArrangement *)arrangement
{
	// Before the seats are asked for: this may forget them.
	[arrangement useSidesPlacedAutomatically:NO];

	NSArray<LDrawStepCalloutSeat *>	*seats		= [arrangement seatsOfBoxes:boxes];
	BOOL							 isElsewhere	= (arrangement.usesFileSides == NO) || arrangement.isMoving
												   || arrangement.isHolding;
	BOOL							 setsOut		= (arrangement.isAtRest == NO) && isElsewhere;

	arrangement.usesFileSides = YES;

	arrangement.isAtRest	= YES;
	arrangement.isHolding	= NO;

	for (NSUInteger index = 0; index < boxes.count; index++) {
		LDrawStepCalloutSeat	*seat	= seats[index];
		Point2					 placed	= boxes[index].placedRect.origin;

		if (setsOut && seat.hasShown) {
			Point2 shown = PointInView(seat.shown, pageRect, pointsPerPageInch);

			[arrangement setLag:InchesFrom(placed, shown, pointsPerPageInch) ofSeat:seat];
		}

		// A box that is held is under the pointer. Let go, it is in its
		// place at once.
		if (boxes[index].isHeld) {
			[arrangement setLag:ZeroPoint2 ofSeat:seat];
		}

		Point2 lag = [arrangement lagOfSeat:seat];

		[boxes[index] followTo:V2Add(placed, V2MulScalar(lag, pointsPerPageInch)) submodelShift:ZeroPoint2];

		seat.hasShown	= YES;
		seat.shown		= V2Add(PointOnPage(placed, pageRect, pointsPerPageInch), lag);
	}

}//end restBoxes:onPage:pointsPerPageInch:arrangement:

@end
