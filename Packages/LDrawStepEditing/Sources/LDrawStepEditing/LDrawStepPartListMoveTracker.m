//==============================================================================
//
//  File:       LDrawStepPartListMoveTracker.m
//  Package:    LDrawStepEditing
//
//  Purpose:    Follows a drag of the parts list on LPub3D's page.
//
//  Created by Sergey Slobodenyuk on 2026-10-21.
//
//==============================================================================

#import <LDrawStepEditing/LDrawStepPartListMoveTracker.h>

#import <LDrawFeatures/LDrawStepPartListPresentation.h>


/// How near the frame snaps to a column or row of the page's places, in
/// points.
static const double SNAP_POINTS = 6.0;

/// How far the pointer goes before a press is a drag, in points.
static const double DRAG_START_POINTS = 3.0;

/// The page's nine places, by row and column.
static const LPubPlacementPosition PLACES[3][3] = {
	{ LPubPlacementPositionTopLeft,		LPubPlacementPositionTop,		LPubPlacementPositionTopRight },
	{ LPubPlacementPositionLeft,		LPubPlacementPositionCenter,	LPubPlacementPositionRight },
	{ LPubPlacementPositionBottomLeft,	LPubPlacementPositionBottom,	LPubPlacementPositionBottomRight }
};


//========== GetPlaceLines() ===================================================
///
/// @abstract	Where the frame's corner is at each of the page's places: three
/// 			columns across and three rows down.
///
//==============================================================================
static void GetPlaceLines(LDrawStepPartListPresentation *presentation, double *columns, double *rows)
{
	for (NSInteger index = 0; index < 3; index++) {
		columns[index]	= [presentation listOriginAtPagePosition:PLACES[1][index]].x;
		rows[index]		= [presentation listOriginAtPagePosition:PLACES[index][1]].y;
	}

}//end GetPlaceLines


//========== EditPlacingList() =================================================
///
/// @abstract	The edit that puts the frame's corner at `origin`: at the place
/// 			in `column` and `row`, or with -1 for either at the nearest
/// 			place, with the offset from it as shares of the page.
///
//==============================================================================
static LDrawStepAssemblyEdit *EditPlacingList(Point2 origin, const double *columns, const double *rows,
											  NSInteger column, NSInteger row, Box2 page,
											  LDrawStepAssemblyScope scope, LDrawModel *model)
{
	if (V2BoxWidth(page) <= 0.0 || V2BoxHeight(page) <= 0.0) {
		return nil;
	}

	if (column < 0 || row < 0) {
		double nearest = INFINITY;

		for (NSInteger down = 0; down < 3; down++) {
			for (NSInteger across = 0; across < 3; across++) {
				double distance = hypot(origin.x - columns[across], origin.y - rows[down]);

				if (distance < nearest) {
					nearest	= distance;
					column	= across;
					row		= down;
				}
			}
		}
	}

	Point2 offset = V2Make((origin.x - columns[column]) / V2BoxWidth(page),
						   (origin.y - rows[row]) / V2BoxHeight(page));

	return [LDrawStepAssemblyEdit editPlacingListOnPageAt:PLACES[row][column] offset:offset scope:scope inModel:model];

}//end EditPlacingList


//========== SnapIndex() =======================================================
///
/// @abstract	The index of the value within the snap distance of `value`,
/// 			the nearest of them, or -1 for none.
///
//==============================================================================
static NSInteger SnapIndex(double value, const double *targets)
{
	NSInteger	found	= -1;
	double		nearest	= SNAP_POINTS;

	for (NSInteger index = 0; index < 3; index++) {
		if (fabs(targets[index] - value) < nearest) {
			found	= index;
			nearest	= fabs(targets[index] - value);
		}
	}

	return found;

}//end SnapIndex


@implementation LDrawStepPartListMoveTracker
{
	/// Where the pointer took the frame, from its top left corner.
	Point2		grab;

	/// Where the frame was when the drag started.
	Point2		startOrigin;

	/// The frame's corner at each of the page's places: three columns across
	/// and three rows down.
	double		columns[3];
	double		rows[3];

	/// The page the offset is a share of, and the size of the frame on it.
	Box2		pageRect;
	Size2		frameSize;

	/// The column and row the frame snapped to, or -1.
	NSInteger	snappedColumn;
	NSInteger	snappedRow;

	/// The pointer went far enough for a drag.
	BOOL		hasMoved;
}


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_guides = [NSData data];
	}
	return self;

}//end init


//========== beginAtPoint:presentation: ========================================
- (BOOL) beginAtPoint:(Point2)point presentation:(nullable LDrawStepPartListPresentation *)presentation
{
	Box2 frame = presentation.frameRect;

	self->_isMoving = NO;

	if (presentation.isOnPage == NO
		|| V2BoxWidth(frame) <= 0.0 || V2BoxHeight(frame) <= 0.0
		|| V2BoxContains(frame, point) == NO) {
		return NO;
	}

	GetPlaceLines(presentation, self->columns, self->rows);

	self->grab			= V2Make(point.x - frame.origin.x, point.y - frame.origin.y);
	self->startOrigin	= frame.origin;
	self->pageRect		= presentation.pageRect;
	self->frameSize		= frame.size;
	self->_guides		= [NSData data];
	self->snappedColumn	= -1;
	self->snappedRow	= -1;
	self->hasMoved		= NO;
	self->_origin		= frame.origin;
	self->_isMoving		= YES;

	return YES;

}//end beginAtPoint:presentation:


//========== dragToPoint: ======================================================
- (void) dragToPoint:(Point2)point
{
	if (self.isMoving == NO) {
		return;
	}

	Point2 raw = V2Make(point.x - self->grab.x, point.y - self->grab.y);

	if (hypot(raw.x - self->startOrigin.x, raw.y - self->startOrigin.y) >= DRAG_START_POINTS) {
		self->hasMoved = YES;
	}

	if (self->hasMoved == NO) {
		return;
	}

	self->snappedColumn	= SnapIndex(raw.x, self->columns);
	self->snappedRow	= SnapIndex(raw.y, self->rows);

	self->_origin = V2Make((self->snappedColumn >= 0) ? self->columns[self->snappedColumn] : raw.x,
						   (self->snappedRow >= 0) ? self->rows[self->snappedRow] : raw.y);

	self->_guides = [self guidesOfSnaps];

}//end dragToPoint:


//========== guidesOfSnaps =====================================================
///
/// @abstract	A line across the page for each axis the frame snapped on: at
///				its near edge in the first column or row, its middle in the
///				second, and its far edge in the third.
///
//==============================================================================
- (NSData *) guidesOfSnaps
{
	NSMutableData	*guides	= [NSMutableData data];
	Box2			 page	= self->pageRect;

	if (self->snappedColumn >= 0) {
		double	x		= self->columns[self->snappedColumn] + self->frameSize.width * self->snappedColumn / 2.0;
		Box2	line	= V2MakeBox(x, V2BoxMinY(page), 0.0, V2BoxHeight(page));

		[guides appendBytes:&line length:sizeof(Box2)];
	}

	if (self->snappedRow >= 0) {
		double	y		= self->rows[self->snappedRow] + self->frameSize.height * self->snappedRow / 2.0;
		Box2	line	= V2MakeBox(V2BoxMinX(page), y, V2BoxWidth(page), 0.0);

		[guides appendBytes:&line length:sizeof(Box2)];
	}

	return guides;

}//end guidesOfSnaps


//========== editForDropInModel:scope: =========================================
///
/// @abstract	The edit that places the list where it is held.
///
/// @discussion	On one of the page's places it goes there with no offset.
/// 			Elsewhere it goes to the nearest place, with the offset from it.
///
//==============================================================================
- (nullable LDrawStepAssemblyEdit *) editForDropInModel:(nullable LDrawModel *)model
												  scope:(LDrawStepAssemblyScope)scope
{
	if (self.isMoving == NO || self->hasMoved == NO) {
		return nil;
	}

	return EditPlacingList(self.origin, self->columns, self->rows, self->snappedColumn, self->snappedRow,
						   self->pageRect, scope, model);

}//end editForDropInModel:scope:


//========== editPlacingListAtOrigin:presentation:scope:inModel: ===============
+ (nullable LDrawStepAssemblyEdit *) editPlacingListAtOrigin:(Point2)origin
												presentation:(nullable LDrawStepPartListPresentation *)presentation
													   scope:(LDrawStepAssemblyScope)scope
													 inModel:(nullable LDrawModel *)model
{
	double columns[3];
	double rows[3];

	if (presentation.isOnPage == NO) {
		return nil;
	}

	GetPlaceLines(presentation, columns, rows);

	return EditPlacingList(origin, columns, rows, -1, -1, presentation.pageRect, scope, model);

}//end editPlacingListAtOrigin:presentation:scope:inModel:


//========== end ===============================================================
- (void) end
{
	self->_isMoving	= NO;
	self->hasMoved	= NO;
	self->_guides	= [NSData data];

}//end end


@end
