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

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LPubModelScale.h>
#import <LDrawCore/LPubPlacement.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepCalloutStyle.h>
#import <LDrawFeatures/LDrawStepPageNumbers.h>
#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>
#import <LDrawFeatures/LDrawStepPartListStyle.h>

#import "LDrawStepCalloutContent.h"
#import "LDrawStepCalloutFollower.h"
#import "LDrawStepPageNumberStyle.h"


/// Below this size there is nothing worth drawing, and a camera cannot make a
/// projection.
static const double MINIMUM_CONTENT_SIDE = 8.0;

/// How far the dashed line runs outside the step while it is arranged, how
/// big the handles on its corners are drawn, and how much further out a press
/// still takes one, in points.
static const double ARRANGE_FRAME_OUTSET	= 6.0;
static const double ARRANGE_HANDLE_SIDE		= 7.0;
static const double ARRANGE_HANDLE_REACH	= 3.0;


//========== MirroredPosition() ================================================
///
/// @abstract	The place on the other side of the page, left for right. LPub3D
/// 			puts the number of an even page there when the file asks.
///
//==============================================================================
static LPubPlacementPosition MirroredPosition(LPubPlacementPosition position)
{
	switch (position) {
		case LPubPlacementPositionTopLeft:		return LPubPlacementPositionTopRight;
		case LPubPlacementPositionTopRight:		return LPubPlacementPositionTopLeft;
		case LPubPlacementPositionLeft:			return LPubPlacementPositionRight;
		case LPubPlacementPositionRight:		return LPubPlacementPositionLeft;
		case LPubPlacementPositionBottomLeft:	return LPubPlacementPositionBottomRight;
		case LPubPlacementPositionBottomRight:	return LPubPlacementPositionBottomLeft;
		default:								return position;
	}

}//end MirroredPosition


//========== GrowBounds() ======================================================
///
/// @abstract	Widens the corners `minimum` and `maximum` to take in a box.
///
//==============================================================================
static void GrowBounds(Point2 *minimum, Point2 *maximum, Box2 box)
{
	*minimum = V2Make(MIN(minimum->x, V2BoxMinX(box)), MIN(minimum->y, V2BoxMinY(box)));
	*maximum = V2Make(MAX(maximum->x, V2BoxMaxX(box)), MAX(maximum->y, V2BoxMaxY(box)));

}//end GrowBounds


//========== PlacedShare() =====================================================
///
/// @abstract	Where a box placed at this position is held, as shares of its
/// 			size: 0 at its left or top, 1 at its right or bottom, and 0.5 in
/// 			its middle.
///
//==============================================================================
static Point2 PlacedShare(LPubPlacementPosition position)
{
	switch (position) {
		case LPubPlacementPositionTopLeft:		return V2Make(0.0, 0.0);
		case LPubPlacementPositionTop:			return V2Make(0.5, 0.0);
		case LPubPlacementPositionTopRight:		return V2Make(1.0, 0.0);
		case LPubPlacementPositionRight:		return V2Make(1.0, 0.5);
		case LPubPlacementPositionBottomRight:	return V2Make(1.0, 1.0);
		case LPubPlacementPositionBottom:		return V2Make(0.5, 1.0);
		case LPubPlacementPositionBottomLeft:	return V2Make(0.0, 1.0);
		case LPubPlacementPositionLeft:			return V2Make(0.0, 0.5);
		case LPubPlacementPositionCenter:		return V2Make(0.5, 0.5);
	}

	return V2Make(0.5, 0.5);

}//end PlacedShare


@implementation LDrawStepPartListPresentation
{
	/// The sizes each axis inherits, indexed by LPubPliAxis.
	double	inheritedInches[2];

	/// The document's own page, in points. The page is bigger when it follows
	/// the host's shape, with this one in its middle.
	Size2	filePageSize;

	/// How the file styles and places the list, and the metrics it is packed
	/// with then. Only on the page.
	LDrawStepPartListStyle		*listStyle;
	LDrawStepPartListMetrics	 styledMetrics;

	/// The step's CONSTRAIN in force, read once whether or not a drag is shown.
	LDrawStepPartListConstraint	 fileConstraint;

	/// Whether the list is placed against the assembly, which makes it part of
	/// what is centered on the page.
	BOOL						 listIsCenteredWithAssembly;

	/// Where the step's box is held as it grows, as shares of its size.
	Point2						 stepAnchorShare;

	/// The angle the list's icons and the callouts' lists are drawn at.
	Matrix4						 stepViewTransform;

	/// The file the icon model takes submodels from, when it is first asked
	/// for.
	__weak LDrawFile			*iconFile;
}

@synthesize iconModel = _iconModel;

//---------- presentationForModel:host: ------------------------------[static]--
///
/// @abstract	Collects, packs and places the list for the model's visible
/// 			step.
///
//------------------------------------------------------------------------------
+ (instancetype) presentationForModel:(nullable LDrawModel *)model
								 host:(LDrawStepPartListHostState)host
{
	return [[self alloc] initWithModel:model host:host pageNumbers:nil];

}//end presentationForModel:host:


//---------- presentationForModel:host:pageNumbers: ------------------[static]--
+ (instancetype) presentationForModel:(nullable LDrawModel *)model
								 host:(LDrawStepPartListHostState)host
						  pageNumbers:(nullable LDrawStepPageNumbers *)pageNumbers
{
	return [[self alloc] initWithModel:model host:host pageNumbers:pageNumbers];

}//end presentationForModel:host:pageNumbers:


//========== initWithModel:host:pageNumbers: ===================================
///
/// @abstract	Does the work, in the order it has to happen.
///
//==============================================================================
- (instancetype) initWithModel:(nullable LDrawModel *)model
						  host:(LDrawStepPartListHostState)host
				   pageNumbers:(nullable LDrawStepPageNumbers *)pageNumbers
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

	self->_calloutChrome	= self->_chrome;
	self->_pageNumberRect	= ZeroBox2;

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

	LDrawStepPartListMetrics metrics		= [LDrawStepPartListLayout defaultMetrics];
	LDrawStepPartListMetrics listMetrics	= metrics;

	if (self->_isOnPage) {
		metrics = [LDrawStepPartListPolicy metrics:metrics
						 scaledToPointsPerPageInch:self->_pointsPerPageInch];

		// The packer keeps the room and the view draws the text, so both are
		// scaled by the same ratio.
		self->_chrome = [LDrawStepPartListPolicy chrome:self->_chrome
							  scaledToPointsPerPageInch:self->_pointsPerPageInch];
		self->_calloutChrome = self->_chrome;

		listMetrics = [self applyStyleOfModel:model toMetrics:metrics];

		[self placePageNumberForModel:model pageNumbers:pageNumbers];
	}

	self->stepViewTransform = [LDrawStepPartListPolicy viewTransformForVisibleStepOfModel:model];

	// The list first: the callouts go under its frame. They keep the plain
	// metrics, since the file's PLI lines are not theirs.
	[self packListForModel:model host:host metrics:listMetrics];
	[self placeCalloutsForModel:model host:host metrics:metrics];

	// After the callouts, which are part of what is centered, and before a
	// drag is shown, which is not.
	[self findStepCenterForModel:model host:host];
	[self findFileObstaclesOfBoxes];

	if (host.hasCalloutPreview && host.calloutPreviewBox < self->_calloutBoxes.count) {
		[self->_calloutBoxes[host.calloutPreviewBox] previewOrigin:host.calloutPreviewPoint];
	}

	return self;

}//end initWithModel:host:pageNumbers:


//========== applyStyleOfModel:toMetrics: ======================================
///
/// @abstract	Takes the look of the list from the file's PLI lines: the
/// 			frame's outline, fill and padding, the counts, the room kept
/// 			around the list, and where it goes.
///
//==============================================================================
- (LDrawStepPartListMetrics) applyStyleOfModel:(LDrawModel *)model
									 toMetrics:(LDrawStepPartListMetrics)metrics
{
	double scale = self->_pointsPerPageInch;

	self->listStyle		= [LDrawStepPartListStyle styleForVisibleStepOfModel:model];
	self->styledMetrics	= [self->listStyle metricsFromMetrics:metrics pointsPerPageInch:scale];
	self->_chrome		= [self->listStyle chromeFromChrome:self->_chrome pointsPerPageInch:scale];

	return self->styledMetrics;

}//end applyStyleOfModel:toMetrics:


// MARK: - THE FILE'S STYLE -


//========== countText =========================================================
- (nullable LDrawStepCalloutText *) countText
{
	return self->listStyle.countText;

}//end countText


//========== annotationText ====================================================
- (nullable LDrawStepCalloutText *) annotationText
{
	return self->listStyle.annotationText;

}//end annotationText


//========== hasPageColor ======================================================
- (BOOL) hasPageColor
{
	return self->listStyle.hasPageColor;

}//end hasPageColor


//========== pageColor =========================================================
- (LPubColorComponents) pageColor
{
	return self->listStyle.pageColor;

}//end pageColor


//========== placePageNumberForModel:pageNumbers: ==============================
///
/// @abstract	Finds the visible step's page number and where it goes on the
/// 			page. With no PAGE NUMBER PLACEMENT line it goes in the bottom
/// 			right corner.
///
/// @discussion	Only a place inside the page is read, since the page's header
/// 			and footer are not drawn here. A count for another file is
/// 			made again.
///
//==============================================================================
- (void) placePageNumberForModel:(LDrawModel *)model pageNumbers:(nullable LDrawStepPageNumbers *)pageNumbers
{
	LDrawStepPageNumberStyle *style = nil;

	if ([LDrawStepPartList showsPageNumber]) {
		style = [LDrawStepPageNumberStyle styleForVisibleStepOfModel:model];
	}

	if (style == nil) {
		return;
	}

	LDrawFile *file = [model enclosingFile];

	if (pageNumbers.file != file) {
		pageNumbers = [LDrawStepPageNumbers pageNumbersOfFile:file];
	}

	NSArray<LDrawStepPageNumber *> *pages = [pageNumbers pagesShowingStep:[model visibleStep]];

	if (pages.count == 0) {
		return;
	}

	NSString				*text		= [LDrawStepPageNumbers textForPages:pages];
	LPubPlacement			*placement	= style.placement;
	LPubPlacementPosition	 position	= LPubPlacementPositionBottomRight;
	Point2					 offset		= ZeroPoint2;
	double					 scale		= self->_pointsPerPageInch;
	Size2					 inches		= [style.text sizeForText:text];
	Size2					 size		= V2MakeSize(inches.width * scale, inches.height * scale);

	if (placement.isInsidePage) {
		position	= placement.position;
		offset		= placement.offset;
	}

	if (style.togglesSides && pages.firstObject.number % 2 == 0) {
		position = MirroredPosition(position);
	}

	Point2 origin = [LDrawStepCalloutBox originForSize:size
											  position:position
										 justification:LPubPlacementPositionCenter
											  isInside:YES
												anchor:self->_pageRect
												margin:[self gapOnPageForMargins:style.margins]];

	origin.x += V2BoxWidth(self->_pageRect) * offset.x;
	origin.y += V2BoxHeight(self->_pageRect) * offset.y;

	self->_pageNumber		= text;
	self->_pageNumberText	= style.text;
	self->_pageNumberRect	= V2MakeBox(origin.x, origin.y, size.width, size.height);

}//end placePageNumberForModel:pageNumbers:


//========== gapOnPageForMargins: ==============================================
///
/// @abstract	The room between the page's edges and something placed inside
/// 			it with these margins, in points.
///
/// @discussion	LPub3D keeps the larger of the page's margin and the thing's.
///
//==============================================================================
- (Size2) gapOnPageForMargins:(Size2)margins
{
	Size2	page	= self->listStyle.pageMargins;
	double	scale	= self->_pointsPerPageInch;

	return V2MakeSize(MAX(page.width, margins.width) * scale, MAX(page.height, margins.height) * scale);

}//end gapOnPageForMargins:


//========== allowedFrameSize ==================================================
- (Size2) allowedFrameSize
{
	if (self->_isOnPage == NO) {
		return [LDrawStepPartListPolicy allowedFrameSizeInHostSize:self->_hostSize pointsPerPageInch:0.0];
	}

	Size2 gap = [self gapOnPageForMargins:self->listStyle.margins];

	return V2MakeSize(MAX(0.0, V2BoxWidth(self->_pageRect) - 2.0 * gap.width),
					  MAX(0.0, V2BoxHeight(self->_pageRect) - 2.0 * gap.height));

}//end allowedFrameSize


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

	Size2 room = self.allowedFrameSize;

	// After scaling, so the budget allows for the padding the frame is drawn
	// with.
	metrics = [LDrawStepPartListPolicy metrics:metrics fittingAllowedSize:room];

	LDrawStepPartListConstraint	constraint		= [self constraintForModel:model
																	  host:host
															  allowedWidth:room.width
															 pointsPerInch:metrics.pointsPerInch];
	Matrix4						viewTransform	= self->stepViewTransform;

	self->_layout		= [LDrawStepPartListLayout layoutForEntries:entries
														 constraint:constraint
													  viewTransform:viewTransform
															metrics:metrics];

	// A packing wider than the room on the page is packed again at that width,
	// so it wraps. The half point allows for rounding.
	if (self->_isOnPage && self->_layout.frameSize.width > room.width + 0.5) {
		constraint.mode		= LPubPliConstrainModeWidth;
		constraint.inches	= (float)(room.width / metrics.pointsPerInch);

		self->_layout		= [LDrawStepPartListLayout layoutForEntries:entries
															 constraint:constraint
														  viewTransform:viewTransform
																metrics:metrics];
	}

	// The document's file, so a submodel draws its real contents.
	self->iconFile			= [model enclosingFile];
	self->_iconKey			= [LDrawStepPartListModelBuilder iconKeyForLayout:self->_layout
																viewTransform:viewTransform];

	self->_iconZoomPercentage	= [LDrawStepPartListModelBuilder zoomPercentageForLayout:self->_layout];
	self->_iconCenter			= [LDrawStepPartListModelBuilder centerPointForLayout:self->_layout];

	[self placeFrameWithMetrics:metrics host:host];
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
	options.listViewTransform	= self->stepViewTransform;
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

	BOOL readsLines = ([LDrawStepPartList placesCalloutsAutomatically] == NO);

	for (LDrawStepCalloutBox *box in self->_calloutBoxes) {
		Box2 frame = box.frameRect;

		// A line that is not read does not say where the step goes either.
		[key appendFormat:@"\n%@", readsLines ? (box.callout.placement.lPubCommandString ?: @"") : @""];

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

	// A list centered with the assembly moves the step when its line, its
	// CONSTRAIN or its style changes its size. Not its measured size, which a
	// resize drag changes as it goes. In page inches.
	if (self->listIsCenteredWithAssembly) {
		LDrawStepPartListConstraint	constraint	= self->fileConstraint;
		LDrawStepPartListMetrics	metrics		= self->styledMetrics;
		LDrawStepPartListStyle		*style		= self->listStyle;
		double						 scale		= self->_pointsPerPageInch;

		[key appendFormat:@"\n%@ %ld %.4f %ld", style.placement.lPubCommandString,
		 (long)constraint.mode, constraint.inches, (long)constraint.columns];
		[key appendFormat:@" %.4f %.4f %.4f %.4f %.4f %.4f %.4f",
		 metrics.framePadding / scale, metrics.labelHeight / scale, metrics.labelCharacterWidth / scale,
		 style.margins.width, style.margins.height, style.pageMargins.width, style.pageMargins.height];
	}

	self->_placementKey = key;

	if (V2BoxWidth(assembly) <= 0.0 || V2BoxHeight(assembly) <= 0.0) {
		return;
	}

	self->_hasStepCenter	= YES;
	self->_stepCenterInView	= [self stepCenterForAssembly:assembly placement:placement leavingOut:nil];
	self->_stepRect			= [self stepBoxForAssembly:assembly leavingOut:nil];
	self->stepAnchorShare	= PlacedShare(placement.isInsidePage ? placement.position : LPubPlacementPositionCenter);

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


//========== findFileObstaclesOfBoxes ==========================================
///
/// @abstract	Tells each box what it keeps clear of where the file puts it,
/// 			when it is dropped in a turned view: the parts list, and the
/// 			other boxes as the file has them.
///
/// @discussion	Each is made bigger by the room the two keep, the larger of
/// 			their margins. A box's first drop moves the assembly, and the
/// 			other boxes placed against the assembly with it, so those are
/// 			counted where they will be then.
///
//==============================================================================
- (void) findFileObstaclesOfBoxes
{
	if (self->_isOnPage == NO) {
		return;
	}

	double	scale		= self->_pointsPerPageInch;
	Size2	listMargin	= V2MakeSize(self->listStyle.margins.width * scale, self->listStyle.margins.height * scale);
	BOOL	hasList		= (V2BoxWidth(self->_frameRect) > 0.0 && V2BoxHeight(self->_frameRect) > 0.0);

	for (LDrawStepCalloutBox *box in self->_calloutBoxes) {
		NSMutableData	*obstacles	= [NSMutableData data];
		Size2			 margins	= box.style.margins;

		if (hasList) {
			Box2 list = V2BoxInset(self->_frameRect,
								   -MAX(margins.width * scale, listMargin.width),
								   -MAX(margins.height * scale, listMargin.height));

			[obstacles appendBytes:&list length:sizeof(Box2)];
		}

		for (LDrawStepCalloutBox *other in self->_calloutBoxes) {
			if (other == box) {
				continue;
			}

			Size2	theirs	= other.style.margins;
			Point2	move	= other.isPlacedAgainstAssembly ? box.assemblyShiftAfterDrag : ZeroPoint2;
			Box2	rect	= V2BoxInset(LDrawStepCalloutMovedBox(other.placedRect, move),
										 -MAX(margins.width, theirs.width) * scale,
										 -MAX(margins.height, theirs.height) * scale);

			[obstacles appendBytes:&rect length:sizeof(Box2)];
		}

		box.fileObstacles = obstacles;
	}

}//end findFileObstaclesOfBoxes


//========== pageMargins =======================================================
- (Size2) pageMargins
{
	return self->listStyle.pageMargins;

}//end pageMargins


//========== stepAnchorInView ==================================================
- (Point2) stepAnchorInView
{
	Box2 step = self->_stepRect;

	return V2Make(V2BoxMinX(step) + self->stepAnchorShare.x * V2BoxWidth(step),
				  V2BoxMinY(step) + self->stepAnchorShare.y * V2BoxHeight(step));

}//end stepAnchorInView


//========== arrangeFrameRect ==================================================
- (Box2) arrangeFrameRect
{
	Box2 step = self->_stepRect;

	if (V2BoxWidth(step) <= 0.0 || V2BoxHeight(step) <= 0.0) {
		return ZeroBox2;
	}

	return V2BoxInset(step, -ARRANGE_FRAME_OUTSET, -ARRANGE_FRAME_OUTSET);

}//end arrangeFrameRect


//========== rectOfArrangeHandle: ==============================================
///
/// @abstract	The square drawn for a handle, on its corner of the frame.
///
/// @discussion	The corner the step is placed by stays put as it grows, so a
/// 			drag there could not scale it, and it has no handle.
///
//==============================================================================
- (Box2) rectOfArrangeHandle:(LDrawStepArrangeHandle)handle
{
	Box2	frame		= self.arrangeFrameRect;
	BOOL	isRight		= (handle == LDrawStepArrangeHandleTopRight || handle == LDrawStepArrangeHandleBottomRight);
	BOOL	isBottom	= (handle == LDrawStepArrangeHandleBottomLeft || handle == LDrawStepArrangeHandleBottomRight);
	Point2	share		= V2Make(isRight ? 1.0 : 0.0, isBottom ? 1.0 : 0.0);

	if (handle == LDrawStepArrangeHandleNone
		|| V2BoxWidth(frame) <= 0.0
		|| (share.x == self->stepAnchorShare.x && share.y == self->stepAnchorShare.y)) {
		return ZeroBox2;
	}

	Point2 corner = V2Make(isRight ? V2BoxMaxX(frame) : V2BoxMinX(frame),
						   isBottom ? V2BoxMaxY(frame) : V2BoxMinY(frame));

	return V2SizeCenteredOnPoint(V2MakeSize(ARRANGE_HANDLE_SIDE, ARRANGE_HANDLE_SIDE), corner);

}//end rectOfArrangeHandle:


//========== arrangeHandleAtPoint: =============================================
- (LDrawStepArrangeHandle) arrangeHandleAtPoint:(Point2)point
{
	const LDrawStepArrangeHandle handles[] = {
		LDrawStepArrangeHandleTopLeft, LDrawStepArrangeHandleTopRight,
		LDrawStepArrangeHandleBottomRight, LDrawStepArrangeHandleBottomLeft
	};

	for (size_t index = 0; index < sizeof(handles) / sizeof(handles[0]); index++) {
		Box2 rect = [self rectOfArrangeHandle:handles[index]];

		if (V2BoxWidth(rect) > 0.0
			&& V2BoxContains(V2BoxInset(rect, -ARRANGE_HANDLE_REACH, -ARRANGE_HANDLE_REACH), point)) {
			return handles[index];
		}
	}

	return LDrawStepArrangeHandleNone;

}//end arrangeHandleAtPoint:


//========== stepBoxForAssembly:leavingOut: ====================================
///
/// @abstract	The box around the assembly and what is centered with it: the
/// 			callouts placed against it that have not been dragged, but for
/// 			one box, and a list placed against it.
///
//==============================================================================
- (Box2) stepBoxForAssembly:(Box2)assembly leavingOut:(nullable LDrawStepCalloutBox *)leftOut
{
	Point2 minimum = assembly.origin;
	Point2 maximum = V2Make(V2BoxMaxX(assembly), V2BoxMaxY(assembly));

	for (LDrawStepCalloutBox *box in self->_calloutBoxes) {
		Box2 frame = box.frameRect;

		if (box.isCenteredWithAssembly && box != leftOut) {
			GrowBounds(&minimum, &maximum, frame);
		}
	}

	// LPub3D lays a list placed against the assembly out with the step.
	Box2 list = self->_frameRect;

	if (self->listIsCenteredWithAssembly && V2BoxWidth(list) > 0.0 && V2BoxHeight(list) > 0.0) {
		GrowBounds(&minimum, &maximum, list);
	}

	return V2MakeBox(minimum.x, minimum.y, maximum.x - minimum.x, maximum.y - minimum.y);

}//end stepBoxForAssembly:leavingOut:


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
/// 			Both are read on the document's own page. A page grown to the
/// 			host's shape keeps that one in its middle, so the step is not
/// 			pushed to the far edge of a tall window.
///
//==============================================================================
- (Point2) stepCenterForAssembly:(Box2)assembly
					   placement:(nullable LPubPlacement *)placement
					  leavingOut:(nullable LDrawStepCalloutBox *)leftOut
{
	Box2	around	= [self stepBoxForAssembly:assembly leavingOut:leftOut];
	Point2	minimum	= around.origin;
	Point2	maximum	= V2Make(V2BoxMaxX(around), V2BoxMaxY(around));

	LPubPlacementPosition	position	= LPubPlacementPositionCenter;
	Point2					offset		= ZeroPoint2;

	if (placement.isInsidePage) {
		position	= placement.position;
		offset		= placement.offset;
	}

	Size2	pageSize	= self->_pageRect.size;
	Size2	filePage	= self->filePageSize;
	Box2	placedOn	= V2MakeBox((pageSize.width - filePage.width) / 2.0, (pageSize.height - filePage.height) / 2.0,
								filePage.width, filePage.height);
	double	scale		= self->_pointsPerPageInch;
	Size2	margin		= V2MakeSize(self->listStyle.pageMargins.width * scale,
									 self->listStyle.pageMargins.height * scale);
	Size2	together	= V2MakeSize(maximum.x - minimum.x, maximum.y - minimum.y);
	Point2	onPage		= [LDrawStepCalloutBox originForSize:together
													position:position
											   justification:LPubPlacementPositionCenter
													isInside:YES
													  anchor:placedOn
													  margin:margin];

	onPage.x += filePage.width * offset.x;
	onPage.y += filePage.height * offset.y;

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
																		 hostSize:host.viewSize
																		  inModel:model];
	double	pointsPerPageInch	=
		[LDrawStepPartListPolicy pointsPerPageInchForAssemblyScale:host.assemblyScale inModel:model];

	if (V2BoxWidth(page) <= 0.0 || V2BoxHeight(page) <= 0.0 || pointsPerPageInch <= 0.0) {
		return;
	}

	Size2 filePage = [LDrawStepPartListPolicy pageSizeInInchesInModel:model];

	self->_isOnPage	= YES;
	self->_pageRect	= page;
	self->_pointsPerPageInch	= pointsPerPageInch;
	self->filePageSize			= V2MakeSize(filePage.width * pointsPerPageInch, filePage.height * pointsPerPageInch);

}//end placePageForModel:host:


//========== outlineWidth ======================================================
- (double) outlineWidth
{
	if ([LDrawStepPartList drawsBoldOutlines] == NO) {
		return 0.0;
	}

	return [LDrawStepPartListPolicy outlineWidthForPointsPerPageInch:self->_pointsPerPageInch];

}//end outlineWidth


//========== placeFrameWithMetrics:host: =======================================
///
/// @abstract	Places the frame, and the icon area inside its padding.
///
/// @discussion	On the page the frame goes where the file places it on the
/// 			paper, so it stays put there as the view pans.
///
//==============================================================================
- (void) placeFrameWithMetrics:(LDrawStepPartListMetrics)metrics host:(LDrawStepPartListHostState)host
{
	if (self->_layout.placements.count == 0) {
		return;
	}

	Box2 frame = ZeroBox2;

	if (self->_isOnPage) {
		frame = [self placeFrameOnPageWithHost:host];
	}
	else {
		frame = [LDrawStepPartListPolicy frameRectForFrameSize:self->_layout.frameSize
													inHostSize:self->_hostSize
											 pointsPerPageInch:0.0];
	}

	Box2 content = V2BoxInset(frame, metrics.framePadding, metrics.framePadding);

	// A very small view can leave the padding no room at all.
	if (V2BoxWidth(content) < MINIMUM_CONTENT_SIDE || V2BoxHeight(content) < MINIMUM_CONTENT_SIDE) {
		return;
	}

	self->_frameRect	= frame;
	self->_contentRect	= content;

}//end placeFrameWithMetrics:host:


//========== placeFrameOnPageWithHost: =========================================
///
/// @abstract	Puts the frame where the PLI PLACEMENT line says: inside the
/// 			page, or against the assembly. With no line, or one against
/// 			anything else, it goes in the page's top left corner.
///
/// @discussion	LPub3D's own place for a list is beside the step number, which
/// 			is not drawn here. Inside the page the frame keeps the larger of
/// 			the page's margin and the list's. Against the assembly it keeps
/// 			the list's. The offset is a share of the size of what the list
/// 			is placed against.
///
//==============================================================================
- (Box2) placeFrameOnPageWithHost:(LDrawStepPartListHostState)host
{
	LPubPlacement			*placement		= self->listStyle.placement;
	Box2					 assembly		= host.assemblyRect;
	double					 scale			= self->_pointsPerPageInch;
	LPubPlacementPosition	 position		= LPubPlacementPositionTopLeft;
	LPubPlacementPosition	 justification	= LPubPlacementPositionCenter;
	BOOL					 isInside		= YES;
	Point2					 offset			= ZeroPoint2;
	Box2					 anchor			= self->_pageRect;
	Size2					 margin			= [self gapOnPageForMargins:self->listStyle.margins];

	if (placement.isInsidePage) {
		position	= placement.position;
		offset		= placement.offset;
	}
	else if ([placement.relativeTo isEqualToString:LPUB_ASSEM]
			 && V2BoxWidth(assembly) > 0.0 && V2BoxHeight(assembly) > 0.0) {
		position		= placement.position;
		justification	= placement.justification;
		isInside		= placement.isInside;
		offset			= placement.offset;
		anchor			= assembly;
		margin			= V2MakeSize(self->listStyle.margins.width * scale, self->listStyle.margins.height * scale);

		self->listIsCenteredWithAssembly = YES;
	}

	// The packer already kept the list within the page less its margins, so
	// it is drawn at its own size and never cut.
	Size2 size = self->_layout.frameSize;

	// A drag holds the frame where it is, at its size.
	if (host.hasListPreview) {
		return V2MakeBox(host.listPreviewOrigin.x, host.listPreviewOrigin.y, size.width, size.height);
	}

	Point2 origin	= [LDrawStepCalloutBox originForSize:size
											   position:position
										  justification:justification
											   isInside:isInside
												 anchor:anchor
												 margin:margin];
	Point2 grown	= [LDrawStepCalloutBox originForSize:V2MakeSize(size.width + 1.0, size.height + 1.0)
											   position:position
										  justification:justification
											   isInside:isInside
												 anchor:anchor
												 margin:margin];

	// The edge that stays put as the list grows is the one placed. When that
	// is the right or bottom edge, the frame grows the other way.
	self->_growsLeftward	= (grown.x < origin.x - 0.75);
	self->_growsUpward		= (grown.y < origin.y - 0.75);

	origin.x += V2BoxWidth(anchor) * offset.x;
	origin.y += V2BoxHeight(anchor) * offset.y;

	return V2MakeBox(origin.x, origin.y, size.width, size.height);

}//end placeFrameOnPageWithHost:


//========== listOriginAtPagePosition: =========================================
- (Point2) listOriginAtPagePosition:(LPubPlacementPosition)position
{
	if (self->_isOnPage == NO || self->_layout.placements.count == 0) {
		return ZeroPoint2;
	}

	return [LDrawStepCalloutBox originForSize:self->_layout.frameSize
									 position:position
								justification:LPubPlacementPositionCenter
									 isInside:YES
									   anchor:self->_pageRect
									   margin:[self gapOnPageForMargins:self->listStyle.margins]];

}//end listOriginAtPagePosition:


// MARK: - RESIZING -


//========== resizePointForPoint: ==============================================
- (Point2) resizePointForPoint:(Point2)point
{
	Box2 frame = self->_frameRect;

	if (self->_growsLeftward) {
		point.x = 2.0 * V2BoxMaxX(frame) - point.x;
	}
	if (self->_growsUpward) {
		point.y = 2.0 * V2BoxMaxY(frame) - point.y;
	}

	return point;

}//end resizePointForPoint:


//========== resizeFrame =======================================================
///
/// @abstract	The frame mirrored as `-resizePointForPoint:` mirrors a point:
/// 			its edge that stays put is on its left and top.
///
//==============================================================================
- (Box2) resizeFrame
{
	Box2 frame = self->_frameRect;

	if (self->_growsLeftward) {
		frame.origin.x = V2BoxMaxX(frame);
	}
	if (self->_growsUpward) {
		frame.origin.y = V2BoxMaxY(frame);
	}

	return frame;

}//end resizeFrame


//========== iconModel =========================================================
- (nullable LDrawModel *) iconModel
{
	if (self->_iconModel == nil && self->_layout != nil) {
		self->_iconModel = [LDrawStepPartListModelBuilder modelForLayout:self->_layout
														   viewTransform:self->stepViewTransform
													   submodelsFromFile:self->iconFile];
	}

	return self->_iconModel;

}//end iconModel


//========== controlAtPoint: ===================================================
- (LDrawStepPartListControl) controlAtPoint:(Point2)point
{
	// The corner pin sits where no edge is dragged, so it can go first.
	if (self.placementPinned && V2BoxContains(self.placementPinRect, point)) {
		return LDrawStepPartListControlPlacementPin;
	}

	return [LDrawStepPartListPolicy controlAtPoint:[self resizePointForPoint:point]
										   inFrame:[self resizeFrame]
									   widthPinned:self.widthPinned
									  heightPinned:self.heightPinned];

}//end controlAtPoint:


//========== pinRectForAxis: ===================================================
- (Box2) pinRectForAxis:(LPubPliAxis)axis
{
	return [self viewRectForResizeRect:[LDrawStepPartListPolicy pinRectForAxis:axis inFrame:[self resizeFrame]]];

}//end pinRectForAxis:


//========== placementPinRect ==================================================
- (Box2) placementPinRect
{
	return [self viewRectForResizeRect:[LDrawStepPartListPolicy placementPinRectInFrame:[self resizeFrame]]];

}//end placementPinRect


//========== viewRectForResizeRect: ============================================
///
/// @abstract	A rect of the resize space mirrored back into the view, so a pin
/// 			is drawn where it is hit.
///
//==============================================================================
- (Box2) viewRectForResizeRect:(Box2)rect
{
	Box2 frame = self->_frameRect;

	if (self->_growsLeftward) {
		rect.origin.x = 2.0 * V2BoxMaxX(frame) - V2BoxMaxX(rect);
	}
	if (self->_growsUpward) {
		rect.origin.y = 2.0 * V2BoxMaxY(frame) - V2BoxMaxY(rect);
	}

	return rect;

}//end viewRectForResizeRect:


//========== constraintForModel:host:allowedWidth:pointsPerInch: ===============
///
/// @abstract	The constraint to pack with, a WIDTH narrowed to `allowedWidth`
/// 			points.
///
/// @discussion	On the page a drag wins, then the CONSTRAIN in force for the
/// 			step. Off the page the document's lines are ignored: they are
/// 			page inches, and there is no page to measure them on.
///
//==============================================================================
- (LDrawStepPartListConstraint) constraintForModel:(LDrawModel *)model
											  host:(LDrawStepPartListHostState)host
									  allowedWidth:(double)allowedWidth
									 pointsPerInch:(double)pointsPerInch
{
	LDrawStepPartListConstraint constraint;

	if (self->_isOnPage == NO) {
		constraint = [LDrawStepPartListPolicy viewportConstraintForHostSize:self->_hostSize
															  pointsPerInch:pointsPerInch];
	}
	else {
		self->fileConstraint	= [LDrawStepPartListPolicy constraintForVisibleStepOfModel:model];
		constraint				= self->fileConstraint;

		if (host.hasPreview) {
			constraint			= [LDrawStepPartListLayout defaultConstraint];
			constraint.mode		= LPubPliConstrainModeForAxis(host.previewAxis);
			constraint.inches	= (float)host.previewInches;
		}
	}

	return [LDrawStepPartListPolicy constraint:constraint
						  clampedToAllowedWidth:allowedWidth
								  pointsPerInch:pointsPerInch];

}//end constraintForModel:host:allowedWidth:pointsPerInch:


//========== updatePinsForModel:host: ==========================================
///
/// @abstract	A pin marks a size or a place the step sets itself, and clicking
/// 			it clears that. Only on the page, where the frame can be resized.
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

	// A drag of the list may write a line or not, so its pin waits for the drop.
	self->_placementPinned = (host.hasListPreview == NO) && [LDrawStepPartListPolicy isPlacementPinnedInStep:step];

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
/// @discussion	Cells are measured from the corner of the icon area. A point on
/// 			a count or a badge picks its part, even outside the part's cell.
///
//==============================================================================
- (nullable LDrawStepPartListEntry *) entryAtPoint:(Point2)point
{
	return [self->_layout placementAtPoint:V2Sub(point, self->_contentRect.origin)].entry;

}//end entryAtPoint:


//========== calloutBoxAtPoint: ================================================
- (nullable LDrawStepCalloutBox *) calloutBoxAtPoint:(Point2)point
{
	return [LDrawStepCalloutBox boxAtPoint:point amongBoxes:self->_calloutBoxes];

}//end calloutBoxAtPoint:


//========== moveCalloutBoxesFrom:to:arrangement: ==============================
- (void) moveCalloutBoxesFrom:(NSArray<NSData *> *)laidOutPlaces
						   to:(NSArray<NSData *> *)places
				  arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
{
	if (self->_isOnPage == NO) {
		return;
	}

	[LDrawStepCalloutFollower moveBoxes:self->_calloutBoxes
								   from:laidOutPlaces
									 to:places
								 onPage:self->_pageRect
							  listFrame:self->_frameRect
					  pointsPerPageInch:self->_pointsPerPageInch
							arrangement:arrangement];

}//end moveCalloutBoxesFrom:to:arrangement:


//========== placeCalloutBoxesAroundAssembly:places:arrangement: ===============
- (void) placeCalloutBoxesAroundAssembly:(Box2)assemblyRect
								  places:(NSArray<NSData *> *)places
							 arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
{
	if (self->_isOnPage == NO) {
		return;
	}

	[LDrawStepCalloutFollower placeBoxes:self->_calloutBoxes
						  aroundAssembly:assemblyRect
								  places:places
								  onPage:self->_pageRect
							   listFrame:self->_frameRect
					   pointsPerPageInch:self->_pointsPerPageInch
							 arrangement:arrangement];

}//end placeCalloutBoxesAroundAssembly:places:arrangement:


//========== restCalloutBoxesWithArrangement: ==================================
- (void) restCalloutBoxesWithArrangement:(LDrawStepCalloutArrangement *)arrangement
{
	if (self->_isOnPage == NO) {
		return;
	}

	[LDrawStepCalloutFollower restBoxes:self->_calloutBoxes
								 onPage:self->_pageRect
					  pointsPerPageInch:self->_pointsPerPageInch
							arrangement:arrangement];

}//end restCalloutBoxesWithArrangement:


//========== inheritedInchesForAxis: ===========================================
- (double) inheritedInchesForAxis:(LPubPliAxis)axis
{
	return self->inheritedInches[axis];

}//end inheritedInchesForAxis:

@end
