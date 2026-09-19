//==============================================================================
//
//  File:       LDrawStepPartListPresentation.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>

@class LDrawModel;
@class LDrawStepPartListLayout;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @struct     LDrawStepPartListHostState
///
/// @abstract   What the host measures for one redraw: the things only a view
///             can answer.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepPartListHostState {
	/// The view the list is drawn over, in points.
	Size2		viewSize;
	/// Points per LDU the model is drawn at beside the page anchor. Only read
	/// on LPub3D's page; 0 draws no page.
	double		assemblyScale;
	/// The page anchor projected into the view, in its points, y down.
	Point2		anchorInView;
	/// A resize drag in progress, its axis and the size it asks for.
	BOOL		hasPreview;
	LPubPliAxis	previewAxis;
	double		previewInches;
} LDrawStepPartListHostState;


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPresentation
///
/// @abstract   Everything the host draws for the visible step: the page, the
///             packed list, its icon model, the chrome and the pins.
///
/// @discussion Worked out in one place because the order matters: the metrics
///             are scaled to the page before the height budget is taken from
///             it, and the document's CONSTRAIN is read only on the page.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPresentation : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// Collects, packs and places the list for the model's visible step.
+ (instancetype) presentationForModel:(nullable LDrawModel *)model
								 host:(LDrawStepPartListHostState)host
	NS_SWIFT_NAME(init(model:host:));

/// Whether the list is drawn on LPub3D's page. Only then does the document's
/// CONSTRAIN count, and only then can the frame be resized.
@property (nonatomic, readonly) BOOL isOnPage;

/// The page in the view, or `ZeroBox2` when there is none.
@property (nonatomic, readonly) Box2 pageRect;

/// Points one page inch covers, or 0 off the page.
@property (nonatomic, readonly) double pointsPerPageInch;

/// What the frame is packed against and sits in: the page, else the view.
@property (nonatomic, readonly) Size2 hostSize;

/// The frame in the view, and the icon area inside its padding. Both are
/// `ZeroBox2` when there is nothing to draw.
@property (nonatomic, readonly) Box2 frameRect;
@property (nonatomic, readonly) Box2 contentRect;

/// The values the frame is drawn with, scaled to the page when there is one.
@property (nonatomic, readonly) LDrawStepPartListChrome chrome;

/// The packed list, or nil when there is nothing to draw.
@property (nonatomic, readonly, nullable) LDrawStepPartListLayout *layout;

/// The parts placed as the layout says, for the icon view to draw, and the
/// camera that view needs to show them where the layout put them.
@property (nonatomic, readonly, nullable) LDrawModel *iconModel;
@property (nonatomic, readonly) double iconZoomPercentage;
@property (nonatomic, readonly) Point3 iconCenter;

/// Whether each axis shows a pin: set by the step's own line, or by where a
/// drag would leave it.
@property (nonatomic, readonly) BOOL widthPinned;
@property (nonatomic, readonly) BOOL heightPinned;

/// The size the step has on this axis without its own line, which a drag
/// snaps to. 0 for none, and always 0 off the page.
- (double) inheritedInchesForAxis:(LPubPliAxis)axis NS_SWIFT_NAME(inheritedInches(forAxis:));

@end

NS_ASSUME_NONNULL_END
