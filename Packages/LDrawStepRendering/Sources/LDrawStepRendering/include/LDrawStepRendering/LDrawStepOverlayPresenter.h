//==============================================================================
//
//  File:       LDrawStepOverlayPresenter.h
//  Package:    LDrawStepRendering
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawFeatures/LDrawStepPartListPageFitter.h>

@class LDrawModel;
@class LDrawStepLayoutCache;
@class LDrawStepPartListPageAnchor;
@class LDrawStepPartListPresentation;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @protocol   LDrawStepOverlayCamera
///
/// @abstract   The questions the overlay asks of the view that draws the model.
///             A point of the view is in the view's own points, with y running
///             down.
///
//------------------------------------------------------------------------------
@protocol LDrawStepOverlayCamera <LDrawStepPartListPageView>

/// The angle the model is seen from, in degrees.
- (Tuple3) viewingAngle;

/// Where a model point lands in the view.
- (CGPoint) viewPointForModelPoint:(Point3)modelPoint;

/// The model point drawn at a point of the view, as deep in the model as the
/// reference point.
- (Point3) modelPointForViewPoint:(CGPoint)viewPoint depthReferencePoint:(Point3)depthPoint;

/// The rectangle around where these model points land in the view. The points
/// are Point3 values.
- (CGRect) viewRectForModelPoints:(NSData *)points;

/// Where each of these model points lands in the view: a Point2 for each
/// Point3.
- (NSData *) viewPointsForModelPoints:(NSData *)points;

/// Scrolls so that a model point lands on a point of the view.
- (void) scrollModelPoint:(Point3)modelPoint toViewPoint:(CGPoint)viewPoint;

@end


//------------------------------------------------------------------------------
///
/// @enum       LDrawStepOverlayChange
///
/// @abstract   What a change means for the overlay.
///
//------------------------------------------------------------------------------
typedef NS_OPTIONS(NSUInteger, LDrawStepOverlayChange) {
	LDrawStepOverlayChangeNone		= 0,
	/// The step has to be laid out again: call -reload.
	LDrawStepOverlayChangeLayout	= 1 << 0,
	/// The callouts' pictures may show something else now: discard them.
	LDrawStepOverlayChangePictures	= 1 << 1,
	/// Only the callouts' arrows moved, and they were worked out again: draw.
	LDrawStepOverlayChangeArrows	= 1 << 2
};


//------------------------------------------------------------------------------
///
/// @class      LDrawStepOverlayPresenter
///
/// @abstract   Works out what a step shows over its model: the parts list,
///             LPub3D's page and the callouts. It lays them out again when
///             the model or the camera changes.
///
/// @discussion The host tells it when something changed, and draws what it
///             lays out. On LPub3D's page it also puts each step in its place
///             on the page, and keeps the page still while the camera is
///             turned. A callout's box then moves with its submodel, from
///             where the file puts it.
///
///             In a turn the boxes may change places, and go to another side
///             of their submodels. They move there over a short time, so the
///             host lays the step out again soon while `isMovingCallouts`.
///
//------------------------------------------------------------------------------
@interface LDrawStepOverlayPresenter : NSObject

/// The model whose visible step is shown.
@property (nonatomic, weak, nullable) LDrawModel *model;

/// The view the model is drawn in. Nil while the overlay is on no view.
@property (nonatomic, weak, nullable) id<LDrawStepOverlayCamera> camera;

/// Where the page is pinned. The presenter starts with its own, and a host
/// that also fits the page gives it the shared one.
@property (nonatomic, strong) LDrawStepPartListPageAnchor *pageAnchor;

/// The size of the view the overlay covers, in points.
@property (nonatomic) Size2 viewSize;

/// Keeps what centering each step measured, for this presenter and any other
/// that shares it. Nil measures a step each time it is centered.
@property (nonatomic, strong, nullable) LDrawStepLayoutCache *layoutCache;

/// A resize drag in progress. The list is packed at this size instead of the
/// file's, so nothing is written until the drag is let go.
@property (nonatomic) BOOL hasSizePreview;
@property (nonatomic) LPubPliAxis previewAxis;
@property (nonatomic) double previewInches;

/// A callout drag in progress: which box of the step, and where its corner is
/// held, in the view.
@property (nonatomic) BOOL hasCalloutPreview;
@property (nonatomic) NSUInteger calloutPreviewBox;
@property (nonatomic) Point2 calloutPreviewPoint;

/// Collects, packs and places the visible step again.
- (void) reload;

/// Whether a callout's box was still on its way to its place in the last
/// layout. The host then reloads again in a moment, to draw it further along.
@property (nonatomic, readonly) BOOL isMovingCallouts;

/// The time a box's move is measured by, in seconds. Nil for the time the
/// system has been up. A test gives its own.
@property (nonatomic, copy, nullable) NSTimeInterval (^clock)(void);

/// What the last reload laid out. Nil before the first, and after -reset.
@property (nonatomic, readonly, nullable) LDrawStepPartListPresentation *presentation;

/// Each callout's arrows in the view: one block of LDrawStepCalloutArrow
/// values per box, in the order of the presentation's boxes.
@property (nonatomic, readonly, copy) NSArray<NSData *> *calloutArrows;

/// Puts the visible step in its place on LPub3D's page again, and keeps where
/// the middle of the page is in the page anchor. The camera is not moved: the
/// host scrolls when the page has to stay where it was on screen. Does
/// nothing with no camera, or off the page.
- (void) centerPageOnStep;

/// Call when the camera zoomed, scrolled or turned. On the page everything
/// follows the camera. Off it only the arrows do, since they point into the
/// model.
- (LDrawStepOverlayChange) changeForCameraMove;

/// Call when something a step shows may have changed. `object` is what
/// changed: a directive, or nil for something outside the file such as the
/// part library. A change in another file means nothing here.
- (LDrawStepOverlayChange) changeForChangedObject:(nullable id)object;

/// Forgets what was laid out. Call it when the overlay is taken off its view.
- (void) reset;

@end

NS_ASSUME_NONNULL_END
