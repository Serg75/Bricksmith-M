//==============================================================================
//
//  File:       LDrawStepPartListPageFitter.m
//  Package:    LDrawFeatures
//
//  Purpose:    Fits LPub3D's page in a view.
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListPageFitter.h>

#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>


@implementation LDrawStepPartListPageFitter

//========== initWithPageAnchor: ===============================================
- (instancetype) initWithPageAnchor:(LDrawStepPartListPageAnchor *)pageAnchor
{
	self = [super init];
	if (self) {
		self->_pageAnchor		= pageAnchor;
		self->_fittedViewSize	= ZeroSize2;
	}
	return self;

}//end initWithPageAnchor:


//========== fitPageOfModel:inView:viewSize:keepingMagnification: ==============
///
/// @abstract	Fits the whole page in the view, with its middle in the middle.
///
/// @discussion	Only the zoom changes, so the model keeps its scale on the
/// 			page. The zoom is set so that scale lands beside the anchor,
/// 			where perspective may draw the model bigger or smaller than the
/// 			zoom says. Re-centering drops any pan the user made.
///
//==============================================================================
- (BOOL) fitPageOfModel:(nullable LDrawModel *)model
				 inView:(id<LDrawStepPartListPageView>)view
			   viewSize:(Size2)viewSize
   keepingMagnification:(BOOL)keepsMagnification
{
	double target = [LDrawStepPartListPolicy assemblyScaleFittingPageInHostSize:viewSize inModel:model];

	if (target <= 0.0) {
		return NO;
	}

	LDrawStepPartListPageAnchor *pageAnchor = self->_pageAnchor;

	// A fit measures the anchor again. A resize keeps it.
	if (keepsMagnification == NO) {
		[pageAnchor invalidate];
	}

	CGFloat	zoom		= target * 100.0 / [pageAnchor drawnScaleRatioOfModel:model inView:view];
	double	previousFit	= [LDrawStepPartListPolicy assemblyScaleFittingPageInHostSize:self->_fittedViewSize
																			  inModel:model];

	if (keepsMagnification && previousFit > 0.0) {
		zoom = [view zoomPercentage] * target / previousFit;
	}

	self->_fittedViewSize = viewSize;

	[view setZoomPercentage:zoom];

	// Zoom first: the scroll is in points, and those have just changed size.
	[view scrollCenterToModelPoint:[pageAnchor pageCenterForModel:model]];

	return YES;

}//end fitPageOfModel:inView:viewSize:keepingMagnification:


//========== pointsPerPageInchOfModel:inView: ==================================
- (double) pointsPerPageInchOfModel:(nullable LDrawModel *)model inView:(id<LDrawStepPartListPageView>)view
{
	double ratio			= [self->_pageAnchor drawnScaleRatioOfModel:model inView:view];
	double assemblyScale	= [view zoomPercentage] / 100.0 * ratio;

	return [LDrawStepPartListPolicy pointsPerPageInchForAssemblyScale:assemblyScale inModel:model];

}//end pointsPerPageInchOfModel:inView:


//========== showPageOfModel:inView:atPointsPerPageInch: =======================
///
/// @abstract	Zooms the view so one inch of the model's page covers this many
/// 			points.
///
//==============================================================================
- (BOOL) showPageOfModel:(nullable LDrawModel *)model
				  inView:(id<LDrawStepPartListPageView>)view
	 atPointsPerPageInch:(double)pointsPerPageInch
{
	double current = [self pointsPerPageInchOfModel:model inView:view];

	if (current <= 0.0 || pointsPerPageInch <= 0.0) {
		return NO;
	}

	[view setZoomPercentage:[view zoomPercentage] * pointsPerPageInch / current];

	return YES;

}//end showPageOfModel:inView:atPointsPerPageInch:

@end
