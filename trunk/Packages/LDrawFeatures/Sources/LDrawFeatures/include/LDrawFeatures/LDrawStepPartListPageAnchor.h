//==============================================================================
//
//  File:       LDrawStepPartListPageAnchor.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-17.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawModel;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPageAnchor
///
/// @abstract   Keeps the model point the page is pinned to, so the page does
///             not move when the step, the parts or the removed groups change.
///
/// @discussion The host measures once per Steps session, submodel switch or
///             Zoom to Fit, and shares one instance between everything that
///             places the page.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPageAnchor : NSObject

/// The stored point. Measured again for a different model or after
/// -invalidate. Zero for nil.
- (Point3) anchorForModel:(nullable LDrawModel *)model NS_SWIFT_NAME(anchor(forModel:));

/// Whether the host still has to measure the scale the model is drawn at
/// beside the anchor.
@property (nonatomic, readonly) BOOL needsDrawnScale;

/// Keeps how much bigger the model is drawn beside the anchor than the zoom
/// alone says. Kept with the anchor, so the page keeps one scale while the
/// steps turn the model.
- (void) noteDrawnPointsPerLDU:(double)drawnPointsPerLDU atZoomScale:(double)zoomScale
	NS_SWIFT_NAME(noteDrawnPointsPerLDU(_:atZoomScale:));

/// Points per LDU the page is sized from at this zoom (zoom percentage / 100):
/// the zoom times the kept ratio, or the zoom alone before one is noted.
- (double) assemblyScaleForZoomScale:(double)zoomScale
	NS_SWIFT_NAME(assemblyScale(forZoomScale:));

/// Measure the point and the ratio again on the next call.
- (void) invalidate;

@end

NS_ASSUME_NONNULL_END
