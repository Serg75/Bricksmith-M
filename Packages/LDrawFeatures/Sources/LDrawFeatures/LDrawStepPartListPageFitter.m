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


/// A perspective frustum is not quite linear, so the zoom is aimed at the
/// scale this many times.
static const NSUInteger FIT_PASSES = 2;


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
/// @abstract	Fits the whole page in the view, with the anchor in the middle.
///
/// @discussion	The page is sized from the scale the model is drawn at beside
/// 			the anchor, which perspective makes differ from the zoom, so a
/// 			fit aims the zoom at that scale and then remembers the ratio.
/// 			Re-centering drops any pan the user made.
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

	// A fit measures the model again. A resize keeps the point.
	if (keepsMagnification == NO) {
		[pageAnchor invalidate];
	}

	Point3	anchor		= [pageAnchor anchorForModel:model];
	CGFloat	zoom		= [view zoomPercentage];
	double	previousFit	= [LDrawStepPartListPolicy assemblyScaleFittingPageInHostSize:self->_fittedViewSize
																			  inModel:model];

	if (keepsMagnification && previousFit > 0.0) {
		zoom *= target / previousFit;
	}
	else {
		for (NSUInteger pass = 0; pass < FIT_PASSES; pass++) {
			double drawnPointsPerLDU = [view pointsPerLDUAtModelPoint:anchor];

			if (drawnPointsPerLDU <= 0.0) {
				zoom = target * 100.0;
				break;
			}

			zoom *= target / drawnPointsPerLDU;
			[view setZoomPercentage:zoom];
		}

		// Kept until the next fit, so the steps' rotations do not resize the
		// page.
		[pageAnchor noteDrawnPointsPerLDU:[view pointsPerLDUAtModelPoint:anchor]
							  atZoomScale:[view zoomPercentage] / 100.0];
	}

	self->_fittedViewSize = viewSize;

	[view setZoomPercentage:zoom];

	// Zoom first: the scroll is in points, and those have just changed size.
	[view scrollCenterToModelPoint:anchor];

	return YES;

}//end fitPageOfModel:inView:viewSize:keepingMagnification:

@end
