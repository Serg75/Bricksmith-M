//==============================================================================
//
//  File:       LDrawStepCalloutBox.m
//  Package:    LDrawFeatures
//
//  Purpose:    Places the boxes a step's callouts are drawn in.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepCalloutBox.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawCore/LPubPlacement.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutStyle.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

#import "LDrawStepCalloutContent.h"
#import "LDrawStepPartListInternal.h"


//========== LDrawStepCalloutAppendRotation() ==================================
///
/// @abstract	Adds the turn a matrix makes to a picture's key.
///
//==============================================================================
void LDrawStepCalloutAppendRotation(NSMutableString *key, Matrix4 matrix)
{
	for (int row = 0; row < 3; row++) {
		[key appendFormat:@"/%.4f,%.4f,%.4f",
		 matrix.element[row][0], matrix.element[row][1], matrix.element[row][2]];
	}

}//end LDrawStepCalloutAppendRotation


//========== LDrawStepCalloutMovedBox() ========================================
Box2 LDrawStepCalloutMovedBox(Box2 box, Point2 offset)
{
	return V2MakeBox(box.origin.x + offset.x, box.origin.y + offset.y, box.size.width, box.size.height);

}//end LDrawStepCalloutMovedBox


/// How far short of a placement's edge an arrow stops: LPub3D's margin on the
/// page, and about as many points off it.
static const double ARROW_GAP_INCHES = 0.05;
static const double ARROW_GAP_POINTS = 4.0;

/// How near a corner of the box an arrow may leave it, off the page.
static const double ARROW_INSET_POINTS = 7.0;

/// How far apart two arrows leave one edge of the box, on the page and off it.
static const double ARROW_SPACING_INCHES = 0.08;
static const double ARROW_SPACING_POINTS = 6.0;


//------------------------------------------------------------------------------
///
/// @enum       BoxEdge
///
/// @abstract   The edge of a box an arrow leaves. An arrow to a point inside
///             the box leaves none.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSUInteger, BoxEdge)
{
	BoxEdgeTop,
	BoxEdgeBottom,
	BoxEdgeLeft,
	BoxEdgeRight,
	BoxEdgeCount,
	BoxEdgeNone = BoxEdgeCount
};


//------------------------------------------------------------------------------
///
/// @struct     EdgeArrow
///
/// @abstract   One arrow, measured from the edge of the box it leaves.
///
//------------------------------------------------------------------------------
typedef struct EdgeArrow
{
	/// Which of the placements handed in it goes to.
	NSUInteger	index;

	BoxEdge		edge;

	/// The placement's middle: how far along the edge, and how far out from
	/// it. The second is above 0.
	double		along;
	double		out;

	/// Where the arrow leaves the edge, along it.
	double		start;

} EdgeArrow;


//========== Turn() ============================================================
///
/// @abstract	Which way the path from `origin` to `first` to `second` turns:
/// 			above 0 one way, below 0 the other, 0 for a straight line.
///
//==============================================================================
static double Turn(Point2 origin, Point2 first, Point2 second)
{
	return (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x);

}//end Turn


//========== ComparePoints() ===================================================
static int ComparePoints(const void *first, const void *second)
{
	const Point2 *a = first;
	const Point2 *b = second;

	if (a->x != b->x) {
		return (a->x < b->x) ? -1 : 1;
	}
	if (a->y != b->y) {
		return (a->y < b->y) ? -1 : 1;
	}
	return 0;

}//end ComparePoints


//========== ConvexOutline() ===================================================
///
/// @abstract	The corners of the smallest outline with no dents around some
/// 			points, in order around it. `corners` needs room for twice the
/// 			points. Fewer than three corners come back for points on one
/// 			line.
///
//==============================================================================
static NSUInteger ConvexOutline(const Point2 *points, NSUInteger count, Point2 *corners)
{
	Point2		*sorted	= malloc(count * sizeof(Point2));
	NSUInteger	 size	= 0;

	memcpy(sorted, points, count * sizeof(Point2));
	qsort(sorted, count, sizeof(Point2), ComparePoints);

	// One side from left to right, then the other side back.
	for (NSUInteger index = 0; index < count; index++) {
		while (size >= 2 && Turn(corners[size - 2], corners[size - 1], sorted[index]) <= 0.0) {
			size -= 1;
		}
		corners[size++] = sorted[index];
	}

	NSUInteger kept = size + 1;

	for (NSUInteger index = count - 1; index > 0; index--) {
		while (size >= kept && Turn(corners[size - 2], corners[size - 1], sorted[index - 1]) <= 0.0) {
			size -= 1;
		}
		corners[size++] = sorted[index - 1];
	}

	free(sorted);

	// The last corner is the first one again.
	return size - 1;

}//end ConvexOutline


//========== IsInsideOutline() =================================================
///
/// @abstract	Whether a point is inside an outline with no dents. Its corners
/// 			run one way around, so the point is then on the same side of
/// 			every edge.
///
//==============================================================================
static BOOL IsInsideOutline(Point2 point, const Point2 *corners, NSUInteger count)
{
	BOOL isOnOneSide	= NO;
	BOOL isOnOtherSide	= NO;

	for (NSUInteger index = 0; index < count; index++) {
		double side = Turn(corners[index], corners[(index + 1) % count], point);

		isOnOneSide		= isOnOneSide || side > 0.0;
		isOnOtherSide	= isOnOtherSide || side < 0.0;
	}

	return (isOnOneSide && isOnOtherSide) == NO;

}//end IsInsideOutline


//========== FirstCrossing() ===================================================
///
/// @abstract	How far along the way from `start` to `end` a line first
/// 			crosses an outline, from 0 to 1. NO when it does not cross it.
///
//==============================================================================
static BOOL FirstCrossing(Point2 start, Point2 end, const Point2 *corners, NSUInteger count, double *outShare)
{
	Vector2	way		= V2Sub(end, start);
	double	nearest	= INFINITY;

	for (NSUInteger index = 0; index < count; index++) {
		Point2	from	= corners[index];
		Vector2	edge	= V2Sub(corners[(index + 1) % count], from);
		double	spread	= way.x * edge.y - way.y * edge.x;

		// Side by side, the two never cross.
		if (fabs(spread) < DBL_EPSILON) {
			continue;
		}

		Vector2	toEdge		= V2Sub(from, start);
		double	alongWay	= (toEdge.x * edge.y - toEdge.y * edge.x) / spread;
		double	alongEdge	= (toEdge.x * way.y - toEdge.y * way.x) / spread;

		if (alongWay >= 0.0 && alongWay <= 1.0 && alongEdge >= 0.0 && alongEdge <= 1.0) {
			nearest = MIN(nearest, alongWay);
		}
	}

	if (nearest == INFINITY) {
		return NO;
	}

	*outShare = nearest;
	return YES;

}//end FirstCrossing


//========== CompareNumbers() ==================================================
static int CompareNumbers(const void *first, const void *second)
{
	double a = *(const double *)first;
	double b = *(const double *)second;

	return (a > b) - (a < b);

}//end CompareNumbers


//========== LeansLower() ======================================================
///
/// @abstract	Whether, seen from a place on their edge, one arrow's placement
/// 			is further round toward the low end of the edge than another's.
/// 			Of two in one direction, the nearer one is.
///
//==============================================================================
static BOOL LeansLower(EdgeArrow arrow, EdgeArrow other, double place)
{
	double turn = (other.along - place) * arrow.out - other.out * (arrow.along - place);

	if (turn != 0.0) {
		return turn > 0.0;
	}
	return arrow.out < other.out;

}//end LeansLower


//========== PlaceStarts() =====================================================
///
/// @abstract	Works out where the arrows of one edge leave it, between `low`
/// 			and `high` along the edge.
///
/// @discussion	Alone, an arrow leaves at the place nearest its placement.
/// 			Places closer than `spacing` are moved apart, and share out an
/// 			edge too short for that. From the low end, each place then goes
/// 			to the arrow whose placement is furthest round toward that end,
/// 			so that no two arrows cross.
///
//==============================================================================
static void PlaceStarts(EdgeArrow *arrows, NSUInteger count, double low, double high, double spacing)
{
	if (count == 0) {
		return;
	}

	double *places = malloc(count * sizeof(double));

	for (NSUInteger index = 0; index < count; index++) {
		places[index] = MIN(MAX(arrows[index].along, low), high);
	}
	qsort(places, count, sizeof(double), CompareNumbers);

	if (count > 1) {
		spacing = MIN(spacing, (high - low) / (count - 1));
	}

	// Each place moves clear of the one before it, then back from the high
	// end.
	for (NSUInteger index = 1; index < count; index++) {
		places[index] = MAX(places[index], places[index - 1] + spacing);
	}
	places[count - 1] = MIN(places[count - 1], high);

	for (NSUInteger index = count - 1; index > 0; index--) {
		places[index - 1] = MIN(places[index - 1], places[index] - spacing);
	}

	for (NSUInteger place = 0; place < count; place++) {
		NSUInteger chosen = place;

		for (NSUInteger index = place + 1; index < count; index++) {
			if (LeansLower(arrows[index], arrows[chosen], places[place])) {
				chosen = index;
			}
		}

		EdgeArrow arrow = arrows[chosen];

		arrows[chosen]		= arrows[place];
		arrows[place]		= arrow;
		arrows[place].start	= places[place];
	}

	free(places);

}//end PlaceStarts


/// How many times a dropped box is moved off what is in its way in the file.
/// Clearing one thing may put it over another.
static const NSUInteger CLEARING_PASSES = 8;

/// How far two rectangles may reach over each other, in points, and still be
/// clear of each other.
static const double CLEARING_SLACK = 0.001;


//========== OriginClearOf() ===================================================
///
/// @abstract	The corner nearest `origin` that has a box of `size` clear of
/// 			every one of `obstacles`, between the corners `least` and
/// 			`most`.
///
/// @discussion	A box over an obstacle goes the shortest way off it that keeps
/// 			it between the two corners. One that has no such way stays over
/// 			it.
///
//==============================================================================
static Point2 OriginClearOf(Point2 origin, Size2 size, NSData *obstacles, Point2 least, Point2 most)
{
	const Box2	*rects	= obstacles.bytes;
	NSUInteger	 count	= obstacles.length / sizeof(Box2);

	origin = V2Make(MAX(least.x, MIN(most.x, origin.x)), MAX(least.y, MIN(most.y, origin.y)));

	for (NSUInteger pass = 0; pass < CLEARING_PASSES; pass++) {
		BOOL isSettled = YES;

		for (NSUInteger index = 0; index < count; index++) {
			Box2	rect		= rects[index];
			Point2	ways[4]		= {
				V2Make(V2BoxMinX(rect) - (origin.x + size.width), 0.0),
				V2Make(V2BoxMaxX(rect) - origin.x, 0.0),
				V2Make(0.0, V2BoxMinY(rect) - (origin.y + size.height)),
				V2Make(0.0, V2BoxMaxY(rect) - origin.y)
			};
			double	shortest	= DBL_MAX;
			Point2	way			= ZeroPoint2;

			// Past one of its sides already.
			if (ways[0].x > -CLEARING_SLACK || ways[1].x < CLEARING_SLACK
				|| ways[2].y > -CLEARING_SLACK || ways[3].y < CLEARING_SLACK) {
				continue;
			}

			for (NSUInteger side = 0; side < 4; side++) {
				Point2	moved	= V2Add(origin, ways[side]);
				double	length	= fabs(ways[side].x) + fabs(ways[side].y);
				BOOL	fits	= moved.x >= least.x - CLEARING_SLACK && moved.x <= most.x + CLEARING_SLACK
							   && moved.y >= least.y - CLEARING_SLACK && moved.y <= most.y + CLEARING_SLACK;

				if (fits && length < shortest) {
					shortest	= length;
					way			= ways[side];
				}
			}

			if (shortest < DBL_MAX) {
				origin		= V2Add(origin, way);
				isSettled	= NO;
			}
		}

		if (isSettled) {
			break;
		}
	}

	return origin;

}//end OriginClearOf


//========== BoxHasArea() ======================================================
static BOOL BoxHasArea(Box2 box)
{
	return V2BoxWidth(box) > 0.0 && V2BoxHeight(box) > 0.0;

}//end BoxHasArea


// MARK: -

@implementation LDrawStepCalloutPicture
{
	/// Made when first asked for, so a picture the host already has costs
	/// nothing.
	LDrawModel	*_model;

	/// What the model is made from: an assembly up to a step, or a layout.
	LDrawModel	*_assembly;
	NSUInteger	 _lastStepIndex;
	LDrawColor	*_color;
	LDrawFile	*_file;
	Matrix4		 _viewTransform;
}

//========== initWithRect:assembly:throughStep:viewTransform:color:... =========
- (instancetype) initWithRect:(Box2)rect
					 assembly:(LDrawModel *)assembly
				  throughStep:(NSUInteger)lastStepIndex
				viewTransform:(Matrix4)viewTransform
						color:(nullable LDrawColor *)color
			   zoomPercentage:(double)zoomPercentage
					   center:(Point3)center
				   subjectKey:(NSString *)subjectKey
{
	self = [super init];
	if (self) {
		self->_rect				= rect;
		self->_assembly			= assembly;
		self->_lastStepIndex	= lastStepIndex;
		self->_viewTransform	= viewTransform;
		self->_color			= color;
		self->_zoomPercentage	= zoomPercentage;
		self->_center			= center;
		self->_subjectKey		= [subjectKey copy];
		self->_contentKey		= [NSString stringWithFormat:@"%@|%.2f", subjectKey, zoomPercentage];
	}
	return self;

}//end initWithRect:assembly:throughStep:viewTransform:color:...


//========== initWithLayout:viewTransform:file:origin:isPartsList: =============
///
/// @abstract	A picture of a packed layout: its icons, and the camera that
/// 			shows each one in its cell.
///
//==============================================================================
- (instancetype) initWithLayout:(LDrawStepPartListLayout *)layout
				  viewTransform:(Matrix4)viewTransform
						   file:(nullable LDrawFile *)file
						 origin:(Point2)origin
					isPartsList:(BOOL)isPartsList
{
	self = [super init];
	if (self) {
		Size2 size = layout.contentSize;

		self->_rect				= V2MakeBox(origin.x, origin.y, size.width, size.height);
		self->_layout			= layout;
		self->_isPartsList		= isPartsList;
		self->_viewTransform	= viewTransform;
		self->_file				= file;
		self->_zoomPercentage	= [LDrawStepPartListModelBuilder zoomPercentageForLayout:layout];
		self->_center			= [LDrawStepPartListModelBuilder centerPointForLayout:layout];
		self->_subjectKey		= [LDrawStepCalloutPicture keyForLayout:layout viewTransform:viewTransform isSized:NO];
		self->_contentKey		= [LDrawStepCalloutPicture keyForLayout:layout viewTransform:viewTransform isSized:YES];
	}
	return self;

}//end initWithLayout:viewTransform:file:origin:isPartsList:


//========== model =============================================================
- (LDrawModel *) model
{
	if (self->_model != nil) {
		return self->_model;
	}

	if (self->_layout != nil) {
		self->_model = [LDrawStepPartListModelBuilder modelForLayout:self->_layout
													   viewTransform:self->_viewTransform
												   submodelsFromFile:self->_file];
	}
	else {
		self->_model = [LDrawStepPartListModelBuilder modelForModel:self->_assembly
														throughStep:self->_lastStepIndex
													  viewTransform:self->_viewTransform
															  color:self->_color];
	}

	return self->_model;

}//end model


//---------- keyForLayout:viewTransform:isSized: ---------------------[static]--
///
/// @abstract	Names what a layout's picture shows: each part or submodel, its
/// 			color and its turn. A sized key has its place and its size too.
///
/// @discussion	An unsized key has the shelf each cell is on instead, and
/// 			whether the cell is drawn small on its own. A zoom changes
/// 			neither, and two arrangements of the same parts differ in them,
/// 			so one is not shown in place of the other.
///
//------------------------------------------------------------------------------
+ (NSString *) keyForLayout:(LDrawStepPartListLayout *)layout
			  viewTransform:(Matrix4)viewTransform
					isSized:(BOOL)isSized
{
	NSMutableString *key = [NSMutableString stringWithString:@"cells"];

	LDrawStepCalloutAppendRotation(key, viewTransform);

	for (LDrawStepPartListPlacement *placement in layout.placements) {
		[key appendFormat:@"|%@", placement.entry.groupKey];

		if (isSized) {
			[key appendFormat:@"/%.4f/%.1f,%.1f",
			 placement.scale, placement.iconFrame.origin.x, placement.iconFrame.origin.y];
		}
		else {
			[key appendFormat:@"/%lu%@",
			 (unsigned long)placement.rowIndex, placement.isScaledDown ? @"s" : @""];
		}

		LDrawStepCalloutAppendRotation(key, placement.entry.listOrientation);
	}

	return key;

}//end keyForLayout:viewTransform:isSized:


//========== moveBy: ===========================================================
- (void) moveBy:(Point2)offset
{
	self->_rect = LDrawStepCalloutMovedBox(self->_rect, offset);

}//end moveBy:

@end


// MARK: -

@implementation LDrawStepCalloutLabel

//========== initWithRect:text:isStepNumber: ===================================
- (instancetype) initWithRect:(Box2)rect text:(NSString *)text isStepNumber:(BOOL)isStepNumber
{
	self = [super init];
	if (self) {
		self->_rect			= rect;
		self->_text			= [text copy];
		self->_isStepNumber	= isStepNumber;
	}
	return self;

}//end initWithRect:text:isStepNumber:


//========== moveBy: ===========================================================
- (void) moveBy:(Point2)offset
{
	self->_rect = LDrawStepCalloutMovedBox(self->_rect, offset);

}//end moveBy:

@end


// MARK: -

@implementation LDrawStepCalloutStep

//========== initWithStep:number:rect:dividerRect:... ==========================
- (instancetype) initWithStep:(LDrawStep *)step
					   number:(NSUInteger)number
						 rect:(Box2)rect
				  dividerRect:(Box2)dividerRect
			isFirstOfSubmodel:(BOOL)isFirstOfSubmodel
			 hasDividerBefore:(BOOL)hasDividerBefore
{
	self = [super init];
	if (self) {
		self->_step					= step;
		self->_number				= number;
		self->_rect					= rect;
		self->_dividerRect			= dividerRect;
		self->_isFirstOfSubmodel	= isFirstOfSubmodel;
		self->_hasDividerBefore		= hasDividerBefore;
	}
	return self;

}//end initWithStep:number:rect:dividerRect:...


//========== moveBy: ===========================================================
- (void) moveBy:(Point2)offset
{
	self->_rect			= LDrawStepCalloutMovedBox(self->_rect, offset);
	self->_dividerRect	= LDrawStepCalloutMovedBox(self->_dividerRect, offset);

}//end moveBy:

@end


// MARK: -

@implementation LDrawStepCalloutBox
{
	LDrawStepCalloutContent	*_content;

	/// The middle of each placement, as Point3 values.
	NSMutableData			*_tips;

	/// The outline of each placement an arrow goes to, worked out when first
	/// asked for.
	NSArray<NSData *>		*_tipOutlines;

	/// How far short of a placement's edge an arrow stops, in the view's
	/// points.
	double					 _arrowGap;

	/// How near a corner an arrow may leave the box: along the top and bottom
	/// edges, and along the sides.
	Size2					 _arrowInset;

	/// How far apart two arrows leave one edge of the box, in the view's
	/// points.
	double					 _arrowSpacing;

	/// What the box is placed against, and where its corner goes with no
	/// offset. Both are read when a drag is turned back into an offset.
	Box2					 _anchorRect;
	Point2					 _unoffsetOrigin;

	/// Where the box's corner goes before it follows its submodel or a drag.
	Point2					 _placedOrigin;

	/// How far the box's submodel has moved in the view since the step was
	/// laid out. A box beside its submodel on the file's side is drawn that
	/// far from where the file puts it.
	Point2					 _submodelShift;

	/// The page the box is on, or an empty box off the page.
	Box2					 _pageRect;
}


// MARK: - PACKING -


//---------- boxesForCallouts:inModel:options: -----------------------[static]--
///
/// @abstract	Packs one box per callout and puts each in its place.
///
/// @discussion	On the page, with the assembly measured, a box goes where its
/// 			PLACEMENT line says. Otherwise the boxes stack down the host's
/// 			left edge. The first column starts under the parts list. Later
/// 			columns start at the top, to the right of the list and of the
/// 			boxes already placed.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepCalloutBox *> *) boxesForCallouts:(NSArray<LDrawStepCallout *> *)callouts
											  inModel:(nullable LDrawModel *)model
											  options:(LDrawStepCalloutBoxOptions)options
{
	NSMutableArray<LDrawStepCalloutBox *>	*boxes		= [NSMutableArray array];
	Box2									 hostRect	= options.hostRect;
	Box2									 listFrame	= options.listFrame;

	if (callouts.count == 0 || V2BoxWidth(hostRect) <= 0.0 || V2BoxHeight(hostRect) <= 0.0) {
		return boxes;
	}

	double	inset		= [LDrawStepPartListPolicy frameInsetForPointsPerPageInch:options.pointsPerPageInch];
	BOOL	hasList		= BoxHasArea(listFrame);
	BOOL	isPlaced	= (options.pointsPerPageInch > 0.0 && BoxHasArea(options.assemblyRect));
	double	columnTop	= V2BoxMinY(hostRect) + inset;
	double	bottom		= V2BoxMaxY(hostRect) - inset;
	double	x			= V2BoxMinX(hostRect) + inset;
	double	y			= hasList ? V2BoxMaxY(listFrame) + inset : columnTop;
	double	columnRight	= x;

	for (LDrawStepCallout *callout in callouts) {

		LDrawStepCalloutBox *box = [[LDrawStepCalloutBox alloc] initWithCallout:callout
																		inModel:model
																		options:options];
		if (box == nil) {
			continue;
		}

		if (isPlaced) {
			[box placeWithOptions:options];
			[boxes addObject:box];
			continue;
		}

		Size2 size = box.frameRect.size;

		// No room below, so start a new column clear of the list. A box at the
		// top of a column stays there even when it is too tall.
		if (y + size.height > bottom && y > columnTop) {
			x			= MAX(columnRight, hasList ? V2BoxMaxX(listFrame) : columnRight) + inset;
			y			= columnTop;
			columnRight	= x;
		}

		[box moveTo:V2Make(x, y)];

		columnRight	= MAX(columnRight, x + size.width);
		y			+= size.height + inset;

		[boxes addObject:box];
	}

	for (LDrawStepCalloutBox *box in boxes) {
		box->_placedOrigin = box.frameRect.origin;
	}

	return boxes;

}//end boxesForCallouts:inModel:options:


//---------- boxAtPoint:amongBoxes: ----------------------------------[static]--
+ (nullable LDrawStepCalloutBox *) boxAtPoint:(Point2)point amongBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
{
	for (LDrawStepCalloutBox *box in [boxes reverseObjectEnumerator]) {
		if (V2BoxContains(box.frameRect, point)) {
			return box;
		}
	}

	return nil;

}//end boxAtPoint:amongBoxes:


//========== placeWithOptions: =================================================
///
/// @abstract	Puts the box where LPub3D puts it: at the side or corner its
/// 			PLACEMENT line names, of the thing the line names, moved by the
/// 			line's offset.
///
/// @discussion	With no such line the box goes to the right of the assembly, in
/// 			the middle. The box keeps the room its MARGINS line asks for.
///
//==============================================================================
- (void) placeWithOptions:(LDrawStepCalloutBoxOptions)options
{
	// A box that is put by itself starts where one with no line goes. Its
	// line is not read.
	BOOL					 isAutomatic	= [LDrawStepPartList placesCalloutsAutomatically];
	LPubPlacement			*placement		= isAutomatic ? nil : self.callout.placement;
	LPubPlacementPosition	 position		= LPubPlacementPositionRight;
	LPubPlacementPosition	 justification	= LPubPlacementPositionCenter;
	BOOL					 isInside		= NO;
	BOOL					 isStandIn		= NO;
	Point2					 offset			= ZeroPoint2;
	Box2					 anchor			= options.assemblyRect;

	self->_isCenteredWithAssembly	= (isAutomatic == NO);
	self->_isPlacedAgainstAssembly	= YES;

	if (placement != nil) {
		position		= placement.position;
		justification	= placement.justification;
		isInside		= placement.isInside;
		offset			= placement.offset;

		// Anything else LPub3D can place against is not drawn here, so the
		// assembly stands in for it.
		if ([placement.relativeTo isEqualToString:LPUB_PAGE]) {
			anchor = options.hostRect;
			self->_isPlacedAgainstAssembly = NO;
		}
		else if ([placement.relativeTo isEqualToString:LPUB_PLI] && BoxHasArea(options.listFrame)) {
			anchor = options.listFrame;
			self->_isPlacedAgainstAssembly = NO;
		}
		else {
			isStandIn = ([placement.relativeTo isEqualToString:LPUB_ASSEM] == NO);
		}

		// LPub3D leaves a box out once it has been dragged, so that dragging
		// one does not move the assembly.
		BOOL isDragged = (offset.x != 0.0 || offset.y != 0.0);

		self->_isCenteredWithAssembly = [placement.relativeTo isEqualToString:LPUB_ASSEM] && isDragged == NO;
	}

	Size2	margins	= self.style.margins;
	double	scale	= options.pointsPerPageInch;
	Point2	origin	= [LDrawStepCalloutBox originForSize:self.frameRect.size
												position:position
										   justification:justification
												isInside:isInside
												  anchor:anchor
												  margin:V2MakeSize(margins.width * scale, margins.height * scale)];

	self->_anchorRect		= anchor;
	self->_pageRect			= options.hostRect;
	self->_unoffsetOrigin	= origin;

	// A drag is written as a share of the size of what the line names. The
	// assembly is another size, so a box it stands in for is not dragged.
	// Neither is one whose line is not read.
	self->_isPlacedByFile	= (isStandIn == NO && isAutomatic == NO);

	// The offset is a share of the size of what the box is placed against.
	origin.x += V2BoxWidth(anchor) * offset.x;
	origin.y += V2BoxHeight(anchor) * offset.y;

	[self moveTo:origin];

}//end placeWithOptions:


//---------- originForSize:position:justification:isInside:anchor:margin: --[static]--
///
/// @abstract	The corner of a box of `size` put at a side or corner of
/// 			`anchor`, as LPub3D places one thing against another.
///
/// @discussion	Outside, the box sits past that edge, `margin` away, and
/// 			`justification` says where along a side it goes. Inside, it sits
/// 			against the edge from within, and a side or the middle centers
/// 			it on the other axis.
///
//------------------------------------------------------------------------------
+ (Point2) originForSize:(Size2)size
				position:(LPubPlacementPosition)position
		   justification:(LPubPlacementPosition)justification
				isInside:(BOOL)isInside
				  anchor:(Box2)anchor
				  margin:(Size2)margin
{
	BOOL isLeft		= (position == LPubPlacementPositionTopLeft || position == LPubPlacementPositionLeft
					   || position == LPubPlacementPositionBottomLeft);
	BOOL isRight	= (position == LPubPlacementPositionTopRight || position == LPubPlacementPositionRight
					   || position == LPubPlacementPositionBottomRight);
	BOOL isTop		= (position == LPubPlacementPositionTopLeft || position == LPubPlacementPositionTop
					   || position == LPubPlacementPositionTopRight);
	BOOL isBottom	= (position == LPubPlacementPositionBottomLeft || position == LPubPlacementPositionBottom
					   || position == LPubPlacementPositionBottomRight);

	double spareWidth	= V2BoxWidth(anchor) - size.width;
	double spareHeight	= V2BoxHeight(anchor) - size.height;
	Point2 origin		= anchor.origin;

	if (isInside) {
		origin.x += isLeft ? margin.width : (isRight ? spareWidth - margin.width : spareWidth / 2.0);
		origin.y += isTop ? margin.height : (isBottom ? spareHeight - margin.height : spareHeight / 2.0);

		return origin;
	}

	if (isLeft) {
		origin.x -= size.width + margin.width;
	}
	else if (isRight) {
		origin.x += V2BoxWidth(anchor) + margin.width;
	}
	else if (justification == LPubPlacementPositionCenter) {
		origin.x += spareWidth / 2.0;
	}
	else if (justification == LPubPlacementPositionRight) {
		origin.x += spareWidth;
	}

	if (isTop) {
		origin.y -= size.height + margin.height;
	}
	else if (isBottom) {
		origin.y += V2BoxHeight(anchor) + margin.height;
	}
	else if (justification == LPubPlacementPositionCenter) {
		origin.y += spareHeight / 2.0;
	}
	else if (justification == LPubPlacementPositionBottom) {
		origin.y += spareHeight;
	}

	return origin;

}//end originForSize:position:justification:isInside:anchor:margin:


//========== initWithCallout:inModel:options: ==================================
///
/// @abstract	Packs one callout, at the view's origin. Nil when there is
/// 			nothing to draw.
///
/// @discussion	On the page the box shows the steps, as LPub3D prints them, and
/// 			looks as the file says. Off it there is no room for that, so it
/// 			shows each submodel finished.
///
//==============================================================================
- (nullable instancetype) initWithCallout:(LDrawStepCallout *)callout
								  inModel:(nullable LDrawModel *)model
								  options:(LDrawStepCalloutBoxOptions)options
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	LDrawStepCalloutContent	*content	= nil;
	LDrawStepCalloutStyle	*style		= nil;
	Size2					 padding	= V2MakeSize(options.metrics.framePadding, options.metrics.framePadding);
	Size2					 inset		= V2MakeSize(ARROW_INSET_POINTS, ARROW_INSET_POINTS);
	double					 gap		= ARROW_GAP_POINTS;
	double					 spacing	= ARROW_SPACING_POINTS;

	if (options.pointsPerPageInch > 0.0) {
		double scale = options.pointsPerPageInch;

		style	= [LDrawStepCalloutStyle styleForCallout:callout];
		content	= [LDrawStepCalloutContent stripOfCallout:callout inModel:model options:options style:style];

		// Inside the outline, and the room the file keeps clear within it.
		padding	= V2MakeSize((style.borderMargins.width + style.borderThickness) * scale,
							 (style.borderMargins.height + style.borderThickness) * scale);

		gap		= ARROW_GAP_INCHES * scale;
		spacing	= ARROW_SPACING_INCHES * scale;

		// An arrow leaves the box past its rounded corner, and half the
		// border's margin further along. A box with neither still keeps it
		// off the corner.
		inset	= V2MakeSize(MAX(spacing, (style.borderMargins.width / 2.0 + style.cornerRadius) * scale),
							 MAX(spacing, (style.borderMargins.height / 2.0 + style.cornerRadius) * scale));
	}
	else {
		content = [LDrawStepCalloutContent summaryOfCallout:callout inModel:model options:options];
	}

	if (content == nil) {
		return nil;
	}

	self->_callout		= callout;
	self->_style		= style;
	self->_content		= content;
	self->_frameRect	= V2MakeBox(0.0, 0.0,
									content.size.width + 2.0 * padding.width,
									content.size.height + 2.0 * padding.height);
	self->_tips			= [LDrawStepCalloutBox tipsForCallout:callout];
	self->_arrowGap		= gap;
	self->_arrowInset	= inset;
	self->_arrowSpacing	= spacing;

	// The content is measured from inside the padding.
	[self moveContentBy:V2Make(padding.width, padding.height)];

	return self;

}//end initWithCallout:inModel:options:


//========== moveTo: ===========================================================
///
/// @abstract	Puts the box's top left corner at a point of the view.
///
//==============================================================================
- (void) moveTo:(Point2)origin
{
	Point2 offset = V2Sub(origin, self->_frameRect.origin);

	self->_frameRect = LDrawStepCalloutMovedBox(self->_frameRect, offset);

	[self moveContentBy:offset];

}//end moveTo:


//========== moveContentBy: ====================================================
- (void) moveContentBy:(Point2)offset
{
	for (LDrawStepCalloutPicture *picture in self->_content.pictures) {
		[picture moveBy:offset];
	}
	for (LDrawStepCalloutLabel *label in self->_content.labels) {
		[label moveBy:offset];
	}
	for (LDrawStepCalloutStep *step in self->_content.steps) {
		[step moveBy:offset];
	}

	[self->_content moveSubmodelAreasBy:offset];

	Box2		*dividers	= self->_content.dividers.mutableBytes;
	NSUInteger	 count		= self.dividerCount;

	for (NSUInteger index = 0; index < count; index++) {
		dividers[index] = LDrawStepCalloutMovedBox(dividers[index], offset);
	}

}//end moveContentBy:


// MARK: - CONTENT -


- (NSArray<LDrawStepCalloutPicture *> *) pictures
{
	return self->_content.pictures;
}

- (NSArray<LDrawStepCalloutLabel *> *) labels
{
	return self->_content.labels;
}

- (NSUInteger) dividerCount
{
	return self->_content.dividers.length / sizeof(Box2);
}

- (NSUInteger) summarizedStepCount
{
	return self->_content.summarizedStepCount;
}


//========== dividerRectAtIndex: ===============================================
- (Box2) dividerRectAtIndex:(NSUInteger)index
{
	if (index >= self.dividerCount) {
		return ZeroBox2;
	}

	return ((const Box2 *)self->_content.dividers.bytes)[index];

}//end dividerRectAtIndex:


- (NSArray<LDrawStepCalloutStep *> *) steps
{
	return self->_content.steps;
}


//========== stepAtPoint: ======================================================
///
/// @abstract	The step at a point of the view, or nil.
///
/// @discussion	The steps' shares come first. The room between two columns or
/// 			rows belongs to no share, and counts for the step after it.
///
//==============================================================================
- (nullable LDrawStepCalloutStep *) stepAtPoint:(Point2)point
{
	NSArray<LDrawStepCalloutStep *> *steps = self.steps;

	for (LDrawStepCalloutStep *step in steps) {
		if (V2BoxContains(step.rect, point)) {
			return step;
		}
	}

	for (LDrawStepCalloutStep *step in steps) {
		if (BoxHasArea(step.dividerRect) && V2BoxContains(step.dividerRect, point)) {
			return step;
		}
	}

	return nil;

}//end stepAtPoint:


//========== submodelAtPoint: ==================================================
///
/// @abstract	The submodel shown at a point of the view, or nearest to it.
///
//==============================================================================
- (nullable LDrawModel *) submodelAtPoint:(Point2)point
{
	NSArray<LDrawModel *>	*submodels	= self->_content.areaSubmodels;
	const Box2				*areas		= self->_content.submodelAreas.bytes;
	LDrawModel				*nearest	= nil;
	double					 shortest	= DBL_MAX;

	for (NSUInteger index = 0; index < submodels.count; index++) {
		Box2 area = areas[index];

		// How far outside the area the point is. Nothing for a point in it.
		double dx		= MAX(MAX(V2BoxMinX(area) - point.x, point.x - V2BoxMaxX(area)), 0.0);
		double dy		= MAX(MAX(V2BoxMinY(area) - point.y, point.y - V2BoxMaxY(area)), 0.0);
		double distance	= hypot(dx, dy);

		if (distance < shortest) {
			shortest	= distance;
			nearest		= submodels[index];
		}
	}

	return nearest;

}//end submodelAtPoint:


// MARK: - ARROWS -


- (NSUInteger) tipCount
{
	return self->_tips.length / sizeof(Point3);
}


//========== getPlacementOffset:forOrigin: =====================================
///
/// @abstract	The offset a PLACEMENT line needs for the box's corner to land
/// 			at `origin`: how far that is from where the box goes with no
/// 			offset, as a share of what it is placed against.
///
/// @discussion	Writing the line has the step centered again, which moves the
/// 			assembly when the box was centered with it until now. A box
/// 			placed against the assembly moves along. So the offset is
/// 			measured from where the box will go with no offset then, and
/// 			the box ends up at `origin`.
///
/// 			A box that follows its submodel is drawn away from where the
/// 			line puts it. The line is written for the file's side of the
/// 			submodel: it puts the box as far from `origin` as the submodel
/// 			has moved, so that beside its submodel the box is at `origin`.
///
/// 			Where the file then puts the box cannot be seen in a turned
/// 			view. So a box dropped on the page gets a place in the file
/// 			that is on the page too, and clear of the parts list and of the
/// 			other boxes. Off the page it would stop following.
///
//==============================================================================
- (BOOL) getPlacementOffset:(Point2 *)outOffset forOrigin:(Point2)origin
{
	if (self.isPlacedByFile == NO || BoxHasArea(self->_anchorRect) == NO) {
		return NO;
	}

	Point2	unoffset	= V2Add(self->_unoffsetOrigin, self->_assemblyShiftAfterDrag);
	Point2	wanted		= V2Sub(origin, self->_submodelShift);
	Size2	size		= self->_frameRect.size;
	Box2	page		= self->_pageRect;
	Box2	dropped		= V2MakeBox(origin.x, origin.y, size.width, size.height);
	BOOL	isFollowing	= (self->_submodelShift.x != 0.0 || self->_submodelShift.y != 0.0);
	BOOL	isOnPage	= BoxHasArea(page)
					   && V2BoxMinX(dropped) >= V2BoxMinX(page) && V2BoxMaxX(dropped) <= V2BoxMaxX(page)
					   && V2BoxMinY(dropped) >= V2BoxMinY(page) && V2BoxMaxY(dropped) <= V2BoxMaxY(page);

	// On the page, or as far off it as the file has the box now.
	if (isFollowing && isOnPage) {
		Point2 placed	= self->_placedOrigin;
		Point2 least	= V2Make(MIN(V2BoxMinX(page), placed.x), MIN(V2BoxMinY(page), placed.y));
		Point2 most		= V2Make(MAX(V2BoxMaxX(page) - size.width, placed.x),
								 MAX(V2BoxMaxY(page) - size.height, placed.y));

		wanted = OriginClearOf(wanted, size, self.fileObstacles, least, most);
	}

	*outOffset = V2Make((wanted.x - unoffset.x) / V2BoxWidth(self->_anchorRect),
						(wanted.y - unoffset.y) / V2BoxHeight(self->_anchorRect));
	return YES;

}//end getPlacementOffset:forOrigin:


//========== previewOrigin: ====================================================
- (void) previewOrigin:(Point2)origin
{
	self->_isHeld = YES;

	[self moveTo:origin];

}//end previewOrigin:


//========== placedRect ========================================================
- (Box2) placedRect
{
	Size2 size = self->_frameRect.size;

	return V2MakeBox(self->_placedOrigin.x, self->_placedOrigin.y, size.width, size.height);

}//end placedRect


//========== followTo:submodelShift: ===========================================
- (void) followTo:(Point2)origin submodelShift:(Point2)submodelShift
{
	self->_submodelShift = submodelShift;

	// A box held by a drag stays under the pointer.
	if (self->_isHeld == NO) {
		[self moveTo:origin];
	}

}//end followTo:submodelShift:


//========== placementsMiddle ==================================================
- (Point3) placementsMiddle
{
	NSArray<LDrawPart *>	*placements	= self.callout.placements;
	Point3					 sum		= ZeroPoint3;

	if (placements.count == 0) {
		return ZeroPoint3;
	}

	for (LDrawPart *part in placements) {
		sum = V3Add(sum, [LDrawStepCalloutBox middleOfPlacement:part]);
	}

	return V3MulScalar(sum, 1.0 / placements.count);

}//end placementsMiddle


//========== tipModelPointAtIndex: =============================================
- (Point3) tipModelPointAtIndex:(NSUInteger)index
{
	if (index >= self.tipCount) {
		return ZeroPoint3;
	}

	return ((const Point3 *)self->_tips.bytes)[index];

}//end tipModelPointAtIndex:


//========== tipOutlinePointsAtIndex: ==========================================
- (NSData *) tipOutlinePointsAtIndex:(NSUInteger)index
{
	if (index >= self.tipCount) {
		return [NSData data];
	}

	if (self->_tipOutlines == nil) {
		self->_tipOutlines = [LDrawStepCalloutBox tipOutlinesForCallout:self.callout count:self.tipCount];
	}

	return self->_tipOutlines[index];

}//end tipOutlinePointsAtIndex:


//========== arrowsToMiddles:outlines: =========================================
///
/// @abstract	The box's arrows: each from an edge of the box toward a
/// 			placement's middle, to just short of the placement's outline.
///
//==============================================================================
- (NSData *) arrowsToMiddles:(NSData *)middles outlines:(NSArray<NSData *> *)outlines
{
	const Point2	*points	= middles.bytes;
	NSUInteger		 count	= middles.length / sizeof(Point2);
	NSMutableData	*drawn	= [NSMutableData data];

	if (count == 0) {
		return drawn;
	}

	EdgeArrow *arrows = malloc(count * sizeof(EdgeArrow));
	EdgeArrow *onEdge = malloc(count * sizeof(EdgeArrow));

	for (NSUInteger index = 0; index < count; index++) {
		arrows[index]		= [self edgeArrowToMiddle:points[index]];
		arrows[index].index	= index;
	}

	// The arrows of one edge find their places on it together.
	for (BoxEdge edge = 0; edge < BoxEdgeCount; edge++) {
		NSUInteger edgeCount = 0;

		for (NSUInteger index = 0; index < count; index++) {
			if (arrows[index].edge == edge) {
				onEdge[edgeCount++] = arrows[index];
			}
		}

		[self placeStartsOfArrows:onEdge count:edgeCount onEdge:edge];

		for (NSUInteger index = 0; index < edgeCount; index++) {
			arrows[onEdge[index].index].start = onEdge[index].start;
		}
	}

	for (NSUInteger index = 0; index < count; index++) {
		if (arrows[index].edge == BoxEdgeNone) {
			continue;
		}

		NSData					*outline	= (index < outlines.count) ? outlines[index] : nil;
		LDrawStepCalloutArrow	 arrow;

		arrow.start	= [self pointOfEdge:arrows[index].edge at:arrows[index].start];
		arrow.tip	= [LDrawStepCalloutBox tipOnWayFrom:arrow.start
											   toMiddle:points[index]
												outline:outline
													gap:self->_arrowGap];

		[drawn appendBytes:&arrow length:sizeof(LDrawStepCalloutArrow)];
	}

	free(arrows);
	free(onEdge);

	return drawn;

}//end arrowsToMiddles:outlines:


//========== edgeArrowToMiddle: ================================================
///
/// @abstract	An arrow toward a point, measured from the edge it leaves.
///
/// @discussion	A point past a corner is past two edges, and the arrow leaves
/// 			the one the point is further past.
///
//==============================================================================
- (EdgeArrow) edgeArrowToMiddle:(Point2)middle
{
	Box2		frame	= self.frameRect;
	double		pastX	= MAX(V2BoxMinX(frame) - middle.x, middle.x - V2BoxMaxX(frame));
	double		pastY	= MAX(V2BoxMinY(frame) - middle.y, middle.y - V2BoxMaxY(frame));
	EdgeArrow	arrow	= { 0 };

	if (V2BoxContains(frame, middle)) {
		arrow.edge = BoxEdgeNone;
	}
	else if (pastY >= pastX) {
		arrow.edge	= (middle.y < V2BoxMinY(frame)) ? BoxEdgeTop : BoxEdgeBottom;
		arrow.along	= middle.x;
		arrow.out	= pastY;
	}
	else {
		arrow.edge	= (middle.x < V2BoxMinX(frame)) ? BoxEdgeLeft : BoxEdgeRight;
		arrow.along	= middle.y;
		arrow.out	= pastX;
	}

	return arrow;

}//end edgeArrowToMiddle:


//========== placeStartsOfArrows:count:onEdge: =================================
///
/// @abstract	Works out where the arrows of one edge leave it, clear of the
/// 			edge's two corners. An edge too short to keep clear of both is
/// 			left at its middle.
///
//==============================================================================
- (void) placeStartsOfArrows:(EdgeArrow *)arrows count:(NSUInteger)count onEdge:(BoxEdge)edge
{
	Box2	frame			= self.frameRect;
	BOOL	isHorizontal	= (edge == BoxEdgeTop || edge == BoxEdgeBottom);
	double	low				= isHorizontal ? V2BoxMinX(frame) : V2BoxMinY(frame);
	double	high			= isHorizontal ? V2BoxMaxX(frame) : V2BoxMaxY(frame);
	double	room			= isHorizontal ? self->_arrowInset.width : self->_arrowInset.height;
	double	inset			= MIN(room, (high - low) / 2.0);

	PlaceStarts(arrows, count, low + inset, high - inset, self->_arrowSpacing);

}//end placeStartsOfArrows:count:onEdge:


//========== pointOfEdge:at: ===================================================
///
/// @abstract	The point this far along an edge of the box, in the view.
///
//==============================================================================
- (Point2) pointOfEdge:(BoxEdge)edge at:(double)along
{
	Box2 frame = self.frameRect;

	switch (edge) {
		case BoxEdgeTop:	return V2Make(along, V2BoxMinY(frame));
		case BoxEdgeBottom:	return V2Make(along, V2BoxMaxY(frame));
		case BoxEdgeLeft:	return V2Make(V2BoxMinX(frame), along);
		default:			return V2Make(V2BoxMaxX(frame), along);
	}

}//end pointOfEdge:at:


//---------- tipOnWayFrom:toMiddle:outline:gap: ----------------------[static]--
///
/// @abstract	Where an arrow from `start` toward a placement's middle stops:
/// 			`gap` short of the first edge of the placement's outline it
/// 			meets.
///
/// @discussion	The outline is taken with no dents, which is close enough for
/// 			an arrow. An arrow that starts inside it has no edge to stop at
/// 			and goes to the middle, and so does one with nothing to
/// 			measure.
///
//------------------------------------------------------------------------------
+ (Point2) tipOnWayFrom:(Point2)start
			   toMiddle:(Point2)middle
				outline:(nullable NSData *)outline
					gap:(double)gap
{
	NSUInteger count = outline.length / sizeof(Point2);

	if (count < 3) {
		return middle;
	}

	NSMutableData	*storage		= [NSMutableData dataWithLength:2 * count * sizeof(Point2)];
	Point2			*corners		= storage.mutableBytes;
	NSUInteger		 cornerCount	= ConvexOutline(outline.bytes, count, corners);
	double			 share			= 1.0;

	if (cornerCount < 3
		|| IsInsideOutline(start, corners, cornerCount)
		|| FirstCrossing(start, middle, corners, cornerCount, &share) == NO) {
		return middle;
	}

	// Short of the edge by the gap, and never behind the start.
	double length = hypot(middle.x - start.x, middle.y - start.y);

	if (length > 0.0) {
		share = MAX(share - gap / length, 0.0);
	}

	return V2Make(start.x + (middle.x - start.x) * share, start.y + (middle.y - start.y) * share);

}//end tipOnWayFrom:toMiddle:outline:gap:


//---------- tipsForCallout: -----------------------------------------[static]--
///
/// @abstract	Where a callout's arrows point: the middle of a placement, in
/// 			the step's model, for each POINTER line the callout has.
///
/// @discussion	The file's own tips are places on LPub3D's picture of the step,
/// 			which Bricksmith cannot match closely enough, so only their
/// 			number is used.
///
//------------------------------------------------------------------------------
+ (NSMutableData *) tipsForCallout:(LDrawStepCallout *)callout
{
	NSArray<LDrawPart *>	*placements	= callout.placements;
	NSUInteger				 count		= MIN(placements.count, callout.pointers.count);
	NSMutableData			*tips		= [NSMutableData dataWithCapacity:count * sizeof(Point3)];

	for (NSUInteger index = 0; index < count; index++) {
		Point3 tip = [self middleOfPlacement:placements[index]];

		[tips appendBytes:&tip length:sizeof(Point3)];
	}

	return tips;

}//end tipsForCallout:


//---------- tipOutlinesForCallout:count: ----------------------------[static]--
///
/// @abstract	The outline of each placement an arrow goes to, in the step's
/// 			model: the submodel's outline points, placed as the part places
/// 			the submodel.
///
//------------------------------------------------------------------------------
+ (NSArray<NSData *> *) tipOutlinesForCallout:(LDrawStepCallout *)callout count:(NSUInteger)count
{
	NSArray<LDrawPart *>				*placements	= callout.placements;
	NSArray<LDrawModel *>				*submodels	= callout.submodels;
	NSArray<LDrawStepPartListEntry *>	*entries	= callout.entries;
	NSMutableArray<NSData *>			*outlines	= [NSMutableArray arrayWithCapacity:count];

	for (NSUInteger index = 0; index < count; index++) {
		LDrawPart		*part		= placements[index];
		LDrawModel		*submodel	= [LDrawStepPartList assemblyPlacedByPart:part];
		NSUInteger		 row		= (submodel != nil) ? [submodels indexOfObjectIdenticalTo:submodel] : NSNotFound;
		NSData			*points		= (row != NSNotFound) ? entries[row].outlinePoints : nil;
		NSUInteger		 pointCount	= points.length / sizeof(Point3);
		NSMutableData	*placed		= [NSMutableData dataWithLength:pointCount * sizeof(Point3)];
		const Point3	*source		= points.bytes;
		Point3			*target		= placed.mutableBytes;
		Matrix4			 transform	= [part transformationMatrix];

		for (NSUInteger pointIndex = 0; pointIndex < pointCount; pointIndex++) {
			target[pointIndex] = V3MulPointByProjMatrix(source[pointIndex], transform);
		}

		[outlines addObject:placed];
	}

	return outlines;

}//end tipOutlinesForCallout:count:


//---------- middleOfPlacement: --------------------------------------[static]--
///
/// @abstract	The middle of what a part places, in the part's model.
///
/// @discussion	Without a part catalog it cannot be measured, and the point is
/// 			where the part is placed.
///
//------------------------------------------------------------------------------
+ (Point3) middleOfPlacement:(LDrawPart *)part
{
	if ([LDrawPartLibrary sharedPartLibraryIfRegistered] != nil) {
		Box3 bounds = [part boundingBox3];

		if (V3EqualBoxes(bounds, InvalidBox) == NO) {
			return V3Midpoint(bounds.min, bounds.max);
		}
	}

	return [part position];

}//end middleOfPlacement:


@end
