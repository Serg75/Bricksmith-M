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
@class LDrawStepCalloutBox;
@class LDrawStepPartListEntry;
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
	/// Where the model point the page is kept centered on lands in the view,
	/// in its points, y down.
	Point2		pageCenterInView;
	/// The box around the step's assembly as the view draws it, or an empty
	/// box when it was not measured. Only read on the page, to place callouts
	/// and to center the page.
	Box2		assemblyRect;
	/// A resize drag in progress, its axis and the size it asks for.
	BOOL		hasPreview;
	LPubPliAxis	previewAxis;
	double		previewInches;
	/// A callout drag in progress: which box of the step, and where its corner
	/// is held, in the view.
	BOOL		hasCalloutPreview;
	NSUInteger	calloutPreviewBox;
	Point2		calloutPreviewPoint;
} LDrawStepPartListHostState;


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPresentation
///
/// @abstract   Everything the host draws for the visible step: the page, the
///             packed list, its icon model, the chrome, the pins and the
///             callouts.
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

/// Where the middle of the page belongs for this step, in the view. LPub3D
/// takes one box around the assembly and the callouts placed against it that
/// have not been dragged, and puts that box where the `ASSEM PLACEMENT` line
/// says: in the middle of the page when there is no such line. The page itself
/// is drawn where the host keeps it, so the host moves it here when the step
/// is to be centered. NO off the page, and with no assembly measured.
@property (nonatomic, readonly) BOOL hasStepCenter;
@property (nonatomic, readonly) Point2 stepCenterInView;

/// The text of the PLACEMENT lines that say where the step's assembly and
/// callouts go on the page, with the way each callout's steps run, which of
/// them follow a divider, and the size of each box that is centered with the
/// assembly. A host compares it, to know when the step has to be centered
/// again. Empty off the page.
@property (nonatomic, readonly) NSString *placementKey;

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

/// The row of the list whose cell is under a point of the view, or nil.
- (nullable LDrawStepPartListEntry *) entryAtPoint:(Point2)point NS_SWIFT_NAME(entry(at:));

/// The parts placed as the layout says, for the icon view to draw, and the
/// camera that view needs to show them where the layout put them.
@property (nonatomic, readonly, nullable) LDrawModel *iconModel;
@property (nonatomic, readonly) double iconZoomPercentage;
@property (nonatomic, readonly) Point3 iconCenter;

/// One box per callout of the step, stacked under the frame. Empty when the
/// step has none.
@property (nonatomic, readonly) NSArray<LDrawStepCalloutBox *> *calloutBoxes;

/// The callout's box under a point of the view, or nil. Where two overlap it
/// is the one drawn last, which is the one on top.
- (nullable LDrawStepCalloutBox *) calloutBoxAtPoint:(Point2)point NS_SWIFT_NAME(calloutBox(at:));

/// Whether each axis shows a pin: set by the step's own line, or by where a
/// drag would leave it.
@property (nonatomic, readonly) BOOL widthPinned;
@property (nonatomic, readonly) BOOL heightPinned;

/// The size the step has on this axis without its own line, which a drag
/// snaps to. 0 for none, and always 0 off the page.
- (double) inheritedInchesForAxis:(LPubPliAxis)axis NS_SWIFT_NAME(inheritedInches(forAxis:));

@end

NS_ASSUME_NONNULL_END
