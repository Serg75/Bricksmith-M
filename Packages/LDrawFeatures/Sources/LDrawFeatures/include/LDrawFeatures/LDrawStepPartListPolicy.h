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
@class LPubPliCameraAngles;
@class LPubPlacement;

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
	LDrawStepPartListControlNone			= 0,
	LDrawStepPartListControlWidthEdge		= 1,
	LDrawStepPartListControlHeightEdge		= 2,
	LDrawStepPartListControlWidthPin		= 3,
	LDrawStepPartListControlHeightPin		= 4,
	LDrawStepPartListControlPlacementPin	= 5
};


//------------------------------------------------------------------------------
///
/// @enum       LDrawStepPartListFill
///
/// @abstract   What the frame is filled with. The host's icons are drawn on the
///             same color, so it shows behind the parts as well.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepPartListFill) {
	/// The host's own list background. Off the page.
	LDrawStepPartListFillHost	= 0,
	/// `fillRGBA`, from the file or LPub3D's white.
	LDrawStepPartListFillColor	= 1,
	/// Nothing: the file makes the list see-through.
	LDrawStepPartListFillClear	= 2
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

	/// Laid over everything outside the page LPub3D would print on, to show
	/// what will not print.
	double	pageSurroundRGBA[4];

	double	borderWidth;
	double	cornerRadius;
	double	labelPointSize;
	/// The callouts' titles and step badges. On the page it is also the size
	/// badges', when the file gives their font.
	double	annotationPointSize;

	/// Dash and gap of the box drawn where a missing part would be.
	double	placeholderDashLength;
	double	placeholderGapLength;

	/// The frame's fill, and its color when that is `LDrawStepPartListFillColor`.
	LDrawStepPartListFill	fill;
	double					fillRGBA[4];

	/// How the frame's outline is drawn, numbered as LPubLineStyle. A width of
	/// 0 draws none.
	NSInteger				borderLineStyle;

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

/// How far the frame sits in from the host's corner: LPub3D's margin on the
/// page, a fixed one in the view. `pointsPerPageInch` is 0 off the page.
+ (double) frameInsetForPointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(frameInset(forPointsPerPageInch:));

/// Where a frame of this size sits in a host view: the top-left corner, inset
/// by the margin.
+ (Box2) frameRectForFrameSize:(Size2)frameSize
					inHostSize:(Size2)hostSize
			 pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(frameRect(forFrameSize:inHostSize:pointsPerPageInch:));

// MARK: - Fitting the host

/// The most room the frame may take on each axis, in points: the page less
/// LPub3D's margins, or a share of the view off the page. A host with margins
/// of its own passes its own room to the calls below instead.
+ (Size2) allowedFrameSizeInHostSize:(Size2)hostSize pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(allowedFrameSize(inHostSize:pointsPerPageInch:));

/// The same metrics, with the height limit taken from the room the frame may
/// take. Run it after scaling, so the budget leaves room for the padding the
/// frame is drawn with. No room left gives a budget of 1 point, not 0, which
/// the packer reads as no limit.
+ (LDrawStepPartListMetrics) metrics:(LDrawStepPartListMetrics)metrics
				  fittingAllowedSize:(Size2)allowedSize
	NS_SWIFT_NAME(metrics(_:fittingAllowedSize:));

/// The constraint to pack with, a `WIDTH` narrowed to `allowedWidth` points.
///
/// It is narrowed here only. The document keeps the value that was written, so
/// a model does not change because of the size of the window that opened it. A
/// drag stops at the same width, so it never writes one wider.
+ (LDrawStepPartListConstraint) constraint:(LDrawStepPartListConstraint)constraint
					 clampedToAllowedWidth:(double)allowedWidth
							 pointsPerInch:(double)pointsPerInch
	NS_SWIFT_NAME(constraint(_:clampedToAllowedWidth:pointsPerInch:));

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

/// Where the pin of the step's own placement sits: the frame's top left
/// corner, which is the corner that stays put in this space.
+ (Box2) placementPinRectInFrame:(Box2)frame NS_SWIFT_NAME(placementPinRect(inFrame:));

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
/// the page, then to what can be drawn: `allowedSize`, in points, and the
/// sizes past which the frame is drawn the same. A width stops at one shelf holding
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
					 allowedSize:(Size2)allowedSize
			   pointsPerPageInch:(double)pointsPerPageInch
				 inheritedInches:(double)inheritedInches
	NS_SWIFT_NAME(inches(forDraggingAxis:toPoint:fromOrigin:layout:allowedSize:pointsPerPageInch:inheritedInches:));


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

/// The angle the visible step is seen at: on LPub3D's page the angle LPub3D
/// prints it at, else the step's own rotation.
+ (Tuple3) viewingAngleForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(viewingAngle(forVisibleStepOf:));

/// The angle LPub3D draws a step's assembly at, in degrees, as a viewport's
/// viewing angle: the step's ROTSTEP, then the `ASSEM CAMERA_ANGLES` in force
/// for the step in place of Bricksmith's 3D view. With no such line it is the
/// model's own angle. An ABS rotation keeps no camera angles unless they name
/// a custom viewpoint.
+ (Tuple3) assemblyViewingAngleForStepAtIndex:(NSUInteger)stepIndex inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(assemblyViewingAngle(forStepAt:inModel:));

/// Whether the rotation a step is seen at comes from an ABS ROTSTEP: the last
/// REL, ABS or END up to the step is an ABS.
+ (BOOL) isAbsoluteRotationAtStepIndex:(NSUInteger)stepIndex inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(isAbsoluteRotation(atStep:inModel:));

/// The turn a step's ROTSTEP gives the parts, with no view after it. The
/// identity for a step with no rotation.
+ (Matrix4) assemblyRotationForStepAtIndex:(NSUInteger)stepIndex inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(assemblyRotation(forStepAt:inModel:));

/// The view a camera line puts after the rotation. With no line it is
/// Bricksmith's 3D view, LPub3D's default of 23, 45.
+ (Matrix4) assemblyCameraForAngles:(nullable LPubPliCameraAngles *)angles
	NS_SWIFT_NAME(assemblyCamera(for:));

/// The `ASSEM CAMERA_ANGLES` line in force for a step, reading the lines in
/// `excluded` as if they were not there.
+ (nullable LPubPliCameraAngles *) assemblyCameraAnglesForStepAtIndex:(NSUInteger)stepIndex
															  inModel:(nullable LDrawModel *)model
															excluding:(nullable NSArray<LDrawDirective *> *)excluded
	NS_SWIFT_NAME(assemblyCameraAngles(forStepAt:inModel:excluding:));

/// What LPub3D's camera sees: the parts turned, then the camera. Under an ABS
/// rotation the camera looks straight on, unless the line names a custom
/// viewpoint.
+ (Matrix4) assemblyViewWithRotation:(Matrix4)rotation
							  camera:(nullable LPubPliCameraAngles *)angles
						  isAbsolute:(BOOL)isAbsolute
	NS_SWIFT_NAME(assemblyView(rotation:camera:isAbsolute:));

/// A rotation as a viewport's viewing angle, in degrees.
+ (Tuple3) viewingAngleForView:(Matrix4)view NS_SWIFT_NAME(viewingAngle(forView:));

/// A viewing angle as LPub3D's camera angles after the visible step's
/// rotation, in degrees. NO when the view is tilted to one side.
+ (BOOL) getAssemblyLatitude:(double *)latitude
				   longitude:(double *)longitude
			 forViewingAngle:(Tuple3)angle
					 inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(getAssemblyLatitude(_:longitude:forViewingAngle:inModel:));

/// The viewing angle of LPub3D's camera at these angles after the visible
/// step's rotation.
+ (Tuple3) assemblyViewingAngleForLatitude:(double)latitude
								 longitude:(double)longitude
								   inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(assemblyViewingAngle(latitude:longitude:inModel:));

/// The page LPub3D would print this document on, in inches, with `PAGE
/// ORIENTATION` applied. The orientation says which measurement is the long
/// side. Zero when the document names its page instead of measuring it.
/// Measurements are read in the `RESOLUTION` unit, so a DPCM file is in
/// centimeters.
+ (Size2) pageSizeInInchesInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(pageSizeInInches(inModel:));

/// The page as a host of this size shows it, in inches. The document's page,
/// grown to the host's shape when the page follows it (see
/// +[LDrawStepPartList pageFollowsHostShape]). Zero when the document does not
/// measure its page.
+ (Size2) pageSizeInInchesInModel:(nullable LDrawModel *)model forHostSize:(Size2)hostSize
	NS_SWIFT_NAME(pageSizeInInches(inModel:forHostSize:));

/// The `ASSEM PLACEMENT` line in force for the visible step, or nil. It says
/// where on the page LPub3D puts the step's assembly.
+ (nullable LPubPlacement *) assemblyPlacementForVisibleStepOfModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(assemblyPlacement(forVisibleStepOf:));

/// How many inches one of the file's measuring units is: 1, or 1/2.54 for a
/// file whose `RESOLUTION` is in dots per centimeter.
+ (double) inchesPerUnitInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(inchesPerUnit(inModel:));

/// How many inches one dot is at the file's `RESOLUTION`. LPub3D prints 150
/// dots to the inch when a file says nothing.
+ (double) inchesPerDotInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(inchesPerDot(inModel:));

/// How many models deep a model sits under the file's first one, by the
/// placement LPub3D comes to first. 0 for the first model, and for a model
/// placed nowhere.
+ (NSUInteger) submodelDepthOfModel:(nullable LDrawModel *)model NS_SWIFT_NAME(submodelDepth(of:));

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

/// How many points an inch of the page covers when the whole page fits in the
/// host, less a 6 point margin. Zero when the document does not measure its
/// page.
+ (double) pointsPerPageInchFittingPageInHostSize:(Size2)hostSize inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(pointsPerPageInchFittingPage(inHostSize:inModel:));

/// The model point the page is centered on: the middle of every step, leaving
/// out groups removed by the step on display. Taken from the steps on display
/// only, the page would slide across the window as the model grows.
///
/// Keep the result with LDrawStepPartListPageAnchor instead of measuring each
/// time.
+ (Point3) pageAnchorInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(pageAnchor(inModel:));

/// The box around every step of the model, whichever are on display.
/// InvalidBox for a model with nothing to measure.
+ (Box3) boundsOfAllStepsInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(boundsOfAllSteps(inModel:));

/// The points the parts the model has on display reach furthest out to, as
/// Point3 values in the model's coordinates. The host projects them to find
/// where the assembly is drawn. Nil with nothing to measure, or no part
/// catalog.
+ (nullable NSData *) assemblyOutlinePointsInModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(assemblyOutlinePoints(inModel:));

/// The points the parts of the steps before the one on display reach furthest
/// out to, in the model's coordinates. Nil with none, or with no catalog.
+ (nullable NSData *) earlierAssemblyOutlinePointsInModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(earlierAssemblyOutlinePoints(inModel:));

/// Whether the step on display is drawn on LPub3D's page: Steps mode, the list
/// and the page preference are on, and the file measures its page. A step that
/// hides its list still has its page.
+ (BOOL) drawsPageInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(drawsPage(inModel:));

/// Whether the host shows anything for the step on display: its list, its
/// page or its callouts.
+ (BOOL) showsAnythingInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(showsAnything(inModel:));

/// The page, centered on `center`, at the size it takes when the assembly is
/// drawn at `pointsPerLDU`, in a host of `hostSize`. `ZeroBox2` when the
/// document does not measure its page.
///
/// The center is a point in the host view. Get it by projecting a model point,
/// so the page moves with the step when the user pans.
+ (Box2) pageRectCenteredOn:(Point2)center
			  assemblyScale:(double)pointsPerLDU
				   hostSize:(Size2)hostSize
					inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(pageRect(centeredOn:assemblyScale:hostSize:inModel:));

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
/// matches the room the packer kept for it. The border is LPub3D's square
/// 1/32 in line.
+ (LDrawStepPartListChrome) chrome:(LDrawStepPartListChrome)chrome
		 scaledToPointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(chrome(_:scaledToPointsPerPageInch:));

/// Points per LDU for the parts list icons when the viewport draws the
/// assembly at `pointsPerLDU`, keeping the proportion LPub3D would print. Zero
/// when `pointsPerLDU` or the assembly scale is not above zero.
+ (double) partListScaleForAssemblyScale:(double)pointsPerLDU inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(partListScale(forAssemblyScale:inModel:));

/// How wide the parts are outlined on the page, in points, so they read as in
/// printed instructions. It grows with the zoom up to 2 points. 0 when
/// `pointsPerPageInch` is 0.
+ (double) outlineWidthForPointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(outlineWidth(forPointsPerPageInch:));

/// Whether the step's own CONSTRAIN pins this axis: a `WIDTH` for the width
/// axis, or `HEIGHT` for the height axis. The frame's pins show this and
/// clicking one clears it.
+ (BOOL) isAxis:(LPubPliAxis)axis pinnedInStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(isAxis(_:pinnedInStep:));

/// Whether the step places its list itself: it has a `LOCAL` `PLI PLACEMENT`
/// line. The frame's corner pin shows this and clicking it clears it.
+ (BOOL) isPlacementPinnedInStep:(nullable LDrawStep *)step NS_SWIFT_NAME(isPlacementPinned(inStep:));

@end

NS_ASSUME_NONNULL_END
