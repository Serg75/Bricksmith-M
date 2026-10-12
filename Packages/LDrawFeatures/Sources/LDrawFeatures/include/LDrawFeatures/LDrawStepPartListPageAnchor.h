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
/// @abstract   Keeps the model points the page is pinned to, so the page does
///             not move when the parts or the removed groups change.
///
/// @discussion There are two. The anchor is the middle of the whole model, and
///             the page is sized by how the model is drawn beside it. The page
///             center is where the middle of the page is drawn, and the host
///             sets it for each step.
///
///             It also keeps where the step's assembly sits on the page, so
///             what is placed against the assembly stays put while the camera
///             is turned.
///
///             The host measures once per Steps session, submodel switch or
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

/// The kept ratio, or 0 before one is noted. A host that leaves a model and
/// comes back to it puts the ratio back, so the model is as big on its page
/// as it was.
@property (nonatomic) double drawnScaleRatio;

/// The model point the middle of the page is drawn at. The anchor, until the
/// host sets one for this model.
- (Point3) pageCenterForModel:(nullable LDrawModel *)model NS_SWIFT_NAME(pageCenter(forModel:));

/// Whether the host has set a page center for this model since the anchor was
/// measured.
- (BOOL) hasPageCenterForModel:(nullable LDrawModel *)model NS_SWIFT_NAME(hasPageCenter(forModel:));

- (void) setPageCenter:(Point3)center forModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(setPageCenter(_:forModel:));

/// Keeps the box around the step's assembly as it sits on the page: its place
/// from the middle of the page, in page inches. `rect` and `pageCenter` are in
/// the view. A box with no area, or a page with no scale, keeps nothing.
- (void) noteAssemblyRect:(Box2)rect
		 aroundPageCenter:(Point2)pageCenter
		pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(noteAssemblyRect(_:aroundPageCenter:pointsPerPageInch:));

/// Whether a box is kept.
@property (nonatomic, readonly) BOOL hasAssemblyRect;

/// The kept box in the view, for a page whose middle and scale are these. An
/// empty box when none is kept.
- (Box2) assemblyRectAroundPageCenter:(Point2)pageCenter pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(assemblyRect(aroundPageCenter:pointsPerPageInch:));

- (void) forgetAssemblyRect;

/// Measure the anchor and the ratio again on the next call, and forget the
/// page center and the assembly's box.
- (void) invalidate;

@end

NS_ASSUME_NONNULL_END
