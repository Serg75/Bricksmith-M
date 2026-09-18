//==============================================================================
//
//  File:       LDrawStepPartListLayout.m
//  Package:    LDrawFeatures
//
//  Purpose:    Packs a step's parts list into a box.
//
//  Notes:      Cells are sorted tallest first and laid on shelves, left to
//              right. A cell is a part's projected bounding box, so an angled
//              part leaves some empty space in its cell.
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
/// The room the multiplier needs, and the badge's width, in points.
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
@end

@implementation LDrawStepPartListPlacedCell
@end


/// One packed shelf.
typedef NSArray<LDrawStepPartListPlacedCell *> LDrawStepPartListRow;


/// The result of one pack attempt.
@interface LDrawStepPartListPacking : NSObject
@property (nonatomic) NSArray<LDrawStepPartListRow *>					*rows;
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

	// Room for the badge: an 8 point label, its border, and a point of gap.
	metrics.annotationHeight			= 13.0;

	// A little wider than the widest digit of the text they measure.
	metrics.labelCharacterWidth			= 6.5;
	metrics.annotationCharacterWidth	= 5.0;
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

	[layout measureResizeLimitsOfCells:cells metrics:metrics];

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

		while (kept.count > 1 && [self heightOfRows:kept metrics:metrics] > heightBudget) {
			overflowCount += [(NSArray *)kept.firstObject count];
			[kept removeObjectAtIndex:0];
		}
		rows = kept;
	}

	[layout applyRows:rows
			  metrics:metrics
		overflowCount:overflowCount];

	[layout measureResizeStartForConstraint:constraint metrics:metrics];

	return layout;

}//end layoutForEntries:constraint:viewTransform:metrics:


//========== measureResizeLimitsOfCells:metrics: ===============================
///
/// @abstract	The frame sizes past which a resize drag changes nothing, at the
/// 			base scale and whatever the constraint.
///
//==============================================================================
- (void) measureResizeLimitsOfCells:(NSArray<LDrawStepPartListCell *> *)cells
							metrics:(LDrawStepPartListMetrics)metrics
{
	// A width of 0 draws no icon smaller, as in the searching modes.
	NSArray<LDrawStepPartListPlacedCell *>	*placedCells	=
		[[self class] placedCellsForCells:cells
								  atScale:metrics.baseScale
							 contentWidth:0.0
								  metrics:metrics];
	double									 rowWidth		= 0.0;
	double									 widestCell		= 0.0;
	double									 widestRoom		= 0.0;

	for (LDrawStepPartListPlacedCell *placed in placedCells) {
		rowWidth	+= placed.size.width;
		widestCell	= MAX(widestCell, placed.size.width);
		widestRoom	= MAX(widestRoom, [[self class] roomOfPlacedCell:placed metrics:metrics].size.width);
	}

	// Narrower than this an icon is drawn smaller, and a smaller icon takes a
	// shelf of its own.
	double fraction		= MIN(metrics.maximumCellWidthFraction, 1.0);
	double oneRowWidth	= (fraction > 0.0) ? MAX(rowWidth, widestRoom / fraction) : rowWidth;

	// The narrowest packing HEIGHT tries is as wide as the widest cell.
	LDrawStepPartListPacking	*tallest	= [[self class] shelfPackPlacedCells:placedCells
																	contentWidth:widestCell
																		 metrics:metrics];
	double						 padding	= 2.0 * metrics.framePadding;

	self.oneRowFrameWidth	= oneRowWidth + padding;
	self.oneRowFrameHeight	= [[self class] heightOfRow:placedCells metrics:metrics] + padding;
	self.tallestFrameHeight	= tallest.height + padding;
	self.shareFrameWidth	= (fraction > 0.0) ? widestRoom / fraction + padding : 0.0;

}//end measureResizeLimitsOfCells:metrics:


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


//========== applyRows:metrics:overflowCount: ==================================
///
/// @abstract	Turns packed shelves into placements with absolute positions.
///
//==============================================================================
- (void) applyRows:(NSArray<LDrawStepPartListRow *> *)rows
		   metrics:(LDrawStepPartListMetrics)metrics
	 overflowCount:(NSUInteger)overflowCount
{
	NSMutableArray<LDrawStepPartListPlacement *>	*placements	= [NSMutableArray array];
	double											y			= 0.0;

	// The widest shelf, whatever WIDTH asked for, as LPub3D does. Found before
	// anything is placed, because a capped cell is centered across it.
	double contentWidth = [[self class] widestRowWidthOfRows:rows];

	for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {

		NSArray<LDrawStepPartListPlacedCell *>	*row			= rows[rowIndex];
		double									 rowHeight		= [[self class] heightOfRow:row metrics:metrics];
		BOOL									 labelIsInStrip	= [[self class] rowKeepsLabelStrip:row];
		double									 stripHeight	= labelIsInStrip ? metrics.labelHeight : 0.0;

		// A cell drawn smaller has the shelf to itself and is centered. The
		// rest run left to right.
		double x = 0.0;

		if (row.count == 1 && row.firstObject.isScaledDown) {
			x = MAX(0.0, (contentWidth - row.firstObject.size.width) / 2.0);
		}

		for (LDrawStepPartListPlacedCell *placed in row) {

			// Cell bottoms line up, and so do the icon bottoms, since every cell
			// on a shelf gets the same count strip.
			double top = y + rowHeight - (placed.size.height + stripHeight);

			[placements addObject:[self placementForCell:placed
												atOrigin:V2Make(x, top)
												rowIndex:rowIndex
										  labelIsInStrip:labelIsInStrip
												 metrics:metrics]];
			x += placed.size.width;
		}

		y += rowHeight + metrics.rowGap;
	}

	self.rowCount		= rows.count;
	self.placements		= placements;
	self.overflowCount	= overflowCount;
	self.contentSize	= V2MakeSize(contentWidth, [[self class] heightOfRows:rows metrics:metrics]);

}//end applyRows:metrics:overflowCount:


//========== placementForCell:atOrigin:rowIndex:labelIsInStrip:metrics: ========
///
/// @abstract	One cell's frames, given the cell's top-left corner and whether
/// 			its shelf puts the counts in strips.
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

	placement.entry				= cell.entry;
	placement.scale				= placedCell.scale;
	placement.isScaledDown		= placedCell.isScaledDown;
	placement.rowIndex			= rowIndex;
	placement.annotationText	= placedCell.showsAnnotation ? cell.studText : nil;

	double badgeStripHeight = placedCell.showsAnnotation ? metrics.annotationHeight : 0.0;
	double labelStripHeight = labelIsInStrip ? metrics.labelHeight : 0.0;

	placement.cellFrame	= V2MakeBox(origin.x, origin.y, placedCell.size.width,
									placedCell.size.height + labelStripHeight);

	// A cell can be wider than its icon, and the icon stays centered in it. The
	// boxes beside the part move across with the icon.
	double	roomWidth	= cell.iconLDU.width * placedCell.scale + 2.0 * padding;
	Point2	roomOrigin	= V2Make(origin.x + MAX(0.0, placedCell.size.width - roomWidth) / 2.0,
								 origin.y + badgeStripHeight);

	placement.iconFrame	= V2MakeBox(roomOrigin.x + padding,
									roomOrigin.y + padding,
									roomWidth - 2.0 * padding,
									MAX(0.0, placedCell.size.height - 2.0 * padding - badgeStripHeight));

	// On a strip shelf the count is below the icon, so the badge has nothing to avoid.
	Box2 labelBox = labelIsInStrip ? ZeroBox2 : placedCell.labelBox;

	if (placedCell.showsAnnotation == NO) {
		placement.annotationFrame = V2MakeBox(origin.x, origin.y, 0.0, 0.0);
	}
	else {
		Box2 badge = [[self class] badgeBoxOfCell:placedCell avoiding:labelBox metrics:metrics];

		placement.annotationFrame = OffsetBox(badge, roomOrigin);
	}

	placement.labelFrame = labelIsInStrip
						 ? V2MakeBox(origin.x,
									 origin.y + placedCell.size.height,
									 placedCell.size.width,
									 metrics.labelHeight)
						 : OffsetBox(labelBox, roomOrigin);

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
/// @discussion	The cells given are not changed, so they can be packed again at
/// 			other widths.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) shelfPackPlacedCells:(NSArray<LDrawStepPartListPlacedCell *> *)placedCells
									   contentWidth:(double)contentWidth
											metrics:(LDrawStepPartListMetrics)metrics
{
	NSMutableArray<NSMutableArray<LDrawStepPartListPlacedCell *> *>	*rows		= [NSMutableArray array];
	NSMutableArray<LDrawStepPartListPlacedCell *>					*currentRow	= [NSMutableArray array];
	double															 rowWidth	= 0.0;

	for (LDrawStepPartListPlacedCell *placed in placedCells) {

		if (placed.isScaledDown) {
			// Otherwise a wide cell leaves a ragged shelf.
			if (currentRow.count > 0) {
				[rows addObject:currentRow];
				currentRow = [NSMutableArray array];
				rowWidth = 0.0;
			}
			[rows addObject:[NSMutableArray arrayWithObject:placed]];
			continue;
		}

		if (currentRow.count > 0 && rowWidth + placed.size.width > contentWidth + FIT_EPSILON) {
			[rows addObject:currentRow];
			currentRow = [NSMutableArray array];
			rowWidth = 0.0;
		}

		[currentRow addObject:placed];
		rowWidth += placed.size.width;
	}

	if (currentRow.count > 0) {
		[rows addObject:currentRow];
	}

	return [self packingWithRows:rows metrics:metrics];

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

	for (NSMutableArray<LDrawStepPartListPlacedCell *> *row in rows) {
		for (NSUInteger column = 0; column < row.count; column++) {
			LDrawStepPartListPlacedCell *placed = row[column];
			placed.size = V2MakeSize(columnWidths[column].doubleValue, placed.size.height);
		}
	}

	return [self packingWithRows:rows metrics:metrics];

}//end gridPackCells:atScale:columns:metrics:


//---------- packingWithRows:metrics: --------------------------------[static]--
///
/// @abstract	A packing of these finished shelves, measured.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPacking *) packingWithRows:(NSArray<LDrawStepPartListRow *> *)rows
									   metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListPacking *packing = [LDrawStepPartListPacking new];

	packing.rows		= rows;
	packing.height		= [self heightOfRows:rows metrics:metrics];
	packing.usedWidth	= [self widestRowWidthOfRows:rows];

	return packing;

}//end packingWithRows:metrics:


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
	NSArray<NSNumber *>						*candidates		= [self candidateWidthsForPlacedCells:placedCells];
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


//---------- candidateWidthsForPlacedCells: --------------------------[static]--
///
/// @abstract	The widths worth trying, smallest first and without repeats.
///
/// @discussion	Measured from the cells the shelves will pack, labels and all,
/// 			because a cell can be wider than its icon.
///
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *) candidateWidthsForPlacedCells:(NSArray<LDrawStepPartListPlacedCell *> *)placedCells
{
	NSMutableArray<NSNumber *>	*candidates	= [NSMutableArray array];
	double						 running	= 0.0;
	double						 widest		= 0.0;

	for (LDrawStepPartListPlacedCell *placed in placedCells) {
		widest = MAX(widest, placed.size.width);
	}

	for (LDrawStepPartListPlacedCell *placed in placedCells) {
		running += placed.size.width;

		// No shelf is narrower than the widest cell.
		double candidate = MAX(widest, running);

		if (candidates.count == 0 || candidates.lastObject.doubleValue < candidate) {
			[candidates addObject:@(candidate)];
		}
	}

	return candidates;

}//end candidateWidthsForPlacedCells:


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
		[placedCells addObject:[self placedCellForCell:cell
											   atScale:scale
										  contentWidth:contentWidth
											   metrics:metrics]];
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

	placed.labelBox = [self bottomLabelBoxOfCell:placed metrics:metrics];
	[self sizePlacedCell:placed metrics:metrics];

	return placed;

}//end placedCellForCell:atScale:contentWidth:metrics:


//---------- bottomLabelBoxOfCell:metrics: ---------------------------[static]--
///
/// @abstract	The multiplier's place beside the part, on the bottom line of
/// 			the icon's box: slid in from each bottom corner, keeping the one
/// 			nearer the middle. Empty when both corners are blocked.
///
/// @discussion	The outline is convex, so if any place on the line is clear, a
/// 			corner is. Nearer the middle, because a count near an edge looks
/// 			like it belongs to the gap between two cells.
///
//------------------------------------------------------------------------------
+ (Box2) bottomLabelBoxOfCell:(LDrawStepPartListPlacedCell *)placed
					  metrics:(LDrawStepPartListMetrics)metrics
{
	Size2	size	= placed.cell.labelSize;
	Box2	room	= [self roomOfPlacedCell:placed metrics:metrics];

	if (size.width > room.size.width || size.height > room.size.height) {
		return ZeroBox2;
	}

	NSData		*outline	= ScaledOutlineOfCell(placed.cell, placed.scale, V2BoxMid(room));
	NSUInteger	 count		= outline.length / sizeof(Point2);
	double		 y			= V2BoxMaxY(room) - size.height;
	Point2		 middle		= V2Make(V2BoxMidX(room) - size.width / 2.0, y);
	Box2		 left		= ZeroBox2;
	Box2		 right		= ZeroBox2;

	BOOL fitsFromLeft	= SlideBoxToward(size, V2Make(room.origin.x, y), middle,
										 outline.bytes, count, ZeroBox2, metrics.decorationGap, &left);
	BOOL fitsFromRight	= SlideBoxToward(size, V2Make(V2BoxMaxX(room) - size.width, y), middle,
										 outline.bytes, count, ZeroBox2, metrics.decorationGap, &right);

	if (fitsFromLeft && fitsFromRight) {
		return (middle.x - left.origin.x <= right.origin.x - middle.x) ? left : right;
	}

	return fitsFromLeft ? left : (fitsFromRight ? right : ZeroBox2);

}//end bottomLabelBoxOfCell:metrics:


//---------- badgeBoxOfCell:avoiding:metrics: ------------------------[static]--
///
/// @abstract	Where the size badge goes: centered across the icon's box, then
/// 			let down until it is `decorationGap` clear of the part and of
/// 			`labelBox`. Measured in the icon box, so negative y is the strip
/// 			above it.
///
/// @discussion	A part drawn at an angle does not reach the top of its box, so
/// 			letting the badge down closes that gap. It never goes past the
/// 			middle of the box.
///
//------------------------------------------------------------------------------
+ (Box2) badgeBoxOfCell:(LDrawStepPartListPlacedCell *)placed
			   avoiding:(Box2)labelBox
				metrics:(LDrawStepPartListMetrics)metrics
{
	Box2	 room		= [self roomOfPlacedCell:placed metrics:metrics];
	Size2	 size		= V2MakeSize(placed.cell.annotationWidth, metrics.annotationHeight);
	Point2	 middle		= V2BoxMid(room);
	NSData	*outline	= ScaledOutlineOfCell(placed.cell, placed.scale, middle);

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


//---------- sizePlacedCell:metrics: ---------------------------------[static]--
///
/// @abstract	The cell's size: the icon's padded box plus the badge's strip.
/// 			The count's strip is added per shelf.
///
//------------------------------------------------------------------------------
+ (void) sizePlacedCell:(LDrawStepPartListPlacedCell *)placed
				metrics:(LDrawStepPartListMetrics)metrics
{
	LDrawStepPartListCell	*cell	= placed.cell;
	Box2					 room	= [self roomOfPlacedCell:placed metrics:metrics];

	// A label in a strip is centered across the cell, so the cell is at least as
	// wide as the label. A count that fits beside its part is never wider.
	double width = MAX(room.size.width, cell.labelSize.width);

	if (placed.showsAnnotation) {
		width = MAX(width, cell.annotationWidth);
	}

	placed.size = V2MakeSize(width, room.size.height + (placed.showsAnnotation ? metrics.annotationHeight : 0.0));

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


//---------- heightOfRows:metrics: -----------------------------------[static]--
///
/// @abstract	Sum of the shelf heights.
///
//------------------------------------------------------------------------------
+ (double) heightOfRows:(NSArray<LDrawStepPartListRow *> *)rows
				metrics:(LDrawStepPartListMetrics)metrics
{
	double total = 0.0;

	for (NSArray<LDrawStepPartListPlacedCell *> *row in rows) {
		total += [self heightOfRow:row metrics:metrics];
	}

	if (rows.count > 1) {
		total += (double)(rows.count - 1) * metrics.rowGap;
	}

	return total;

}//end heightOfRows:metrics:


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
		if (BoxIsEmpty(placed.labelBox)) {
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


//---------- widestRowWidthOfRows: -----------------------------------[static]--
///
/// @abstract	The width of the widest shelf.
///
//------------------------------------------------------------------------------
+ (double) widestRowWidthOfRows:(NSArray<LDrawStepPartListRow *> *)rows
{
	double widest = 0.0;

	for (NSArray<LDrawStepPartListPlacedCell *> *row in rows) {
		double rowWidth = 0.0;

		for (LDrawStepPartListPlacedCell *placed in row) {
			rowWidth += placed.size.width;
		}
		widest = MAX(widest, rowWidth);
	}

	return widest;

}//end widestRowWidthOfRows:


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

		cell.labelSize			= [self labelSizeForQuantity:entry.quantity metrics:metrics];
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
