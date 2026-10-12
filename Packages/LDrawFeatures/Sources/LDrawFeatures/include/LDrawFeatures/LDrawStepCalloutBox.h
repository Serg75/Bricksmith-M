//==============================================================================
//
//  File:       LDrawStepCalloutBox.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubPlacement.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawFeatures/LDrawStepPartListLayout.h>

@class LDrawModel;
@class LDrawPart;
@class LDrawStep;
@class LDrawStepCallout;
@class LDrawStepCalloutStyle;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @struct     LDrawStepCalloutBoxOptions
///
/// @abstract   Everything the callout boxes need to know about where they are
///             drawn.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepCalloutBoxOptions
{
	/// The list's metrics, already scaled to the page when there is one.
	LDrawStepPartListMetrics	metrics;

	/// Points per LDU a callout's assembly is drawn at on the page.
	double						assemblyScale;

	/// The page, else the view.
	Box2						hostRect;

	/// The parts list's frame, or an empty box when the step shows none.
	Box2						listFrame;

	/// Where the step's assembly is drawn in the view, or an empty box when
	/// the host did not measure it. Only read on the page.
	Box2						assemblyRect;

	/// 0 off the page.
	double						pointsPerPageInch;

	/// The view the step's parts list shows its parts from.
	Matrix4						listViewTransform;

	/// NO when the step hides its parts list, so a box lists no parts either.
	BOOL						showsLists;

} LDrawStepCalloutBoxOptions;


//------------------------------------------------------------------------------
///
/// @struct     LDrawStepCalloutArrow
///
/// @abstract   One arrow of a callout's box, in the view: where it leaves the
///             box, and where its tip is.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepCalloutArrow
{
	Point2	start;
	Point2	tip;

} LDrawStepCalloutArrow;


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutPicture
///
/// @abstract   One picture in a callout's box, for the host to draw off screen.
///
/// @discussion The model is a throwaway one whose parts already carry the
///             view, so the camera looks straight at it, unrotated.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutPicture : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// Where the picture goes, in the view.
@property (nonatomic, readonly) Box2		rect;

/// What it shows, and the camera that puts it in `rect`.
@property (nonatomic, readonly) LDrawModel	*model;
@property (nonatomic, readonly) double		zoomPercentage;
@property (nonatomic, readonly) Point3		center;

/// Names what the picture shows. Two pictures with the same key and size look
/// the same, until the file changes.
@property (nonatomic, readonly) NSString	*contentKey;

/// Names what the picture shows whatever its size, and for a packed list how
/// it is arranged. A host that has a picture with this key can show it at
/// another size while the zoom changes.
@property (nonatomic, readonly) NSString	*subjectKey;

/// The cells the picture is packed in, for the counts and badges drawn over
/// it. Nil for a picture of one assembly.
@property (nonatomic, readonly, nullable) LDrawStepPartListLayout *layout;

/// YES for a parts list, which labels every cell. NO for submodels shown
/// finished, where one of something needs no count.
@property (nonatomic, readonly) BOOL		isPartsList;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutLabel
///
/// @abstract   One line of text in a callout's box.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutLabel : NSObject

- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly) Box2		rect;
@property (nonatomic, readonly) NSString	*text;

/// YES for the number of a step. NO for how many times the box is built.
@property (nonatomic, readonly) BOOL		isStepNumber;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutStep
///
/// @abstract   One step of a submodel as a callout's box shows it, for a host
///             that lets a divider be put before the step or taken away.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutStep : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// The step, in the called-out submodel.
@property (nonatomic, readonly) LDrawStep	*step;

/// The step's number among those the box shows of its submodel, from 1.
@property (nonatomic, readonly) NSUInteger	number;

/// The step's share of the box, in the view: its picture, number and parts,
/// and the room around them up to the next step.
@property (nonatomic, readonly) Box2		rect;

/// YES for the first step shown of a submodel. It starts a column or row
/// whatever the file says, so no divider goes before it.
@property (nonatomic, readonly) BOOL		isFirstOfSubmodel;

/// YES when a DIVIDER line makes the step start a column or row.
@property (nonatomic, readonly) BOOL		hasDividerBefore;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutBox
///
/// @abstract   One callout as the host draws it.
///
/// @discussion Off the page the box shows each called-out submodel finished,
///             with how many times it is placed. On the page it shows the
///             submodel step by step, as LPub3D does.
///
///             Geometry is in the view's points, origin top left, y down.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutBox : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// Packs one box per callout. On the page each goes where its PLACEMENT line
/// says, against the step's assembly, even when that is off the page. Off the
/// page, or with no assembly measured, they stack down the host's left edge,
/// under the list's frame when there is one, and a box that does not fit below
/// starts a new column. `model` is the step's model.
+ (NSArray<LDrawStepCalloutBox *> *) boxesForCallouts:(NSArray<LDrawStepCallout *> *)callouts
											  inModel:(nullable LDrawModel *)model
											  options:(LDrawStepCalloutBoxOptions)options
	NS_SWIFT_NAME(boxes(forCallouts:inModel:options:));

/// The box under a point of the view, or nil. Where two overlap it is the one
/// later in `boxes`, which is drawn last and so lies on top.
+ (nullable LDrawStepCalloutBox *) boxAtPoint:(Point2)point amongBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
	NS_SWIFT_NAME(box(at:among:));

@property (nonatomic, readonly) LDrawStepCallout	*callout;

/// How the file says the box looks. Nil off the page, where the host draws
/// the box its own way.
@property (nonatomic, readonly, nullable) LDrawStepCalloutStyle *style;

/// The box in the view.
@property (nonatomic, readonly) Box2				frameRect;

/// The pictures in the box, in drawing order.
@property (nonatomic, readonly) NSArray<LDrawStepCalloutPicture *>	*pictures;

/// The step numbers and the count, when the box shows steps.
@property (nonatomic, readonly) NSArray<LDrawStepCalloutLabel *>	*labels;

/// The lines between groups of steps. Each is a thin box to fill.
@property (nonatomic, readonly) NSUInteger			dividerCount;
- (Box2) dividerRectAtIndex:(NSUInteger)index NS_SWIFT_NAME(dividerRect(at:));

/// How many steps build the box's submodels, for a box that shows them
/// finished. 0 when the box shows the steps, or there is only one.
@property (nonatomic, readonly) NSUInteger			summarizedStepCount;

/// The steps the box shows, in order. Empty for a box that shows its
/// submodels finished.
@property (nonatomic, readonly) NSArray<LDrawStepCalloutStep *>	*steps;

/// The step at a point of the view, or nil. A point between two columns or
/// rows, on the line or in the room beside it, gives the step after the line.
- (nullable LDrawStepCalloutStep *) stepAtPoint:(Point2)point NS_SWIFT_NAME(step(at:));

/// The submodel the box shows at a point of the view: the one whose step, or
/// whose picture among those shown finished, is there. For a point between
/// them or beside them it is the nearest. Nil for a box that shows nothing.
- (nullable LDrawModel *) submodelAtPoint:(Point2)point NS_SWIFT_NAME(submodel(at:));

/// How many arrows the box has: one for each POINTER line of the callout, up
/// to one for each placement. A callout with no such line has none.
@property (nonatomic, readonly) NSUInteger			tipCount;

/// The middle of what a part places, in the part's model. Where the part is
/// placed when it cannot be measured.
+ (Point3) middleOfPlacement:(LDrawPart *)part NS_SWIFT_NAME(middle(ofPlacement:));

/// What an arrow is aimed at, in the step's model: the middle of a placement.
/// The host projects it into the view.
- (Point3) tipModelPointAtIndex:(NSUInteger)index NS_SWIFT_NAME(tipModelPoint(at:));

/// The points the placement an arrow goes to reaches furthest out to, in the
/// step's model, as Point3 values. The host projects them into the view.
/// Empty when the placement cannot be measured.
- (NSData *) tipOutlinePointsAtIndex:(NSUInteger)index NS_SWIFT_NAME(tipOutlinePoints(at:));

/// The box's arrows in the view, as LDrawStepCalloutArrow values. `middles`
/// holds the middle of each placement, and `outlines` each placement's outline
/// points, both as Point2 values, as the host projects them.
///
/// An arrow leaves the box at the point of its edge nearest the middle, but
/// never at a corner. Arrows that would leave an edge closer than a small
/// space leave it that far apart, in the order that keeps them from crossing.
/// Each runs toward its middle, and stops a little short of where it first
/// meets the outline. With no outline to stop at, its tip is the middle. A
/// middle inside the box gets no arrow.
- (NSData *) arrowsToMiddles:(NSData *)middles outlines:(NSArray<NSData *> *)outlines
	NS_SWIFT_NAME(arrows(toMiddles:outlines:));

/// YES when the box sits where its PLACEMENT line says, or where LPub3D puts
/// a box with no such line. Only then can it be dragged. NO for a box placed
/// against something that is not drawn here, where the assembly stands in.
@property (nonatomic, readonly) BOOL				isPlacedByFile;

/// The offset a PLACEMENT line needs for the box's corner to land at `origin`.
/// On the page the step is centered again once the line is written, which
/// moves the assembly when the box was centered with it. The offset allows
/// for that, so the box is at `origin` afterwards. NO when the box is not
/// placed by the file, or what it is placed against has no size.
- (BOOL) getPlacementOffset:(Point2 *)outOffset forOrigin:(Point2)origin
	NS_SWIFT_NAME(getPlacementOffset(_:forOrigin:));

@end

NS_ASSUME_NONNULL_END
