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

/// Fits the whole page in a view of this size, with the anchor in the middle.
///
/// A fit measures the anchor again. Keeping the magnification is for a resize:
/// the zoom is scaled by how much the fit changed, so everything stays where it
/// was on the page. Returns NO when the document does not measure its page.
- (BOOL) fitPageOfModel:(nullable LDrawModel *)model
				 inView:(id<LDrawStepPartListPageView>)view
			   viewSize:(Size2)viewSize
   keepingMagnification:(BOOL)keepsMagnification
	NS_SWIFT_NAME(fitPage(of:in:viewSize:keepingMagnification:));

@end

NS_ASSUME_NONNULL_END
