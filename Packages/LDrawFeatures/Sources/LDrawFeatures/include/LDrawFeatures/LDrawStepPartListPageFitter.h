//==============================================================================
//
//  File:       LDrawStepPartListPageFitter.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawModel;
@class LDrawStepPartListPageAnchor;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @protocol   LDrawStepPartListPageView
///
/// @abstract   The camera calls a page fit needs from the view the model is
///             drawn in.
///
//------------------------------------------------------------------------------
@protocol LDrawStepPartListPageView <NSObject>

- (CGFloat) zoomPercentage;
- (void) setZoomPercentage:(CGFloat)newPercentage;

/// How many points one LDU covers on screen beside this model point.
- (double) pointsPerLDUAtModelPoint:(Point3)modelPoint;

- (void) scrollCenterToModelPoint:(Point3)modelPoint;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPageFitter
///
/// @abstract   Fits LPub3D's page in a view, and keeps it fitted as the view
///             is resized.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPageFitter : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// The anchor is shared with everything that places the page.
- (instancetype) initWithPageAnchor:(LDrawStepPartListPageAnchor *)pageAnchor NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) LDrawStepPartListPageAnchor *pageAnchor;

/// The view size the page was last fitted to, or zero before a fit. A resize
/// scales the zoom by how much the fit changed since then.
@property (nonatomic) Size2 fittedViewSize;

/// Fits the whole page in a view of this size, with the page center in the
/// middle.
///
/// A fit measures the anchor again and forgets the page center, so the host
/// centers the page on its step afterwards. Keeping the magnification is for a
/// resize: the zoom is scaled by how much the fit changed, so everything stays
/// where it was on the page. Returns NO when the document does not measure its
/// page.
- (BOOL) fitPageOfModel:(nullable LDrawModel *)model
				 inView:(id<LDrawStepPartListPageView>)view
			   viewSize:(Size2)viewSize
   keepingMagnification:(BOOL)keepsMagnification
	NS_SWIFT_NAME(fitPage(of:in:viewSize:keepingMagnification:));

/// How many points one inch of the model's page covers in the view: the scale
/// the model is drawn at beside the anchor, read as LPub3D's 1/64 inch per LDU
/// times ASSEM MODEL_SCALE.
- (double) pointsPerPageInchOfModel:(nullable LDrawModel *)model inView:(id<LDrawStepPartListPageView>)view
	NS_SWIFT_NAME(pointsPerPageInch(of:in:));

/// Zooms the view so one inch of the model's page covers this many points. A
/// host that puts another model on display uses it to keep the page the size
/// the last one had. Returns NO, and leaves the zoom alone, when either scale
/// is not above 0.
- (BOOL) showPageOfModel:(nullable LDrawModel *)model
				  inView:(id<LDrawStepPartListPageView>)view
	 atPointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(showPage(of:in:atPointsPerPageInch:));

@end

NS_ASSUME_NONNULL_END
