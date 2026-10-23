//==============================================================================
//
//  File:       LDrawStepOverlayPresenter.m
//  Package:    LDrawStepRendering
//
//  Purpose:    Keeps what a step shows over its model in step with the model
//              and the camera.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepRendering/LDrawStepOverlayPresenter.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubCallout.h>
#import <LDrawCore/LPubModelScale.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutArrangement.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPageNumbers.h>
#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>

#import "LDrawStepDrawing.h"
#import "LDrawStepLayoutCacheEntries.h"


/// How far two viewing angles may differ, in degrees, and still be one view.
static const double VIEWING_ANGLE_TOLERANCE = 0.0001;

/// How far apart two turns' matrices may be and still count as one turn:
/// about a twentieth of a degree.
static const double ROTATION_TOLERANCE = 0.001;

/// How far two zooms may differ, as a share of the zoom, and still be one.
static const double ZOOM_TOLERANCE = 0.000001;

// What the arranged step snaps to, and how near it must come.
static const double OFFSET_SNAP_POINTS		= 6.0;	// the page's middle lines and margins, in points
static const double SCALE_SNAP				= 0.01;	// a scale the step inherits, or a step of the scale
static const double SCALE_SNAP_STEP			= 0.05;	// the steps of the scale
static const double ANGLE_SNAP_DEGREES		= 2.0;	// the angles the step inherits
static const double ANGLE_SNAP_STEP			= 15.0;	// the steps of a turn with Shift, in degrees

/// How near the step's middle or edge lies to a guide for the guide to show,
/// in points.
static const double GUIDE_TOLERANCE_POINTS	= 0.5;

/// How far the page anchor may move on screen, in points, and still not be a
/// pan.
static const double PAN_TOLERANCE_POINTS	= 0.001;


//========== MovedPlaces() =====================================================
///
/// @abstract	Box2 values measured from `origin` and made `scale` times as
///				big.
///
//==============================================================================
static NSData * MovedPlaces(NSData *places, Point2 origin, double scale)
{
	NSMutableData	*moved	= [places mutableCopy];
	Box2			*boxes	= moved.mutableBytes;
	NSUInteger		 count	= moved.length / sizeof(Box2);

	for (NSUInteger index = 0; index < count; index++) {
		Box2 box = boxes[index];

		boxes[index] = V2MakeBox((box.origin.x - origin.x) * scale, (box.origin.y - origin.y) * scale,
								 box.size.width * scale, box.size.height * scale);
	}

	return moved;

}//end MovedPlaces


//========== IsSameViewingAngle() ==============================================
static BOOL IsSameViewingAngle(Tuple3 first, Tuple3 second)
{
	return fabs(first.x - second.x) < VIEWING_ANGLE_TOLERANCE
		&& fabs(first.y - second.y) < VIEWING_ANGLE_TOLERANCE
		&& fabs(first.z - second.z) < VIEWING_ANGLE_TOLERANCE;

}//end IsSameViewingAngle


//========== FileOffsetOfModel() ===============================================
///
/// @abstract	The offset the visible step's ASSEM PLACEMENT gives it on the
/// 			page. A line that places it against anything but the page is
/// 			read as none.
///
//==============================================================================
static Point2 FileOffsetOfModel(LDrawModel *model)
{
	LPubPlacement *placement = [LDrawStepPartListPolicy assemblyPlacementForVisibleStepOfModel:model];

	return placement.isInsidePage ? placement.offset : ZeroPoint2;

}//end FileOffsetOfModel


//========== SnapDistance() ====================================================
///
/// @abstract	How far to move a box along one axis so its near edge meets the
///				near margin, its middle the page's middle, or its far edge the
///				far margin: the shortest of those within the snap distance, or
///				0.
///
//==============================================================================
static double SnapDistance(double low, double high, double nearMargin, double middle, double farMargin)
{
	double moves[3]	= { nearMargin - low, middle - (low + high) / 2.0, farMargin - high };
	double best		= 0.0;
	double nearest	= OFFSET_SNAP_POINTS;

	for (int index = 0; index < 3; index++) {
		if (fabs(moves[index]) < nearest) {
			best	= moves[index];
			nearest	= fabs(moves[index]);
		}
	}

	return best;

}//end SnapDistance


//========== BoxAroundPoints() =================================================
///
/// @abstract	The box around these Point2 values, or ZeroBox2 for none.
///
//==============================================================================
static Box2 BoxAroundPoints(NSData *points)
{
	const Point2	*point	= points.bytes;
	NSUInteger		 count	= points.length / sizeof(Point2);

	if (count == 0) {
		return ZeroBox2;
	}

	Point2 minimum = point[0];
	Point2 maximum = point[0];

	for (NSUInteger index = 1; index < count; index++) {
		minimum = V2Make(MIN(minimum.x, point[index].x), MIN(minimum.y, point[index].y));
		maximum = V2Make(MAX(maximum.x, point[index].x), MAX(maximum.y, point[index].y));
	}

	return V2MakeBox(minimum.x, minimum.y, maximum.x - minimum.x, maximum.y - minimum.y);

}//end BoxAroundPoints


//------------------------------------------------------------------------------
///
/// @class      LDrawStepKeptPage
///
/// @abstract   Where a step's assembly sat on its page when it was laid out:
///             the outline around it, as Point2 values in page inches from the
///             page's middle, and how many page inches an LDU covered there.
///
//------------------------------------------------------------------------------
@interface LDrawStepKeptPage : NSObject

@property (nonatomic, copy) NSData	*outline;
@property (nonatomic) double		 inchesPerLDU;

@end

@implementation LDrawStepKeptPage
@end


@interface LDrawStepOverlayPresenter ()

@property (nonatomic, strong, nullable) LDrawStepPartListPresentation *presentation;
@property (nonatomic, copy) NSArray<NSData *> *calloutArrows;

@end


@implementation LDrawStepOverlayPresenter
{
	/// The points the parts of the step on display reach furthest out to, and
	/// the step they were taken for. Dropped when the file changes.
	NSData				*assemblyOutline;
	__weak LDrawStep	*assemblyOutlineStep;

	/// The pages of the model's file, counted once. Dropped when the file
	/// changes.
	LDrawStepPageNumbers	*pageNumbers;

	/// The step the page was last centered on, and the PLACEMENT lines it had
	/// then. The page is centered again when either changes.
	__weak LDrawStep	*centeredStep;
	NSString			*centeredPlacementKey;

	/// Whether that centering had an assembly to measure. A step centered
	/// with nothing to measure is centered again once there is.
	BOOL				 hasMeasuredCenter;

	/// The viewing angle the step was laid out at. While the camera is turned
	/// away from it, the assembly's box keeps its place on the page, and each
	/// callout moves with its submodel from where the file puts it.
	Tuple3				 layoutViewingAngle;

	/// Where what each callout places was drawn at that angle, as Box2
	/// values from the middle of the assembly's box, in page inches: a box
	/// with no size at the middle of its placements, then the box around each
	/// placement an arrow goes to. Kept by the callout's BEGIN line.
	NSMapTable<LPubCallout *, NSData *>	*submodelPlaces;

	/// The sides the callouts' boxes have taken in a turn, and the moves
	/// under way.
	LDrawStepCalloutArrangement			*calloutArrangement;

	/// Where the middle of the page was last drawn, and the viewing angle
	/// then. A turn keeps the page there.
	BOOL				 hasPageMiddle;
	CGPoint				 pageMiddle;
	Tuple3				 pageViewingAngle;

	/// While arranging: where the middle of the page is held in the view, and
	/// how many points its inch covers.
	CGPoint				 arrangedPageMiddle;
	double				 arrangedPointsPerInch;

	/// The step arranged, and the camera as it was last laid out for. A move
	/// of the camera is read against it.
	__weak LDrawStep	*arrangedStep;
	Tuple3				 arrangedCameraAngle;
	double				 arrangedCameraZoom;
	CGPoint				 arrangedAnchorPoint;

	/// A reload is under way. It moves the camera to hold the page, and has
	/// laid out for those moves already.
	BOOL				 isReloading;

	/// The angle LPub3D prints a step at, and that step. Read again for
	/// another step, or after the file changes.
	__weak LDrawStep	*angleStep;
	Tuple3				 stepAngle;

	/// The step is laid out afresh at the camera's angle on the next reload.
	BOOL				 needsArrangedLayout;

	/// The scale was set, so the model is zoomed to it.
	BOOL				 needsArrangedZoom;

	/// The offset was set, so the model moves under the page.
	BOOL				 keepsArrangedOffset;

	/// The arranged values as the user moved them, before they snapped. A move
	/// adds to these, so a drag can go on past where it snapped.
	Point2				 rawArrangedOffset;
	double				 rawArrangedScale;
	BOOL				 hasRawArrangedAngles;
	double				 rawArrangedLatitude;
	double				 rawArrangedLongitude;

	/// Where each step's assembly sat on its page when it was last laid out
	/// as the file has it. Kept until it or an earlier step changes.
	NSMapTable<LDrawStep *, LDrawStepKeptPage *>	*pageOutlines;

	/// While arranging: the points the parts of the earlier steps reach
	/// furthest out to, read once.
	NSData								*earlierOutline;
}


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		NSPointerFunctionsOptions weakObjects = NSPointerFunctionsWeakMemory
											  | NSPointerFunctionsObjectPointerPersonality;

		self->_pageAnchor		= [[LDrawStepPartListPageAnchor alloc] init];
		self->_calloutArrows	= @[];
		self->_arrangedGuides	= [NSData data];
		self->submodelPlaces	= [NSMapTable mapTableWithKeyOptions:weakObjects
														valueOptions:NSPointerFunctionsStrongMemory];
		self->pageOutlines		= [NSMapTable mapTableWithKeyOptions:weakObjects
														valueOptions:NSPointerFunctionsStrongMemory];

		self->_previousStepOutline = [NSData data];

		self->calloutArrangement = [[LDrawStepCalloutArrangement alloc] init];
	}
	return self;

}//end init


//========== reset =============================================================
- (void) reset
{
	self.presentation		= nil;
	self.calloutArrows		= @[];
	self->hasPageMiddle		= NO;
	self->_isArranging		= NO;
	self->_arrangedGuides	= [NSData data];

	self->_previousStepOutline		= [NSData data];
	self->_previousStepPicture		= nil;
	self->_isTurnedFromStepAngle	= NO;
	self->earlierOutline			= nil;

	[self->submodelPlaces removeAllObjects];
	[self->pageOutlines removeAllObjects];
	[self->calloutArrangement reset];

}//end reset


//========== isMovingCallouts ==================================================
- (BOOL) isMovingCallouts
{
	return self->calloutArrangement.isMoving;

}//end isMovingCallouts


// MARK: - LAYING OUT -


//========== reload ============================================================
- (void) reload
{
	self->isReloading = YES;

	// Another step ends the arranging. The host writes what was arranged
	// before it changes the step.
	if (self.isArranging && self->arrangedStep != [self.model visibleStep]) {
		[self endArranging];
	}

	// One walk of the file for all the lookups of this layout.
	[LDrawStepPartListPolicy performWithCachedLookups:^{
		LDrawStepPartListHostState		 host			= {0};
		LDrawStepPartListPresentation	*presentation	= nil;

		if (self.isArranging) {
			[self reloadArranging];
			return;
		}

		[self keepPageInPlaceThroughTurn];

		// Another step is measured afresh, as the camera sees it now.
		if ([self isLaidOutForVisibleStep] == NO) {
			[self startLayout];
		}

		host			= [self hostState];
		presentation	= [self presentationForHost:host];

		// Centering moves the camera, so the step is laid out again for it.
		if ([self needsPageCenterForPresentation:presentation]) {
			[self centerPageOnPresentation:presentation keepingItOnScreen:YES];

			host			= [self hostState];
			presentation	= [self presentationForHost:host];
		}

		[self moveCalloutsWithSubmodelsInPresentation:presentation aroundAssembly:host.assemblyRect];
		[self notePageOutlineOfPresentation:presentation host:host];

		self->_isTurnedFromStepAngle = presentation.isOnPage && [self isCameraTurnedFromStepAngle];

		self.presentation = presentation;
	}];

	[self updateCalloutArrows];

	self->isReloading = NO;

}//end reload


//========== presentationForHost: ==============================================
///
/// @abstract	Lays the visible step out for what the host measured, with the
/// 			page numbers kept for the file.
///
//==============================================================================
- (LDrawStepPartListPresentation *) presentationForHost:(LDrawStepPartListHostState)host
{
	LDrawFile *file = [self.model enclosingFile];

	if ([LDrawStepPartList showsPageNumber] && file != nil && self->pageNumbers.file != file) {
		self->pageNumbers = [LDrawStepPageNumbers pageNumbersOfFile:file];
	}

	return [LDrawStepPartListPresentation presentationForModel:self.model host:host pageNumbers:self->pageNumbers];

}//end presentationForHost:


//========== changeForCameraMove ===============================================
- (LDrawStepOverlayChange) changeForCameraMove
{
	if (self->isReloading) {
		return LDrawStepOverlayChangeNone;
	}

	if (self.presentation.isOnPage) {
		return LDrawStepOverlayChangeLayout;
	}

	if (self.presentation.calloutBoxes.count > 0) {
		[self updateCalloutArrows];
		return LDrawStepOverlayChangeArrows;
	}

	return LDrawStepOverlayChangeNone;

}//end changeForCameraMove


//========== changeForChangedObject: ===========================================
///
/// @abstract	What a change to a file, or to the part library, means here.
///
/// @discussion	A callout's picture is kept by what it shows, not by what is
///				inside its submodel. A line of the model on display is in no
///				called-out submodel, so the pictures stay. A color it defines
///				may be used anywhere.
///
//==============================================================================
- (LDrawStepOverlayChange) changeForChangedObject:(nullable id)object
{
	LDrawModel		*model		= self.model;
	LDrawDirective	*directive	= [object isKindOfClass:[LDrawDirective class]] ? object : nil;
	LDrawFile		*file		= [directive enclosingFile];

	if (file != nil && file != [model enclosingFile]) {
		return LDrawStepOverlayChangeNone;
	}

	// The parts the assembly is measured by, and the pages, may have changed.
	self->assemblyOutline	= nil;
	self->pageNumbers		= nil;
	self->earlierOutline	= nil;
	self->angleStep			= nil;
	[self.layoutCache removeAll];
	[self forgetPageOutlinesChangedBy:directive];

	BOOL isInModel = directive != nil
				  && [directive isKindOfClass:[LDrawColor class]] == NO
				  && [directive enclosingModel] == model;

	return isInModel ? LDrawStepOverlayChangeLayout
					 : (LDrawStepOverlayChangeLayout | LDrawStepOverlayChangePictures);

}//end changeForChangedObject:


// MARK: - ARRANGING -


//========== beginArranging ====================================================
///
/// @abstract	Starts arranging the visible step, from where its lines put it.
///
/// @discussion	The page is held as it is drawn. The first reload lays the step
/// 			out at the camera's angle, at the file's scale, and moves the
/// 			model so the step is where its lines say: a step that edits
/// 			have moved since it was centered does not start with an offset
/// 			the user did not make.
///
//==============================================================================
- (BOOL) beginArranging
{
	LDrawModel						*model			= self.model;
	id<LDrawStepOverlayCamera>		 camera			= self.camera;
	LDrawStepPartListPresentation	*presentation	= self.presentation;

	if (camera == nil || presentation.isOnPage == NO || presentation.pointsPerPageInch <= 0.0) {
		return NO;
	}

	self->_isArranging			= YES;
	self->_arrangedScale		= [LDrawStepPartListPolicy modelScaleForBranch:LPubModelScaleBranchAssembly
																	   inModel:model];
	self->_arrangedOffset		= FileOffsetOfModel(model);
	self->arrangedPageMiddle	= [camera viewPointForModelPoint:[self.pageAnchor pageCenterForModel:model]];
	self->arrangedPointsPerInch	= presentation.pointsPerPageInch;
	self->arrangedStep			= [model visibleStep];
	self->needsArrangedLayout	= YES;
	self->keepsArrangedOffset	= YES;

	self->rawArrangedOffset		= self->_arrangedOffset;
	self->rawArrangedScale		= self->_arrangedScale;
	self->hasRawArrangedAngles	= NO;
	self->earlierOutline		= nil;

	[self noteArrangedCamera];

	return YES;

}//end beginArranging


//========== endArranging ======================================================
- (void) endArranging
{
	if (self.isArranging == NO) {
		return;
	}

	self->_isArranging			= NO;
	self->arrangedStep			= nil;
	self->_arrangedGuides		= [NSData data];
	self->_previousStepOutline	= [NSData data];
	self->_previousStepPicture	= nil;
	self->earlierOutline		= nil;

	// Laid out afresh, and centered where the lines say.
	self->centeredStep	= nil;
	self->hasPageMiddle	= NO;

}//end endArranging


//========== arrangedViewingAngle ==============================================
- (Tuple3) arrangedViewingAngle
{
	return self->arrangedCameraAngle;

}//end arrangedViewingAngle


//========== turnArrangedStepToViewingAngle: ===================================
///
/// @abstract	Turns the camera to an angle the host chose, such as a typed one
///				or a reset. It is kept as it is, without snapping.
///
//==============================================================================
- (void) turnArrangedStepToViewingAngle:(Tuple3)angle
{
	id<LDrawStepOverlayCamera> camera = self.camera;

	if (self.isArranging == NO || [camera respondsToSelector:@selector(setViewingAngle:)] == NO) {
		return;
	}

	[camera setViewingAngle:angle];

	// Laid out at the angle as it is, which a layout does not snap.
	self->needsArrangedLayout	= YES;
	self->hasRawArrangedAngles	= NO;

}//end turnArrangedStepToViewingAngle:


//========== setArrangedScale: =================================================
- (void) setArrangedScale:(double)scale
{
	if (self.isArranging == NO || scale <= 0.0) {
		return;
	}

	self->_arrangedScale		= scale;
	self->rawArrangedScale		= scale;
	self->needsArrangedZoom		= YES;
	self->keepsArrangedOffset	= YES;

}//end setArrangedScale:


//========== setArrangedOffset: ================================================
- (void) setArrangedOffset:(Point2)offset
{
	if (self.isArranging == NO) {
		return;
	}

	self->_arrangedOffset		= offset;
	self->rawArrangedOffset		= offset;
	self->keepsArrangedOffset	= YES;

}//end setArrangedOffset:


//========== moveArrangedStepByInches: =========================================
- (void) moveArrangedStepByInches:(Vector2)distance
{
	Size2 page = [LDrawStepPartListPolicy pageSizeInInchesInModel:self.model];

	if (self.isArranging == NO || page.width <= 0.0 || page.height <= 0.0) {
		return;
	}

	self.arrangedOffset = V2Make(self.arrangedOffset.x + distance.x / page.width,
								 self.arrangedOffset.y + distance.y / page.height);

}//end moveArrangedStepByInches:


//========== zoomArrangedStepToScale: ==========================================
- (void) zoomArrangedStepToScale:(double)scale
{
	if (self.isArranging == NO || scale <= 0.0) {
		return;
	}

	// The raw scale is where the next move goes on from, past the snap.
	self.arrangedScale		= [self snappedScale:scale];
	self->rawArrangedScale	= scale;

}//end zoomArrangedStepToScale:


//========== arrangedPointsPerInch ==============================================
- (double) arrangedPointsPerInch
{
	return self.isArranging ? self->arrangedPointsPerInch : 0.0;

}//end arrangedPointsPerInch


//========== holdArrangedPage ==================================================
///
/// @abstract	Holds the page as it is drawn now. Its inch is read from the
/// 			arranged scale and the scale the model is drawn at.
///
//==============================================================================
- (void) holdArrangedPage
{
	LDrawModel					*model	= self.model;
	id<LDrawStepOverlayCamera>	 camera	= self.camera;
	double						 drawn	= [self assemblyScale];
	double						 scale	= self.arrangedScale * [LPubModelScale inchesPerLDU];

	if (self.isArranging == NO || camera == nil || drawn <= 0.0 || scale <= 0.0) {
		return;
	}

	self->arrangedPageMiddle	= [camera viewPointForModelPoint:[self.pageAnchor pageCenterForModel:model]];
	self->arrangedPointsPerInch	= drawn / scale;

	[self noteArrangedCamera];

}//end holdArrangedPage


//========== fitArrangedPage ===================================================
- (void) fitArrangedPage
{
	LDrawModel					*model	= self.model;
	id<LDrawStepOverlayCamera>	 camera	= self.camera;
	Size2						 view	= self.viewSize;
	double						 fit	= [LDrawStepPartListPolicy pointsPerPageInchFittingPageInHostSize:view
																								  inModel:model];

	if (self.isArranging == NO || camera == nil || fit <= 0.0 || self->arrangedPointsPerInch <= 0.0) {
		return;
	}

	// The model is drawn bigger in proportion to the zoom, and the page with it.
	[camera setZoomPercentage:[camera zoomPercentage] * fit / self->arrangedPointsPerInch];
	[camera scrollModelPoint:[self.pageAnchor pageCenterForModel:model]
				 toViewPoint:CGPointMake(view.width / 2.0, view.height / 2.0)];

	[self holdArrangedPage];

}//end fitArrangedPage


//========== reloadArranging ===================================================
///
/// @abstract	Lays the step out while arranging, and reads what the camera's
/// 			last move made of it.
///
/// @discussion	A turn lays the step out afresh at the new angle, and zooms so
/// 			the model keeps its size beside the page anchor. A zoom gives a
/// 			new scale. After either, the model is scrolled so the step keeps
/// 			its offset on the page. A scroll alone gives a new offset.
///
/// 			The page is held where it was drawn, at its size, all the time.
///
//==============================================================================
- (void) reloadArranging
{
	LDrawModel					*model		= self.model;
	id<LDrawStepOverlayCamera>	 camera		= self.camera;
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	double						 zoom		= [camera zoomPercentage];
	double						 inchScale	= self->arrangedPointsPerInch * [LPubModelScale inchesPerLDU];
	Tuple3						 angle		= [camera viewingAngle];
	CGPoint						 anchor		= [camera viewPointForModelPoint:[pageAnchor anchorForModel:model]];
	BOOL						 isTurned	= IsSameViewingAngle(angle, self->arrangedCameraAngle) == NO;
	BOOL						 isZoomed	= fabs(zoom - self->arrangedCameraZoom) > zoom * ZOOM_TOLERANCE;
	BOOL						 isPanned	= hypot(anchor.x - self->arrangedAnchorPoint.x,
													anchor.y - self->arrangedAnchorPoint.y) > PAN_TOLERANCE_POINTS;
	BOOL						 zoomsToIt	= NO;

	// A turn that snaps turns the camera again, before the step is measured
	// at its angle.
	if (isTurned && self->needsArrangedLayout == NO) {
		[self snapArrangedTurn];
	}

	isTurned	|= self->needsArrangedLayout;
	zoomsToIt	= isTurned || self->needsArrangedZoom;

	if (isTurned) {
		[self startLayout];
	}

	// A zoom gives a scale, which may snap. Then the model is zoomed to it.
	if (zoomsToIt == NO && isZoomed && inchScale > 0.0) {
		double read		= [self assemblyScale] / inchScale;
		double snapped	= [self snappedScaleForRead:read];

		self->_arrangedScale	= snapped;
		zoomsToIt				= fabs(snapped - read) > read * ZOOM_TOLERANCE;
	}

	if (zoomsToIt) {
		double ratio = [pageAnchor drawnScaleRatioOfModel:model inView:camera];

		[camera setZoomPercentage:self.arrangedScale * inchScale / ratio * 100.0];
	}

	[self holdArrangedPageCenter];

	LDrawStepPartListHostState		 host			= [self hostState];
	LDrawStepPartListPresentation	*presentation	= [self presentationForHost:host];

	Size2	inches		= [LDrawStepPartListPolicy pageSizeInInchesInModel:model];
	Size2	page		= V2MakeSize(inches.width * self->arrangedPointsPerInch,
									 inches.height * self->arrangedPointsPerInch);
	Point2	fileOffset	= FileOffsetOfModel(model);
	Point2	middle		= V2Make(self->arrangedPageMiddle.x, self->arrangedPageMiddle.y);

	if (presentation.hasStepCenter && page.width > 0.0 && page.height > 0.0) {
		Point2	center	= presentation.stepCenterInView;
		BOOL	keeps	= isTurned || isZoomed || zoomsToIt || self->keepsArrangedOffset;

		// A scroll gives an offset, which may snap. Then the model is moved
		// to it.
		if (keeps == NO) {
			Point2 read		= V2Make(fileOffset.x + (center.x - middle.x) / page.width,
									 fileOffset.y + (center.y - middle.y) / page.height);
			Point2 snapped	= read;

			// The raw offset moves with the step, past any snap.
			self->rawArrangedOffset = V2Make(self->rawArrangedOffset.x + read.x - self->_arrangedOffset.x,
											 self->rawArrangedOffset.y + read.y - self->_arrangedOffset.y);

			// Only a pan snaps. A drag of the list or of a callout's box can
			// move the step's box too, and the model stays put then.
			if (isPanned) {
				snapped = [self snappedOffsetForRead:read inPresentation:presentation pageSize:page];
			}

			self->_arrangedOffset	= snapped;
			keeps					= (fabs(snapped.x - read.x) * page.width > GUIDE_TOLERANCE_POINTS / 10.0
									   || fabs(snapped.y - read.y) * page.height > GUIDE_TOLERANCE_POINTS / 10.0);
		}

		if (keeps) {
			// Where the page's middle belongs for the arranged offset. The
			// model moves so that it is where the page's middle is held.
			Point2	placed	= V2Make(center.x - (self.arrangedOffset.x - fileOffset.x) * page.width,
									 center.y - (self.arrangedOffset.y - fileOffset.y) * page.height);
			Point3	point	= [camera modelPointForViewPoint:CGPointMake(placed.x, placed.y)
										 depthReferencePoint:[pageAnchor anchorForModel:model]];

			[camera scrollModelPoint:point toViewPoint:self->arrangedPageMiddle];
			[self holdArrangedPageCenter];

			host			= [self hostState];
			presentation	= [self presentationForHost:host];
		}
	}

	self->needsArrangedLayout	= NO;
	self->needsArrangedZoom		= NO;
	self->keepsArrangedOffset	= NO;
	[self noteArrangedCamera];

	self->_arrangedGuides			= [self guidesOfPresentation:presentation];
	self->_previousStepOutline		= self.showsPreviousStep ? [self previousStepOutlineInView] : [NSData data];
	self->_previousStepPicture		= self.showsPreviousStep ? [self previousStepPictureInView] : nil;
	self->_isTurnedFromStepAngle	= NO;

	[self moveCalloutsWithSubmodelsInPresentation:presentation aroundAssembly:host.assemblyRect];

	self.presentation = presentation;

}//end reloadArranging


//========== snapArrangedTurn ==================================================
///
/// @abstract	Snaps a turn to the angles the step inherits, or with Shift to
///				steps of 15°, and turns the camera there.
///
/// @discussion	The angles are LPub3D's, after the step's rotation. A view
///				tilted to one side has none, and does not snap.
///
//==============================================================================
- (void) snapArrangedTurn
{
	LDrawModel					*model		= self.model;
	id<LDrawStepOverlayCamera>	 camera		= self.camera;
	double						 latitude	= 0.0;
	double						 longitude	= 0.0;
	double						 shownLat	= 0.0;
	double						 shownLon	= 0.0;

	BOOL isUpright	= [LDrawStepPartListPolicy getAssemblyLatitude:&latitude
														 longitude:&longitude
												   forViewingAngle:[camera viewingAngle]
														   inModel:model];
	BOOL wasUpright	= [LDrawStepPartListPolicy getAssemblyLatitude:&shownLat
														 longitude:&shownLon
												   forViewingAngle:self->arrangedCameraAngle
														   inModel:model];

	if (isUpright == NO) {
		self->hasRawArrangedAngles = NO;
		return;
	}

	if (self->hasRawArrangedAngles && wasUpright) {
		self->rawArrangedLatitude	+= latitude - shownLat;
		self->rawArrangedLongitude	+= remainder(longitude - shownLon, 360.0);
	}
	else {
		self->rawArrangedLatitude	= latitude;
		self->rawArrangedLongitude	= longitude;
	}

	self->rawArrangedLatitude	= MAX(-90.0, MIN(90.0, self->rawArrangedLatitude));
	self->hasRawArrangedAngles	= YES;

	double snappedLat = self->rawArrangedLatitude;
	double snappedLon = self->rawArrangedLongitude;

	if (self.snapsTurnsToSteps) {
		snappedLat = round(snappedLat / ANGLE_SNAP_STEP) * ANGLE_SNAP_STEP;
		snappedLon = round(snappedLon / ANGLE_SNAP_STEP) * ANGLE_SNAP_STEP;
	}
	else if (self.hasArrangedSnapAngles
			 && fabs(snappedLat - self.arrangedSnapLatitude) < ANGLE_SNAP_DEGREES
			 && fabs(remainder(snappedLon - self.arrangedSnapLongitude, 360.0)) < ANGLE_SNAP_DEGREES) {
		snappedLat = self.arrangedSnapLatitude;
		snappedLon = self.arrangedSnapLongitude;
	}

	BOOL isSnapped = fabs(snappedLat - latitude) > VIEWING_ANGLE_TOLERANCE
				  || fabs(remainder(snappedLon - longitude, 360.0)) > VIEWING_ANGLE_TOLERANCE;

	if (isSnapped && [camera respondsToSelector:@selector(setViewingAngle:)]) {
		[camera setViewingAngle:[LDrawStepPartListPolicy assemblyViewingAngleForLatitude:snappedLat
																			   longitude:snappedLon
																				 inModel:model]];
	}

}//end snapArrangedTurn


//========== snappedScaleForRead: ==============================================
///
/// @abstract	The scale a zoom gives, snapped. The zoom is added to the scale
///				as it was before it last snapped.
///
//==============================================================================
- (double) snappedScaleForRead:(double)read
{
	double raw = (self->_arrangedScale > 0.0) ? self->rawArrangedScale * read / self->_arrangedScale : read;

	self->rawArrangedScale = raw;

	return [self snappedScale:raw];

}//end snappedScaleForRead:


//========== snappedScale: =====================================================
///
/// @abstract	A scale snapped to the one the step inherits, or to a step of
///				0.05, when it is near one.
///
//==============================================================================
- (double) snappedScale:(double)raw
{
	double best		= raw;
	double nearest	= SCALE_SNAP;
	double stepped	= round(raw / SCALE_SNAP_STEP) * SCALE_SNAP_STEP;

	if (stepped > 0.0 && fabs(stepped - raw) < nearest) {
		best	= stepped;
		nearest	= fabs(stepped - raw);
	}

	if (self.arrangedSnapScale > 0.0 && fabs(self.arrangedSnapScale - raw) < nearest) {
		best = self.arrangedSnapScale;
	}

	return best;

}//end snappedScale:


//========== snappedOffsetForRead:inPresentation:pageSize: =====================
///
/// @abstract	The raw offset, snapped on each axis so the step's middle meets
///				the page's middle, or its edge the page's margin, when it is
///				that near.
///
/// @discussion	The step's box is drawn at the offset read. It moves by the
///				page's size times a change of offset, so where it would be at
///				the raw offset is worked out from there.
///
//==============================================================================
- (Point2) snappedOffsetForRead:(Point2)read
				 inPresentation:(LDrawStepPartListPresentation *)presentation
					   pageSize:(Size2)page
{
	Point2	raw		= self->rawArrangedOffset;
	Box2	step	= presentation.stepRect;
	Box2	paper	= presentation.pageRect;
	Size2	margins	= presentation.pageMargins;

	if (V2BoxWidth(step) <= 0.0 || V2BoxHeight(step) <= 0.0) {
		return raw;
	}

	double	shiftX	= (raw.x - read.x) * page.width;
	double	shiftY	= (raw.y - read.y) * page.height;
	double	inX		= margins.width * self->arrangedPointsPerInch;
	double	inY		= margins.height * self->arrangedPointsPerInch;
	double	moveX	= SnapDistance(V2BoxMinX(step) + shiftX, V2BoxMaxX(step) + shiftX,
								   V2BoxMinX(paper) + inX, V2BoxMidX(paper), V2BoxMaxX(paper) - inX);
	double	moveY	= SnapDistance(V2BoxMinY(step) + shiftY, V2BoxMaxY(step) + shiftY,
								   V2BoxMinY(paper) + inY, V2BoxMidY(paper), V2BoxMaxY(paper) - inY);

	return V2Make(raw.x + moveX / page.width, raw.y + moveY / page.height);

}//end snappedOffsetForRead:inPresentation:pageSize:


//========== guidesOfPresentation: =============================================
///
/// @abstract	The page's middle lines and margins the step lines up with:
///				each a Box2 with no width or no height, across the page.
///
//==============================================================================
- (NSData *) guidesOfPresentation:(LDrawStepPartListPresentation *)presentation
{
	NSMutableData	*guides		= [NSMutableData data];
	Box2			 step		= presentation.stepRect;
	Box2			 paper		= presentation.pageRect;
	Size2			 margins	= presentation.pageMargins;
	double			 inX		= margins.width * self->arrangedPointsPerInch;
	double			 inY		= margins.height * self->arrangedPointsPerInch;

	if (V2BoxWidth(step) <= 0.0 || V2BoxHeight(step) <= 0.0 || V2BoxWidth(paper) <= 0.0) {
		return guides;
	}

	double across[3]	= { V2BoxMinX(paper) + inX, V2BoxMidX(paper), V2BoxMaxX(paper) - inX };
	double steps[3]		= { V2BoxMinX(step), V2BoxMidX(step), V2BoxMaxX(step) };
	double down[3]		= { V2BoxMinY(paper) + inY, V2BoxMidY(paper), V2BoxMaxY(paper) - inY };
	double stepsDown[3]	= { V2BoxMinY(step), V2BoxMidY(step), V2BoxMaxY(step) };

	for (int index = 0; index < 3; index++) {
		if (fabs(steps[index] - across[index]) < GUIDE_TOLERANCE_POINTS) {
			Box2 line = V2MakeBox(across[index], V2BoxMinY(paper), 0.0, V2BoxHeight(paper));

			[guides appendBytes:&line length:sizeof(Box2)];
		}

		if (fabs(stepsDown[index] - down[index]) < GUIDE_TOLERANCE_POINTS) {
			Box2 line = V2MakeBox(V2BoxMinX(paper), down[index], V2BoxWidth(paper), 0.0);

			[guides appendBytes:&line length:sizeof(Box2)];
		}
	}

	return guides;

}//end guidesOfPresentation:


//========== holdArrangedPageCenter ============================================
///
/// @abstract	Keeps the model point under the held middle of the page as the
/// 			page's center, so the page is drawn there whatever the camera
/// 			did.
///
//==============================================================================
- (void) holdArrangedPageCenter
{
	LDrawModel					*model		= self.model;
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	Point3						 center		= [self.camera modelPointForViewPoint:self->arrangedPageMiddle
															  depthReferencePoint:[pageAnchor anchorForModel:model]];

	[pageAnchor setPageCenter:center forModel:model];

}//end holdArrangedPageCenter


//========== noteArrangedCamera ================================================
- (void) noteArrangedCamera
{
	Point3 anchor = [self.pageAnchor anchorForModel:self.model];

	self->arrangedCameraAngle	= [self.camera viewingAngle];
	self->arrangedCameraZoom	= [self.camera zoomPercentage];
	self->arrangedAnchorPoint	= [self.camera viewPointForModelPoint:anchor];

}//end noteArrangedCamera


//========== pageHoldingAssemblyScale ==========================================
///
/// @abstract	The scale the page is sized from while arranging: the one that
/// 			gives the held inch for the file's MODEL_SCALE.
///
/// @discussion	The model is drawn at another scale when it was zoomed. The
/// 			page, the parts list and the callouts keep their size.
///
//==============================================================================
- (double) pageHoldingAssemblyScale
{
	return self->arrangedPointsPerInch
		 * [LPubModelScale inchesPerLDU]
		 * [LDrawStepPartListPolicy modelScaleForBranch:LPubModelScaleBranchAssembly inModel:self.model];

}//end pageHoldingAssemblyScale


// MARK: - THE PREVIOUS STEP -


//========== notePageOutlineOfPresentation:host: ===============================
///
/// @abstract	Keeps where the visible step's assembly sits on its page, so the
///				next step can show it and line up with it.
///
/// @discussion	Only as the file has it: not while the camera is turned away
///				from the step's angle, nor while something on the page is
///				dragged. A step already kept is not measured again.
///
//==============================================================================
- (void) notePageOutlineOfPresentation:(LDrawStepPartListPresentation *)presentation
								  host:(LDrawStepPartListHostState)host
{
	LDrawStep	*step	= [self.model visibleStep];
	double		 scale	= presentation.pointsPerPageInch;

	if (step == nil
		|| presentation.hasStepCenter == NO
		|| scale <= 0.0
		|| [self->pageOutlines objectForKey:step] != nil
		|| [self isTurnedSinceLayout]
		|| self.isMovingCallouts
		|| self.hasSizePreview || self.hasCalloutPreview || self.hasListPreview) {
		return;
	}

	NSData			*outline	= nil;
	Box2			 box		= host.assemblyRect;
	Point2			 middle		= V2BoxMid(presentation.pageRect);
	NSMutableData	*inches		= nil;

	if (self->assemblyOutline.length > 0) {
		outline = LDrawStepConvexOutline([self.camera viewPointsForModelPoints:self->assemblyOutline]);
	}

	// With no parts to outline, the box the camera measured.
	if (outline.length == 0) {
		Point2 corners[4] = {
			box.origin,
			V2Make(V2BoxMaxX(box), V2BoxMinY(box)),
			V2Make(V2BoxMaxX(box), V2BoxMaxY(box)),
			V2Make(V2BoxMinX(box), V2BoxMaxY(box))
		};

		outline = [NSData dataWithBytes:corners length:sizeof(corners)];
	}

	inches = [outline mutableCopy];

	Point2		*point	= inches.mutableBytes;
	NSUInteger	 count	= inches.length / sizeof(Point2);

	for (NSUInteger index = 0; index < count; index++) {
		point[index] = V2Make((point[index].x - middle.x) / scale, (point[index].y - middle.y) / scale);
	}

	LDrawStepKeptPage *kept = [LDrawStepKeptPage new];

	kept.outline		= inches;
	kept.inchesPerLDU	= [self assemblyScale] / scale;

	[self->pageOutlines setObject:kept forKey:step];

}//end notePageOutlineOfPresentation:host:


//========== forgetPageOutlinesChangedBy: ======================================
///
/// @abstract	Forgets where steps a change may move sat on their pages: the
///				changed step and the ones after it in its model, and the steps
///				of every other model, since a model may place another.
///
/// @discussion	A note for the whole file or model is read as a change to the
///				step on display: a change of step posts one, after the new step
///				is on display, and the overlay's edits are to that step. A
///				change that is not to the file forgets them all.
///
//==============================================================================
- (void) forgetPageOutlinesChangedBy:(nullable LDrawDirective *)directive
{
	LDrawDirective	*container	= directive;
	LDrawModel		*model		= nil;
	NSUInteger		 first		= NSNotFound;

	while (container != nil && [container isKindOfClass:[LDrawStep class]] == NO) {
		container = [container enclosingDirective];
	}

	if (container == nil && directive != nil) {
		container = [self.model visibleStep];
	}

	if (container != nil) {
		model = [container enclosingModel];
		first = [[model steps] indexOfObjectIdenticalTo:container];
	}

	for (LDrawStep *step in [[self->pageOutlines keyEnumerator] allObjects]) {
		BOOL isEarlier = (first != NSNotFound
						  && [step enclosingModel] == model
						  && [[model steps] indexOfObjectIdenticalTo:step] < first);

		if (isEarlier == NO) {
			[self->pageOutlines removeObjectForKey:step];
		}
	}

}//end forgetPageOutlinesChangedBy:


//========== keptPageOfPreviousStep ============================================
///
/// @abstract	Where the step before the visible one sat on its page, or nil
///				when that is not known.
///
//==============================================================================
- (nullable LDrawStepKeptPage *) keptPageOfPreviousStep
{
	NSArray<LDrawStep *>	*steps	= [self.model steps];
	NSUInteger				 index	= [steps indexOfObjectIdenticalTo:[self.model visibleStep]];

	if (index == NSNotFound || index == 0) {
		return nil;
	}

	return [self->pageOutlines objectForKey:steps[index - 1]];

}//end keptPageOfPreviousStep


//========== previousStepOutlineInView =========================================
///
/// @abstract	That outline on the page held while arranging.
///
//==============================================================================
- (NSData *) previousStepOutlineInView
{
	NSMutableData	*outline	= [[self keptPageOfPreviousStep].outline mutableCopy];
	double			 scale		= self->arrangedPointsPerInch;
	CGPoint			 middle		= self->arrangedPageMiddle;

	if (outline == nil || scale <= 0.0) {
		return [NSData data];
	}

	Point2		*point	= outline.mutableBytes;
	NSUInteger	 count	= outline.length / sizeof(Point2);

	for (NSUInteger index = 0; index < count; index++) {
		point[index] = V2Make(middle.x + point[index].x * scale, middle.y + point[index].y * scale);
	}

	return outline;

}//end previousStepOutlineInView


//========== earlierOutlinePoints ==============================================
///
/// @abstract	The points the parts of the earlier steps reach furthest out
///				to, read once while arranging.
///
//==============================================================================
- (NSData *) earlierOutlinePoints
{
	if (self->earlierOutline == nil) {
		self->earlierOutline = [LDrawStepPartListPolicy earlierAssemblyOutlinePointsInModel:self.model]
							?: [NSData data];
	}

	return self->earlierOutline;

}//end earlierOutlinePoints


//========== previousStepPictureInView =========================================
///
/// @abstract	The picture of the previous step's assembly, in the middle of
///				where its outline is drawn now.
///
/// @discussion	The parts are turned to the previous step's angle, and drawn
///				at as many page inches an LDU as it drew them.
///
//==============================================================================
- (nullable LDrawStepCalloutPicture *) previousStepPictureInView
{
	LDrawModel			*model		= self.model;
	LDrawStepKeptPage	*kept		= [self keptPageOfPreviousStep];
	NSUInteger			 index		= [[model steps] indexOfObjectIdenticalTo:[model visibleStep]];
	NSData				*outline	= [self earlierOutlinePoints];
	const Point3		*point		= outline.bytes;
	NSUInteger			 count		= outline.length / sizeof(Point3);
	Box3				 turned		= InvalidBox;

	if (kept == nil || kept.inchesPerLDU <= 0.0 || count == 0 || index == NSNotFound || index == 0) {
		return nil;
	}

	Tuple3	angle	= [LDrawStepPartListPolicy assemblyViewingAngleForStepAtIndex:index - 1 inModel:model];
	Matrix4	view	= [LDrawStepPartListLayout viewTransformForAngle:angle];

	for (NSUInteger pointIndex = 0; pointIndex < count; pointIndex++) {
		turned = V3UnionBoxAndPoint(turned, V3MulPointByProjMatrix(point[pointIndex], view));
	}

	return [LDrawStepCalloutPicture pictureOfModel:model
									   throughStep:index - 1
									 viewTransform:view
											  rect:BoxAroundPoints(self.previousStepOutline)
									zoomPercentage:kept.inchesPerLDU * self->arrangedPointsPerInch * 100.0
											center:V3Midpoint(turned.min, turned.max)
										subjectKey:[NSString stringWithFormat:@"previous step %p", kept]];

}//end previousStepPictureInView


//========== earlierPartsRect ==================================================
///
/// @abstract	The box around the parts of the earlier steps, as the camera
///				draws them now.
///
//==============================================================================
- (Box2) earlierPartsRect
{
	CGRect rect = [self.camera viewRectForModelPoints:[self earlierOutlinePoints]];

	return LDrawStepBoxFromRect(rect);

}//end earlierPartsRect


//========== canAlignArrangedStepWithPreviousStep ==============================
- (BOOL) canAlignArrangedStepWithPreviousStep
{
	Box2 earlier = ZeroBox2;

	if (self.isArranging == NO || [self keptPageOfPreviousStep].outline.length == 0) {
		return NO;
	}

	earlier = [self earlierPartsRect];

	return V2BoxWidth(earlier) > 0.0 && V2BoxHeight(earlier) > 0.0;

}//end canAlignArrangedStepWithPreviousStep


//========== alignArrangedStepWithPreviousStep =================================
- (void) alignArrangedStepWithPreviousStep
{
	double scale = self->arrangedPointsPerInch;

	if ([self canAlignArrangedStepWithPreviousStep] == NO || scale <= 0.0) {
		return;
	}

	Point2	was		= V2BoxMid(BoxAroundPoints([self keptPageOfPreviousStep].outline));
	Point2	drawn	= V2BoxMid([self earlierPartsRect]);
	Point2	now		= V2Make((drawn.x - self->arrangedPageMiddle.x) / scale,
							 (drawn.y - self->arrangedPageMiddle.y) / scale);

	[self moveArrangedStepByInches:V2Make(was.x - now.x, was.y - now.y)];

}//end alignArrangedStepWithPreviousStep


//========== centerArrangedStepOnPage ==========================================
- (void) centerArrangedStepOnPage
{
	double	scale	= self->arrangedPointsPerInch;
	Box2	step	= self.presentation.stepRect;

	if (self.isArranging == NO || scale <= 0.0 || V2BoxWidth(step) <= 0.0 || V2BoxHeight(step) <= 0.0) {
		return;
	}

	[self moveArrangedStepByInches:V2Make((self->arrangedPageMiddle.x - V2BoxMidX(step)) / scale,
										  (self->arrangedPageMiddle.y - V2BoxMidY(step)) / scale)];

}//end centerArrangedStepOnPage


// MARK: - CENTERING THE PAGE -


//========== needsPageCenterForPresentation: ===================================
///
/// @abstract	Whether the step has to be put in its place on the page again:
///				another step is on display, one of its PLACEMENT lines
///				changed, the page anchor was measured again, or the step can
///				be measured now and could not be when it was centered.
///
/// @discussion	Not for any other change to the step. Moving a part would
///				otherwise move the page under the pointer.
///
//==============================================================================
- (BOOL) needsPageCenterForPresentation:(LDrawStepPartListPresentation *)presentation
{
	if (presentation.isOnPage == NO || self.camera == nil) {
		return NO;
	}

	if ([self isLaidOutForVisibleStep] == NO) {
		return YES;
	}

	if (presentation.hasStepCenter && self->hasMeasuredCenter == NO) {
		return YES;
	}

	return [presentation.placementKey isEqualToString:self->centeredPlacementKey] == NO;

}//end needsPageCenterForPresentation:


//========== isLaidOutForVisibleStep ===========================================
///
/// @abstract	Whether the page has a place for the step on display: it was
///				centered on that step, and the page anchor has not been
///				measured again since.
///
//==============================================================================
- (BOOL) isLaidOutForVisibleStep
{
	LDrawModel *model = self.model;

	return [self.pageAnchor hasPageCenterForModel:model] && self->centeredStep == [model visibleStep];

}//end isLaidOutForVisibleStep


//========== startLayout =======================================================
///
/// @abstract	Has the step's assembly measured afresh, as the camera sees it
///				now.
///
//==============================================================================
- (void) startLayout
{
	[self.pageAnchor forgetAssemblyRect];
	[self.pageAnchor forgetDrawnScale];
	[self->submodelPlaces removeAllObjects];
	[self->calloutArrangement reset];

	self->layoutViewingAngle = [self.camera viewingAngle];

}//end startLayout


//========== isCameraTurnedFromStepAngle =======================================
///
/// @abstract	Whether the camera looks at the visible step from another angle
///				than LPub3D prints it at.
///
//==============================================================================
- (BOOL) isCameraTurnedFromStepAngle
{
	LDrawModel	*model	= self.model;
	LDrawStep	*step	= [model visibleStep];
	NSUInteger	 index	= [[model steps] indexOfObjectIdenticalTo:step];

	if (self.camera == nil || index == NSNotFound) {
		return NO;
	}

	if (step != self->angleStep) {
		self->angleStep	= step;
		self->stepAngle	= [LDrawStepPartListPolicy assemblyViewingAngleForStepAtIndex:index inModel:model];
	}

	return Matrix4AnglesWithinTolerance([self.camera viewingAngle], self->stepAngle, ROTATION_TOLERANCE) == NO;

}//end isCameraTurnedFromStepAngle


//========== isTurnedSinceLayout ===============================================
- (BOOL) isTurnedSinceLayout
{
	return IsSameViewingAngle([self.camera viewingAngle], self->layoutViewingAngle) == NO;

}//end isTurnedSinceLayout


//========== keepPageInPlaceThroughTurn ========================================
///
/// @abstract	After the camera was turned, keeps the page where it was drawn.
///				The model turns on the paper, and the page and what is laid
///				out on it stay put.
///
/// @discussion	The page is pinned to a model point, which a turn moves on
///				screen. So after a turn the point is taken again from under
///				the page's middle. A pan or a zoom moves the page with the
///				model, and the page's new place is noted.
///
//==============================================================================
- (void) keepPageInPlaceThroughTurn
{
	LDrawModel					*model		= self.model;
	id<LDrawStepOverlayCamera>	 camera		= self.camera;
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;

	if (camera == nil
		|| [LDrawStepPartListPolicy drawsPageInModel:model] == NO
		|| [pageAnchor hasPageCenterForModel:model] == NO) {
		return;
	}

	Tuple3 angle = [camera viewingAngle];

	if (self->hasPageMiddle && IsSameViewingAngle(angle, self->pageViewingAngle) == NO) {
		Point3 anchor = [pageAnchor anchorForModel:model];
		Point3 center = [camera modelPointForViewPoint:self->pageMiddle depthReferencePoint:anchor];

		[pageAnchor setPageCenter:center forModel:model];
	}
	else {
		self->pageMiddle	= [camera viewPointForModelPoint:[pageAnchor pageCenterForModel:model]];
		self->hasPageMiddle	= YES;
	}

	self->pageViewingAngle = angle;

}//end keepPageInPlaceThroughTurn


//========== centerPageOnStep ==================================================
///
/// @abstract	Puts the visible step in its place on the page again, and keeps
///				the model point that is drawn at the middle of the page.
///
/// @discussion	The step is laid out once just to measure it. Where the page
///				went is kept in the layout cache, and used instead the next
///				time the step is centered in the same view.
///
//==============================================================================
- (void) centerPageOnStep
{
	LDrawModel *model = self.model;

	if (self.camera == nil || [LDrawStepPartListPolicy drawsPageInModel:model] == NO) {
		return;
	}

	// The outline may be from before the change that asks for this.
	self->assemblyOutline = nil;

	[self startLayout];

	LDrawStepLayoutCache	*cache	= self.layoutCache;
	NSString				*key	= [self centerKey];
	LDrawStepKeptCenter		*kept	= (key != nil) ? [cache centerForKey:key] : nil;

	if (kept != nil) {
		[self.pageAnchor setPageCenter:kept.pageCenter forModel:model];
		[self noteCenteredStepWithPlacementKey:kept.placementKey isMeasured:kept.hasStepCenter];
		return;
	}

	[LDrawStepPartListPolicy performWithCachedLookups:^{
		LDrawStepPartListPresentation *measured = nil;

		measured = [self presentationForHost:[self hostState]];

		[self centerPageOnPresentation:measured keepingItOnScreen:NO];

		if (key != nil) {
			Point3				 center	= [self.pageAnchor pageCenterForModel:model];
			LDrawStepKeptCenter	*made	= nil;

			made = [[LDrawStepKeptCenter alloc] initWithPageCenter:center
			                                         hasStepCenter:measured.hasStepCenter
			                                          placementKey:measured.placementKey ?: @""];

			[cache setCenter:made forKey:key];
		}
	}];

}//end centerPageOnStep


//========== centerPageOnPresentation:keepingItOnScreen: =======================
///
/// @abstract	Keeps the model point that belongs at the middle of the page for
///				the step a presentation shows. With nothing to measure that is
///				the anchor.
///
/// @discussion	Keeping the page on screen scrolls it back to where it was, so
///				the model moves on the page instead. A page that had no place
///				yet is left where the centering puts it.
///
//==============================================================================
- (void) centerPageOnPresentation:(LDrawStepPartListPresentation *)presentation
				keepingItOnScreen:(BOOL)keepsOnScreen
{
	LDrawModel					*model		= self.model;
	id<LDrawStepOverlayCamera>	 camera		= self.camera;
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	BOOL						 isHeld		= keepsOnScreen && [pageAnchor hasPageCenterForModel:model];
	CGPoint						 heldPoint	= CGPointZero;
	Point3						 anchor		= [pageAnchor anchorForModel:model];
	Point3						 center		= anchor;

	if (isHeld) {
		heldPoint = [camera viewPointForModelPoint:[pageAnchor pageCenterForModel:model]];
	}

	if (presentation.hasStepCenter) {
		Point2 middle = presentation.stepCenterInView;

		center = [camera modelPointForViewPoint:CGPointMake(middle.x, middle.y) depthReferencePoint:anchor];
	}

	[pageAnchor setPageCenter:center forModel:model];

	// The assembly's box is kept from the middle of the page, which has just
	// moved.
	if (presentation.hasStepCenter && pageAnchor.hasAssemblyRect) {
		double	scale	= presentation.pointsPerPageInch;
		Box2	rect	= [pageAnchor assemblyRectAroundPageCenter:V2BoxMid(presentation.pageRect)
												 pointsPerPageInch:scale];

		[pageAnchor noteAssemblyRect:rect aroundPageCenter:presentation.stepCenterInView pointsPerPageInch:scale];
	}

	[self noteCenteredStepWithPlacementKey:presentation.placementKey isMeasured:presentation.hasStepCenter];

	if (isHeld) {
		[camera scrollModelPoint:center toViewPoint:heldPoint];
	}

}//end centerPageOnPresentation:keepingItOnScreen:


//========== noteCenteredStepWithPlacementKey:isMeasured: ======================
///
/// @abstract	Notes that the page was just centered on the visible step, and
///				what that centering went by.
///
//==============================================================================
- (void) noteCenteredStepWithPlacementKey:(nullable NSString *)placementKey isMeasured:(BOOL)isMeasured
{
	self->centeredStep			= [self.model visibleStep];
	self->centeredPlacementKey	= [placementKey copy];
	self->hasMeasuredCenter		= isMeasured;

	// Where the page is drawn is noted again once the camera has settled.
	self->hasPageMiddle = NO;

}//end noteCenteredStepWithPlacementKey:isMeasured:


//========== stepKey ===========================================================
///
/// @abstract	What the layout cache knows the visible step by: its model's
///				name and its place in the model. Nil for a model with no name,
///				or with no layout cache.
///
//==============================================================================
- (nullable NSString *) stepKey
{
	LDrawModel	*model	= self.model;
	NSString	*name	= nil;

	if (self.layoutCache == nil || [model isKindOfClass:[LDrawMPDModel class]] == NO) {
		return nil;
	}

	name = [(LDrawMPDModel *)model modelName];

	if (name.length == 0) {
		return nil;
	}

	NSUInteger index = [[model steps] indexOfObjectIdenticalTo:[model visibleStep]];

	return [NSString stringWithFormat:@"%@\n%lu", name, (unsigned long)index];

}//end stepKey


//========== centerKey =========================================================
///
/// @abstract	What the layout cache keeps the page's place by: the step, and
///				the view as the camera draws it now. Nil when nothing is kept.
///
/// @discussion	The scroll is told by where the anchor is drawn. A drag in
///				progress is not kept, since it moves the page.
///
//==============================================================================
- (nullable NSString *) centerKey
{
	LDrawModel					*model		= self.model;
	id<LDrawStepOverlayCamera>	 camera		= self.camera;
	NSString					*stepKey	= [self stepKey];

	if (stepKey == nil || self.hasSizePreview || self.hasCalloutPreview || self.hasListPreview) {
		return nil;
	}

	Tuple3	angle	= [camera viewingAngle];
	Size2	size	= self.viewSize;
	CGPoint	anchor	= [camera viewPointForModelPoint:[self.pageAnchor anchorForModel:model]];

	double	zoom	= [camera zoomPercentage];

	return [NSString stringWithFormat:@"%@\n%.4f %.4f %.4f %.4f %.1f %.1f %.1f %.1f", stepKey,
			angle.x, angle.y, angle.z, zoom, size.width, size.height, anchor.x, anchor.y];

}//end centerKey


// MARK: - FOLLOWING THE SUBMODELS -


//========== moveCalloutsWithSubmodelsInPresentation:aroundAssembly: ===========
///
/// @abstract	While the camera is turned away from the angle the step was
///				laid out at, moves each callout's box as far as its submodel
///				has moved on the page since, and off the arrows.
///
/// @discussion	At the angle of the layout the boxes are where the file puts
///				them, and where what each callout places is drawn is kept. A
///				callout that is new while the camera is turned, or has another
///				number of arrows, is kept as it is drawn then.
///
///				Boxes that are placed automatically are put beside the
///				assembly by themselves instead, at every angle.
///
///				A place is kept from the middle of the assembly's box. That
///				box stays on the page through a turn, and moves with the step
///				when the page is centered again.
///
//==============================================================================
- (void) moveCalloutsWithSubmodelsInPresentation:(LDrawStepPartListPresentation *)presentation
								  aroundAssembly:(Box2)assemblyRect
{
	NSArray<LDrawStepCalloutBox *>	*boxes	= presentation.calloutBoxes;
	double							 scale	= presentation.pointsPerPageInch;

	// With nothing to move, no move is under way either.
	if (self.camera == nil || presentation.isOnPage == NO || boxes.count == 0
		|| V2BoxWidth(assemblyRect) <= 0.0 || V2BoxHeight(assemblyRect) <= 0.0) {
		[self->calloutArrangement reset];
		return;
	}

	self->calloutArrangement.time = (self.clock != nil) ? self.clock() : [NSProcessInfo processInfo].systemUptime;

	BOOL						 isTurned		= [self isTurnedSinceLayout];
	Point2						 middle			= V2BoxMid(assemblyRect);
	NSMutableArray<NSData *>	*places			= [NSMutableArray array];
	NSMutableArray<NSData *>	*laidOutPlaces	= [NSMutableArray array];

	// Where the view's corner is as the kept places are measured: from the
	// assembly's middle, in page inches.
	Point2 inViewOrigin = V2Make(-middle.x / scale, -middle.y / scale);

	// Kept for boxes that are placed automatically too, so they are there
	// when the file places the boxes again in a turned view.
	for (LDrawStepCalloutBox *box in boxes) {
		LPubCallout	*key	= box.callout.beginDirective;
		NSData		*drawn	= [self drawnPlacesOfBox:box];
		NSData		*kept	= isTurned ? [self->submodelPlaces objectForKey:key] : nil;

		if (kept.length != drawn.length) {
			kept = MovedPlaces(drawn, middle, 1.0 / scale);

			[self->submodelPlaces setObject:kept forKey:key];
		}

		[places addObject:drawn];
		[laidOutPlaces addObject:MovedPlaces(kept, inViewOrigin, scale)];
	}

	// Where the file puts the boxes is not read: they go beside the assembly
	// as the camera draws it now, at every angle.
	if ([LDrawStepPartList placesCalloutsAutomatically]) {
		[presentation placeCalloutBoxesAroundAssembly:[self assemblyRect]
											   places:places
										  arrangement:self->calloutArrangement];
	}
	else if (isTurned) {
		[presentation moveCalloutBoxesFrom:laidOutPlaces to:places arrangement:self->calloutArrangement];
	}
	else {
		[presentation restCalloutBoxesWithArrangement:self->calloutArrangement];
	}

}//end moveCalloutsWithSubmodelsInPresentation:aroundAssembly:


//========== drawnPlacesOfBox: =================================================
///
/// @abstract	Where the camera draws what a callout places, as Box2 values:
///				a box with no size at the middle of its placements, then the
///				box around each placement an arrow goes to.
///
/// @discussion	A placement that cannot be measured is a box with no size at
///				its middle.
///
//==============================================================================
- (NSData *) drawnPlacesOfBox:(LDrawStepCalloutBox *)box
{
	id<LDrawStepOverlayCamera>	 camera	= self.camera;
	NSMutableData				*places	= [NSMutableData data];
	CGPoint						 middle	= [camera viewPointForModelPoint:box.placementsMiddle];
	Box2						 place	= V2MakeBox(middle.x, middle.y, 0.0, 0.0);

	[places appendBytes:&place length:sizeof(Box2)];

	for (NSUInteger index = 0; index < box.tipCount; index++) {
		NSData *outline = [box tipOutlinePointsAtIndex:index];

		if (outline.length > 0) {
			CGRect rect = [camera viewRectForModelPoints:outline];

			place = LDrawStepBoxFromRect(rect);
		}
		else {
			CGPoint tip = [camera viewPointForModelPoint:[box tipModelPointAtIndex:index]];

			place = V2MakeBox(tip.x, tip.y, 0.0, 0.0);
		}

		[places appendBytes:&place length:sizeof(Box2)];
	}

	return places;

}//end drawnPlacesOfBox:


// MARK: - ARROWS -


//========== updateCalloutArrows ===============================================
///
/// @abstract	Works out each callout's arrows: from the box toward the middle
///				of each called-out placement, as far as the placement's edge,
///				as the camera draws it.
///
//==============================================================================
- (void) updateCalloutArrows
{
	NSMutableArray<NSData *>	*arrowsByBox	= [NSMutableArray array];
	id<LDrawStepOverlayCamera>	 camera			= self.camera;

	if (camera == nil) {
		self.calloutArrows = @[];
		return;
	}

	for (LDrawStepCalloutBox *box in self.presentation.calloutBoxes) {
		NSMutableData				*middles	= [NSMutableData data];
		NSMutableArray<NSData *>	*outlines	= [NSMutableArray array];

		for (NSUInteger index = 0; index < box.tipCount; index++) {
			CGPoint	point	= [camera viewPointForModelPoint:[box tipModelPointAtIndex:index]];
			Point2	middle	= V2Make(point.x, point.y);

			[middles appendBytes:&middle length:sizeof(Point2)];
			[outlines addObject:[camera viewPointsForModelPoints:[box tipOutlinePointsAtIndex:index]]];
		}
		[arrowsByBox addObject:[box arrowsToMiddles:middles outlines:outlines]];
	}

	self.calloutArrows = arrowsByBox;

}//end updateCalloutArrows


// MARK: - WHAT THE VIEW MEASURES -


//========== hostState =========================================================
///
/// @abstract	What only the view can tell the layout: its size, the scale the
///				model is drawn at beside the anchor, where the page's middle
///				and the assembly land, and any drag.
///
//==============================================================================
- (LDrawStepPartListHostState) hostState
{
	LDrawStepPartListHostState	 host	= {0};
	LDrawModel					*model	= self.model;
	id<LDrawStepOverlayCamera>	 camera	= self.camera;

	host.viewSize		= self.viewSize;
	host.hasPreview		= self.hasSizePreview;
	host.previewAxis	= self.previewAxis;
	host.previewInches	= self.previewInches;

	host.hasCalloutPreview		= self.hasCalloutPreview;
	host.calloutPreviewBox		= self.calloutPreviewBox;
	host.calloutPreviewPoint	= self.calloutPreviewPoint;

	host.hasListPreview			= self.hasListPreview;
	host.listPreviewOrigin		= self.listPreviewOrigin;

	// Measuring projects through the camera, so only when there is a page.
	if ([LDrawStepPartListPolicy drawsPageInModel:model] && camera != nil) {
		Point3	pageCenter	= [self.pageAnchor pageCenterForModel:model];
		CGPoint	viewPoint	= [camera viewPointForModelPoint:pageCenter];

		host.assemblyScale		= self.isArranging ? [self pageHoldingAssemblyScale] : [self assemblyScale];
		host.pageCenterInView	= V2Make(viewPoint.x, viewPoint.y);
		host.assemblyRect		= [self assemblyRectForHost:host];
	}

	return host;

}//end hostState


//========== assemblyScale =====================================================
///
/// @abstract	Points per LDU the page is sized from: the scale the model is
///				drawn at beside the anchor.
///
/// @discussion	In perspective that differs from the zoom by how deep the
///				anchor is. It is measured at the angle each step is laid out at
///				and kept as a ratio, so a turn does not resize the page.
///
//==============================================================================
- (double) assemblyScale
{
	id<LDrawStepOverlayCamera>	camera	= self.camera;
	double						ratio	= [self.pageAnchor drawnScaleRatioOfModel:self.model inView:camera];

	return [camera zoomPercentage] / 100.0 * ratio;

}//end assemblyScale


//========== assemblyRect ======================================================
///
/// @abstract	The box around the step's assembly as the camera draws it.
///
/// @discussion	The points it is measured by are kept until the file or the
///				step changes, so a pan or a zoom only projects them again.
///				The layout cache keeps them for each step.
///
//==============================================================================
- (Box2) assemblyRect
{
	LDrawModel	*model	= self.model;
	LDrawStep	*step	= [model visibleStep];

	if (self->assemblyOutline == nil || self->assemblyOutlineStep != step) {
		NSString	*key		= [self stepKey];
		NSData		*outline	= (key != nil) ? [self.layoutCache outlineForKey:key] : nil;

		if (outline == nil) {
			outline = [LDrawStepPartListPolicy assemblyOutlinePointsInModel:model] ?: [NSData data];

			if (key != nil) {
				[self.layoutCache setOutline:outline forKey:key];
			}
		}

		self->assemblyOutline		= outline;
		self->assemblyOutlineStep	= step;
	}

	CGRect rect = [self.camera viewRectForModelPoints:self->assemblyOutline];

	return LDrawStepBoxFromRect(rect);

}//end assemblyRect


//========== assemblyRectForHost: ==============================================
///
/// @abstract	The box around the step's assembly that the page is laid out
///				against.
///
/// @discussion	While the camera is at the angle the step was laid out at, the
///				box is measured as the camera draws it, and its place on the
///				page is kept. Once the camera is turned the kept box is used,
///				so what the file places against the assembly has the same
///				place to start from while the model turns.
///
//==============================================================================
- (Box2) assemblyRectForHost:(LDrawStepPartListHostState)host
{
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	Point2						 middle		= host.pageCenterInView;
	double						 scale		= 0.0;

	scale = [LDrawStepPartListPolicy pointsPerPageInchForAssemblyScale:host.assemblyScale inModel:self.model];

	if ([self isTurnedSinceLayout] && pageAnchor.hasAssemblyRect) {
		return [pageAnchor assemblyRectAroundPageCenter:middle pointsPerPageInch:scale];
	}

	Box2 measured = [self assemblyRect];

	[pageAnchor noteAssemblyRect:measured aroundPageCenter:middle pointsPerPageInch:scale];

	return measured;

}//end assemblyRectForHost:

@end
