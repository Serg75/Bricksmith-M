//==============================================================================
//
//  File:       LDrawStepPartListPresentation.m
//  Package:    LDrawFeatures
//
//  Purpose:    Works out what the host draws for the visible step.
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListPresentation.h>

#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LPubModelScale.h>
#import <LDrawCore/LPubPlacement.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>

#import "LDrawStepCalloutContent.h"


/// Below this size there is nothing worth drawing, and a camera cannot make a
/// projection.
static const double MINIMUM_CONTENT_SIDE = 8.0;


@implementation LDrawStepPartListPresentation
{
	/// The sizes each axis inherits, indexed by LPubPliAxis.
	double	inheritedInches[2];
}

//---------- presentationForModel:host: ------------------------------[static]--
///
/// @abstract	Collects, packs and places the list for the model's visible
/// 			step.
///
//------------------------------------------------------------------------------
+ (instancetype) presentationForModel:(nullable LDrawModel *)model
								 host:(LDrawStepPartListHostState)host
{
	return [[self alloc] initWithModel:model host:host];

}//end presentationForModel:host:


//========== initWithModel:host: ===============================================
///
/// @abstract	Does the work, in the order it has to happen.
///
//==============================================================================
- (instancetype) initWithModel:(nullable LDrawModel *)model host:(LDrawStepPartListHostState)host
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	self->_pageRect		= ZeroBox2;
	self->_frameRect	= ZeroBox2;
	self->_contentRect	= ZeroBox2;
	self->_chrome		= [LDrawStepPartListPolicy defaultChrome];
	self->_calloutBoxes	= @[];
	self->_placementKey	= @"";

	if (model == nil) {
		return self;
	}

	[self placePageForModel:model host:host];

	// Everything is packed against whatever it sits in: the page when there is
	// one, else the view. So a CONSTRAIN is measured on the page.
	Size2 hostSize = self->_isOnPage ? self->_pageRect.size : host.viewSize;

	self->_hostSize = hostSize;

	if (hostSize.width <= 0.0 || hostSize.height <= 0.0) {
		return self;
	}

	LDrawStepPartListMetrics metrics = [LDrawStepPartListLayout defaultMetrics];

	if (self->_isOnPage) {
		metrics = [LDrawStepPartListPolicy metrics:metrics
						 scaledToPointsPerPageInch:self->_pointsPerPageInch];

		// The packer keeps the room and the view draws the text, so both are
		// scaled by the same ratio.
		self->_chrome = [LDrawStepPartListPolicy chrome:self->_chrome
							  scaledToPointsPerPageInch:self->_pointsPerPageInch];
	}

	// The list first: the callouts go under its frame.
	[self packListForModel:model host:host metrics:metrics];
	[self placeCalloutsForModel:model host:host metrics:metrics];

	// After the callouts, which are part of what is centered, and before a
	// drag is shown, which is not.
	[self findStepCenterForModel:model host:host];

	if (host.hasCalloutPreview && host.calloutPreviewBox < self->_calloutBoxes.count) {
		[self->_calloutBoxes[host.calloutPreviewBox] previewOrigin:host.calloutPreviewPoint];
	}

	return self;

}//end initWithModel:host:


//========== packListForModel:host:metrics: ====================================
///
/// @abstract	Collects the step's parts, packs them and places the frame.
///
/// @discussion	`metrics` are already scaled to the page when there is one.
///
//==============================================================================
- (void) packListForModel:(LDrawModel *)model
					 host:(LDrawStepPartListHostState)host
				  metrics:(LDrawStepPartListMetrics)metrics
{
	Size2 hostSize = self->_hostSize;

	// A step that hides its list still shows its page.
	NSArray *entries = [LDrawStepPartList isShownForVisibleStepOfModel:model]
					 ? [LDrawStepPartList entriesForVisibleStepOfModel:model]
					 : @[];

	if (entries.count == 0) {
		return;
	}

	if (self->_isOnPage) {
		metrics.baseScale = [LDrawStepPartListPolicy partListScaleForAssemblyScale:host.assemblyScale
																		   inModel:model];
	}

	// After scaling, so the budget allows for the padding the frame is drawn
	// with.
	metrics = [LDrawStepPartListPolicy metrics:metrics
							   fittingHostSize:hostSize
							 pointsPerPageInch:self->_pointsPerPageInch];

	LDrawStepPartListConstraint	constraint		= [self constraintForModel:model
																	  host:host
																  hostSize:hostSize
															 pointsPerInch:metrics.pointsPerInch];
	Matrix4						viewTransform	= [LDrawStepPartListPolicy viewTransformForVisibleStepOfModel:model];

	self->_layout		= [LDrawStepPartListLayout layoutForEntries:entries
														 constraint:constraint
													  viewTransform:viewTransform
															metrics:metrics];

	// The document's file, so a submodel draws its real contents.
	self->_iconModel	= [LDrawStepPartListModelBuilder modelForLayout:self->_layout
														  viewTransform:viewTransform
													  submodelsFromFile:[model enclosingFile]];

	self->_iconZoomPercentage	= [LDrawStepPartListModelBuilder zoomPercentageForLayout:self->_layout];
	self->_iconCenter			= [LDrawStepPartListModelBuilder centerPointForLayout:self->_layout];

	[self placeFrameWithMetrics:metrics];
	[self updatePinsForModel:model host:host];

}//end packListForModel:host:metrics:


//========== placeCalloutsForModel:host:metrics: ===============================
///
/// @abstract	Packs a box for each callout of the step, under the list's
/// 			frame.
///
/// @discussion	On the page a callout's assembly is drawn at life size, which is
/// 			LPub3D's scale for it when the file sets none. The parts in a
/// 			box are drawn at the list's scale.
///
//==============================================================================
- (void) placeCalloutsForModel:(LDrawModel *)model
						  host:(LDrawStepPartListHostState)host
					   metrics:(LDrawStepPartListMetrics)metrics
{
	NSArray<LDrawStepCallout *> *callouts = [LDrawStepCallout calloutsForVisibleStepOfModel:model];

	if (callouts.count == 0) {
		return;
	}

	LDrawStepCalloutBoxOptions options;

	options.metrics				= metrics;
	options.assemblyScale		= metrics.baseScale;
	options.hostRect			= V2MakeBox(0.0, 0.0, self->_hostSize.width, self->_hostSize.height);
	options.listFrame			= self->_frameRect;
	options.pointsPerPageInch	= self->_pointsPerPageInch;
	options.listViewTransform	= [LDrawStepPartListPolicy viewTransformForVisibleStepOfModel:model];
	options.showsLists			= [LDrawStepPartList isShownForVisibleStepOfModel:model];

	options.assemblyRect		= ZeroBox2;

	if (self->_isOnPage) {
		options.hostRect			= self->_pageRect;
		options.assemblyRect		= host.assemblyRect;
		options.assemblyScale		= self->_pointsPerPageInch * [LPubModelScale inchesPerLDU];
		options.metrics.baseScale	= [LDrawStepPartListPolicy partListScaleForAssemblyScale:host.assemblyScale
																					 inModel:model];
	}

	self->_calloutBoxes = [LDrawStepCalloutBox boxesForCallouts:callouts inModel:model options:options];

}//end placeCalloutsForModel:host:metrics:


//========== findStepCenterForModel:host: ======================================
///
/// @abstract	Works out where the middle of the page belongs for this step,
/// 			and notes the lines that say so.
///
/// @discussion	It also tells each box placed against the assembly how far the
/// 			assembly will move when that box is dragged. A dragged box is
/// 			no longer centered with the assembly, so the step is centered
/// 			again without it.
///
//==============================================================================
- (void) findStepCenterForModel:(LDrawModel *)model host:(LDrawStepPartListHostState)host
{
	if (self->_isOnPage == NO) {
		return;
	}

	LPubPlacement	*placement	= [LDrawStepPartListPolicy assemblyPlacementForVisibleStepOfModel:model];
	NSMutableString	*key		= [NSMutableString stringWithString:placement.lPubCommandString ?: @""];
	Box2			 assembly	= host.assemblyRect;

	for (LDrawStepCalloutBox *box in self->_calloutBoxes) {
		Box2 frame = box.frameRect;

		[key appendFormat:@"\n%@", box.callout.placement.lPubCommandString ?: @""];

		// The way the steps run and where they are divided change the size
		// of the box, as a PLACEMENT line changes its place.
		[key appendString:box.callout.isVertical ? @"v" : @"h"];

		for (LDrawStepCalloutStep *step in box.steps) {
			[key appendString:step.hasDividerBefore ? @"|" : @"."];
		}

		// Any other line that resizes a centered box moves the step's center
		// too. In page inches, so the key is the same at every zoom.
		if (box.isCenteredWithAssembly) {
			[key appendFormat:@" %.2fx%.2f",
			 frame.size.width / self->_pointsPerPageInch, frame.size.height / self->_pointsPerPageInch];
		}
	}

	self->_placementKey = key;

	if (V2BoxWidth(assembly) <= 0.0 || V2BoxHeight(assembly) <= 0.0) {
		return;
	}

	self->_hasStepCenter	= YES;
	self->_stepCenterInView	= [self stepCenterForAssembly:assembly placement:placement leavingOut:nil];

	// A box that is dragged is left out of what is centered, and the host
	// then centers the step again with the page where it is.
	Point2 pageMiddle = V2BoxMid(self->_pageRect);

	for (LDrawStepCalloutBox *box in self->_calloutBoxes) {
		if (box.isPlacedAgainstAssembly) {
			Point2 center = [self stepCenterForAssembly:assembly placement:placement leavingOut:box];

			box.assemblyShiftAfterDrag = V2Sub(pageMiddle, center);
		}
	}

}//end findStepCenterForModel:host:


//========== stepCenterForAssembly:placement:leavingOut: =======================
///
/// @abstract	Where the middle of the page belongs for an assembly and the
/// 			boxes centered with it, but for one box. Nil leaves none out.
///
/// @discussion	The box around the assembly and those callouts goes where the
/// 			ASSEM PLACEMENT line says, moved by the line's offset as a
/// 			share of the page. A line that places the assembly against
/// 			anything but the page is read as none.
///
//==============================================================================
- (Point2) stepCenterForAssembly:(Box2)assembly
					   placement:(nullable LPubPlacement *)placement
					  leavingOut:(nullable LDrawStepCalloutBox *)leftOut
{
	Point2 minimum = assembly.origin;
	Point2 maximum = V2Make(V2BoxMaxX(assembly), V2BoxMaxY(assembly));

	for (LDrawStepCalloutBox *box in self->_calloutBoxes) {
		Box2 frame = box.frameRect;

		if (box.isCenteredWithAssembly && box != leftOut) {
			minimum = V2Make(MIN(minimum.x, V2BoxMinX(frame)), MIN(minimum.y, V2BoxMinY(frame)));
			maximum = V2Make(MAX(maximum.x, V2BoxMaxX(frame)), MAX(maximum.y, V2BoxMaxY(frame)));
		}
	}

	LPubPlacementPosition	position	= LPubPlacementPositionCenter;
	Point2					offset		= ZeroPoint2;

	if (placement != nil && placement.isInside && [placement.relativeTo isEqualToString:LPUB_PAGE]) {
		position	= placement.position;
		offset		= placement.offset;
	}

	Size2	pageSize	= self->_pageRect.size;
	double	margin		= [LDrawStepPartListPolicy frameInsetForPointsPerPageInch:self->_pointsPerPageInch];
	Size2	together	= V2MakeSize(maximum.x - minimum.x, maximum.y - minimum.y);
	Point2	onPage		= [LDrawStepCalloutBox originForSize:together
													position:position
											   justification:LPubPlacementPositionCenter
													isInside:YES
													  anchor:V2MakeBox(0.0, 0.0, pageSize.width, pageSize.height)
													  margin:V2MakeSize(margin, margin)];

	onPage.x += pageSize.width * offset.x;
	onPage.y += pageSize.height * offset.y;

	// The page's corner is that far up and left of the box's corner.
	return V2Make(minimum.x - onPage.x + pageSize.width / 2.0,
				  minimum.y - onPage.y + pageSize.height / 2.0);

}//end stepCenterForAssembly:placement:leavingOut:


//========== placePageForModel:host: ===========================================
///
/// @abstract	Puts the page around the point the host keeps it centered on,
/// 			when the document is drawn on one.
///
//==============================================================================
- (void) placePageForModel:(LDrawModel *)model host:(LDrawStepPartListHostState)host
{
	if ([LDrawStepPartListPolicy drawsPageInModel:model] == NO || host.assemblyScale <= 0.0) {
		return;
	}

	Box2	page					= [LDrawStepPartListPolicy pageRectCenteredOn:host.pageCenterInView
																	assemblyScale:host.assemblyScale
																		  inModel:model];
	double	pointsPerPageInch	=
		[LDrawStepPartListPolicy pointsPerPageInchForAssemblyScale:host.assemblyScale inModel:model];

	if (V2BoxWidth(page) <= 0.0 || V2BoxHeight(page) <= 0.0 || pointsPerPageInch <= 0.0) {
		return;
	}

	self->_isOnPage	= YES;
	self->_pageRect	= page;
	self->_pointsPerPageInch	= pointsPerPageInch;

}//end placePageForModel:host:


//========== placeFrameWithMetrics: ============================================
///
/// @abstract	Puts the frame in the host's corner, and the icon area inside its
/// 			padding.
///
/// @discussion	On the page the frame goes in the page's corner, so it stays put
/// 			on the paper as the view pans.
///
//==============================================================================
- (void) placeFrameWithMetrics:(LDrawStepPartListMetrics)metrics
{
	if (self->_layout.placements.count == 0) {
		return;
	}

	Point2	hostOrigin	= self->_isOnPage ? self->_pageRect.origin : ZeroPoint2;
	Box2	frame		= [LDrawStepPartListPolicy frameRectForFrameSize:self->_layout.frameSize
															  inHostSize:self->_hostSize
													   pointsPerPageInch:self->_pointsPerPageInch];

	frame.origin = V2Add(frame.origin, hostOrigin);

	Box2 content = V2BoxInset(frame, metrics.framePadding, metrics.framePadding);

	// A very small view can leave the padding no room at all.
	if (V2BoxWidth(content) < MINIMUM_CONTENT_SIDE || V2BoxHeight(content) < MINIMUM_CONTENT_SIDE) {
		return;
	}

	self->_frameRect	= frame;
	self->_contentRect	= content;

}//end placeFrameWithMetrics:


//========== constraintForModel:host:hostSize:pointsPerInch: ===================
///
/// @abstract	The constraint to pack with, narrowed to fit the host.
///
/// @discussion	On the page a drag wins, then the CONSTRAIN in force for the
/// 			step. Off the page the document's lines are ignored: they are
/// 			page inches, and there is no page to measure them on.
///
//==============================================================================
- (LDrawStepPartListConstraint) constraintForModel:(LDrawModel *)model
											  host:(LDrawStepPartListHostState)host
										  hostSize:(Size2)hostSize
									 pointsPerInch:(double)pointsPerInch
{
	LDrawStepPartListConstraint constraint;

	if (self->_isOnPage == NO) {
		constraint = [LDrawStepPartListPolicy viewportConstraintForHostSize:hostSize
															  pointsPerInch:pointsPerInch];
	}
	else if (host.hasPreview) {
		// Already clamped to what can be drawn.
		constraint			= [LDrawStepPartListLayout defaultConstraint];
		constraint.mode		= LPubPliConstrainModeForAxis(host.previewAxis);
		constraint.inches	= (float)host.previewInches;
	}
	else {
		constraint = [LDrawStepPartListPolicy constraintForVisibleStepOfModel:model];
	}

	return [LDrawStepPartListPolicy constraint:constraint
							 clampedToHostSize:hostSize
								 pointsPerInch:pointsPerInch
							 pointsPerPageInch:self->_pointsPerPageInch];

}//end constraintForModel:host:hostSize:pointsPerInch:


//========== updatePinsForModel:host: ==========================================
///
/// @abstract	A pin marks a size the step sets itself, and clicking it clears
/// 			that. Only on the page, where the frame can be resized.
///
//==============================================================================
- (void) updatePinsForModel:(LDrawModel *)model host:(LDrawStepPartListHostState)host
{
	if (self->_isOnPage == NO) {
		return;
	}

	LDrawStep *step = [model visibleStep];

	self->_widthPinned	= [LDrawStepPartListPolicy isAxis:LPubPliAxisWidth pinnedInStep:step];
	self->_heightPinned	= [LDrawStepPartListPolicy isAxis:LPubPliAxisHeight pinnedInStep:step];

	self->inheritedInches[LPubPliAxisWidth]		= [LDrawStepPartListPolicy inheritedInchesForAxis:LPubPliAxisWidth
																						  inModel:model];
	self->inheritedInches[LPubPliAxisHeight]	= [LDrawStepPartListPolicy inheritedInchesForAxis:LPubPliAxisHeight
																						  inModel:model];

	// During a drag the pins show what letting go would leave.
	if (host.hasPreview) {
		LDrawStepPartListEdit	*edit	= [LDrawStepPartListEdit editForDraggingAxis:host.previewAxis
																			toInches:host.previewInches
																			 inModel:model];
		BOOL					 pinned	= (edit.resetsAxis == NO);

		self->_widthPinned	= pinned && (host.previewAxis == LPubPliAxisWidth);
		self->_heightPinned	= pinned && (host.previewAxis == LPubPliAxisHeight);
	}

}//end updatePinsForModel:host:


//========== entryAtPoint: =====================================================
///
/// @abstract	The row of the list whose cell is under a point of the view.
///
/// @discussion	Cells are measured from the corner of the icon area.
///
//==============================================================================
- (nullable LDrawStepPartListEntry *) entryAtPoint:(Point2)point
{
	Point2 inContent = V2Sub(point, self->_contentRect.origin);

	for (LDrawStepPartListPlacement *placement in self->_layout.placements) {
		if (V2BoxContains(placement.cellFrame, inContent)) {
			return placement.entry;
		}
	}

	return nil;

}//end entryAtPoint:


//========== calloutBoxAtPoint: ================================================
- (nullable LDrawStepCalloutBox *) calloutBoxAtPoint:(Point2)point
{
	return [LDrawStepCalloutBox boxAtPoint:point amongBoxes:self->_calloutBoxes];

}//end calloutBoxAtPoint:


//========== inheritedInchesForAxis: ===========================================
- (double) inheritedInchesForAxis:(LPubPliAxis)axis
{
	return self->inheritedInches[axis];

}//end inheritedInchesForAxis:

@end
