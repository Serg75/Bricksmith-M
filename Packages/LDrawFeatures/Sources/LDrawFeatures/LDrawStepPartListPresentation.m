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
#import <LDrawFeatures/LDrawStepCalloutStyle.h>
#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>
#import <LDrawFeatures/LDrawStepPartListStyle.h>

#import "LDrawStepCalloutContent.h"
#import "LDrawStepCalloutFollower.h"


/// Below this size there is nothing worth drawing, and a camera cannot make a
/// projection.
static const double MINIMUM_CONTENT_SIDE = 8.0;


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

	self->_calloutChrome = self->_chrome;

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
	}

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

}//end initWithModel:host:


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


//========== listGapOnPage =====================================================
///
/// @abstract	The room between the page's edges and a list placed inside it,
/// 			in points.
///
/// @discussion	LPub3D keeps the larger of the page's margin and the list's.
///
//==============================================================================
- (Size2) listGapOnPage
{
	Size2	page	= self->listStyle.pageMargins;
	Size2	list	= self->listStyle.margins;
	double	scale	= self->_pointsPerPageInch;

	return V2MakeSize(MAX(page.width, list.width) * scale, MAX(page.height, list.height) * scale);

}//end listGapOnPage


//========== allowedFrameSize ==================================================
- (Size2) allowedFrameSize
{
	if (self->_isOnPage == NO) {
		return [LDrawStepPartListPolicy allowedFrameSizeInHostSize:self->_hostSize pointsPerPageInch:0.0];
	}

	Size2 gap = [self listGapOnPage];

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
	Matrix4						viewTransform	= [LDrawStepPartListPolicy viewTransformForVisibleStepOfModel:model];

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
	self->_iconModel	= [LDrawStepPartListModelBuilder modelForLayout:self->_layout
														  viewTransform:viewTransform
													  submodelsFromFile:[model enclosingFile]];

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

	LPubPlacementPosition	position	= LPubPlacementPositionCenter;
	Point2					offset		= ZeroPoint2;

	if (placement != nil && placement.isInside && [placement.relativeTo isEqualToString:LPUB_PAGE]) {
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
	Size2					 margin			= [self listGapOnPage];

	if (placement.isInside && [placement.relativeTo isEqualToString:LPUB_PAGE]) {
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


//========== controlAtPoint: ===================================================
- (LDrawStepPartListControl) controlAtPoint:(Point2)point
{
	return [LDrawStepPartListPolicy controlAtPoint:[self resizePointForPoint:point]
										   inFrame:[self resizeFrame]
									   widthPinned:self.widthPinned
									  heightPinned:self.heightPinned];

}//end controlAtPoint:


//========== pinRectForAxis: ===================================================
- (Box2) pinRectForAxis:(LPubPliAxis)axis
{
	Box2 pin	= [LDrawStepPartListPolicy pinRectForAxis:axis inFrame:[self resizeFrame]];
	Box2 frame	= self->_frameRect;

	// Mirrored back, so the pin is on the edge that moves.
	if (self->_growsLeftward) {
		pin.origin.x = 2.0 * V2BoxMaxX(frame) - V2BoxMaxX(pin);
	}
	if (self->_growsUpward) {
		pin.origin.y = 2.0 * V2BoxMaxY(frame) - V2BoxMaxY(pin);
	}

	return pin;

}//end pinRectForAxis:


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
