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
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>


/// How far two viewing angles may differ, in degrees, and still be one view.
static const double VIEWING_ANGLE_TOLERANCE = 0.0001;


//========== IsSameViewingAngle() ==============================================
static BOOL IsSameViewingAngle(Tuple3 first, Tuple3 second)
{
	return fabs(first.x - second.x) < VIEWING_ANGLE_TOLERANCE
		&& fabs(first.y - second.y) < VIEWING_ANGLE_TOLERANCE
		&& fabs(first.z - second.z) < VIEWING_ANGLE_TOLERANCE;

}//end IsSameViewingAngle


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

	/// The step the page was last centered on, and the PLACEMENT lines it had
	/// then. The page is centered again when either changes.
	__weak LDrawStep	*centeredStep;
	NSString			*centeredPlacementKey;

	/// Whether that centering had an assembly to measure. A step centered
	/// with nothing to measure is centered again once there is.
	BOOL				 hasMeasuredCenter;

	/// The viewing angle the step was laid out at. While the camera is turned
	/// away from it, the callouts keep their place on the page.
	Tuple3				 layoutViewingAngle;

	/// Where the middle of the page was last drawn, and the viewing angle
	/// then. A turn keeps the page there.
	BOOL				 hasPageMiddle;
	CGPoint				 pageMiddle;
	Tuple3				 pageViewingAngle;
}


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_pageAnchor		= [[LDrawStepPartListPageAnchor alloc] init];
		self->_calloutArrows	= @[];
	}
	return self;

}//end init


//========== reset =============================================================
- (void) reset
{
	self.presentation		= nil;
	self.calloutArrows		= @[];
	self->hasPageMiddle		= NO;

}//end reset


// MARK: - LAYING OUT -


//========== reload ============================================================
- (void) reload
{
	// One walk of the file for all the lookups of this layout.
	[LDrawStepPartListPolicy performWithCachedLookups:^{
		LDrawModel						*model			= self.model;
		LDrawStepPartListPresentation	*presentation	= nil;

		[self keepPageInPlaceThroughTurn];

		// Another step is measured afresh, as the camera sees it now.
		if ([self isLaidOutForVisibleStep] == NO) {
			[self startLayout];
		}

		presentation = [LDrawStepPartListPresentation presentationForModel:model host:[self hostState]];

		// Centering moves the camera, so the step is laid out again for it.
		if ([self needsPageCenterForPresentation:presentation]) {
			[self centerPageOnPresentation:presentation keepingItOnScreen:YES];

			presentation = [LDrawStepPartListPresentation presentationForModel:model host:[self hostState]];
		}

		self.presentation = presentation;
	}];

	[self updateCalloutArrows];

}//end reload


//========== changeForCameraMove ===============================================
- (LDrawStepOverlayChange) changeForCameraMove
{
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

	// The parts the assembly is measured by may have changed.
	self->assemblyOutline = nil;

	BOOL isInModel = directive != nil
				  && [directive isKindOfClass:[LDrawColor class]] == NO
				  && [directive enclosingModel] == model;

	return isInModel ? LDrawStepOverlayChangeLayout
					 : (LDrawStepOverlayChangeLayout | LDrawStepOverlayChangePictures);

}//end changeForChangedObject:


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

	self->layoutViewingAngle = [self.camera viewingAngle];

}//end startLayout


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
/// @discussion	The step is laid out once just to measure it.
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

	[LDrawStepPartListPolicy performWithCachedLookups:^{
		LDrawStepPartListPresentation *measured = nil;

		measured = [LDrawStepPartListPresentation presentationForModel:model host:[self hostState]];

		[self centerPageOnPresentation:measured keepingItOnScreen:NO];
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

	self->centeredStep			= [model visibleStep];
	self->centeredPlacementKey	= [presentation.placementKey copy];
	self->hasMeasuredCenter		= presentation.hasStepCenter;

	// Where the page is drawn is noted again once the camera has settled.
	self->hasPageMiddle = NO;

	if (isHeld) {
		[camera scrollModelPoint:center toViewPoint:heldPoint];
	}

}//end centerPageOnPresentation:keepingItOnScreen:


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
///				model is drawn at, where the page's middle and the assembly
///				land, and any drag.
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

	// Measuring projects through the camera, so only when there is a page.
	if ([LDrawStepPartListPolicy drawsPageInModel:model] && camera != nil) {
		Point3	pageCenter	= [self.pageAnchor pageCenterForModel:model];
		CGPoint	viewPoint	= [camera viewPointForModelPoint:pageCenter];

		host.assemblyScale		= [self assemblyScale];
		host.pageCenterInView	= V2Make(viewPoint.x, viewPoint.y);
		host.assemblyRect		= [self assemblyRectForHost:host];
	}

	return host;

}//end hostState


//========== assemblyScale =====================================================
///
/// @abstract	Points per LDU the camera is drawing the model at.
///
/// @discussion	A perspective view draws a near part larger than the zoom alone
///				says, so the page is sized from the scale the model is drawn at
///				beside the anchor. The ratio between the two is measured once
///				and kept, or every step's rotation would resize the page.
///
//==============================================================================
- (double) assemblyScale
{
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	id<LDrawStepOverlayCamera>	 camera		= self.camera;
	double						 zoomScale	= [camera zoomPercentage] / 100.0;

	if (pageAnchor.needsDrawnScale) {
		Point3 anchor = [pageAnchor anchorForModel:self.model];

		[pageAnchor noteDrawnPointsPerLDU:[camera pointsPerLDUAtModelPoint:anchor] atZoomScale:zoomScale];
	}

	return [pageAnchor assemblyScaleForZoomScale:zoomScale];

}//end assemblyScale


//========== assemblyRect ======================================================
///
/// @abstract	The box around the step's assembly as the camera draws it.
///
/// @discussion	The points it is measured by are kept until the file or the
///				step changes, so a pan or a zoom only projects them again.
///
//==============================================================================
- (Box2) assemblyRect
{
	LDrawModel	*model	= self.model;
	LDrawStep	*step	= [model visibleStep];

	if (self->assemblyOutline == nil || self->assemblyOutlineStep != step) {
		self->assemblyOutline		= [LDrawStepPartListPolicy assemblyOutlinePointsInModel:model] ?: [NSData data];
		self->assemblyOutlineStep	= step;
	}

	CGRect rect = [self.camera viewRectForModelPoints:self->assemblyOutline];

	return V2MakeBox(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect), CGRectGetHeight(rect));

}//end assemblyRect


//========== assemblyRectForHost: ==============================================
///
/// @abstract	The box around the step's assembly that the page is laid out
///				against.
///
/// @discussion	While the camera is at the angle the step was laid out at, the
///				box is measured as the camera draws it, and its place on the
///				page is kept. Once the camera is turned the kept box is used,
///				so the callouts stay where they are while the model turns.
///
//==============================================================================
- (Box2) assemblyRectForHost:(LDrawStepPartListHostState)host
{
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	Point2						 middle		= host.pageCenterInView;
	Tuple3						 angle		= [self.camera viewingAngle];
	BOOL						 isTurned	= (IsSameViewingAngle(angle, self->layoutViewingAngle) == NO);
	double						 scale		= 0.0;

	scale = [LDrawStepPartListPolicy pointsPerPageInchForAssemblyScale:host.assemblyScale inModel:self.model];

	if (isTurned && pageAnchor.hasAssemblyRect) {
		return [pageAnchor assemblyRectAroundPageCenter:middle pointsPerPageInch:scale];
	}

	Box2 measured = [self assemblyRect];

	[pageAnchor noteAssemblyRect:measured aroundPageCenter:middle pointsPerPageInch:scale];

	return measured;

}//end assemblyRectForHost:

@end
