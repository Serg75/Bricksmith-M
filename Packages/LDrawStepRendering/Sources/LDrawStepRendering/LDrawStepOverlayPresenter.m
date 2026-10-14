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
#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutArrangement.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>

#import "LDrawStepLayoutCacheEntries.h"


/// How far two viewing angles may differ, in degrees, and still be one view.
static const double VIEWING_ANGLE_TOLERANCE = 0.0001;


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
		self->submodelPlaces	= [NSMapTable mapTableWithKeyOptions:weakObjects
														valueOptions:NSPointerFunctionsStrongMemory];

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

	[self->submodelPlaces removeAllObjects];
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
	// One walk of the file for all the lookups of this layout.
	[LDrawStepPartListPolicy performWithCachedLookups:^{
		LDrawModel						*model			= self.model;
		LDrawStepPartListHostState		 host			= {0};
		LDrawStepPartListPresentation	*presentation	= nil;

		[self keepPageInPlaceThroughTurn];

		// Another step is measured afresh, as the camera sees it now.
		if ([self isLaidOutForVisibleStep] == NO) {
			[self startLayout];
		}

		host			= [self hostState];
		presentation	= [LDrawStepPartListPresentation presentationForModel:model host:host];

		// Centering moves the camera, so the step is laid out again for it.
		if ([self needsPageCenterForPresentation:presentation]) {
			[self centerPageOnPresentation:presentation keepingItOnScreen:YES];

			host			= [self hostState];
			presentation	= [LDrawStepPartListPresentation presentationForModel:model host:host];
		}

		[self moveCalloutsWithSubmodelsInPresentation:presentation aroundAssembly:host.assemblyRect];

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
	[self.layoutCache removeAll];

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
	[self.pageAnchor forgetDrawnScale];
	[self->submodelPlaces removeAllObjects];
	[self->calloutArrangement reset];

	self->layoutViewingAngle = [self.camera viewingAngle];

}//end startLayout


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

		measured = [LDrawStepPartListPresentation presentationForModel:model host:[self hostState]];

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

	if (stepKey == nil || self.hasSizePreview || self.hasCalloutPreview) {
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

			place = V2MakeBox(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect), CGRectGetHeight(rect));
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
