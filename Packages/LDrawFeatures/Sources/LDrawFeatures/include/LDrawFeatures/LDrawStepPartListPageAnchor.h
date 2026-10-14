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
@protocol LDrawStepPartListPageView;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPageAnchor
///
/// @abstract   Keeps the model points the page is pinned to, so the page does
///             not move when the parts or the removed groups change.
///
/// @discussion There are two. The anchor is the middle of the whole model, and
///             the page is sized by how the model is drawn there. The page
///             center is where the middle of the page is drawn, and the host
///             sets it for each step.
///
///             It also keeps where the step's assembly sits on the page, so
///             what is placed against the assembly stays put while the camera
///             is turned.
///
///             The anchor is measured once per Steps session, submodel switch
///             or Zoom to Fit, and the ratio once for each step laid out. The
///             host shares one instance between everything that places the
///             page.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPageAnchor : NSObject

/// The stored point. Measured again for a different model or after
/// -invalidate. Zero for nil.
- (Point3) anchorForModel:(nullable LDrawModel *)model NS_SWIFT_NAME(anchor(forModel:));

/// How much bigger the model is drawn beside the anchor than the view's zoom
/// says. Measured in the view the first time it is asked for, and kept until
/// -forgetDrawnScale or another model. In perspective it depends on how deep
/// the anchor is, so the host forgets it for each step it lays out and keeps
/// it while the camera is turned. 1 when the view cannot measure it.
- (double) drawnScaleRatioOfModel:(nullable LDrawModel *)model inView:(id<LDrawStepPartListPageView>)view
	NS_SWIFT_NAME(drawnScaleRatio(of:in:));

/// Forgets the kept ratio, for another step or another angle.
- (void) forgetDrawnScale;

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
