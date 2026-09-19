//==============================================================================
//
//  File:       LDrawStepPartListPolicy.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubModelScale.h>

#import <LDrawFeatures/LDrawStepPartListLayout.h>

@class LDrawDirective;
@class LDrawStep;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepPartListHandle
///
/// @abstract   What the pointer is over, and so what a drag from here would
///             resize.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepPartListHandle) {
	LDrawStepPartListHandleNone		= 0,
	LDrawStepPartListHandleWidth	= 1,
	LDrawStepPartListHandleHeight	= 2
};


//------------------------------------------------------------------------------
///
/// @enum       LDrawStepPartListControl
///
/// @abstract   Which of the frame's controls is under the pointer: an edge to
///             drag, or a pin to click.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepPartListControl) {
	LDrawStepPartListControlNone		= 0,
	LDrawStepPartListControlWidthEdge	= 1,
	LDrawStepPartListControlHeightEdge	= 2,
	LDrawStepPartListControlWidthPin	= 3,
	LDrawStepPartListControlHeightPin	= 4
};


//------------------------------------------------------------------------------
///
/// @struct     LDrawStepPartListChrome
///
/// @abstract   The values the frame is drawn with. Colors are RGBA floats and
///             fonts a point size, because no AppKit or UIKit type may appear
///             in a package header.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepPartListChrome
{
	double	borderRGBA[4];
	double	labelRGBA[4];
	/// Fill and outline of the size badge for a part the packer shrank.
	double	markerRGBA[4];

	/// The size badge is a filled, outlined pill, never bare text, so it is not
	/// read as a second multiplier. For a part the packer shrank it uses the
	/// marker color instead, with the fill color as its text.
	double	annotationFillRGBA[4];
	double	annotationBorderRGBA[4];
	double	annotationTextRGBA[4];

	/// Dashed outline of the page LPub3D would print on. Kept faint, since it
	/// sits behind the model and is not part of it.
	double	pageRGBA[4];

	/// Laid over everything outside that page, to show what will not print.
	double	pageSurroundRGBA[4];

	double	borderWidth;
	double	cornerRadius;
	double	labelPointSize;
	double	annotationPointSize;

	/// Length of one dash, and of the gap after it, in the page outline.
	double	pageDashLength;

	/// Line width of the page outline, kept apart from the frame border.
	double	pageLineWidth;

	/// Dash and gap of the box drawn where a missing part would be.
	double	placeholderDashLength;
	double	placeholderGapLength;

} LDrawStepPartListChrome;


//------------------------------------------------------------------------------
///
/// @struct     LDrawStepPartListBadgeStyle
///
/// @abstract   The colors one size badge is drawn with.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepPartListBadgeStyle
{
	double	fillRGBA[4];
	double	borderRGBA[4];
	double	textRGBA[4];

} LDrawStepPartListBadgeStyle;


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPolicy
///
/// @abstract   Where the frame goes, how big it may get, and what it is drawn
///             with.
///
/// @discussion This class makes the decisions. The view only draws what it is
///             given.
///
///             Geometry is in points, with the origin at the top left and y
///             growing downward, as in the layout. A flipped AppKit view can
///             use these boxes as they are.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPolicy : NSObject

// MARK: - Placement
//
// `pointsPerPageInch` is 0 when the host is not LPub3D's page.
// On the page the margin and the room are LPub3D's, in page inches: 0.05 in in
// from the corner, and the whole page less that margin. Otherwise a 12 point
// margin, and at most four tenths of the view's width and six tenths of its
// height.

/// Where a frame of this size sits in a host view: the top-left corner, inset
/// by the margin.
+ (Box2) frameRectForFrameSize:(Size2)frameSize
					inHostSize:(Size2)hostSize
			 pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(frameRect(forFrameSize:inHostSize:pointsPerPageInch:));

// MARK: - Fitting the host

/// The same metrics, with the height limit taken from the host. Run it after
/// scaling, so the budget leaves room for the padding the frame is drawn with.
/// A host with no room left gives a budget of 1 point, not 0, which the packer
/// reads as no limit.
+ (LDrawStepPartListMetrics) metrics:(LDrawStepPartListMetrics)metrics
					 fittingHostSize:(Size2)hostSize
				   pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(metrics(_:fittingHostSize:pointsPerPageInch:));

/// The constraint to pack with.
///
/// A `WIDTH` too wide for the host is narrowed here only. The document keeps
/// the value that was written, so a model does not change because of the size
/// of the window that opened it. A drag stops at the same width, so it never
/// writes one wider.
+ (LDrawStepPartListConstraint) constraint:(LDrawStepPartListConstraint)constraint
						 clampedToHostSize:(Size2)hostSize
							 pointsPerInch:(double)pointsPerInch
						 pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(constraint(_:clampedToHostSize:pointsPerInch:pointsPerPageInch:));

// MARK: - Drawing values

+ (LDrawStepPartListChrome) defaultChrome;

/// The frame's own background: the viewport's color moved a tenth of the way
/// to white over a dark viewport, or to black over a light one. Both are sRGB.
+ (void) getListBackgroundRGBA:(double *)outRGBA forViewportRGBA:(const double *)viewportRGBA
	NS_SWIFT_NAME(getListBackgroundRGBA(_:forViewportRGBA:));

/// The colors of a size badge. A part the packer drew smaller gets the marker
/// color, with the fill color as its text.
+ (LDrawStepPartListBadgeStyle) badgeStyleForScaledDownPart:(BOOL)isScaledDown
													 chrome:(LDrawStepPartListChrome)chrome
	NS_SWIFT_NAME(badgeStyle(forScaledDownPart:chrome:));

/// Where the notice of parts left out goes: along the top of the icon area,
/// where the dropped rows would have been, one label high.
+ (Box2) overflowNoticeRectForContentWidth:(double)contentWidth chrome:(LDrawStepPartListChrome)chrome
	NS_SWIFT_NAME(overflowNoticeRect(forContentWidth:chrome:));


// MARK: - Resizing
//
// Hit-testing and drag arithmetic for any host.

/// What a drag starting at this point would resize. Points are in the same
/// space as `frame`. Where the edges meet, the nearer edge wins, since a
/// CONSTRAIN holds one size.
+ (LDrawStepPartListHandle) handleAtPoint:(Point2)point inFrame:(Box2)frame
	NS_SWIFT_NAME(handle(at:inFrame:));

/// Where an axis's indicator pin sits: the midpoint of the edge it pins.
+ (Box2) pinRectForAxis:(LPubPliAxis)axis inFrame:(Box2)frame
	NS_SWIFT_NAME(pinRect(forAxis:inFrame:));

/// The control under this point. A drawn pin beats the edge it sits on, and
/// only a pinned axis has a pin to click.
+ (LDrawStepPartListControl) controlAtPoint:(Point2)point
									inFrame:(Box2)frame
								widthPinned:(BOOL)widthPinned
							   heightPinned:(BOOL)heightPinned
	NS_SWIFT_NAME(control(at:inFrame:widthPinned:heightPinned:));

/// Where a drag grabbed at `point` measures its size from: the point less the
/// smallest size the list packs the same at (`resizeStartSize`). Pass it as
/// `origin` for the whole drag, so the frame does not jump when grabbed.
+ (Point2) dragOriginForAxis:(LPubPliAxis)axis
			  grabbedAtPoint:(Point2)point
					  layout:(nullable LDrawStepPartListLayout *)layout
	NS_SWIFT_NAME(dragOrigin(forAxis:grabbedAt:layout:));

/// The frame size, in inches, that dragging a handle to this point asks for.
/// `origin` is where the size is measured from, and `layout` is the list on
/// show. Clamped to the band that can be written, whose top applies only off
/// the page, then to what can be drawn: the room on the host, and the sizes
/// past which the frame is drawn the same. A width stops at one shelf holding
/// every part. A height stops between that one shelf and the packing as wide as
/// the widest cell. 0 with no layout.
///
/// `inheritedInches` is the size the step inherits on this axis, or 0 for
/// none. A size within a few points of it on screen becomes exactly that size,
/// so letting go there removes the step's line. An inherited size past a stop
/// is not snapped to, and the drag stays at the stop.
+ (double) inchesForDraggingAxis:(LPubPliAxis)axis
						 toPoint:(Point2)point
					  fromOrigin:(Point2)origin
						  layout:(nullable LDrawStepPartListLayout *)layout
						hostSize:(Size2)hostSize
			   pointsPerPageInch:(double)pointsPerPageInch
				 inheritedInches:(double)inheritedInches
	NS_SWIFT_NAME(inches(forDraggingAxis:toPoint:fromOrigin:layout:hostSize:pointsPerPageInch:inheritedInches:));


// MARK: - Pins

/// The step's own CONSTRAIN: its last CONSTRAIN, when that line holds for this
/// step alone, or nil. It does when it or an earlier CONSTRAIN in the step is
/// LOCAL. A line that carries on to later steps is never the step's own.
+ (nullable LPubPliConstrain *) constrainDirectiveInStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(constrainDirective(inStep:));

/// The step's own CONSTRAIN with `excluded` read as if it were not there, so a
/// caller can ask what is left after removing a line.
+ (nullable LPubPliConstrain *) constrainDirectiveInStep:(nullable LDrawStep *)step
											   excluding:(nullable LDrawDirective *)excluded
	NS_SWIFT_NAME(constrainDirective(inStep:excluding:));

/// How the visible step's list is packed on the page: the CONSTRAIN in force
/// for it, else AREA, as in LPub3D.
+ (LDrawStepPartListConstraint) constraintForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(constraint(forVisibleStepOfModel:));

/// How the list is packed off the page, where the document's CONSTRAIN lines
/// are ignored: shelves as wide as four tenths of the view.
+ (LDrawStepPartListConstraint) viewportConstraintForHostSize:(Size2)hostSize
												pointsPerInch:(double)pointsPerInch
	NS_SWIFT_NAME(viewportConstraint(forHostSize:pointsPerInch:));

/// The size, in inches, the visible step is pinned to on this axis without its
/// own line: the CONSTRAIN in force with that line left out, if it pins the
/// axis, else 0. A drag snaps to this, and a resize compares against it to
/// decide whether the step needs a line of its own.
+ (double) inheritedInchesForAxis:(LPubPliAxis)axis inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(inheritedInches(forAxis:inModel:));

// MARK: - Metas in force

/// Runs the block with the walk into each submodel kept, so the lookups of one
/// redraw walk the file once. The file must not change inside the block.
+ (void) performWithCachedLookups:(void (NS_NOESCAPE ^)(void))block
	NS_SWIFT_NAME(withCachedLookups(_:));

/// The line of one kind in force for a step, read as LPub3D reads it, or nil.
/// A LOCAL line, and any later line of its kind in that step, holds for the
/// step. Any other line holds from where it is written. A submodel starts from
/// what held where it is first placed, and its lines never reach its parent.
/// Only `!LPUB` lines carry into a submodel. `excluded` is read as if it were
/// not there.
+ (nullable __kindof LDrawDirective *) directiveInForceForStep:(nullable LDrawStep *)step
													excluding:(nullable LDrawDirective *)excluded
													 matching:(BOOL (NS_NOESCAPE ^)(LDrawDirective *directive))predicate
	NS_SWIFT_NAME(directiveInForce(forStep:excluding:matching:));

/// The scale LPub3D would draw one kind of picture at, as a multiplier on life
/// size: the `MODEL_SCALE` for that branch in force for the visible step, else
/// 1.
+ (float) modelScaleForBranch:(LPubModelScaleBranch)branch inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(modelScale(forBranch:inModel:));

/// The view LPub3D would draw this step's parts list icons from: the
/// `PLI CAMERA_ANGLES` (or legacy `VIEW_ANGLE`) in force for the visible step,
/// else latitude 23, longitude -45. The `PLI PART_ROTATION` in force is applied
/// to the part first. An ABS rotation replaces the camera angles unless they
/// name a custom viewpoint.
+ (Matrix4) partListViewTransformInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(partListViewTransform(inModel:));

/// The angle the icons are drawn at: the visible step's own rotation, or the
/// parts list angle above when the preference says not to follow the step.
+ (Matrix4) viewTransformForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(viewTransform(forVisibleStepOfModel:));

/// The page LPub3D would print this document on, in inches, with `PAGE
/// ORIENTATION` applied. The orientation says which measurement is the long
/// side. Zero when the document names its page instead of measuring it.
/// Measurements are read in the `RESOLUTION` unit, so a DPCM file is in
/// centimeters.
+ (Size2) pageSizeInInchesInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(pageSizeInInches(inModel:));

// MARK: - Page space
//
// Sizes on LPub3D's page, all taken from the zoom the assembly is drawn at.

/// How many points one page inch covers when the viewport draws the assembly
/// at `pointsPerLDU`. Multiply a page length in inches by it to get points.
+ (double) pointsPerPageInchForAssemblyScale:(double)pointsPerLDU inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(pointsPerPageInch(forAssemblyScale:inModel:));

/// Points per LDU at which the whole of the document's page fits in the host,
/// less a 6 point margin. Zero when the document does not measure its page.
+ (double) assemblyScaleFittingPageInHostSize:(Size2)hostSize inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(assemblyScaleFittingPage(inHostSize:inModel:));

/// The model point the page is centered on: the middle of every step, leaving
/// out groups removed by the step on display. Taken from the steps on display
/// only, the page would slide across the window as the model grows.
///
/// Keep the result with LDrawStepPartListPageAnchor instead of measuring each
/// time.
+ (Point3) pageAnchorInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(pageAnchor(inModel:));

/// Whether the step on display is drawn on LPub3D's page: Steps mode, the list
/// and the page preference are on, and the file measures its page. A step that
/// hides its list still has its page.
+ (BOOL) drawsPageInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(drawsPage(inModel:));

/// Whether the host shows anything for the step on display: its list, its
/// page, or both.
+ (BOOL) showsListOrPageInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(showsListOrPage(inModel:));

/// The page, centered on `center`, at the size it takes when the assembly is
/// drawn at `pointsPerLDU`. `ZeroBox2` when the document does not measure its
/// page.
///
/// The center is a point in the host view. Get it by projecting a model point,
/// so the page moves with the step when the user pans.
+ (Box2) pageRectCenteredOn:(Point2)center
			  assemblyScale:(double)pointsPerLDU
					inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(pageRect(centeredOn:assemblyScale:inModel:));

/// The same metrics with their lengths restated in page inches, and
/// `pointsPerInch` set to `pointsPerPageInch`. `framePadding` is LPub3D's parts
/// list border margin and line, 0.08125 in. `maximumHeight` is left as it was,
/// so fit it to the host afterwards.
///
/// Without this the icons would grow with the zoom while the text and padding
/// stayed fixed, so the frame would change shape at every zoom step.
+ (LDrawStepPartListMetrics) metrics:(LDrawStepPartListMetrics)metrics
		   scaledToPointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(metrics(_:scaledToPointsPerPageInch:));

/// The same chrome with its point sizes restated in page inches, so the text
/// matches the room the packer kept for it. The lines are LPub3D's: a square
/// 1/32 in border and a 1/48 in page outline.
+ (LDrawStepPartListChrome) chrome:(LDrawStepPartListChrome)chrome
		 scaledToPointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(chrome(_:scaledToPointsPerPageInch:));

/// Points per LDU for the parts list icons when the viewport draws the
/// assembly at `pointsPerLDU`, keeping the proportion LPub3D would print. Zero
/// when `pointsPerLDU` or the assembly scale is not above zero.
+ (double) partListScaleForAssemblyScale:(double)pointsPerLDU inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(partListScale(forAssemblyScale:inModel:));

/// Whether the step's own CONSTRAIN pins this axis: a `WIDTH` for the width
/// axis, or `HEIGHT` for the height axis. The frame's pins show this and
/// clicking one clears it.
+ (BOOL) isAxis:(LPubPliAxis)axis pinnedInStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(isAxis(_:pinnedInStep:));

@end

NS_ASSUME_NONNULL_END
