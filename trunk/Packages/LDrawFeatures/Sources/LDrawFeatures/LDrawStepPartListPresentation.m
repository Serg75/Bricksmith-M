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

#import <LDrawCore/LDrawModel.h>

#import <LDrawFeatures/LDrawStepPartList.h>
#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>


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

	if (model == nil) {
		return self;
	}

	[self placePageForModel:model host:host];

	// A step that hides its list still shows its page.
	NSArray *entries = [LDrawStepPartList isShownForVisibleStepOfModel:model]
					 ? [LDrawStepPartList entriesForVisibleStepOfModel:model]
					 : @[];

	// The frame is packed against whatever it sits in: the page when there is
	// one, else the view. So a CONSTRAIN is measured on the page.
	Size2 hostSize = self->_isOnPage ? self->_pageRect.size : host.viewSize;

	self->_hostSize = hostSize;

	if (entries.count == 0 || hostSize.width <= 0.0 || hostSize.height <= 0.0) {
		return self;
	}

	LDrawStepPartListMetrics metrics = [LDrawStepPartListLayout defaultMetrics];

	if (self->_isOnPage) {
		metrics				= [LDrawStepPartListPolicy metrics:metrics
									 scaledToPointsPerPageInch:self->_pointsPerPageInch];
		metrics.baseScale	= [LDrawStepPartListPolicy partListScaleForAssemblyScale:host.assemblyScale
																			 inModel:model];

		// The packer keeps the room and the view draws the text, so both are
		// scaled by the same ratio.
		self->_chrome = [LDrawStepPartListPolicy chrome:self->_chrome
							  scaledToPointsPerPageInch:self->_pointsPerPageInch];
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

	return self;

}//end initWithModel:host:


//========== placePageForModel:host: ===========================================
///
/// @abstract	Puts the page around the anchor, when the document is drawn on
/// 			one.
///
//==============================================================================
- (void) placePageForModel:(LDrawModel *)model host:(LDrawStepPartListHostState)host
{
	if ([LDrawStepPartListPolicy drawsPageInModel:model] == NO || host.assemblyScale <= 0.0) {
		return;
	}

	Box2	page					= [LDrawStepPartListPolicy pageRectCenteredOn:host.anchorInView
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


//========== inheritedInchesForAxis: ===========================================
- (double) inheritedInchesForAxis:(LPubPliAxis)axis
{
	return self->inheritedInches[axis];

}//end inheritedInchesForAxis:

@end
