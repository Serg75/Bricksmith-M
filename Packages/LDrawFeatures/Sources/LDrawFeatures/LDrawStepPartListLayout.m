//==============================================================================
//
//  File:       LDrawStepPartListLayout.m
//  Package:    LDrawFeatures
//
//  Purpose:    Packs a step's parts list into a box.
//
//  Notes:      Cells are sorted tallest first and laid on shelves, left to
//              right. A cell is a part's projected bounding box, so an angled
//              part leaves some empty space in its cell, and the next cell on
//              the shelf slides into it.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListLayout.h>

#import <LDrawCore/LDrawStepPartListEntry.h>


/// LDU per stud, for the "1×32" annotation.
static const double LDU_PER_STUD = 20.0;

/// Size used for an entry with no bounds: a broken reference, a synthesized
/// part, or anything when no part catalog is loaded.
static const double FALLBACK_EXTENT_LDU = LDU_PER_STUD;

/// Smallest size an icon may have. A part seen edge-on would otherwise measure
/// zero and divide by zero when it is capped.
static const double MINIMUM_EXTENT_LDU = 1.0;

/// A part whose longer side is over this many studs gets a size badge. Shorter
/// ones are easy to read off the picture.
static const long STUDS_WORTH_ANNOTATING = 4;
/// A tile is smooth, so it needs a badge sooner: anything longer than this.
static const long TILE_STUDS_WORTH_ANNOTATING = 2;

/// How much the scale drops each time the list is shrunk to fit, and the most
/// rounds allowed. The scale floor ends the loop; the count is a backstop.
static const double SHRINK_FACTOR = 0.9;
static const NSUInteger MAXIMUM_SHRINK_ROUNDS = 200;

/// Slack when testing whether one more cell fits a shelf. Without it a row that
/// fits exactly can lose its last cell to rounding.
static const double FIT_EPSILON = 1e-9;


/// How many times a search halves the gap it looks in.
static const NSUInteger HALVING_STEPS = 12;

/// How far apart two parts on a shelf stay, as a share of the smaller one's
/// size, and never less than two paddings. A small part can sit close under a
/// big one, while two big parts keep a wider gap.
static const double PART_GAP_FRACTION = 0.2;

/// Corners this close to the lowest one count as the part's bottom edge.
static const double BOTTOM_EDGE_SLACK = 0.5;

/// How far a label keeps from the parts of other cells, in gaps between the
/// two parts. Nearer, it reads as the other part's.
static const double LABEL_CLEARANCE_GAPS = 2.0;

/// The step, in points, between the places a moving label tries.
static const double LABEL_SEARCH_STEP = 1.0;

/// A label put exactly `decorationGap` from its part can come out a hair nearer
/// after rounding. Testing with this much less of a gap counts it as clear.
static const double TOUCH_SLACK = 1e-6;

/// The most corners an outline keeps.
#define MAXIMUM_OUTLINE_POINTS 16


#pragma mark - Geometry -


//========== Cross() ===========================================================
///
/// @abstract	Twice the signed area of triangle o-a-b. Zero when the three
/// 			points are in a line, and the sign says which way they turn.
///
//==============================================================================
static double Cross(Point2 o, Point2 a, Point2 b)
{
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

}//end Cross


//========== ComparePoints() ===================================================
static int ComparePoints(const void *left, const void *right)
{
	const Point2 *a = left;
	const Point2 *b = right;

	if (a->x != b->x) {
		return (a->x < b->x) ? -1 : 1;
	}
	if (a->y != b->y) {
		return (a->y < b->y) ? -1 : 1;
	}
	return 0;

}//end ComparePoints


//========== ConvexHull() ======================================================
///
/// @abstract	The convex hull of `points`, by Andrew's monotone chain.
///
/// @discussion	Sorts `points` in place and writes the hull to `hull`, which
/// 			needs room for twice `count`. Returns how many corners it wrote,
/// 			fewer than three when the points are in a line.
///
//==============================================================================
static NSUInteger ConvexHull(Point2 *points, NSUInteger count, Point2 *hull)
{
	if (count < 3) {
		return 0;
	}

	qsort(points, count, sizeof(Point2), ComparePoints);

	NSUInteger size = 0;

	for (NSUInteger index = 0; index < count; index++) {
		while (size >= 2 && Cross(hull[size - 2], hull[size - 1], points[index]) <= 0.0) {
			size--;
		}
		hull[size++] = points[index];
	}

	NSUInteger lowerSize = size + 1;

	for (NSUInteger index = count - 1; index > 0; index--) {
		while (size >= lowerSize && Cross(hull[size - 2], hull[size - 1], points[index - 1]) <= 0.0) {
			size--;
		}
		hull[size++] = points[index - 1];
	}

	// The last vertex repeats the first.
	return size - 1;

}//end ConvexHull


//========== FitOutline() ======================================================
///
/// @abstract	A convex polygon as packed `Point2`s, with at most
/// 			MAXIMUM_OUTLINE_POINTS corners.
///
/// @discussion	A bigger polygon is replaced by a sixteen-sided one around it,
/// 			about 2% wider. It still holds every original point, so text kept
/// 			off it stays off the part.
///
//==============================================================================
static NSData *FitOutline(const Point2 *polygon, NSUInteger count)
{
	if (count <= MAXIMUM_OUTLINE_POINTS) {
		return [NSData dataWithBytes:polygon length:count * sizeof(Point2)];
	}

	double	reach[MAXIMUM_OUTLINE_POINTS];
	Point2	outline[MAXIMUM_OUTLINE_POINTS];

	for (NSUInteger side = 0; side < MAXIMUM_OUTLINE_POINTS; side++) {
		double angle = 2.0 * M_PI * side / MAXIMUM_OUTLINE_POINTS;
		double nx = cos(angle), ny = sin(angle);

		reach[side] = -DBL_MAX;
		for (NSUInteger index = 0; index < count; index++) {
			reach[side] = MAX(reach[side], polygon[index].x * nx + polygon[index].y * ny);
		}
	}

	// Each vertex is where one supporting edge meets the next.
	double step = 2.0 * M_PI / MAXIMUM_OUTLINE_POINTS;

	for (NSUInteger side = 0; side < MAXIMUM_OUTLINE_POINTS; side++) {
		NSUInteger	next	= (side + 1) % MAXIMUM_OUTLINE_POINTS;
		double		ax = cos(step * side), ay = sin(step * side);
		double		bx = cos(step * next), by = sin(step * next);
		double		det = ax * by - ay * bx;

		outline[side] = V2Make((reach[side] * by - reach[next] * ay) / det,
							   (ax * reach[next] - bx * reach[side]) / det);
	}

	return [NSData dataWithBytes:outline length:sizeof(outline)];

}//end FitOutline


//========== BoxIsEmpty() ======================================================
static inline BOOL BoxIsEmpty(Box2 box)
{
	return box.size.width <= 0.0 || box.size.height <= 0.0;

}//end BoxIsEmpty


//========== BoxesOverlap() ====================================================
///
/// @abstract	Whether two boxes share any area. Touching is not overlapping,
/// 			and an empty box overlaps nothing.
///
//==============================================================================
static BOOL BoxesOverlap(Box2 a, Box2 b)
{
	if (BoxIsEmpty(a) || BoxIsEmpty(b)) {
		return NO;
	}

	return a.origin.x < b.origin.x + b.size.width  && b.origin.x < a.origin.x + a.size.width
		&& a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height;

}//end BoxesOverlap


//========== BoxIsClear() ======================================================
///
/// @abstract	Whether a box stands `gap` points clear of the outline and of
/// 			`avoidedBox`. Touching counts as blocked.
///
//==============================================================================
static BOOL BoxIsClear(Box2 box, const Point2 *outline, NSUInteger outlineCount, Box2 avoidedBox, double gap)
{
	Box2 grown = V2BoxInset(box, -gap, -gap);

	return V2BoxIntersectsPolygon(grown, outline, (int)outlineCount) == false
		&& BoxesOverlap(grown, avoidedBox) == NO;

}//end BoxIsClear


//========== SlideBoxToward() ==================================================
///
/// @abstract	Puts a box at `start` and slides it toward `end` while it stays
/// 			`gap` points clear of the outline and of `avoidedBox`. Answers
/// 			NO when `start` itself is blocked.
///
/// @discussion	Halving works because the outline is convex: along this path
/// 			there is one point where the box starts to touch it.
///
//==============================================================================
static BOOL SlideBoxToward(Size2 size, Point2 start, Point2 end,
						   const Point2 *outline, NSUInteger outlineCount,
						   Box2 avoidedBox, double gap, Box2 *result)
{
	Box2 (^boxAt)(double) = ^Box2(double fraction) {
		return V2MakeBox(start.x + (end.x - start.x) * fraction,
						 start.y + (end.y - start.y) * fraction,
						 size.width, size.height);
	};

	BOOL (^isClearAt)(double) = ^BOOL(double fraction) {
		return BoxIsClear(boxAt(fraction), outline, outlineCount, avoidedBox, gap);
	};

	if (isClearAt(0.0) == NO) {
		return NO;
	}

	double	clear	= 0.0;
	double	blocked	= 1.0;

	if (isClearAt(1.0)) {
		clear = 1.0;
	}
	else {
		// Halve the gap between the last clear place and the first blocked one.
		for (NSUInteger step = 0; step < HALVING_STEPS; step++) {
			double middle = (clear + blocked) / 2.0;

			if (isClearAt(middle)) {
				clear = middle;
			}
			else {
				blocked = middle;
			}
		}
	}

	*result = boxAt(clear);
	return YES;

}//end SlideBoxToward


//========== OffsetBox() =======================================================
static Box2 OffsetBox(Box2 box, Point2 offset)
{
	return V2MakeBox(box.origin.x + offset.x, box.origin.y + offset.y, box.size.width, box.size.height);

}//end OffsetBox


//========== GrownPolygon() ====================================================
///
/// @abstract	A convex polygon grown by `amount` on every side, as packed
/// 			`Point2`s: the hull of its corners, each moved to the four corners
/// 			of a square around it.
///
//==============================================================================
static NSData *GrownPolygon(const Point2 *polygon, NSUInteger count, double amount)
{
	NSUInteger	 pointCount	= 4 * count;
	Point2		*points		= malloc(pointCount * sizeof(Point2));
	Point2		*hull		= malloc((2 * pointCount + 1) * sizeof(Point2));

	for (NSUInteger index = 0; index < count; index++) {
		Point2 corner = polygon[index];

		points[4 * index + 0] = V2Make(corner.x - amount, corner.y - amount);
		points[4 * index + 1] = V2Make(corner.x + amount, corner.y - amount);
		points[4 * index + 2] = V2Make(corner.x + amount, corner.y + amount);
		points[4 * index + 3] = V2Make(corner.x - amount, corner.y + amount);
	}

	NSUInteger	 hullCount	= ConvexHull(points, pointCount, hull);
	NSData		*grown		= [NSData dataWithBytes:hull length:hullCount * sizeof(Point2)];

	free(hull);
	free(points);

	return grown;

}//end GrownPolygon


//========== GrownBox() ========================================================
///
/// @abstract	A box grown by `amount` on every side, as its four corners packed
/// 			as `Point2`s.
///
//==============================================================================
static NSData *GrownBox(Box2 box, double amount)
{
	Box2	grown		= V2BoxInset(box, -amount, -amount);
	Point2	corners[4]	= { grown.origin,
							V2Make(V2BoxMaxX(grown), grown.origin.y),
							V2Make(V2BoxMaxX(grown), V2BoxMaxY(grown)),
							V2Make(grown.origin.x, V2BoxMaxY(grown)) };

	return [NSData dataWithBytes:corners length:sizeof(corners)];

}//end GrownBox


//========== PolygonSpanInBand() ===============================================
///
/// @abstract	How far left and right a convex polygon reaches between the
/// 			heights `top` and `bottom`, which may be the same. Answers NO
/// 			when it is not in the band. Either out pointer may be NULL.
///
//==============================================================================
static BOOL PolygonSpanInBand(const Point2 *polygon, NSUInteger count, double top, double bottom,
							  double *outLeft, double *outRight)
{
	double	left	= DBL_MAX;
	double	right	= -DBL_MAX;

	for (NSUInteger index = 0; index < count; index++) {
		Point2 a		= polygon[index];
		Point2 b		= polygon[(index + 1) % count];
		double from		= 0.0;
		double to		= 1.0;

		// The part of the edge inside the band.
		if (a.y == b.y) {
			if (a.y < top || a.y > bottom) {
				continue;
			}
		}
		else {
			double atTop	= (top - a.y) / (b.y - a.y);
			double atBottom	= (bottom - a.y) / (b.y - a.y);

			from	= MAX(from, MIN(atTop, atBottom));
			to		= MIN(to, MAX(atTop, atBottom));

			if (from > to) {
				continue;
			}
		}

		double fromX	= a.x + (b.x - a.x) * from;
		double toX		= a.x + (b.x - a.x) * to;

		left	= MIN(left, MIN(fromX, toX));
		right	= MAX(right, MAX(fromX, toX));
	}

	if (outLeft != NULL) {
		*outLeft = left;
	}
	if (outRight != NULL) {
		*outRight = right;
	}

	return left <= right;

}//end PolygonSpanInBand


//========== ReachAtY() ========================================================
///
/// @abstract	How far `fixed` reaches past the left end of `moving` along the
/// 			line at height `y`. -DBL_MAX when the line misses either.
///
//==============================================================================
static double ReachAtY(const Point2 *fixed, NSUInteger fixedCount,
					   const Point2 *moving, NSUInteger movingCount, double y)
{
	double fixedLeft, fixedRight, movingLeft, movingRight;

	if (PolygonSpanInBand(fixed, fixedCount, y, y, &fixedLeft, &fixedRight) == NO
		|| PolygonSpanInBand(moving, movingCount, y, y, &movingLeft, &movingRight) == NO) {
		return -DBL_MAX;
	}

	return fixedRight - movingLeft;

}//end ReachAtY


//========== SlideDistance() ===================================================
///
/// @abstract	How far right the convex polygon `moving` must be moved to stand
/// 			clear of the convex polygon `fixed`, on its right. -DBL_MAX when
/// 			no level line crosses both.
///
/// @discussion	It is the most `fixed` reaches past `moving` along any line
/// 			both cross. Both are convex, so that is largest at the height of a
/// 			corner or at an end of the heights they share, and only those are
/// 			tested.
///
//==============================================================================
static double SlideDistance(NSData *fixed, NSData *moving)
{
	const Point2	*a			= fixed.bytes;
	const Point2	*b			= moving.bytes;
	NSUInteger		 aCount		= fixed.length / sizeof(Point2);
	NSUInteger		 bCount		= moving.length / sizeof(Point2);
	double			 aTop		= DBL_MAX;
	double			 aBottom	= -DBL_MAX;
	double			 bTop		= DBL_MAX;
	double			 bBottom	= -DBL_MAX;

	for (NSUInteger index = 0; index < aCount; index++) {
		aTop	= MIN(aTop, a[index].y);
		aBottom	= MAX(aBottom, a[index].y);
	}
	for (NSUInteger index = 0; index < bCount; index++) {
		bTop	= MIN(bTop, b[index].y);
		bBottom	= MAX(bBottom, b[index].y);
	}

	double top		= MAX(aTop, bTop);
	double bottom	= MIN(aBottom, bBottom);

	// Shapes that only touch along a line share no area.
	if (bottom - top <= FIT_EPSILON) {
		return -DBL_MAX;
	}

	double distance = MAX(ReachAtY(a, aCount, b, bCount, top),
						  ReachAtY(a, aCount, b, bCount, bottom));

	for (NSUInteger index = 0; index < aCount; index++) {
		if (a[index].y > top && a[index].y < bottom) {
			distance = MAX(distance, ReachAtY(a, aCount, b, bCount, a[index].y));
		}
	}
	for (NSUInteger index = 0; index < bCount; index++) {
		if (b[index].y > top && b[index].y < bottom) {
			distance = MAX(distance, ReachAtY(a, aCount, b, bCount, b[index].y));
		}
	}

	return distance;

}//end SlideDistance


//========== MovedPolygon() ====================================================
///
/// @abstract	A polygon moved by `offset`, then with x and y swapped when
/// 			`swapsAxes`, as packed `Point2`s.
///
/// @discussion	Swapping the axes lets `SlideDistance()` measure downward.
///
//==============================================================================
static NSData *MovedPolygon(NSData *polygon, Point2 offset, BOOL swapsAxes)
{
	if (swapsAxes == NO && offset.x == 0.0 && offset.y == 0.0) {
		return polygon;
	}

	NSUInteger		 count	= polygon.length / sizeof(Point2);
	const Point2	*from	= polygon.bytes;
	NSMutableData	*moved	= [NSMutableData dataWithLength:polygon.length];
	Point2			*to		= moved.mutableBytes;

	for (NSUInteger index = 0; index < count; index++) {
		Point2 point = V2Add(from[index], offset);

		to[index] = swapsAxes ? V2Make(point.y, point.x) : point;
	}

	return moved;

}//end MovedPolygon


//========== ContentPointsForInches() ==========================================
///
/// @abstract	The content length in points for a size given in inches: the
/// 			frame less its padding at both ends, and at least one point.
///
//==============================================================================
static double ContentPointsForInches(double inches, LDrawStepPartListMetrics metrics)
{
	return MAX(1.0, inches * metrics.pointsPerInch - 2.0 * metrics.framePadding);

}//end ContentPointsForInches


#pragma mark - Private scratch types -


/// An entry measured once, before any packing. Its size does not depend on the
/// scale or the box width, so every repack reuses it.
@interface LDrawStepPartListCell : NSObject
@property (nonatomic) LDrawStepPartListEntry	*entry;
@property (nonatomic) Size2						 iconLDU;
@property (nonatomic, copy, nullable) NSString	*studText;
@property (nonatomic) BOOL						 needsSizeBadge;
/// The icon's outline as a convex polygon: packed `Point2`s in LDU, measured
/// from the icon's center. Text beside the part is kept off it.
@property (nonatomic) NSData					*outline;
/// How heavy the part looks: the volume of its bounding box.
@property (nonatomic) double					 weight;
/// Whether the multiplier is drawn, the room it needs, and the badge's width,
/// in points. A cell with no multiplier needs no room for it.
@property (nonatomic) BOOL						 showsCount;
@property (nonatomic) Size2						 labelSize;
@property (nonatomic) double					 annotationWidth;
@end

@implementation LDrawStepPartListCell
@end


//========== ScaledOutlineOfCell() =============================================
///
/// @abstract	The cell's outline at its own scale, centered on `middle`: packed
/// 			`Point2`s.
///
//==============================================================================
static NSData *ScaledOutlineOfCell(LDrawStepPartListCell *cell, double scale, Point2 middle)
{
	NSUInteger		 count		= cell.outline.length / sizeof(Point2);
	const Point2	*unscaled	= cell.outline.bytes;
	NSMutableData	*scaled		= [NSMutableData dataWithLength:count * sizeof(Point2)];
	Point2			*outline	= scaled.mutableBytes;

	for (NSUInteger index = 0; index < count; index++) {
		outline[index] = V2Add(middle, V2MulScalar(unscaled[index], scale));
	}

	return scaled;

}//end ScaledOutlineOfCell


/// What a cell draws, as convex polygons measured from the cell's bottom-left
/// corner.
@interface LDrawStepPartListCellShapes : NSObject
/// The part's outline as drawn, grown by a padding, and grown by the gap
/// between two parts of its size.
@property (nonatomic) NSData				*outline;
@property (nonatomic) NSData				*paddedOutline;
@property (nonatomic) NSData				*grownOutline;
/// The count and the badge, each grown by a padding.
@property (nonatomic) NSArray<NSData *>	*labels;
/// The count and the badge as drawn. The badge is empty when there is none.
@property (nonatomic) Box2					 countBox;
@property (nonatomic) Box2					 badgeBox;
/// The outline with x and y swapped, for measuring across a label's width.
@property (nonatomic) NSData				*column;
/// How big the part looks: the shorter side of its icon. It sets how far
/// other parts stay from it.
@property (nonatomic) double				 partSize;
/// How far the labels and the padded outline reach to each side.
@property (nonatomic) double				 left;
@property (nonatomic) double				 right;
@end

@implementation LDrawStepPartListCellShapes
@end


/// The cells and counts of one shelf, in its own coordinates: x from the
/// shelf's left, y from its bottom line, up negative.
@interface LDrawStepPartListShelfLabels : NSObject
/// A `Box2` for each cell, and each cell's shapes.
@property (nonatomic) NSData										*cells;
@property (nonatomic) NSArray<LDrawStepPartListCellShapes *>	*shapes;
/// A `Box2` for each count.
@property (nonatomic) NSData										*counts;
/// How far the counts reach below the shelf's bottom line.
@property (nonatomic) double										 depth;
@end

@implementation LDrawStepPartListShelfLabels
@end


//========== PartGap() =========================================================
///
/// @abstract	How far two parts on a shelf stay apart: a share of the smaller
/// 			one's size, and never less than two paddings.
///
//==============================================================================
static double PartGap(double size, double otherSize, double padding)
{
	return MAX(2.0 * padding, PART_GAP_FRACTION * MIN(size, otherSize));

}//end PartGap


/// What the labels of a shelf keep clear of while they move: each cell's box
/// and shapes, and every label as it stands. Shapes are measured from their
/// cell's bottom-left corner, so a label is moved to the cell rather than a
/// part to the shelf.
typedef struct LDrawStepPartListShelf
{
	NSUInteger											 count;
	const Box2											*cells;
	__unsafe_unretained NSArray<LDrawStepPartListCellShapes *> *shapes;
	Box2												*counts;
	Box2												*badges;
	double												 padding;
	double												 decorationGap;

} LDrawStepPartListShelf;


//========== LabelIsClear() ====================================================
///
/// @abstract	Whether a label of cell `owner` at `box` keeps far enough from
/// 			the rest of the shelf: from other parts by LABEL_CLEARANCE_GAPS
/// 			gaps between the two parts, from other labels by two paddings,
/// 			and from its own other label by `decorationGap`.
///
//==============================================================================
static BOOL LabelIsClear(Box2 box, NSUInteger owner, BOOL isBadge, const LDrawStepPartListShelf *shelf)
{
	double ownSize = shelf->shapes[owner].partSize;

	for (NSUInteger other = 0; other < shelf->count; other++) {
		if (other == owner) {
			Box2 sibling = isBadge ? shelf->counts[other] : shelf->badges[other];

			if (BoxesOverlap(V2BoxInset(box, -shelf->decorationGap, -shelf->decorationGap), sibling)) {
				return NO;
			}
			continue;
		}

		LDrawStepPartListCellShapes	*shapes		= shelf->shapes[other];
		NSData						*part		= shapes.outline;
		double						 partGap	= PartGap(ownSize, shapes.partSize, shelf->padding);
		double						 reach		= LABEL_CLEARANCE_GAPS * partGap;
		Box2						 padded		= V2BoxInset(box, -2.0 * shelf->padding, -2.0 * shelf->padding);
		Box2						 reaching	= V2BoxInset(box, -reach, -reach);

		if (BoxesOverlap(padded, shelf->counts[other]) || BoxesOverlap(padded, shelf->badges[other])) {
			return NO;
		}

		// Only a cell the label's reach touches can be near enough.
		if (BoxesOverlap(reaching, shelf->cells[other])
			&& V2BoxIntersectsPolygon(OffsetBox(reaching, V2Make(-shelf->cells[other].origin.x, 0.0)),
									  part.bytes, (int)(part.length / sizeof(Point2)))) {
			return NO;
		}
	}

	return YES;

}//end LabelIsClear


//========== LabelHitsOwnPart() ================================================
///
/// @abstract	Whether a label of cell `owner` at `box` comes nearer its own
/// 			part than `decorationGap`. Exactly that far is clear.
///
//==============================================================================
static BOOL LabelHitsOwnPart(Box2 box, NSUInteger owner, const LDrawStepPartListShelf *shelf)
{
	NSData	*part		= shelf->shapes[owner].outline;
	double	 gap		= MAX(0.0, shelf->decorationGap - TOUCH_SLACK);
	Box2	 nearPart	= OffsetBox(V2BoxInset(box, -gap, -gap), V2Make(-shelf->cells[owner].origin.x, 0.0));

	return V2BoxIntersectsPolygon(nearPart, part.bytes, (int)(part.length / sizeof(Point2)));

}//end LabelHitsOwnPart


//========== BoxAgainstPart() ==================================================
///
/// @abstract	A label moved to `x` and against its own part: a badge as low as
/// 			it stays `gap` above the part, a count as high as it stays `gap`
/// 			below it, but neither past the line it started on.
///
/// @discussion	`column` is the part's outline with x and y swapped, so its span
/// 			across the label's width is its span in height. It is measured
/// 			from its cell, which starts at `start`.
///
//==============================================================================
static Box2 BoxAgainstPart(Box2 box, double x, NSData *column, double start, BOOL isBadge, double gap)
{
	double	top		= 0.0;
	double	bottom	= 0.0;
	double	from	= x - gap - start;
	Box2	moved	= V2MakeBox(x, box.origin.y, box.size.width, box.size.height);

	if (PolygonSpanInBand(column.bytes, column.length / sizeof(Point2), from, from + box.size.width + 2.0 * gap,
						  &top, &bottom) == NO) {
		return moved;
	}

	if (isBadge) {
		moved.origin.y = MIN(box.origin.y, top - gap - box.size.height);
	}
	else {
		moved.origin.y = MAX(box.origin.y, bottom + gap);
	}

	return moved;

}//end BoxAgainstPart


//========== LabelKeptClear() ==================================================
///
/// @abstract	Moves a label of cell `owner` along its own part until it keeps
/// 			far enough from the rest of the shelf. Answers NO, and leaves it,
/// 			when no place in its cell does.
///
/// @discussion	It first moves away from the nearest other cell, then the other
/// 			way, and takes the first place that is clear, so it moves no
/// 			further than it must. A badge stays below `highest`, the shelf's
/// 			top, and a count above `lowest`. With `alongLine` it keeps its
/// 			height and only moves sideways.
///
//==============================================================================
static BOOL LabelKeptClear(Box2 *box, NSUInteger owner, BOOL isBadge, const LDrawStepPartListShelf *shelf,
						   double highest, double lowest, BOOL alongLine)
{
	Box2 start = *box;

	// Moved straight to a line, a label can land on its own part.
	BOOL (^isClear)(Box2) = ^BOOL(Box2 candidate) {
		return LabelIsClear(candidate, owner, isBadge, shelf)
			&& (alongLine == NO || LabelHitsOwnPart(candidate, owner, shelf) == NO);
	};

	if (BoxIsEmpty(start) || isClear(start)) {
		return YES;
	}

	Box2	cell	= shelf->cells[owner];
	double	minX	= cell.origin.x;
	double	maxX	= V2BoxMaxX(cell) - start.size.width;
	double	middle	= V2BoxMidX(start);
	double	nearest	= DBL_MAX;
	double	away	= 1.0;

	for (NSUInteger other = 0; other < shelf->count; other++) {
		double distance = fabs(V2BoxMidX(shelf->cells[other]) - middle);

		if (other != owner && distance < nearest) {
			nearest	= distance;
			away	= (V2BoxMidX(shelf->cells[other]) < middle) ? 1.0 : -1.0;
		}
	}

	double directions[2] = { away, -away };

	for (NSUInteger pass = 0; pass < 2; pass++) {
		double direction = directions[pass];

		for (double x = start.origin.x + direction * LABEL_SEARCH_STEP;
			 x >= minX - FIT_EPSILON && x <= maxX + FIT_EPSILON;
			 x += direction * LABEL_SEARCH_STEP) {

			Box2 moved = alongLine
					   ? V2MakeBox(x, start.origin.y, start.size.width, start.size.height)
					   : BoxAgainstPart(start, x, shelf->shapes[owner].column, cell.origin.x, isBadge,
										shelf->decorationGap);

			if (moved.origin.y < highest - FIT_EPSILON || V2BoxMaxY(moved) > lowest + FIT_EPSILON) {
				continue;
			}
			if (isClear(moved)) {
				*box = moved;
				return YES;
			}
		}
	}

	return NO;

}//end LabelKeptClear


//========== ShelfOfLabels() ===================================================
///
/// @abstract	A shelf to move labels on, with the cells of `labels`, the counts
/// 			in `counts`, and the badges written into `badges` where their
/// 			cells put them.
///
//==============================================================================
static LDrawStepPartListShelf ShelfOfLabels(LDrawStepPartListShelfLabels *labels, Box2 *counts, Box2 *badges,
											LDrawStepPartListMetrics metrics)
{
	LDrawStepPartListShelf shelf;

	shelf.count			= labels.shapes.count;
	shelf.cells			= labels.cells.bytes;
	shelf.shapes		= labels.shapes;
	shelf.counts		= counts;
	shelf.badges		= badges;
	shelf.padding		= metrics.cellPadding;
	shelf.decorationGap	= metrics.decorationGap;

	for (NSUInteger index = 0; index < shelf.count; index++) {
		badges[index] = OffsetBox(shelf.shapes[index].badgeBox, V2Make(shelf.cells[index].origin.x, 0.0));
	}

	return shelf;

}//end ShelfOfLabels


//========== DepthOfBoxes() ====================================================
///
/// @abstract	How far the lowest of these boxes reaches below the line at 0,
/// 			or 0 when none does.
///
//==============================================================================
static double DepthOfBoxes(const Box2 *boxes, NSUInteger count)
{
	double depth = 0.0;

	for (NSUInteger index = 0; index < count; index++) {
		depth = MAX(depth, V2BoxMaxY(boxes[index]));
	}

	return depth;

}//end DepthOfBoxes


/// One cell after a pack: it knows its scale and its size.
@interface LDrawStepPartListPlacedCell : NSObject
@property (nonatomic) LDrawStepPartListCell	*cell;
@property (nonatomic) double				 scale;
/// The icon's padded box and any badge strip. A count strip is added per shelf.
@property (nonatomic) Size2					 size;
/// Drawn smaller than the rest. Such a cell gets a shelf to itself.
@property (nonatomic) BOOL					 isScaledDown;
@property (nonatomic) BOOL					 showsAnnotation;
/// Where the multiplier sits beside the part, on the bottom line of the icon's
/// padded box and measured from its top-left. Empty when there is no room.
@property (nonatomic) Box2					 labelBox;
/// The multiplier has no room beside the part, so it goes in a strip below.
@property (nonatomic) BOOL					 countIsInStrip;
/// The badge fits on the top line of the icon's box, so the cell keeps no strip
/// for it. Decided with the count beside the part, which it must avoid.
@property (nonatomic) BOOL					 badgeIsInside;
/// The part's outline, measured in the icon's padded box.
@property (nonatomic) NSData				*roomOutline;
/// Its place in packing order. Other cells key what they keep by it.
@property (nonatomic) NSUInteger			 order;
/// What it draws, with the counts beside the part or in a strip. Made when
/// first needed.
@property (nonatomic, nullable) LDrawStepPartListCellShapes *besideShapes;
@property (nonatomic, nullable) LDrawStepPartListCellShapes *stripShapes;
/// How far right of each earlier cell this one must start, by the earlier
/// cell's order and the shelf's kind. Kept because a search packs the same
/// pairs at every width it tries.
@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *slides;
/// How far below the bottom of each cell this one's bottom must be when it
/// stands right under it, by the upper cell's order. Kept for the same reason.
@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *drops;
/// The labels of each shelf this cell starts, by how many cells the shelf
/// holds. Shelves hold cells in packing order, so that names the shelf.
@property (nonatomic) NSMutableDictionary<NSNumber *, LDrawStepPartListShelfLabels *> *shelfLabels;
@end

@implementation LDrawStepPartListPlacedCell
@end


/// One packed shelf.
typedef NSArray<LDrawStepPartListPlacedCell *> LDrawStepPartListRow;

/// Where each cell starts on its shelf, by shelf.
typedef NSMapTable<LDrawStepPartListRow *, NSArray<NSNumber *> *> LDrawStepPartListOffsets;


/// The result of one pack attempt.
@interface LDrawStepPartListPacking : NSObject
@property (nonatomic) NSArray<LDrawStepPartListRow *>					*rows;
@property (nonatomic) LDrawStepPartListOffsets							*offsets;
/// The widest row, which the searching modes score candidates by.
@property (nonatomic) double											 usedWidth;
@property (nonatomic) double											 height;
@end

@implementation LDrawStepPartListPacking
@end


#pragma mark - Placement -


@interface LDrawStepPartListPlacement ()
@property (nonatomic, readwrite) LDrawStepPartListEntry	*entry;
@property (nonatomic, readwrite) Box2					 cellFrame;
@property (nonatomic, readwrite) Box2					 iconFrame;
@property (nonatomic, readwrite) Box2					 annotationFrame;
@property (nonatomic, readwrite) Box2					 labelFrame;
@property (nonatomic, readwrite) BOOL					 showsCount;
@property (nonatomic, readwrite) double					 scale;
@property (nonatomic, readwrite) BOOL					 isScaledDown;
@property (nonatomic, readwrite) NSUInteger				 rowIndex;
@property (nonatomic, readwrite, copy, nullable) NSString *annotationText;
@end


@implementation LDrawStepPartListPlacement

- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@ row %lu at (%.1f, %.1f) %.1fx%.1f%@>",
			NSStringFromClass([self class]),
			self.entry.partName,
			(unsigned long)self.rowIndex,
			self.cellFrame.origin.x, self.cellFrame.origin.y,
			self.cellFrame.size.width, self.cellFrame.size.height,
			self.isScaledDown ? @" reduced" : @""];
}

@end


#pragma mark - Layout -

@interface LDrawStepPartListLayout ()
@property (nonatomic, readwrite) Size2		contentSize;
@property (nonatomic, readwrite) double		scale;
@property (nonatomic, readwrite) NSUInteger	rowCount;
@property (nonatomic, readwrite) NSArray<LDrawStepPartListPlacement *> *placements;
@property (nonatomic, readwrite) NSUInteger	overflowCount;
@property (nonatomic) double				framePadding;
@property (nonatomic, readwrite) double		pointsPerInch;
@property (nonatomic, readwrite) double		oneRowFrameWidth;
@property (nonatomic, readwrite) double		oneRowFrameHeight;
@property (nonatomic, readwrite) double		tallestFrameHeight;
@property (nonatomic, readwrite) Size2		resizeStartSize;
/// The narrowest frame width at which no cell passes its share of the box.
@property (nonatomic) double				shareFrameWidth;
/// What the resize limits are measured from, until they are first read.
@property (nonatomic, nullable) NSArray<LDrawStepPartListCell *> *limitCells;
@property (nonatomic) LDrawStepPartListMetrics limitMetrics;
@end


@implementation LDrawStepPartListLayout

// MARK: - DEFAULTS -

//---------- defaultMetrics ------------------------------------------[static]--
///
/// @abstract	Sensible metrics to start from.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListMetrics) defaultMetrics
{
	LDrawStepPartListMetrics metrics;

	// LPub3D's default resolution, used off the page.
	metrics.pointsPerInch				= 150.0;

	// One point per LDU: a part is the size it is in a viewport at 100%, so a
	// stud is 20 points across. On LPub3D's page the document's scale wins.
	metrics.baseScale					= 1.0;
	metrics.minimumScale				= 0.15;

	metrics.cellPadding					= 3.0;
	metrics.labelHeight					= 12.0;

	// Room for the badge: text the size of the count, its border, and a point
	// of gap.
	metrics.annotationHeight			= 15.0;

	// A little wider than the widest digit of the text they measure.
	metrics.labelCharacterWidth			= 6.5;
	metrics.annotationCharacterWidth	= 6.5;
	metrics.decorationGap				= 1.0;

	metrics.rowGap						= 6.0;

	metrics.framePadding				= 6.0;
	metrics.maximumCellWidthFraction	= 0.6;
	metrics.maximumHeight				= 0.0;

	return metrics;

}//end defaultMetrics


//---------- defaultConstraint ---------------------------------------[static]--
///
/// @abstract	AREA, matching LPub3D's default.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListConstraint) defaultConstraint
{
	LDrawStepPartListConstraint constraint;

	constraint.mode		= LPubPliConstrainModeArea;
	constraint.inches	= 0.0;
	constraint.columns	= 0;

	return constraint;

}//end defaultConstraint


//---------- constraintForDirective: ---------------------------------[static]--
///
/// @abstract	The constraint a directive expresses.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListConstraint) constraintForDirective:(LPubPliConstrain *)directive
{
	if (directive == nil) {
		return [self defaultConstraint];
	}

	LDrawStepPartListConstraint constraint;

	constraint.mode		= directive.mode;
	constraint.inches	= (float)directive.inches;
	constraint.columns	= directive.columns;

	return constraint;

}//end constraintForDirective:


//---------- viewTransformForAngle: ----------------------------------[static]--
///
/// @abstract	A rotation-only transform for the given angle in degrees.
///
//------------------------------------------------------------------------------
+ (Matrix4) viewTransformForAngle:(Tuple3)degrees
{
	return Matrix4Rotate(IdentityMatrix4, degrees);

}//end viewTransformForAngle:


//---------- viewTransformForLatitude:longitude: ---------------------[static]--
///
/// @abstract	The view LPub3D's camera has for these angles, as a rotation.
///
/// @discussion	The columns are the camera's right, up and direction to it, the
/// 			last two negated because Bricksmith has -y up and -z away.
///
//------------------------------------------------------------------------------
+ (Matrix4) viewTransformForLatitude:(double)latitude longitude:(double)longitude
{
	double lon = longitude * M_PI / 180.0;
	double lat = latitude  * M_PI / 180.0;
	double cl = cos(lon), sl = sin(lon);
	double ca = cos(lat), sa = sin(lat);

	// The camera turned about the vertical by longitude, then tilted by
	// latitude, in LDraw's axes.
	Vector3	toCamera	= V3Make(sl * ca, -sa, -cl * ca);
	Vector3	up			= V3Make(-sl * sa, -ca, cl * sa);
	Vector3	right		= V3Cross(up, toCamera);

	Matrix4 transform = IdentityMatrix4;

	transform.element[0][0] = right.x;	transform.element[0][1] = -up.x;	transform.element[0][2] = -toCamera.x;
	transform.element[1][0] = right.y;	transform.element[1][1] = -up.y;	transform.element[1][2] = -toCamera.y;
	transform.element[2][0] = right.z;	transform.element[2][1] = -up.z;	transform.element[2][2] = -toCamera.z;

	return transform;

}//end viewTransformForLatitude:longitude:


//---------- getLatitude:longitude:ofViewTransform: ------------------[static]--
///
/// @abstract	Reads a view transform as LPub3D's camera angles. NO when the
/// 			camera is tilted to one side.
///
/// @discussion	The third column is the direction to the camera and the second
/// 			its up, both negated. Straight above or below, the direction
/// 			has no longitude, and the up gives it.
///
//------------------------------------------------------------------------------
+ (BOOL) getLatitude:(double *)outLatitude longitude:(double *)outLongitude ofViewTransform:(Matrix4)transform
{
	double toX			= -transform.element[0][2];
	double toY			= -transform.element[1][2];
	double toZ			= -transform.element[2][2];
	double upX			= -transform.element[0][1];
	double upZ			= -transform.element[2][1];
	double latitude		= degrees(asin(MAX(-1.0, MIN(1.0, -toY))));
	double longitude	= 0.0;

	if (hypot(toX, toZ) > 0.0001) {
		longitude = degrees(atan2(toX, -toZ));
	}
	else {
		double sign = (latitude > 0.0) ? 1.0 : -1.0;

		longitude = degrees(atan2(-upX * sign, upZ * sign));
	}

	// A view tilted to one side has no such angles.
	if (Matrix4RotationsWithinTolerance([self viewTransformForLatitude:latitude longitude:longitude],
										transform,
										0.001) == false) {
		return NO;
	}

	*outLatitude	= latitude;
	*outLongitude	= longitude;
	return YES;

}//end getLatitude:longitude:ofViewTransform:


// MARK: - LAYOUT -

//---------- layoutForEntries:constraint:viewTransform:metrics: ------[static]--
///
/// @abstract	Packs the entries and returns where everything goes.
///
//------------------------------------------------------------------------------
+ (instancetype) layoutForEntries:(NSArray<LDrawStepPartListEntry *> *)entries
					   constraint:(LDrawStepPartListConstraint)constraint
					viewTransform:(Matrix4)viewTransform
						  metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListLayout *layout = [LDrawStepPartListLayout new];

	layout.framePadding	= metrics.framePadding;
	layout.pointsPerInch	= metrics.pointsPerInch;
	layout.scale		= metrics.baseScale;
	layout.placements	= @[];
	layout.contentSize	= V2MakeSize(0.0, 0.0);

	if (entries.count == 0) {
		return layout;
	}

	NSArray<LDrawStepPartListCell *>	*cells		= [self measuredCellsForEntries:entries
																	  viewTransform:viewTransform
																			metrics:metrics];
	// The room on screen. Only this shrinks icons or drops shelves; a pinned
	// HEIGHT only arranges them.
	double								heightBudget = metrics.maximumHeight;

	// The limits are measured when first read, since only a resize drag reads them.
	layout.limitCells		= cells;
	layout.limitMetrics		= metrics;
	layout.shareFrameWidth	= [self shareFrameWidthOfCells:cells metrics:metrics];

	// Shrink the scale until the packing fits the height, or until the icons
	// would stop being readable.
	double						scale	= metrics.baseScale;
	LDrawStepPartListPacking	*packing = [self packCells:cells atScale:scale constraint:constraint metrics:metrics];
	NSUInteger					rounds	= 0;

	while (heightBudget > 0.0
		   && packing.height > heightBudget
		   && scale > metrics.minimumScale
		   && rounds < MAXIMUM_SHRINK_ROUNDS) {

		scale = MAX(metrics.minimumScale, scale * SHRINK_FACTOR);
		packing = [self packCells:cells atScale:scale constraint:constraint metrics:metrics];
		rounds += 1;
	}

	layout.scale		= scale;

	// Heaviest shelves at the bottom. Ordered before anything is dropped, so an
	// overflowing list loses its lightest parts.
	NSArray<LDrawStepPartListRow *>	*rows			= [self rowsOrderedHeaviestLast:packing.rows];
	NSUInteger											overflowCount	= 0;

	// Still too tall: drop whole shelves from the top, which are the lightest.
	if (heightBudget > 0.0) {
		NSMutableArray *kept = [rows mutableCopy];

		while (kept.count > 1
			   && [self heightOfStackedRows:kept offsets:packing.offsets metrics:metrics] > heightBudget) {
			overflowCount += [(NSArray *)kept.firstObject count];
			[kept removeObjectAtIndex:0];
		}
		rows = kept;
	}

	[layout applyRows:rows
			  offsets:packing.offsets
			  metrics:metrics
		overflowCount:overflowCount];

	[layout measureResizeStartForConstraint:constraint metrics:metrics];

	return layout;

}//end layoutForEntries:constraint:viewTransform:metrics:


//---------- shareFrameWidthOfCells:metrics: -------------------------[static]--
///
/// @abstract	The narrowest frame width at which no cell passes its share of
/// 			the box at the base scale. 0 when cells have no share.
///
//------------------------------------------------------------------------------
+ (double) shareFrameWidthOfCells:(NSArray<LDrawStepPartListCell *> *)cells
						  metrics:(LDrawStepPartListMetrics)metrics
{
	double fraction		= MIN(metrics.maximumCellWidthFraction, 1.0);
	double widestRoom	= 0.0;

	if (fraction <= 0.0) {
		return 0.0;
	}

	for (LDrawStepPartListCell *cell in cells) {
		widestRoom = MAX(widestRoom, cell.iconLDU.width * metrics.baseScale + 2.0 * metrics.cellPadding);
	}

	return widestRoom / fraction + 2.0 * metrics.framePadding;

}//end shareFrameWidthOfCells:metrics:


//========== measureResizeLimits ===============================================
///
/// @abstract	The frame sizes past which a resize drag changes nothing, at the
/// 			base scale and whatever the constraint. Measured once.
///
//==============================================================================
- (void) measureResizeLimits
{
	NSArray<LDrawStepPartListCell *>	*cells		= self.limitCells;
	LDrawStepPartListMetrics			 metrics	= self.limitMetrics;

	if (cells == nil) {
		return;
	}
	self.limitCells = nil;

	// A width of 0 draws no icon smaller, as in the searching modes.
	NSArray<LDrawStepPartListPlacedCell *>	*placedCells	=
		[[self class] placedCellsForCells:cells
								  atScale:metrics.baseScale
							 contentWidth:0.0
								  metrics:metrics];
	LDrawStepPartListPacking				*oneRow			= [[self class] shelfPackPlacedCells:placedCells
																					contentWidth:DBL_MAX
																						 metrics:metrics];
	double									 widestCell		= 0.0;

	for (LDrawStepPartListPlacedCell *placed in placedCells) {
		widestCell = MAX(widestCell, placed.size.width);
	}

	// The narrowest packing HEIGHT tries is as wide as the widest cell.
	LDrawStepPartListPacking	*tallest	= [[self class] shelfPackPlacedCells:placedCells
																	contentWidth:widestCell
																		 metrics:metrics];
	double						 padding	= 2.0 * metrics.framePadding;

	// Narrower than the share width an icon is drawn smaller, and a smaller
	// icon takes a shelf of its own.
	_oneRowFrameWidth	= MAX(oneRow.usedWidth + padding, self.shareFrameWidth);
	_oneRowFrameHeight	= oneRow.height + padding;
	_tallestFrameHeight	= tallest.height + padding;

}//end measureResizeLimits


//========== oneRowFrameWidth ==================================================
- (double) oneRowFrameWidth
{
	[self measureResizeLimits];
	return _oneRowFrameWidth;

}//end oneRowFrameWidth


//========== oneRowFrameHeight =================================================
- (double) oneRowFrameHeight
{
	[self measureResizeLimits];
	return _oneRowFrameHeight;

}//end oneRowFrameHeight


//========== tallestFrameHeight ================================================
- (double) tallestFrameHeight
{
	[self measureResizeLimits];
	return _tallestFrameHeight;

}//end tallestFrameHeight


//========== measureResizeStartForConstraint:metrics: ==========================
///
/// @abstract	The smallest frame size that packs this list the same again,
/// 			for a resize drag to start from.
///
/// @discussion	Any narrower width that still holds the widest shelf, with no
/// 			cell past its share, wraps the shelves the same. A cell drawn
/// 			smaller, shrunk icons and dropped shelves depend on the size
/// 			asked for, so then only that size is sure to.
///
//==============================================================================
- (void) measureResizeStartForConstraint:(LDrawStepPartListConstraint)constraint
								 metrics:(LDrawStepPartListMetrics)metrics
{
	Size2	start				= self.frameSize;
	BOOL	packingWasAdjusted	= (self.scale < metrics.baseScale || self.overflowCount > 0);

	for (LDrawStepPartListPlacement *placement in self.placements) {
		packingWasAdjusted = packingWasAdjusted || placement.isScaledDown;
	}

	if (packingWasAdjusted == NO) {
		start.width = MAX(start.width, self.shareFrameWidth);
	}
	else if (constraint.mode == LPubPliConstrainModeWidth) {
		start.width = MAX(start.width, constraint.inches * self.pointsPerInch);
	}
	else if (constraint.mode == LPubPliConstrainModeHeight) {
		start.height = MAX(start.height, constraint.inches * self.pointsPerInch);
	}

	self.resizeStartSize = start;

}//end measureResizeStartForConstraint:metrics:


//========== applyRows:offsets:metrics:overflowCount: ==========================
///
/// @abstract	Turns packed shelves into placements with absolute positions.
///
//==============================================================================
- (void) applyRows:(NSArray<LDrawStepPartListRow *> *)rows
		   offsets:(LDrawStepPartListOffsets *)offsets
		   metrics:(LDrawStepPartListMetrics)metrics
	 overflowCount:(NSUInteger)overflowCount
{
	NSMutableArray<LDrawStepPartListPlacement *>	*placements	= [NSMutableArray array];
	double											 bottom		= 0.0;

	// The widest shelf, whatever WIDTH asked for, as LPub3D does. Found before
	// anything is placed, because a capped cell is centered across it.
	double				 contentWidth	= [[self class] widestRowWidthOfRows:rows offsets:offsets];
	NSArray<NSNumber *>	*tops			= [[self class] topsOfRows:rows
														   offsets:offsets
													  contentWidth:contentWidth
															bottom:&bottom
														   metrics:metrics];

	for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {

		NSArray<LDrawStepPartListPlacedCell *>	*row			= rows[rowIndex];
		NSArray<NSNumber *>						*rowOffsets		= [offsets objectForKey:row];
		double									 rowHeight		= [[self class] heightOfRow:row metrics:metrics];
		BOOL									 labelIsInStrip	= [[self class] rowKeepsLabelStrip:row];
		double									 y				= tops[rowIndex].doubleValue;
		double									 shift			= [[self class] shiftOfRow:row
																			  contentWidth:contentWidth];
		LDrawStepPartListShelfLabels			*labels			= [[self class] labelsOfRow:row
																					offsets:rowOffsets
																					metrics:metrics];
		NSData									*badges			= [[self class] badgesOfRow:row
																					 labels:labels
																					metrics:metrics];
		Point2									 line			= V2Make(shift, y + rowHeight);

		for (NSUInteger index = 0; index < row.count; index++) {

			LDrawStepPartListPlacedCell *placed = row[index];

			// Cell bottoms line up, and so do the icon bottoms, since every cell
			// on a shelf gets the same count strip.
			double x		= shift + rowOffsets[index].doubleValue;
			double height	= [[self class] heightOfCell:placed labelIsInStrip:labelIsInStrip metrics:metrics];
			double top		= y + rowHeight - height;

			LDrawStepPartListPlacement *placement = [self placementForCell:placed
																  atOrigin:V2Make(x, top)
																  rowIndex:rowIndex
															labelIsInStrip:labelIsInStrip
																   metrics:metrics];

			// The labels as the shelf left them, which can be away from the part.
			if (placement.showsCount) {
				placement.labelFrame = OffsetBox(((const Box2 *)labels.counts.bytes)[index], line);
			}

			if (placed.showsAnnotation) {
				placement.annotationFrame = OffsetBox(((const Box2 *)badges.bytes)[index], line);
			}

			[placements addObject:placement];
		}
	}

	self.rowCount		= rows.count;
	self.placements		= placements;
	self.overflowCount	= overflowCount;
	self.contentSize	= V2MakeSize(contentWidth, bottom);

}//end applyRows:offsets:metrics:overflowCount:


//========== placementForCell:atOrigin:rowIndex:labelIsInStrip:metrics: ========
///
/// @abstract	One cell's frames, given the cell's top-left corner and whether
/// 			its shelf puts the counts in strips. The labels are left for the
/// 			shelf to place, with an empty badge at the cell's corner.
///
//==============================================================================
- (LDrawStepPartListPlacement *) placementForCell:(LDrawStepPartListPlacedCell *)placedCell
										 atOrigin:(Point2)origin
										 rowIndex:(NSUInteger)rowIndex
								   labelIsInStrip:(BOOL)labelIsInStrip
										  metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListPlacement	*placement	= [LDrawStepPartListPlacement new];
	LDrawStepPartListCell		*cell		= placedCell.cell;
	double						 padding	= metrics.cellPadding;
	double						 height		= [[self class] heightOfCell:placedCell
														  labelIsInStrip:labelIsInStrip
																 metrics:metrics];

	placement.entry				= cell.entry;
	placement.scale				= placedCell.scale;
	placement.isScaledDown		= placedCell.isScaledDown;
	placement.rowIndex			= rowIndex;
	placement.annotationText	= placedCell.showsAnnotation ? cell.studText : nil;
	placement.cellFrame			= V2MakeBox(origin.x, origin.y, placedCell.size.width, height);
	placement.annotationFrame	= V2MakeBox(origin.x, origin.y, 0.0, 0.0);
	placement.labelFrame		= V2MakeBox(origin.x, origin.y, 0.0, 0.0);
	placement.showsCount		= cell.showsCount;

	// A cell can be wider than its icon, and the icon stays centered in it.
	Box2	room		= [[self class] roomOfPlacedCell:placedCell metrics:metrics];
	Point2	roomOrigin	= V2Add(origin, V2Make(MAX(0.0, placedCell.size.width - room.size.width) / 2.0,
											   [[self class] badgeStripHeightOfCell:placedCell metrics:metrics]));

	placement.iconFrame	= V2BoxInset(OffsetBox(room, roomOrigin), padding, padding);

	return placement;

}//end placementForCell:atOrigin:rowIndex:labelIsInStrip:metrics:


//========== frameSize =========================================================
///
/// @abstract	The content plus its padding on all four sides.
///
//==============================================================================
- (Size2) frameSize
{
	if (self.placements.count == 0) {
		return V2MakeSize(0.0, 0.0);
	}

	return V2MakeSize(self.contentSize.width  + 2.0 * self.framePadding,
					  self.contentSize.height + 2.0 * self.framePadding);

}//end frameSize


//========== placementAtPoint: =================================================
///
/// @abstract	The placement under a point of the content, or nil.
///
/// @discussion	A count can sink below its shelf and a badge rise into a taller
/// 			neighbor's cell, so a point on a label belongs to that label's
/// 			part. Cells slid together overlap, and then the one whose icon's
/// 			middle is nearest wins.
///
//==============================================================================
- (nullable LDrawStepPartListPlacement *) placementAtPoint:(Point2)point
{
	for (LDrawStepPartListPlacement *placement in self.placements) {
		BOOL onCount = placement.showsCount && V2BoxContains(placement.labelFrame, point);
		BOOL onBadge = (placement.annotationText != nil) && V2BoxContains(placement.annotationFrame, point);

		if (onCount || onBadge) {
			return placement;
		}
	}

	LDrawStepPartListPlacement	*nearest	= nil;
	double						 shortest	= DBL_MAX;

	for (LDrawStepPartListPlacement *placement in self.placements) {
		if (V2BoxContains(placement.cellFrame, point) == NO) {
			continue;
		}

		Point2 middle	= V2BoxMid(placement.iconFrame);
		double distance	= hypot(point.x - middle.x, point.y - middle.y);

		if (distance < shortest) {
			shortest	= distance;
			nearest		= placement;
		}
	}

	return nearest;

}//end placementAtPoint:


// MARK: - PACKING -

//---------- packCells:atScale:constraint:metrics: -------------------[static]--
///
/// @abstract	Packs at a given scale, choosing the content width the
/// 			constraint calls for.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) packCells:(NSArray<LDrawStepPartListCell *> *)cells
								 atScale:(double)scale
							  constraint:(LDrawStepPartListConstraint)constraint
								 metrics:(LDrawStepPartListMetrics)metrics
{
	switch (constraint.mode) {

		case LPubPliConstrainModeColumns: {
			// A huge count would otherwise loop over empty columns.
			NSUInteger columns = MIN((NSUInteger)MAX((NSInteger)1, constraint.columns), cells.count);

			return [self gridPackCells:cells atScale:scale columns:columns metrics:metrics];
		}

		case LPubPliConstrainModeWidth: {
			double contentWidth = ContentPointsForInches(constraint.inches, metrics);

			// The only mode with a width set from outside, so the only one
			// where one huge part can crowd out the rest.
			NSArray<LDrawStepPartListPlacedCell *> *placedCells = [self placedCellsForCells:cells
																					atScale:scale
																			   contentWidth:contentWidth
																					metrics:metrics];

			return [self shelfPackPlacedCells:placedCells contentWidth:contentWidth metrics:metrics];
		}

		case LPubPliConstrainModeHeight:
		case LPubPliConstrainModeSquare:
		case LPubPliConstrainModeArea:
		default:
			return [self searchPackCells:cells atScale:scale constraint:constraint metrics:metrics];
	}

}//end packCells:atScale:constraint:metrics:


//---------- shelfPackPlacedCells:contentWidth:metrics: --------------[static]--
///
/// @abstract	Lays the cells on shelves of a fixed width, in the order given.
///
/// @discussion	Each cell is slid in against the ones before it on its shelf,
/// 			and a shelf is full when the slid cell would still pass the width.
///
/// 			The cells given are not moved, so they can be packed again at
/// 			other widths.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) shelfPackPlacedCells:(NSArray<LDrawStepPartListPlacedCell *> *)placedCells
									   contentWidth:(double)contentWidth
											metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableArray<LDrawStepPartListRow *>	*rows			= [NSMutableArray array];
	LDrawStepPartListOffsets				*offsets		= [self emptyOffsets];
	NSArray<LDrawStepPartListPlacedCell *>	*currentRow		= @[];
	NSArray<NSNumber *>						*rowOffsets		= @[];
	BOOL									 labelIsInStrip	= NO;

	void (^closeRow)(LDrawStepPartListRow *, NSArray<NSNumber *> *) =
		^(LDrawStepPartListRow *row, NSArray<NSNumber *> *rowOffsets) {
			[rows addObject:row];
			[offsets setObject:[self offsetsTuckingTailOfRow:row offsets:rowOffsets] forKey:row];
		};

	for (LDrawStepPartListPlacedCell *placed in placedCells) {

		if (placed.isScaledDown) {
			// Otherwise a wide cell leaves a ragged shelf.
			if (currentRow.count > 0) {
				closeRow(currentRow, rowOffsets);
				currentRow		= @[];
				rowOffsets		= @[];
				labelIsInStrip	= NO;
			}
			closeRow(@[placed], @[@0.0]);
			continue;
		}

		NSArray<LDrawStepPartListPlacedCell *>	*row		= [currentRow arrayByAddingObject:placed];
		BOOL									 inStrip	= labelIsInStrip || placed.countIsInStrip;
		NSArray<NSNumber *>						*rowAt		= nil;

		// A count moving into a strip changes every cell's shape on the shelf.
		if (inStrip == labelIsInStrip) {
			double x = [self offsetOfCell:placed
							   afterCells:currentRow
								  offsets:rowOffsets
						   labelIsInStrip:inStrip
								  metrics:metrics];

			rowAt = [rowOffsets arrayByAddingObject:@(x)];
		}
		else {
			rowAt = [self offsetsOfRow:row labelIsInStrip:inStrip metrics:metrics];
		}

		if (currentRow.count > 0 && [self widthOfRow:row offsets:rowAt] > contentWidth + FIT_EPSILON) {
			closeRow(currentRow, rowOffsets);

			row		= @[placed];
			rowAt	= @[@0.0];
			inStrip	= placed.countIsInStrip;
		}

		currentRow		= row;
		rowOffsets		= rowAt;
		labelIsInStrip	= inStrip;
	}

	if (currentRow.count > 0) {
		closeRow(currentRow, rowOffsets);
	}

	return [self packingWithRows:rows offsets:offsets metrics:metrics];

}//end shelfPackPlacedCells:contentWidth:metrics:


//---------- gridPackCells:atScale:columns:metrics: ------------------[static]--
///
/// @abstract	A fixed number of columns, each as wide as its widest cell.
///
/// @discussion	Nothing is drawn smaller here. The width comes from the parts,
/// 			so a big part just gets a wide column.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) gridPackCells:(NSArray<LDrawStepPartListCell *> *)cells
									 atScale:(double)scale
									 columns:(NSUInteger)columns
									 metrics:(LDrawStepPartListMetrics)metrics
{
	// Built here because the grid widens these cells to their columns. A width
	// of 0 means no cell is drawn smaller.
	NSArray<LDrawStepPartListPlacedCell *>			*placedCells	= [self placedCellsForCells:cells
																						atScale:scale
																				   contentWidth:0.0
																						metrics:metrics];
	NSMutableArray<NSMutableArray<LDrawStepPartListPlacedCell *> *>
													*rows			= [NSMutableArray array];

	for (NSUInteger index = 0; index < placedCells.count; index++) {

		if (index % columns == 0) {
			[rows addObject:[NSMutableArray array]];
		}
		[rows.lastObject addObject:placedCells[index]];
	}

	// Every cell in a column takes that column's width, so the grid lines up.
	NSMutableArray<NSNumber *> *columnWidths = [NSMutableArray array];

	for (NSUInteger column = 0; column < columns; column++) {
		double widest = 0.0;

		for (NSArray<LDrawStepPartListPlacedCell *> *row in rows) {
			if (column < row.count) {
				widest = MAX(widest, row[column].size.width);
			}
		}
		[columnWidths addObject:@(widest)];
	}

	// Nothing slides here, or the columns would not line up.
	LDrawStepPartListOffsets *offsets = [self emptyOffsets];

	for (NSMutableArray<LDrawStepPartListPlacedCell *> *row in rows) {
		NSMutableArray<NSNumber *>	*rowOffsets	= [NSMutableArray array];
		double						 x			= 0.0;

		for (NSUInteger column = 0; column < row.count; column++) {
			LDrawStepPartListPlacedCell *placed = row[column];
			placed.size = V2MakeSize(columnWidths[column].doubleValue, placed.size.height);

			[rowOffsets addObject:@(x)];
			x += placed.size.width;
		}
		[offsets setObject:rowOffsets forKey:row];
	}

	return [self packingWithRows:rows offsets:offsets metrics:metrics];

}//end gridPackCells:atScale:columns:metrics:


//---------- packingWithRows:offsets:metrics: ------------------------[static]--
///
/// @abstract	A packing of these finished shelves, measured.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) packingWithRows:(NSArray<LDrawStepPartListRow *> *)rows
									   offsets:(LDrawStepPartListOffsets *)offsets
									   metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListPacking *packing = [LDrawStepPartListPacking new];

	packing.rows		= rows;
	packing.offsets		= offsets;
	// Measured in the order the shelves are placed, which decides how they stack.
	packing.height		= [self heightOfStackedRows:[self rowsOrderedHeaviestLast:rows]
											offsets:offsets
											metrics:metrics];
	packing.usedWidth	= [self widestRowWidthOfRows:rows offsets:offsets];

	return packing;

}//end packingWithRows:offsets:metrics:


//---------- emptyOffsets --------------------------------------------[static]--
///
/// @abstract	A table of shelf offsets, keyed by the shelf itself rather than
/// 			by what it holds.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListOffsets *) emptyOffsets
{
	NSPointerFunctionsOptions byShelf = NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality;

	return [NSMapTable mapTableWithKeyOptions:byShelf valueOptions:NSPointerFunctionsStrongMemory];

}//end emptyOffsets


//---------- searchPackCells:atScale:constraint:metrics: -------------[static]--
///
/// @abstract	Tries several widths and keeps the best one for this constraint.
///
/// @discussion	The widths tried are the running totals of the cell widths. This
/// 			is a heuristic: other widths can pack differently.
///
/// 			No cell is drawn smaller here, so the cells are sized once and
/// 			every width packs the same ones.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) searchPackCells:(NSArray<LDrawStepPartListCell *> *)cells
									   atScale:(double)scale
									constraint:(LDrawStepPartListConstraint)constraint
									   metrics:(LDrawStepPartListMetrics)metrics
{
	// A width of 0 means no cell is drawn smaller. These modes take their width
	// from the cells, so shrinking one would change the width it came from.
	NSArray<LDrawStepPartListPlacedCell *>	*placedCells	= [self placedCellsForCells:cells
																				atScale:scale
																		   contentWidth:0.0
																				metrics:metrics];
	NSArray<NSNumber *>						*candidates		= [self candidateWidthsForPlacedCells:placedCells
																						  metrics:metrics];
	LDrawStepPartListPacking				*best			= nil;
	double									 bestScore		= 0.0;
	BOOL									 bestFits		= NO;

	for (NSNumber *candidate in candidates) {

		LDrawStepPartListPacking *packing = [self shelfPackPlacedCells:placedCells
														  contentWidth:candidate.doubleValue
															   metrics:metrics];

		double	score	= 0.0;
		BOOL	fits	= YES;

		switch (constraint.mode) {

			case LPubPliConstrainModeSquare:
				score = fabs(packing.usedWidth - packing.height);
				break;

			case LPubPliConstrainModeHeight:
				// The narrowest box that fits the pinned height. If none
				// fits, take the shortest instead: the narrowest would be one
				// tall column, which is the worst answer.
				fits = (packing.height <= ContentPointsForInches(constraint.inches, metrics));
				score = fits ? packing.usedWidth : packing.height;
				break;

			case LPubPliConstrainModeArea:
			default:
				score = packing.usedWidth * packing.height;
				break;
		}

		BOOL better = (best == nil)
					|| (fits && !bestFits)
					|| (fits == bestFits && score < bestScore);

		if (better) {
			best		= packing;
			bestScore	= score;
			bestFits	= fits;
		}
	}

	return best;

}//end searchPackCells:atScale:constraint:metrics:


//---------- candidateWidthsForPlacedCells:metrics: ------------------[static]--
///
/// @abstract	The widths worth trying, smallest first and without repeats.
///
/// @discussion	Each is the width of the first so many cells on one shelf, slid
/// 			together, and measured with labels and all, because a cell can
/// 			be wider than its icon.
///
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *) candidateWidthsForPlacedCells:(NSArray<LDrawStepPartListPlacedCell *> *)placedCells
												metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableSet<NSNumber *>	*candidates	= [NSMutableSet set];
	double						 widest		= 0.0;

	for (LDrawStepPartListPlacedCell *placed in placedCells) {
		widest = MAX(widest, placed.size.width);
	}

	// Counts go in strips from the first cell with no room beside its part.
	NSUInteger firstStripped = placedCells.count;

	for (NSUInteger index = 0; index < placedCells.count && firstStripped == placedCells.count; index++) {
		if (placedCells[index].countIsInStrip) {
			firstStripped = index;
		}
	}

	// A cell's offset depends only on the cells before it, so the first so many
	// cells of these shelves are already slid as they would be on their own.
	NSRange				 besideRange	= NSMakeRange(0, firstStripped);
	NSArray<NSNumber *>	*beside			= [self offsetsOfRow:[placedCells subarrayWithRange:besideRange]
											  labelIsInStrip:NO
													 metrics:metrics];
	NSArray<NSNumber *>	*inStrip		= nil;
	double				 besideEnd		= 0.0;
	double				 stripEnd		= 0.0;

	if (firstStripped < placedCells.count) {
		inStrip = [self offsetsOfRow:placedCells labelIsInStrip:YES metrics:metrics];
	}

	for (NSUInteger index = 0; index < placedCells.count; index++) {
		double width = placedCells[index].size.width;

		if (index < firstStripped) {
			besideEnd = MAX(besideEnd, beside[index].doubleValue + width);
		}
		if (inStrip != nil) {
			stripEnd = MAX(stripEnd, inStrip[index].doubleValue + width);
		}

		// No shelf is narrower than the widest cell.
		[candidates addObject:@(MAX(widest, (index < firstStripped) ? besideEnd : stripEnd))];
	}

	return [candidates.allObjects sortedArrayUsingSelector:@selector(compare:)];

}//end candidateWidthsForPlacedCells:metrics:


//---------- placedCellsForCells:atScale:contentWidth:metrics: -------[static]--
///
/// @abstract	Sizes every cell at one scale, in packing order.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListPlacedCell *> *) placedCellsForCells:(NSArray<LDrawStepPartListCell *> *)cells
														 atScale:(double)scale
													contentWidth:(double)contentWidth
														 metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableArray<LDrawStepPartListPlacedCell *> *placedCells = [NSMutableArray arrayWithCapacity:cells.count];

	for (LDrawStepPartListCell *cell in cells) {
		LDrawStepPartListPlacedCell *placed = [self placedCellForCell:cell
															  atScale:scale
														 contentWidth:contentWidth
															  metrics:metrics];
		placed.order = placedCells.count;
		[placedCells addObject:placed];
	}

	return placedCells;

}//end placedCellsForCells:atScale:contentWidth:metrics:


//---------- placedCellForCell:atScale:contentWidth:metrics: ---------[static]--
///
/// @abstract	Sizes one cell, drawing it smaller if its icon is too wide for
/// 			the box. A `contentWidth` of 0 never draws a cell smaller.
///
/// @discussion	At one shared scale a long beam would fill the box or make every
/// 			other icon too small to read, so it is scaled down on its own.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPlacedCell *) placedCellForCell:(LDrawStepPartListCell *)cell
											atScale:(double)scale
									   contentWidth:(double)contentWidth
											metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListPlacedCell *placed = [LDrawStepPartListPlacedCell new];

	placed.cell				= cell;
	placed.scale			= scale;
	placed.isScaledDown		= NO;
	placed.showsAnnotation	= cell.needsSizeBadge;
	placed.slides			= [NSMutableDictionary dictionary];
	placed.drops			= [NSMutableDictionary dictionary];
	placed.shelfLabels		= [NSMutableDictionary dictionary];

	if (contentWidth > 0.0) {

		// Whatever the fraction says, nothing may be wider than the box.
		double limit = MIN(MAX(contentWidth * metrics.maximumCellWidthFraction, 0.0), contentWidth);

		// Only the icon shrinks, so only the icon is tested.
		if ([self roomOfPlacedCell:placed metrics:metrics].size.width > limit) {

			double availableForIcon = limit - 2.0 * metrics.cellPadding;

			if (availableForIcon <= 0.0) {
				// The padding alone is over the limit, so drop it and give the
				// whole limit to the icon.
				availableForIcon = limit;
			}

			double cappedScale = MIN(scale, availableForIcon / cell.iconLDU.width);

			placed.scale		= cappedScale;
			placed.isScaledDown	= (cappedScale < scale);

			// A smaller icon misleads about its size, so it always gets a badge.
			placed.showsAnnotation	= cell.needsSizeBadge || (placed.isScaledDown && cell.studText != nil);
		}
	}

	Box2 room = [self roomOfPlacedCell:placed metrics:metrics];

	placed.roomOutline		= ScaledOutlineOfCell(cell, placed.scale, V2BoxMid(room));
	placed.labelBox			= cell.showsCount ? [self bottomLabelBoxOfCell:placed metrics:metrics] : ZeroBox2;
	placed.countIsInStrip	= cell.showsCount && BoxIsEmpty(placed.labelBox);
	placed.badgeIsInside	= placed.showsAnnotation
							&& [self getInsideBadgeBox:NULL ofCell:placed avoiding:placed.labelBox metrics:metrics];

	[self sizePlacedCell:placed metrics:metrics];

	return placed;

}//end placedCellForCell:atScale:contentWidth:metrics:


//---------- bottomLabelBoxOfCell:metrics: ---------------------------[static]--
///
/// @abstract	The multiplier's place beside the part, on the bottom line of
/// 			the icon's box, next to the part on the side with more room.
/// 			LPub3D puts it bottom-left, so that side wins a tie. Empty when
/// 			neither side has room.
///
//------------------------------------------------------------------------------
+ (Box2) bottomLabelBoxOfCell:(LDrawStepPartListPlacedCell *)placed
					  metrics:(LDrawStepPartListMetrics)metrics
{
	Size2	size	= placed.cell.labelSize;
	Box2	room	= [self roomOfPlacedCell:placed metrics:metrics];
	Box2	box		= ZeroBox2;

	[self getBox:&box
	  besidePart:placed
		  ofSize:size
		onLineAt:V2BoxMaxY(room) - size.height
		avoiding:ZeroBox2
	prefersRight:NO
		 metrics:metrics];

	return box;

}//end bottomLabelBoxOfCell:metrics:


//---------- getBox:besidePart:ofSize:onLineAt:avoiding:prefersRight:metrics:
///
/// @abstract	Puts a box of `size` on the line at height `y` of the icon's box,
/// 			`decorationGap` from the part and from `avoidedBox`: on the side
/// 			of them with more room on that line, and on the right when both
/// 			sides have the same if `prefersRight`. Answers NO when neither side
/// 			has room. Measured in the icon's box.
///
/// @discussion	A long part drawn at an angle reaches the top line at one end
/// 			and the bottom line at the other, and the box goes in the empty
/// 			corner beside that end.
///
//------------------------------------------------------------------------------
+ (BOOL) getBox:(nullable Box2 *)outBox
	 besidePart:(LDrawStepPartListPlacedCell *)placed
		 ofSize:(Size2)size
	   onLineAt:(double)y
	   avoiding:(Box2)avoidedBox
   prefersRight:(BOOL)prefersRight
		metrics:(LDrawStepPartListMetrics)metrics
{
	Box2	room	= [self roomOfPlacedCell:placed metrics:metrics];
	double	gap		= metrics.decorationGap;

	if (size.width > room.size.width || size.height > room.size.height) {
		return NO;
	}

	NSData	*outline	= placed.roomOutline;
	double	 top		= y - gap;
	double	 bottom		= y + size.height + gap;
	double	 left		= DBL_MAX;
	double	 right		= -DBL_MAX;

	BOOL isBlocked = PolygonSpanInBand(outline.bytes, outline.length / sizeof(Point2), top, bottom, &left, &right);

	if (BoxIsEmpty(avoidedBox) == NO && avoidedBox.origin.y < bottom && V2BoxMaxY(avoidedBox) > top) {
		left		= MIN(left, avoidedBox.origin.x);
		right		= MAX(right, V2BoxMaxX(avoidedBox));
		isBlocked	= YES;
	}

	// Nothing on the line: the corner the box would have gone to.
	double x = prefersRight ? V2BoxMaxX(room) - size.width : room.origin.x;

	if (isBlocked) {
		double roomOnLeft	= left - gap - room.origin.x;
		double roomOnRight	= V2BoxMaxX(room) - (right + gap);
		BOOL   goesRight	= (roomOnRight > roomOnLeft) || (roomOnRight == roomOnLeft && prefersRight);

		if (goesRight && roomOnRight >= size.width) {
			x = right + gap;
		}
		else if (goesRight == NO && roomOnLeft >= size.width) {
			x = left - gap - size.width;
		}
		else {
			return NO;
		}
	}

	if (outBox != NULL) {
		*outBox = V2MakeBox(x, y, size.width, size.height);
	}

	return YES;

}//end getBox:besidePart:ofSize:onLineAt:avoiding:prefersRight:metrics:


//---------- stripLabelBoxOfCell:metrics: ----------------------------[static]--
///
/// @abstract	Where the count goes in the strip below the icon, measured from
/// 			the cell's top-left: at the part's lowest corner, so it sits by
/// 			the part's bottom edge, and leaning toward the part's middle by
/// 			up to half its width, so it stands under the part.
///
/// @discussion	A long part drawn at an angle comes down to the strip at one end
/// 			only, and a count centered under the cell would sit below empty
/// 			space. A count centered on that corner would hang half past the
/// 			end of a small part. Under a flat bottom edge the count is
/// 			centered on it.
///
//------------------------------------------------------------------------------
+ (Box2) stripLabelBoxOfCell:(LDrawStepPartListPlacedCell *)placed
					 metrics:(LDrawStepPartListMetrics)metrics
{
	Box2			 room		= [self roomOfPlacedCell:placed metrics:metrics];
	NSData			*outline	= placed.roomOutline;
	const Point2	*corners	= outline.bytes;
	NSUInteger		 count		= outline.length / sizeof(Point2);
	double			 lowest		= -DBL_MAX;
	double			 left		= DBL_MAX;
	double			 right		= -DBL_MAX;

	for (NSUInteger index = 0; index < count; index++) {
		lowest = MAX(lowest, corners[index].y);
	}
	for (NSUInteger index = 0; index < count; index++) {
		if (corners[index].y >= lowest - BOTTOM_EDGE_SLACK) {
			left	= MIN(left, corners[index].x);
			right	= MAX(right, corners[index].x);
		}
	}

	// The icon's box is centered across the cell.
	double width	= placed.cell.labelSize.width;
	double corner	= (left + right) / 2.0;
	double lean		= MIN(MAX(V2BoxMidX(room) - corner, -width / 2.0), width / 2.0);
	double middle	= corner + lean + MAX(0.0, placed.size.width - room.size.width) / 2.0;
	double x		= MIN(MAX(0.0, middle - width / 2.0), placed.size.width - width);

	return V2MakeBox(x, placed.size.height, width, metrics.labelHeight);

}//end stripLabelBoxOfCell:metrics:


//---------- getInsideBadgeBox:ofCell:avoiding:metrics: --------------[static]--
///
/// @abstract	Puts the size badge on the top line of the icon's box, next to
/// 			the part, on the side with more room. LPub3D puts it top-right,
/// 			so that side wins a tie. Answers NO when neither side has room.
///
//------------------------------------------------------------------------------
+ (BOOL) getInsideBadgeBox:(nullable Box2 *)outBox
					ofCell:(LDrawStepPartListPlacedCell *)placed
				  avoiding:(Box2)labelBox
				   metrics:(LDrawStepPartListMetrics)metrics
{
	return [self getBox:outBox
			 besidePart:placed
				 ofSize:V2MakeSize(placed.cell.annotationWidth, metrics.annotationHeight)
			   onLineAt:0.0
			   avoiding:labelBox
		   prefersRight:YES
				metrics:metrics];

}//end getInsideBadgeBox:ofCell:avoiding:metrics:


//---------- badgeBoxOfCell:avoiding:metrics: ------------------------[static]--
///
/// @abstract	Where the size badge goes, measured in the icon box: on the top
/// 			line of the box when it fits there, otherwise in the strip above,
/// 			at negative y.
///
/// @discussion	In the strip it is centered across the icon's box, then let down
/// 			until it is `decorationGap` clear of the part and of `labelBox`. A
/// 			part drawn at an angle does not reach the top of its box, so
/// 			letting the badge down closes that gap. It never goes past the
/// 			middle of the box.
///
//------------------------------------------------------------------------------
+ (Box2) badgeBoxOfCell:(LDrawStepPartListPlacedCell *)placed
			   avoiding:(Box2)labelBox
				metrics:(LDrawStepPartListMetrics)metrics
{
	Box2 inside = ZeroBox2;

	// It fit with the count beside the part in the way, so it fits with less.
	if (placed.badgeIsInside && [self getInsideBadgeBox:&inside ofCell:placed avoiding:labelBox metrics:metrics]) {
		return inside;
	}

	Box2	 room		= [self roomOfPlacedCell:placed metrics:metrics];
	Size2	 size		= V2MakeSize(placed.cell.annotationWidth, metrics.annotationHeight);
	Point2	 middle		= V2BoxMid(room);
	NSData	*outline	= placed.roomOutline;

	Point2	start	= V2Make(V2SizeCenteredOnPoint(size, middle).origin.x, room.origin.y - size.height);
	Point2	end		= V2SizeCenteredOnPoint(size, middle).origin;
	Box2	lowered	= ZeroBox2;

	if (SlideBoxToward(size, start, end, outline.bytes, outline.length / sizeof(Point2),
					   labelBox, metrics.decorationGap, &lowered) == NO) {
		return V2MakeBox(start.x, start.y, size.width, size.height);
	}

	return lowered;

}//end badgeBoxOfCell:avoiding:metrics:


//---------- roomOfPlacedCell:metrics: -------------------------------[static]--
///
/// @abstract	The icon's padded box, in the cell's coordinates. Labels beside
/// 			the part go inside it, and strips are added around it.
///
//------------------------------------------------------------------------------
+ (Box2) roomOfPlacedCell:(LDrawStepPartListPlacedCell *)placed
				  metrics:(LDrawStepPartListMetrics)metrics
{
	return V2MakeBox(0.0, 0.0,
					 placed.cell.iconLDU.width  * placed.scale + 2.0 * metrics.cellPadding,
					 placed.cell.iconLDU.height * placed.scale + 2.0 * metrics.cellPadding);

}//end roomOfPlacedCell:metrics:


//---------- badgeStripHeightOfCell:metrics: -------------------------[static]--
///
/// @abstract	How tall a strip the cell keeps above its icon for the badge:
/// 			none when there is no badge or it fits on the icon's top line.
///
//------------------------------------------------------------------------------
+ (double) badgeStripHeightOfCell:(LDrawStepPartListPlacedCell *)placed
						  metrics:(LDrawStepPartListMetrics)metrics
{
	return (placed.showsAnnotation && placed.badgeIsInside == NO) ? metrics.annotationHeight : 0.0;

}//end badgeStripHeightOfCell:metrics:


//---------- sizePlacedCell:metrics: ---------------------------------[static]--
///
/// @abstract	The cell's size: the icon's padded box plus any badge strip. The
/// 			count's strip is added per shelf.
///
//------------------------------------------------------------------------------
+ (void) sizePlacedCell:(LDrawStepPartListPlacedCell *)placed
				metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListCell	*cell	= placed.cell;
	Box2					 room	= [self roomOfPlacedCell:placed metrics:metrics];

	// A label in a strip stays inside the cell, so the cell is at least as wide
	// as the label. A count that fits beside its part is never wider.
	double width = MAX(room.size.width, cell.labelSize.width);

	if (placed.showsAnnotation) {
		width = MAX(width, cell.annotationWidth);
	}

	placed.size = V2MakeSize(width, room.size.height + [self badgeStripHeightOfCell:placed metrics:metrics]);

}//end sizePlacedCell:metrics:


//---------- labelSizeForQuantity:metrics: ---------------------------[static]--
///
/// @abstract	The room the "3×" multiplier needs.
///
/// @discussion	Counted from the characters, not measured: the packer has no
/// 			fonts. A point of slack is added at each side.
///
//------------------------------------------------------------------------------
+ (Size2) labelSizeForQuantity:(NSUInteger)quantity
					   metrics:(LDrawStepPartListMetrics)metrics
{
	NSUInteger characters = [self quantityTextForQuantity:quantity].length;

	return V2MakeSize(characters * metrics.labelCharacterWidth + 2.0, metrics.labelHeight);

}//end labelSizeForQuantity:metrics:


//---------- quantityTextForQuantity: --------------------------------[static]--
///
/// @abstract	The multiplier under an icon.
///
/// @discussion	Shown on every entry, including "1×". A cell with no number
/// 			could mean one part or a missing count.
///
//------------------------------------------------------------------------------
+ (NSString *) quantityTextForQuantity:(NSUInteger)quantity
{
	return [NSString stringWithFormat:@"%lu\u00D7", (unsigned long)MAX((NSUInteger)1, quantity)];

}//end quantityTextForQuantity:


//---------- annotationWidthForText:metrics: -------------------------[static]--
///
/// @abstract	How wide the size badge is: its text, plus half the badge's
/// 			height at each end for the rounded ends.
///
//------------------------------------------------------------------------------
+ (double) annotationWidthForText:(nullable NSString *)text
						  metrics:(LDrawStepPartListMetrics)metrics
{
	// The badge is taken as two points shorter than its strip.
	double height = MAX(0.0, metrics.annotationHeight - 2.0);

	return text.length * metrics.annotationCharacterWidth + height;

}//end annotationWidthForText:metrics:


//---------- badgeRectForTextSize:inSlot: ----------------------------[static]--
///
/// @abstract	The size badge around text the host measured, centered in its
/// 			slot.
///
/// @discussion	The packer sized the slot from an estimate of the same width
/// 			(above), so the badge fits unless the font is wider than that.
/// 			Rounded to whole points so a one-point outline is crisp.
///
//------------------------------------------------------------------------------
+ (Box2) badgeRectForTextSize:(Size2)textSize inSlot:(Box2)slot
{
	double height	= MIN(V2BoxHeight(slot), ceil(textSize.height) + 1.0);
	double width	= MIN(V2BoxWidth(slot), ceil(textSize.width) + height);

	return V2MakeBox(round(V2BoxMidX(slot) - width / 2.0),
					 round(V2BoxMidY(slot) - height / 2.0),
					 width,
					 height);

}//end badgeRectForTextSize:inSlot:


//---------- heightOfRow:metrics: ------------------------------------[static]--
///
/// @abstract	How tall a shelf is: its tallest cell, plus the count strip when
/// 			the shelf keeps one.
///
/// @discussion	Every cell on a shelf gets the same strip, so lining up the cell
/// 			bottoms lines up the icons too.
///
//------------------------------------------------------------------------------
+ (double) heightOfRow:(NSArray<LDrawStepPartListPlacedCell *> *)row
			   metrics:(LDrawStepPartListMetrics)metrics
{
	double height = 0.0;

	for (LDrawStepPartListPlacedCell *placed in row) {
		height = MAX(height, placed.size.height);
	}

	return height + ([self rowKeepsLabelStrip:row] ? metrics.labelHeight : 0.0);

}//end heightOfRow:metrics:


//---------- rowKeepsLabelStrip: -------------------------------------[static]--
///
/// @abstract	Whether the counts on this shelf go in strips below the icons.
///
/// @discussion	Counts are read across a shelf, so if one has no room beside its
/// 			part, all go in strips.
///
//------------------------------------------------------------------------------
+ (BOOL) rowKeepsLabelStrip:(NSArray<LDrawStepPartListPlacedCell *> *)row
{
	for (LDrawStepPartListPlacedCell *placed in row) {
		if (placed.countIsInStrip) {
			return YES;
		}
	}

	return NO;

}//end rowKeepsLabelStrip:


//---------- rowsOrderedHeaviestLast: --------------------------------[static]--
///
/// @abstract	The same shelves, stacked with the heaviest at the bottom.
///
/// @discussion	Shelves are filled tallest part first, which puts the biggest
/// 			parts at the top. A shelf weighs as much as its heaviest part.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListRow *> *) rowsOrderedHeaviestLast:(NSArray<LDrawStepPartListRow *> *)rows
{
	double (^heaviest)(LDrawStepPartListRow *) = ^double(LDrawStepPartListRow *row) {
		double weight = 0.0;

		for (LDrawStepPartListPlacedCell *placed in row) {
			weight = MAX(weight, placed.cell.weight);
		}
		return weight;
	};

	// Reversed first, so of two shelves of equal weight the later, shorter one
	// goes above.
	NSArray<LDrawStepPartListRow *> *reversed = rows.reverseObjectEnumerator.allObjects;

	return [reversed sortedArrayWithOptions:NSSortStable
							usingComparator:^NSComparisonResult(LDrawStepPartListRow *a, LDrawStepPartListRow *b) {

		double weightA = heaviest(a);
		double weightB = heaviest(b);

		if (weightA != weightB) {
			return (weightA < weightB) ? NSOrderedAscending : NSOrderedDescending;
		}
		return NSOrderedSame;
	}];

}//end rowsOrderedHeaviestLast:


//---------- widestRowWidthOfRows:offsets: ---------------------------[static]--
///
/// @abstract	The width of the widest shelf.
///
//------------------------------------------------------------------------------
+ (double) widestRowWidthOfRows:(NSArray<LDrawStepPartListRow *> *)rows
						offsets:(LDrawStepPartListOffsets *)offsets
{
	double widest = 0.0;

	for (LDrawStepPartListRow *row in rows) {
		widest = MAX(widest, [self widthOfRow:row offsets:[offsets objectForKey:row]]);
	}

	return widest;

}//end widestRowWidthOfRows:offsets:


//---------- widthOfRow:offsets: -------------------------------------[static]--
///
/// @abstract	How far a shelf reaches: the right edge of the cell that ends
/// 			last. A cell slid under the one before it can end before it.
///
//------------------------------------------------------------------------------
+ (double) widthOfRow:(NSArray<LDrawStepPartListPlacedCell *> *)row
			  offsets:(NSArray<NSNumber *> *)offsets
{
	double width = 0.0;

	for (NSUInteger index = 0; index < row.count; index++) {
		width = MAX(width, offsets[index].doubleValue + row[index].size.width);
	}

	return width;

}//end widthOfRow:offsets:


// MARK: - SLIDING -

//---------- offsetsTuckingTailOfRow:offsets: ------------------------[static]--
///
/// @abstract	The same offsets, with the cells that end under an earlier,
/// 			bigger one moved right until the last of them lines up with its
/// 			right edge.
///
/// @discussion	As LPub3D puts a part that fits under the right side of the one
/// 			before it. Only the cells after the one that ends the shelf move,
/// 			so the shelf keeps its width, and a cell moved right stays as
/// 			clear of the cells before it as it was.
///
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *) offsetsTuckingTailOfRow:(NSArray<LDrawStepPartListPlacedCell *> *)row
										  offsets:(NSArray<NSNumber *> *)offsets
{
	double		width	= [self widthOfRow:row offsets:offsets];
	NSUInteger	last	= 0;

	// The last cell that reaches the end of the shelf.
	for (NSUInteger index = row.count; index > 0; index--) {
		if (offsets[index - 1].doubleValue + row[index - 1].size.width >= width - FIT_EPSILON) {
			last = index - 1;
			break;
		}
	}

	if (last + 1 >= row.count) {
		return offsets;
	}

	NSRange						 range		= NSMakeRange(last + 1, row.count - last - 1);
	NSArray<NSNumber *>			*tail		= [offsets subarrayWithRange:range];
	double						 shift		= width - [self widthOfRow:[row subarrayWithRange:range] offsets:tail];
	NSMutableArray<NSNumber *>	*tucked		= [offsets mutableCopy];

	for (NSUInteger index = range.location; index < row.count; index++) {
		tucked[index] = @(offsets[index].doubleValue + shift);
	}

	return tucked;

}//end offsetsTuckingTailOfRow:offsets:


//---------- offsetsOfRow:labelIsInStrip:metrics: --------------------[static]--
///
/// @abstract	Where each cell on a shelf starts, each slid in against the ones
/// 			before it.
///
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *) offsetsOfRow:(NSArray<LDrawStepPartListPlacedCell *> *)row
						labelIsInStrip:(BOOL)labelIsInStrip
							   metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:row.count];

	for (NSUInteger index = 0; index < row.count; index++) {
		double x = [self offsetOfCell:row[index]
						   afterCells:[row subarrayWithRange:NSMakeRange(0, index)]
							  offsets:offsets
					   labelIsInStrip:labelIsInStrip
							  metrics:metrics];

		[offsets addObject:@(x)];
	}

	return offsets;

}//end offsetsOfRow:labelIsInStrip:metrics:


//---------- offsetOfCell:afterCells:offsets:labelIsInStrip:metrics: -[static]--
///
/// @abstract	Where a cell starts on a shelf after `cells`, which start at
/// 			`offsets`.
///
/// @discussion	The cell is slid left until it comes too near something an
/// 			earlier cell draws: its part the gap between parts from another
/// 			part, and a label two paddings from anything. A part drawn at an
/// 			angle leaves empty corners in its cell, and the next part moves
/// 			into them, as LPub3D slides one part into the next.
///
/// 			It never starts left of the cell before it, nor right of where
/// 			the cells' boxes alone would put it.
///
//------------------------------------------------------------------------------
+ (double) offsetOfCell:(LDrawStepPartListPlacedCell *)placed
			 afterCells:(NSArray<LDrawStepPartListPlacedCell *> *)cells
				offsets:(NSArray<NSNumber *> *)offsets
		 labelIsInStrip:(BOOL)labelIsInStrip
				metrics:(LDrawStepPartListMetrics)metrics
{
	if (cells.count == 0) {
		return 0.0;
	}

	LDrawStepPartListCellShapes	*moving		= [self shapesOfPlacedCell:placed
														labelIsInStrip:labelIsInStrip
															   metrics:metrics];
	double						 padding	= metrics.cellPadding;
	double						 x			= offsets.lastObject.doubleValue;
	double						 boxesEnd	= 0.0;

	// Nearest first. An earlier cell whose shapes end before this cell's shapes
	// begin, with this cell at `x`, cannot push it further, and is skipped.
	for (NSUInteger index = cells.count; index > 0; index--) {
		LDrawStepPartListPlacedCell	*earlier	= cells[index - 1];
		double						 start		= offsets[index - 1].doubleValue;
		LDrawStepPartListCellShapes	*fixed		= [self shapesOfPlacedCell:earlier
															labelIsInStrip:labelIsInStrip
																   metrics:metrics];

		// The moving part is grown by the gap, which reaches past its padding.
		double reach = moving.left + padding - PartGap(fixed.partSize, moving.partSize, padding);

		boxesEnd = MAX(boxesEnd, start + earlier.size.width);

		if (start + fixed.right - reach <= x) {
			continue;
		}

		double slide = [self slideOfCell:placed
							   afterCell:earlier
						  labelIsInStrip:labelIsInStrip
								 metrics:metrics];

		x = MAX(x, start + slide);
	}

	return MIN(x, boxesEnd);

}//end offsetOfCell:afterCells:offsets:labelIsInStrip:metrics:


//---------- slideOfCell:afterCell:labelIsInStrip:metrics: -----------[static]--
///
/// @abstract	How far right of where `earlier` starts the cell `later` must
/// 			start to stay clear of it. Less than `earlier`'s width when
/// 			`later` fits into an empty corner of it.
///
//------------------------------------------------------------------------------
+ (double) slideOfCell:(LDrawStepPartListPlacedCell *)later
			 afterCell:(LDrawStepPartListPlacedCell *)earlier
		labelIsInStrip:(BOOL)labelIsInStrip
			   metrics:(LDrawStepPartListMetrics)metrics
{
	NSNumber	*key		= @(2 * earlier.order + (labelIsInStrip ? 1 : 0));
	NSNumber	*remembered	= later.slides[key];

	if (remembered != nil) {
		return remembered.doubleValue;
	}

	LDrawStepPartListCellShapes	*fixed	= [self shapesOfPlacedCell:earlier
													labelIsInStrip:labelIsInStrip
														   metrics:metrics];
	LDrawStepPartListCellShapes	*moving	= [self shapesOfPlacedCell:later
													labelIsInStrip:labelIsInStrip
														   metrics:metrics];
	double						 slide	= [self distanceToClearShapes:fixed
														   withShapes:moving
															  movedBy:ZeroPoint2
															 downward:NO
															  metrics:metrics];

	later.slides[key] = @(slide);

	return slide;

}//end slideOfCell:afterCell:labelIsInStrip:metrics:


//---------- distanceToClearShapes:withShapes:movedBy:downward:metrics: -------
///
/// @abstract	How much further right, or down when `downward`, the shapes
/// 			`moving` must go, after `offset`, to stand clear of `fixed`: the
/// 			part by the gap between parts, the labels by two paddings.
/// 			-DBL_MAX when nothing of the two shares a line.
///
/// @discussion	Both are measured from their own cell's bottom-left corner.
///
//------------------------------------------------------------------------------
+ (double) distanceToClearShapes:(LDrawStepPartListCellShapes *)fixed
					  withShapes:(LDrawStepPartListCellShapes *)moving
						 movedBy:(Point2)offset
						downward:(BOOL)downward
						 metrics:(LDrawStepPartListMetrics)metrics
{
	NSData *(^place)(NSData *, BOOL) = ^NSData *(NSData *polygon, BOOL moves) {
		return MovedPolygon(polygon, moves ? offset : ZeroPoint2, downward);
	};

	double gap		= PartGap(fixed.partSize, moving.partSize, metrics.cellPadding);
	double ownGap	= PartGap(moving.partSize, moving.partSize, metrics.cellPadding);

	// Only the moving part is grown, by the whole gap.
	NSData						*grownPart		= (gap == ownGap)
												? moving.grownOutline
												: GrownPolygon(moving.outline.bytes,
															   moving.outline.length / sizeof(Point2), gap);
	NSData						*fixedPart		= place(fixed.paddedOutline, NO);
	NSData						*movingPart		= place(moving.paddedOutline, YES);
	NSMutableArray<NSData *>	*movingLabels	= [NSMutableArray arrayWithCapacity:moving.labels.count];
	double						 distance		= SlideDistance(place(fixed.outline, NO), place(grownPart, YES));

	for (NSData *label in moving.labels) {
		NSData *movingLabel = place(label, YES);

		[movingLabels addObject:movingLabel];
		distance = MAX(distance, SlideDistance(fixedPart, movingLabel));
	}
	for (NSData *label in fixed.labels) {
		NSData *fixedLabel = place(label, NO);

		distance = MAX(distance, SlideDistance(fixedLabel, movingPart));

		for (NSData *movingLabel in movingLabels) {
			distance = MAX(distance, SlideDistance(fixedLabel, movingLabel));
		}
	}

	return distance;

}//end distanceToClearShapes:withShapes:movedBy:downward:metrics:


//---------- topsOfRows:offsets:contentWidth:bottom:metrics: ---------[static]--
///
/// @abstract	Where each shelf's top goes, from the top down: `rowGap` below
/// 			everything above it, or closer when it and the shelf above both
/// 			hold one part. Sets `outBottom` to where the lowest one ends.
///
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *) topsOfRows:(NSArray<LDrawStepPartListRow *> *)rows
							 offsets:(LDrawStepPartListOffsets *)offsets
						contentWidth:(double)contentWidth
							  bottom:(double *)outBottom
							 metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableArray<NSNumber *>	*tops			= [NSMutableArray arrayWithCapacity:rows.count];
	LDrawStepPartListPlacedCell	*above			= nil;
	double						 aboveX			= 0.0;
	double						 aboveBottom	= 0.0;
	double						 bottom			= 0.0;
	double						 y				= 0.0;

	for (LDrawStepPartListRow *row in rows) {
		NSArray<NSNumber *>	*rowOffsets	= [offsets objectForKey:row];
		double				 rowHeight	= [self heightOfRow:row metrics:metrics];
		double				 depth		= [self labelsOfRow:row offsets:rowOffsets metrics:metrics].depth;
		double				 x			= [self shiftOfRow:row contentWidth:contentWidth]
										+ rowOffsets.firstObject.doubleValue;

		// One part under one part rises toward it.
		if (row.count == 1 && above != nil) {
			double lowerBottom = [self bottomOfCell:row.firstObject
												atX:x
										  underCell:above
												atX:aboveX
											 bottom:aboveBottom
											metrics:metrics];

			y = lowerBottom - rowHeight;
		}

		[tops addObject:@(y)];

		above		= (row.count == 1) ? row.firstObject : nil;
		aboveX		= x;
		aboveBottom	= y + rowHeight;

		// Counts moved below the shelf's line push the next shelf down.
		bottom	= MAX(bottom, y + rowHeight + depth);
		y		= bottom + metrics.rowGap;
	}

	*outBottom = bottom;

	return tops;

}//end topsOfRows:offsets:contentWidth:bottom:metrics:


//---------- heightOfStackedRows:offsets:metrics: --------------------[static]--
///
/// @abstract	How tall these shelves are, stacked as they are placed.
///
//------------------------------------------------------------------------------
+ (double) heightOfStackedRows:(NSArray<LDrawStepPartListRow *> *)rows
					   offsets:(LDrawStepPartListOffsets *)offsets
					   metrics:(LDrawStepPartListMetrics)metrics
{
	double bottom = 0.0;

	[self topsOfRows:rows
			 offsets:offsets
		contentWidth:[self widestRowWidthOfRows:rows offsets:offsets]
			  bottom:&bottom
			 metrics:metrics];

	return bottom;

}//end heightOfStackedRows:offsets:metrics:


//---------- shiftOfRow:contentWidth: --------------------------------[static]--
///
/// @abstract	How far right a whole shelf goes: a cell drawn smaller has the
/// 			shelf to itself and is centered.
///
//------------------------------------------------------------------------------
+ (double) shiftOfRow:(LDrawStepPartListRow *)row contentWidth:(double)contentWidth
{
	if (row.count == 1 && row.firstObject.isScaledDown) {
		return MAX(0.0, (contentWidth - row.firstObject.size.width) / 2.0);
	}

	return 0.0;

}//end shiftOfRow:contentWidth:


//---------- bottomOfCell:atX:underCell:atX:bottom:metrics: ----------[static]--
///
/// @abstract	Where the bottom of a shelf's only cell goes when the shelf
/// 			above also holds one: raised until something it draws comes as
/// 			near the cell above as two parts on a shelf may.
///
/// @discussion	Two such shelves stack like a column, so the lower part can
/// 			move up into the empty corners of the upper one, as LPub3D lets
/// 			a part down into the one below it in a column. It never goes
/// 			above the top of the shelf above, nor below where the shelf gap
/// 			alone would put it.
///
//------------------------------------------------------------------------------
+ (double) bottomOfCell:(LDrawStepPartListPlacedCell *)lower
					atX:(double)lowerX
			  underCell:(LDrawStepPartListPlacedCell *)upper
					atX:(double)upperX
				 bottom:(double)upperBottom
				metrics:(LDrawStepPartListMetrics)metrics
{
	BOOL	upperInStrip	= upper.countIsInStrip;
	BOOL	lowerInStrip	= lower.countIsInStrip;
	double	upperHeight		= [self heightOfCell:upper labelIsInStrip:upperInStrip metrics:metrics];
	double	lowerHeight		= [self heightOfCell:lower labelIsInStrip:lowerInStrip metrics:metrics];

	// Kept only for cells that start at the same place, as every packing but
	// a cell drawn smaller has them.
	NSNumber	*key		= @(upper.order);
	NSNumber	*remembered	= (lowerX == upperX) ? lower.drops[key] : nil;
	double		 drop		= remembered.doubleValue;

	if (remembered == nil) {
		LDrawStepPartListCellShapes	*fixed	= [self shapesOfPlacedCell:upper
														labelIsInStrip:upperInStrip
															   metrics:metrics];
		LDrawStepPartListCellShapes	*moving	= [self shapesOfPlacedCell:lower
														labelIsInStrip:lowerInStrip
															   metrics:metrics];

		// The labels of the two stay on lines of their own, a shelf gap apart,
		// so a badge below does not read as part of the count above it.
		double lines = [self bottomOfLabels:fixed] + metrics.rowGap - [self topOfLabels:moving];

		drop = [self distanceToClearShapes:fixed
								withShapes:moving
								   movedBy:V2Make(lowerX - upperX, 0.0)
								  downward:YES
								   metrics:metrics];
		drop = MAX(drop, lines);

		if (lowerX == upperX) {
			lower.drops[key] = @(drop);
		}
	}

	double highest	= upperBottom - upperHeight + lowerHeight;
	double lowest	= upperBottom + metrics.rowGap + lowerHeight;

	return MIN(lowest, MAX(highest, upperBottom + drop));

}//end bottomOfCell:atX:underCell:atX:bottom:metrics:


//---------- topOfLabels: --------------------------------------------[static]--
///
/// @abstract	The top of a cell's highest label, measured from the cell's
/// 			bottom. Its bottom when it has no label.
///
//------------------------------------------------------------------------------
+ (double) topOfLabels:(LDrawStepPartListCellShapes *)shapes
{
	double top = 0.0;

	if (BoxIsEmpty(shapes.countBox) == NO) {
		top = MIN(top, shapes.countBox.origin.y);
	}
	if (BoxIsEmpty(shapes.badgeBox) == NO) {
		top = MIN(top, shapes.badgeBox.origin.y);
	}

	return top;

}//end topOfLabels:


//---------- bottomOfLabels: -----------------------------------------[static]--
///
/// @abstract	The bottom of a cell's lowest label, measured from the cell's
/// 			bottom. Far above the cell when it has no label.
///
//------------------------------------------------------------------------------
+ (double) bottomOfLabels:(LDrawStepPartListCellShapes *)shapes
{
	double bottom = -DBL_MAX;

	if (BoxIsEmpty(shapes.countBox) == NO) {
		bottom = MAX(bottom, V2BoxMaxY(shapes.countBox));
	}
	if (BoxIsEmpty(shapes.badgeBox) == NO) {
		bottom = MAX(bottom, V2BoxMaxY(shapes.badgeBox));
	}

	return bottom;

}//end bottomOfLabels:


//---------- heightOfCell:labelIsInStrip:metrics: --------------------[static]--
///
/// @abstract	How tall a cell stands on its shelf: its size, plus the count
/// 			strip when the shelf keeps one.
///
//------------------------------------------------------------------------------
+ (double) heightOfCell:(LDrawStepPartListPlacedCell *)placed
		 labelIsInStrip:(BOOL)labelIsInStrip
				metrics:(LDrawStepPartListMetrics)metrics
{
	return placed.size.height + (labelIsInStrip ? metrics.labelHeight : 0.0);

}//end heightOfCell:labelIsInStrip:metrics:


//---------- roomOriginOfCell:labelIsInStrip:metrics: ----------------[static]--
///
/// @abstract	Where the icon's padded box starts, measured from the cell's
/// 			bottom-left corner: centered across the cell, as when it is
/// 			placed, and below any badge strip.
///
//------------------------------------------------------------------------------
+ (Point2) roomOriginOfCell:(LDrawStepPartListPlacedCell *)placed
			 labelIsInStrip:(BOOL)labelIsInStrip
					metrics:(LDrawStepPartListMetrics)metrics
{
	Box2	room		= [self roomOfPlacedCell:placed metrics:metrics];
	double	cellHeight	= [self heightOfCell:placed labelIsInStrip:labelIsInStrip metrics:metrics];
	double	badgeStrip	= [self badgeStripHeightOfCell:placed metrics:metrics];

	return V2Make(MAX(0.0, placed.size.width - room.size.width) / 2.0, badgeStrip - cellHeight);

}//end roomOriginOfCell:labelIsInStrip:metrics:


//---------- countBoxOfCell:labelIsInStrip:metrics: ------------------[static]--
///
/// @abstract	Where the count goes, measured from the cell's bottom-left
/// 			corner: in the strip or beside the part.
///
//------------------------------------------------------------------------------
+ (Box2) countBoxOfCell:(LDrawStepPartListPlacedCell *)placed
		 labelIsInStrip:(BOOL)labelIsInStrip
				metrics:(LDrawStepPartListMetrics)metrics
{
	if (placed.cell.showsCount == NO) {
		return ZeroBox2;
	}

	if (labelIsInStrip) {
		double cellHeight = [self heightOfCell:placed labelIsInStrip:YES metrics:metrics];

		return OffsetBox([self stripLabelBoxOfCell:placed metrics:metrics], V2Make(0.0, -cellHeight));
	}

	return OffsetBox(placed.labelBox, [self roomOriginOfCell:placed labelIsInStrip:NO metrics:metrics]);

}//end countBoxOfCell:labelIsInStrip:metrics:


//---------- badgeBoxOfCell:labelIsInStrip:metrics: ------------------[static]--
///
/// @abstract	Where the badge goes, measured from the cell's bottom-left
/// 			corner, or an empty box when there is none.
///
/// @discussion	On a strip shelf the count is below the icon, so the badge has
/// 			nothing of its own to avoid.
///
//------------------------------------------------------------------------------
+ (Box2) badgeBoxOfCell:(LDrawStepPartListPlacedCell *)placed
		 labelIsInStrip:(BOOL)labelIsInStrip
				metrics:(LDrawStepPartListMetrics)metrics
{
	if (placed.showsAnnotation == NO) {
		return ZeroBox2;
	}

	Box2 badge = [self badgeBoxOfCell:placed
							 avoiding:(labelIsInStrip ? ZeroBox2 : placed.labelBox)
							  metrics:metrics];

	return OffsetBox(badge, [self roomOriginOfCell:placed labelIsInStrip:labelIsInStrip metrics:metrics]);

}//end badgeBoxOfCell:labelIsInStrip:metrics:


//---------- countBoxOfCell:onLine:metrics: --------------------------[static]--
///
/// @abstract	Where a count beside its part goes when the shelf's counts sit
/// 			on a line `line` points below the shelf's bottom line, measured
/// 			from the cell's bottom-left corner.
///
/// @discussion	Next to the part on that line as on the bottom line, on the side
/// 			with more room. A line below the part, or one with no room next
/// 			to it, puts the count under the part as in a strip, and never
/// 			higher than `decorationGap` below the part, so it can reach past
/// 			the line.
///
//------------------------------------------------------------------------------
+ (Box2) countBoxOfCell:(LDrawStepPartListPlacedCell *)placed
				 onLine:(double)line
				metrics:(LDrawStepPartListMetrics)metrics
{
	Size2			 size		= placed.cell.labelSize;
	Point2			 roomOrigin	= [self roomOriginOfCell:placed labelIsInStrip:NO metrics:metrics];
	double			 y			= line - size.height - roomOrigin.y;
	const Point2	*corners	= placed.roomOutline.bytes;
	NSUInteger		 count		= placed.roomOutline.length / sizeof(Point2);
	double			 gap		= metrics.decorationGap;
	Box2			 box		= ZeroBox2;

	// With nothing of the part on the line, the box would go to a corner of the
	// icon's box rather than next to the part.
	BOOL touchesPart = PolygonSpanInBand(corners, count, y - gap, y + size.height + gap, NULL, NULL);

	if (touchesPart && [self getBox:&box
						 besidePart:placed
							 ofSize:size
						   onLineAt:y
						   avoiding:ZeroBox2
					   prefersRight:NO
							metrics:metrics]) {
		return OffsetBox(box, roomOrigin);
	}

	double partBottom = -DBL_MAX;

	for (NSUInteger index = 0; index < count; index++) {
		partBottom = MAX(partBottom, corners[index].y + roomOrigin.y);
	}

	Box2	strip	= [self stripLabelBoxOfCell:placed metrics:metrics];
	double	top		= MAX(line - size.height, partBottom + gap);

	return V2MakeBox(strip.origin.x, top, size.width, size.height);

}//end countBoxOfCell:onLine:metrics:


//---------- labelsOfRow:offsets:metrics: ----------------------------[static]--
///
/// @abstract	The cells and counts of a shelf, each count moved along the
/// 			bottom of its own part when it came nearer another part than
/// 			LABEL_CLEARANCE_GAPS gaps.
///
/// @discussion	A count beside its part can be slid into the corner of a
/// 			neighbor and read as its label. It moves down below the shelf's
/// 			line by at most a count's height, and the shelf grows by that.
/// 			Counts in a strip stay put. Kept on the shelf's first cell,
/// 			because a search measures the same shelves at many widths.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListShelfLabels *) labelsOfRow:(LDrawStepPartListRow *)row
									   offsets:(NSArray<NSNumber *> *)offsets
									   metrics:(LDrawStepPartListMetrics)metrics
{
	NSUInteger						 count	= row.count;
	NSNumber						*key	= @(count);
	LDrawStepPartListShelfLabels	*labels	= row.firstObject.shelfLabels[key];

	if (labels != nil) {
		return labels;
	}

	BOOL			 labelIsInStrip	= [self rowKeepsLabelStrip:row];
	NSMutableData	*cells			= [NSMutableData dataWithLength:count * sizeof(Box2)];
	NSMutableData	*counts			= [NSMutableData dataWithLength:count * sizeof(Box2)];

	NSMutableArray<LDrawStepPartListCellShapes *> *shapes = [NSMutableArray arrayWithCapacity:count];

	for (NSUInteger index = 0; index < count; index++) {
		LDrawStepPartListPlacedCell	*placed		= row[index];
		double						 x			= offsets[index].doubleValue;
		double						 height		= [self heightOfCell:placed
													  labelIsInStrip:labelIsInStrip
															 metrics:metrics];
		LDrawStepPartListCellShapes	*cellShapes	= [self shapesOfPlacedCell:placed
															labelIsInStrip:labelIsInStrip
																   metrics:metrics];

		((Box2 *)cells.mutableBytes)[index]		= V2MakeBox(x, -height, placed.size.width, height);
		((Box2 *)counts.mutableBytes)[index]	= OffsetBox(cellShapes.countBox, V2Make(x, 0.0));
		[shapes addObject:cellShapes];
	}

	labels			= [LDrawStepPartListShelfLabels new];
	labels.cells	= cells;
	labels.shapes	= shapes;
	labels.counts	= counts;

	if (count > 1 && labelIsInStrip == NO) {
		NSMutableData			*badges	= [NSMutableData dataWithLength:count * sizeof(Box2)];
		LDrawStepPartListShelf	 shelf	= ShelfOfLabels(labels, counts.mutableBytes, badges.mutableBytes, metrics);

		for (NSUInteger index = 0; index < count; index++) {
			LabelKeptClear(&shelf.counts[index], index, NO, &shelf, -DBL_MAX, metrics.labelHeight, NO);
		}

		// The counts of a shelf are read as one line, so when one sank below the
		// shelf's line, the others go down to it too, each next to its own part.
		// If one finds no clear place on that line, every count keeps the place
		// it had.
		double depth = DepthOfBoxes(shelf.counts, count);

		if (depth > FIT_EPSILON) {
			NSData	*before	= [NSData dataWithBytes:shelf.counts length:count * sizeof(Box2)];
			double	 line	= depth;
			BOOL	 clear	= YES;

			for (NSUInteger index = 0; index < count; index++) {
				Box2 sunk = shelf.counts[index];

				if (V2BoxMaxY(sunk) > FIT_EPSILON) {
					sunk.origin.y = depth - sunk.size.height;
				}
				else {
					sunk = OffsetBox([self countBoxOfCell:row[index] onLine:depth metrics:metrics],
									 V2Make(shelf.cells[index].origin.x, 0.0));
				}
				shelf.counts[index] = sunk;
				line = MAX(line, V2BoxMaxY(sunk));
			}

			// A count put under its part can reach past the line; the others follow.
			for (NSUInteger index = 0; index < count; index++) {
				shelf.counts[index].origin.y = line - shelf.counts[index].size.height;
			}

			for (NSUInteger index = 0; index < count && clear; index++) {
				clear = LabelKeptClear(&shelf.counts[index], index, NO, &shelf, -DBL_MAX, DBL_MAX, YES);
			}

			if (clear == NO) {
				memcpy(shelf.counts, before.bytes, before.length);
			}
		}
	}

	labels.depth = DepthOfBoxes(counts.bytes, count);
	row.firstObject.shelfLabels[key] = labels;

	return labels;

}//end labelsOfRow:offsets:metrics:


//---------- badgesOfRow:labels:metrics: -----------------------------[static]--
///
/// @abstract	The badges of a shelf with these cells and counts, as `Box2`s,
/// 			each moved along the top of its own part when it came nearer
/// 			another part than LABEL_CLEARANCE_GAPS gaps.
///
/// @discussion	A badge on the top line of its box can be slid into the corner
/// 			of a neighbor and read as its label. It moves up into the room a
/// 			shorter cell leaves above it on the shelf, so it never changes
/// 			the shelf's size. Badges in a strip stay put.
///
//------------------------------------------------------------------------------
+ (NSData *) badgesOfRow:(LDrawStepPartListRow *)row
				  labels:(LDrawStepPartListShelfLabels *)labels
				 metrics:(LDrawStepPartListMetrics)metrics
{
	NSUInteger				 count		= row.count;
	NSMutableData			*counts		= [labels.counts mutableCopy];
	NSMutableData			*badges		= [NSMutableData dataWithLength:count * sizeof(Box2)];
	LDrawStepPartListShelf	 shelf		= ShelfOfLabels(labels, counts.mutableBytes, badges.mutableBytes, metrics);
	double					 rowHeight	= [self heightOfRow:row metrics:metrics];

	for (NSUInteger index = 0; count > 1 && index < count; index++) {
		if (row[index].badgeIsInside) {
			LabelKeptClear(&shelf.badges[index], index, YES, &shelf, -rowHeight, DBL_MAX, NO);
		}
	}

	return badges;

}//end badgesOfRow:labels:metrics:


//---------- shapesOfPlacedCell:labelIsInStrip:metrics: --------------[static]--
///
/// @abstract	What a cell draws, as convex shapes: the part's outline, the
/// 			count and the badge. Labels are grown by a padding, so labels of
/// 			two cells that touch are two paddings apart.
///
/// @discussion	Measured from the cell's bottom-left corner, so cells standing
/// 			on one shelf can be compared as they are.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListCellShapes *) shapesOfPlacedCell:(LDrawStepPartListPlacedCell *)placed
									 labelIsInStrip:(BOOL)labelIsInStrip
											metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListCellShapes *shapes = labelIsInStrip ? placed.stripShapes : placed.besideShapes;

	if (shapes != nil) {
		return shapes;
	}

	LDrawStepPartListCell		*cell		= placed.cell;
	double						 grow		= metrics.cellPadding;
	Point2						 roomOrigin	= [self roomOriginOfCell:placed
													  labelIsInStrip:labelIsInStrip
															 metrics:metrics];
	NSData						*outline	= MovedPolygon(placed.roomOutline, roomOrigin, NO);
	NSUInteger					 count		= outline.length / sizeof(Point2);
	NSMutableArray<NSData *>	*labels		= [NSMutableArray array];
	Box2						 label		= [self countBoxOfCell:placed
													labelIsInStrip:labelIsInStrip
														   metrics:metrics];
	Box2						 badge		= [self badgeBoxOfCell:placed
													labelIsInStrip:labelIsInStrip
														   metrics:metrics];

	if (BoxIsEmpty(label) == NO) {
		[labels addObject:GrownBox(label, grow)];
	}

	if (BoxIsEmpty(badge) == NO) {
		[labels addObject:GrownBox(badge, grow)];
	}

	shapes					= [LDrawStepPartListCellShapes new];
	shapes.outline			= outline;
	shapes.paddedOutline	= GrownPolygon(outline.bytes, count, grow);
	shapes.labels			= labels;
	shapes.countBox			= label;
	shapes.badgeBox			= badge;
	shapes.column			= MovedPolygon(outline, ZeroPoint2, YES);
	shapes.partSize			= MIN(cell.iconLDU.width, cell.iconLDU.height) * placed.scale;
	shapes.grownOutline		= GrownPolygon(outline.bytes, count, PartGap(shapes.partSize, shapes.partSize, grow));

	double left		= DBL_MAX;
	double right	= -DBL_MAX;

	for (NSData *polygon in [labels arrayByAddingObject:shapes.paddedOutline]) {
		const Point2 *corners = polygon.bytes;

		for (NSUInteger index = 0; index < polygon.length / sizeof(Point2); index++) {
			left	= MIN(left, corners[index].x);
			right	= MAX(right, corners[index].x);
		}
	}

	shapes.left		= left;
	shapes.right	= right;

	if (labelIsInStrip) {
		placed.stripShapes = shapes;
	}
	else {
		placed.besideShapes = shapes;
	}

	return shapes;

}//end shapesOfPlacedCell:labelIsInStrip:metrics:


// MARK: - MEASURING -

//---------- measuredCellsForEntries:viewTransform:metrics: ----------[static]--
///
/// @abstract	Measures every entry once and sorts them for packing.
///
/// @discussion	Sorted tallest icon first, then largest icon area, then in the
/// 			order given. Icon sizes do not depend on the scale, so the order
/// 			holds for every repack.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListCell *> *) measuredCellsForEntries:(NSArray<LDrawStepPartListEntry *> *)entries
												 viewTransform:(Matrix4)viewTransform
													   metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableArray<LDrawStepPartListCell *> *cells = [NSMutableArray arrayWithCapacity:entries.count];

	// A list of nothing but one submodel placed once needs no "1×": the
	// picture alone says what to build.
	LDrawStepPartListEntry	*only		= entries.firstObject;
	BOOL					 hasCounts	= (entries.count != 1 || only.isSubmodel == NO || only.quantity > 1);

	for (LDrawStepPartListEntry *entry in entries) {
		LDrawStepPartListCell	*cell		= [LDrawStepPartListCell new];
		Box3					 bounds		= entry.modelBounds;
		NSData					*outline	= nil;
		long					 studsAcross	= 0;
		long					 studsDeep	= 0;

		cell.entry		= entry;
		cell.iconLDU	= [self projectedExtentOfEntry:entry
											 transform:[self transformForEntry:entry viewTransform:viewTransform]
											   outline:&outline];
		cell.outline	= outline;
		cell.weight		= [self weightOfBounds:bounds];

		// A stud count names a part. A submodel is not one, and "4×6" on it
		// would describe a part that is not there.
		if (entry.isSubmodel == NO && [self getStudsAcross:&studsAcross deep:&studsDeep forBounds:bounds]) {
			long limit = [self isTileTitle:entry.displayTitle] ? TILE_STUDS_WORTH_ANNOTATING : STUDS_WORTH_ANNOTATING;

			// Short side first, the way part names read.
			long shortSide	= MIN(studsAcross, studsDeep);
			long longSide	= MAX(studsAcross, studsDeep);

			cell.studText		= [NSString stringWithFormat:@"%ld\u00D7%ld", shortSide, longSide];
			cell.needsSizeBadge	= longSide > limit;
		}

		cell.showsCount			= hasCounts;
		cell.labelSize			= hasCounts ? [self labelSizeForQuantity:entry.quantity metrics:metrics]
											: V2MakeSize(0.0, 0.0);
		cell.annotationWidth	= [self annotationWidthForText:cell.studText metrics:metrics];

		[cells addObject:cell];
	}

	// Stable, so equal cells keep the order given and the layout is repeatable.
	return [cells sortedArrayWithOptions:NSSortStable
						 usingComparator:^NSComparisonResult(LDrawStepPartListCell *a, LDrawStepPartListCell *b) {

		if (a.iconLDU.height != b.iconLDU.height) {
			return (a.iconLDU.height > b.iconLDU.height) ? NSOrderedAscending : NSOrderedDescending;
		}

		double areaA = a.iconLDU.width * a.iconLDU.height;
		double areaB = b.iconLDU.width * b.iconLDU.height;

		if (areaA != areaB) {
			return (areaA > areaB) ? NSOrderedAscending : NSOrderedDescending;
		}

		return NSOrderedSame;
	}];

}//end measuredCellsForEntries:viewTransform:metrics:


//---------- projectedPointsOfEntry:transform: -----------------------[static]--
///
/// @abstract	The points an entry is measured by, seen through `transform` and
/// 			packed as `Point3`s: its outline points when it has them,
/// 			otherwise the eight corners of its bounds. nil when it has neither.
///
//------------------------------------------------------------------------------
+ (nullable NSData *) projectedPointsOfEntry:(LDrawStepPartListEntry *)entry
								   transform:(Matrix4)transform
{
	NSData *points = entry.outlinePoints;

	if (points.length < sizeof(Point3)) {

		Box3	bounds = entry.modelBounds;
		Point3	corners[8];

		if (V3EqualBoxes(bounds, InvalidBox)) {
			return nil;
		}

		for (NSUInteger corner = 0; corner < 8; corner++) {
			corners[corner] = V3Make((corner & 1) ? bounds.max.x : bounds.min.x,
									 (corner & 2) ? bounds.max.y : bounds.min.y,
									 (corner & 4) ? bounds.max.z : bounds.min.z);
		}
		points = [NSData dataWithBytes:corners length:sizeof(corners)];
	}

	NSUInteger		 count		= points.length / sizeof(Point3);
	const Point3	*source		= points.bytes;
	NSMutableData	*projected	= [NSMutableData dataWithLength:count * sizeof(Point3)];
	Point3			*target		= projected.mutableBytes;

	for (NSUInteger index = 0; index < count; index++) {
		target[index] = V3MulPointByProjMatrix(source[index], transform);
	}

	return projected;

}//end projectedPointsOfEntry:transform:


//---------- transformForEntry:viewTransform: -----------------------[static]--
///
/// @abstract	The entry's own turn, then the list's view.
///
//------------------------------------------------------------------------------
+ (Matrix4) transformForEntry:(LDrawStepPartListEntry *)entry
				viewTransform:(Matrix4)viewTransform
{
	return Matrix4Multiply(entry.listOrientation, viewTransform);

}//end transformForEntry:viewTransform:


//---------- projectedCenterOfEntry:viewTransform: -------------------[static]--
///
/// @abstract	The middle of what the packer measured, in view space.
///
/// @discussion	For a submodel measured by its parts it can be well away from
/// 			the middle of its box, and using the box would leave empty space
/// 			on one side.
///
//------------------------------------------------------------------------------
+ (Point3) projectedCenterOfEntry:(LDrawStepPartListEntry *)entry
					viewTransform:(Matrix4)viewTransform
{
	NSData *points = [self projectedPointsOfEntry:entry
										transform:[self transformForEntry:entry viewTransform:viewTransform]];

	if (points == nil) {
		return ZeroPoint3;
	}

	const Point3	*projected	= points.bytes;
	NSUInteger		 count		= points.length / sizeof(Point3);
	Box3			 box		= InvalidBox;

	for (NSUInteger index = 0; index < count; index++) {
		box = V3UnionBoxAndPoint(box, projected[index]);
	}

	return V3CenterOfBox(box);

}//end projectedCenterOfEntry:viewTransform:


//---------- projectedExtentOfEntry:transform:outline: ---------------[static]--
///
/// @abstract	How much room an entry takes on screen at this rotation, in
/// 			LDU, and its `outline`: a convex polygon of packed `Point2`s
/// 			measured from the icon's center.
///
/// @discussion	Measured from box corners, which a part never crosses, so text
/// 			kept off the outline is kept off the part. With no points, or
/// 			points seen edge-on, the outline is the whole rectangle.
///
//------------------------------------------------------------------------------
+ (Size2) projectedExtentOfEntry:(LDrawStepPartListEntry *)entry
					   transform:(Matrix4)transform
						 outline:(NSData * __autoreleasing *)outline
{
	Size2		extent		= V2MakeSize(FALLBACK_EXTENT_LDU, FALLBACK_EXTENT_LDU);
	NSData		*hull		= nil;
	NSData		*points		= [self projectedPointsOfEntry:entry transform:transform];

	if (points != nil) {

		const Point3	*source		= points.bytes;
		NSUInteger		 count		= points.length / sizeof(Point3);
		Point2			*projected	= malloc(count * sizeof(Point2));
		Point2			*chain		= malloc((2 * count + 1) * sizeof(Point2));
		double			 minX = DBL_MAX, maxX = -DBL_MAX, minY = DBL_MAX, maxY = -DBL_MAX;

		for (NSUInteger index = 0; index < count; index++) {

			Point3 point = source[index];

			projected[index] = V2Make(point.x, point.y);

			minX = MIN(minX, point.x);
			maxX = MAX(maxX, point.x);
			minY = MIN(minY, point.y);
			maxY = MAX(maxY, point.y);
		}

		// A flat part seen edge-on would otherwise measure zero, and dividing
		// by that would crash.
		extent = V2MakeSize(MAX(MINIMUM_EXTENT_LDU, maxX - minX),
							MAX(MINIMUM_EXTENT_LDU, maxY - minY));

		for (NSUInteger index = 0; index < count; index++) {
			projected[index].x -= (minX + maxX) / 2.0;
			projected[index].y -= (minY + maxY) / 2.0;
		}

		NSUInteger hullCount = ConvexHull(projected, count, chain);

		if (hullCount >= 3) {
			hull = FitOutline(chain, hullCount);
		}

		free(chain);
		free(projected);
	}

	if (hull == nil) {
		double halfWidth	= extent.width  / 2.0;
		double halfHeight	= extent.height / 2.0;
		Point2 corners[4]	= { V2Make(-halfWidth, -halfHeight), V2Make( halfWidth, -halfHeight),
								V2Make( halfWidth,  halfHeight), V2Make(-halfWidth,  halfHeight) };

		hull = [NSData dataWithBytes:corners length:sizeof(corners)];
	}

	*outline = hull;

	return extent;

}//end projectedExtentOfEntry:transform:outline:


//---------- weightOfBounds: -----------------------------------------[static]--
///
/// @abstract	How heavy a part looks: the volume of its bounding box.
///
/// @discussion	Taken from the untransformed bounds, so a part weighs the same
/// 			at any angle. An entry with no bounds weighs as much as the
/// 			one-stud cell it is drawn in.
///
//------------------------------------------------------------------------------
+ (double) weightOfBounds:(Box3)bounds
{
	if (V3EqualBoxes(bounds, InvalidBox)) {
		return FALLBACK_EXTENT_LDU * FALLBACK_EXTENT_LDU * FALLBACK_EXTENT_LDU;
	}

	return MAX(MINIMUM_EXTENT_LDU, fabs(bounds.max.x - bounds.min.x))
		 * MAX(MINIMUM_EXTENT_LDU, fabs(bounds.max.y - bounds.min.y))
		 * MAX(MINIMUM_EXTENT_LDU, fabs(bounds.max.z - bounds.min.z));

}//end weightOfBounds:


//---------- getStudsAcross:deep:forBounds: --------------------------[static]--
///
/// @abstract	A part's footprint in whole studs. Answers NO when there is no
/// 			part to measure: no bounds, or less than a stud across.
///
/// @discussion	Only X and Z, because Y is height and studs do not measure it.
/// 			Taken from the part's own bounds, so turning the icon does not
/// 			change it.
///
//------------------------------------------------------------------------------
+ (BOOL) getStudsAcross:(long *)outStudsAcross deep:(long *)outStudsDeep forBounds:(Box3)bounds
{
	if (V3EqualBoxes(bounds, InvalidBox)) {
		return NO;
	}

	long x = lround(fabs(bounds.max.x - bounds.min.x) / LDU_PER_STUD);
	long z = lround(fabs(bounds.max.z - bounds.min.z) / LDU_PER_STUD);

	if (x < 1 || z < 1) {
		return NO;
	}

	*outStudsAcross	= x;
	*outStudsDeep	= z;

	return YES;

}//end getStudsAcross:deep:forBounds:


//---------- isTileTitle: --------------------------------------------[static]--
///
/// @abstract	Whether a part library description names a tile.
///
/// @discussion	LDraw puts the category first, after an optional `=`, `~`, `_`
/// 			or `|` marker. Only the first word counts.
///
//------------------------------------------------------------------------------
+ (BOOL) isTileTitle:(nullable NSString *)title
{
	static NSCharacterSet *markers = nil;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		markers = [NSCharacterSet characterSetWithCharactersInString:@"=~_| "];
	});

	NSString *trimmed = [title stringByTrimmingCharactersInSet:markers];

	if ([trimmed length] < 4) {
		return NO;
	}

	NSComparisonResult match = [trimmed compare:@"Tile"
										options:NSCaseInsensitiveSearch
										  range:NSMakeRange(0, 4)];

	if (match != NSOrderedSame) {
		return NO;
	}

	// "Tile" must be the whole first word, not the start of a longer one.
	return [trimmed length] == 4
		|| [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[trimmed characterAtIndex:4]];

}//end isTileTitle:


@end
