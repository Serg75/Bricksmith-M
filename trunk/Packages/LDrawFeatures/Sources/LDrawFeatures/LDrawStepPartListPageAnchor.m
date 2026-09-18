//==============================================================================
//
//  File:       LDrawStepPartListPageAnchor.m
//  Package:    LDrawFeatures
//
//  Purpose:    Keeps the model point the page is pinned to.
//
//  Created by Sergey Slobodenyuk on 2026-09-17.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>

#import <LDrawCore/LDrawModel.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>


@implementation LDrawStepPartListPageAnchor
{
	/// The model the point was measured in, or nil to measure again.
	__weak LDrawModel	*measuredModel;
	Point3				anchor;

	/// Drawn scale over zoom scale, or 0 until the host notes one.
	double				drawnScaleRatio;
}

//========== anchorForModel: ===================================================
///
/// @abstract	The stored point, measured first for a new model.
///
//==============================================================================
- (Point3) anchorForModel:(nullable LDrawModel *)model
{
	if (model == nil) {
		return ZeroPoint3;
	}

	if (model != self->measuredModel) {
		self->anchor		= [LDrawStepPartListPolicy pageAnchorInModel:model];
		self->measuredModel	= model;
	}

	return self->anchor;

}//end anchorForModel:


//========== invalidate ========================================================
///
/// @abstract	Measure again on the next call.
///
//==============================================================================
- (void) invalidate
{
	self->measuredModel		= nil;
	self->drawnScaleRatio	= 0.0;

}//end invalidate


//========== needsDrawnScale ===================================================
- (BOOL) needsDrawnScale
{
	return self->drawnScaleRatio <= 0.0;

}//end needsDrawnScale


//========== noteDrawnPointsPerLDU:atZoomScale: ================================
///
/// @abstract	Keeps the drawn scale as a ratio against the zoom.
///
/// @discussion	A measure that cannot be read keeps the zoom alone, so it is
/// 			not taken again on every redraw.
///
//==============================================================================
- (void) noteDrawnPointsPerLDU:(double)drawnPointsPerLDU atZoomScale:(double)zoomScale
{
	self->drawnScaleRatio = (drawnPointsPerLDU > 0.0 && zoomScale > 0.0)
						  ? (drawnPointsPerLDU / zoomScale)
						  : 1.0;

}//end noteDrawnPointsPerLDU:atZoomScale:


//========== assemblyScaleForZoomScale: ========================================
///
/// @abstract	Points per LDU the page is sized from at this zoom.
///
//==============================================================================
- (double) assemblyScaleForZoomScale:(double)zoomScale
{
	double ratio = (self->drawnScaleRatio > 0.0) ? self->drawnScaleRatio : 1.0;

	return zoomScale * ratio;

}//end assemblyScaleForZoomScale:

@end
