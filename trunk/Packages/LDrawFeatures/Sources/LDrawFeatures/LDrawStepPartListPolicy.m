//==============================================================================
//
//  File:       LDrawStepPartListPolicy.m
//  Package:    LDrawFeatures
//
//  Purpose:    Where the parts list frame goes and what it is drawn with.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListPolicy.h>

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/LPubModelScale.h>
#import <LDrawCore/LPubPageOrientation.h>
#import <LDrawCore/LPubPageSize.h>
#import <LDrawCore/LPubPliCameraAngles.h>
#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawCore/LPubPliIgnore.h>
#import <LDrawCore/LPubPliPartRotation.h>
#import <LDrawCore/LPubResolution.h>

#import <LDrawFeatures/LDrawStepPartList.h>


static const double VIEWPORT_MARGIN						= 12.0;
static const double MAXIMUM_VIEWPORT_WIDTH_FRACTION		= 0.4;
static const double MAXIMUM_VIEWPORT_HEIGHT_FRACTION	= 0.6;

/// The walk into each submodel, kept while -performWithCachedLookups: runs.
static NSMapTable<LDrawModel *, id>	*PathCache		= nil;
static NSUInteger					 PathCacheDepth	= 0;

/// How far the frame's background is moved from the viewport's, as a fraction
/// of the way to white or black.
static const double BACKGROUND_CONTRAST				= 0.10;

/// LPub3D's default page, parts list and border margin, in inches.
static const double LPUB_MARGIN_INCHES					= 0.05;

/// Points left clear around the page when it is fitted to a view, so its edges
/// stay off the view's border.
static const double PAGE_FIT_MARGIN						= 6.0;

/// LPub3D's default parts list border line, in inches.
static const double LPUB_BORDER_INCHES					= 1.0 / 32.0;

/// LPub3D's line around a transparent page in its editor, in inches.
static const double LPUB_PAGE_GUIDE_INCHES				= 1.0 / 48.0;

/// CONSTRAIN is written with four decimals.
static const double WRITTEN_INCHES_STEP					= 0.0001;

/// How far either side of an edge counts as grabbing it, and how big the
/// indicator pin drawn at an edge's midpoint is.
static const double RESIZE_HANDLE_THICKNESS				= 4.0;
static const double PIN_SIDE							= 9.0;

/// How close, in points, a drag must come to the inherited size to snap to it.
static const double INHERITED_SNAP_DISTANCE				= 6.0;

static const LDrawStepPartListChrome DEFAULT_CHROME = {
	.borderRGBA				= {0.4, 0.4, 0.4, 1.0},
	.labelRGBA				= {0.1, 0.1, 0.1, 1.0},
	.markerRGBA				= {0.85, 0.45, 0.0, 1.0},

	// A light fill and a gray outline, fainter than the multiplier.
	.annotationFillRGBA		= {0.90, 0.93, 0.97, 1.0},
	.annotationBorderRGBA	= {0.50, 0.55, 0.62, 1.0},
	.annotationTextRGBA		= {0.20, 0.24, 0.30, 1.0},

	.pageRGBA				= {0.45, 0.45, 0.45, 0.55},

	// Dark and faint, so what is off the paper still shows.
	.pageSurroundRGBA		= {0.0, 0.0, 0.0, 0.28},

	.borderWidth			= 1.0,
	.cornerRadius			= 4.0,
	.labelPointSize			= 10.0,
	.annotationPointSize	= 8.0,
	.pageDashLength			= 5.0,
	.pageLineWidth			= 1.0,
	.placeholderDashLength	= 3.0,
	.placeholderGapLength	= 2.0,
};


//========== ScopeOfDirective() ================================================
///
/// @abstract	The scope keyword a meta was written with, or Unspecified for a
/// 			directive that has none.
///
//==============================================================================
static LPubMetaScope ScopeOfDirective(LDrawDirective *directive)
{
	// LPub3D keeps one value for these, so LOCAL does not end with the step.
	if ([directive isKindOfClass:[LPubPliPartRotation class]]
		|| [directive isKindOfClass:[LPubResolution class]]) {
		return LPubMetaScopeUnspecified;
	}

	if ([directive respondsToSelector:@selector(scope)]) {
		return [(id)directive scope];
	}

	return LPubMetaScopeUnspecified;

}//end ScopeOfDirective


//========== ReadMetaLine() ====================================================
///
/// @abstract	Reads one line into the step slot or the carried slot, as
/// 			LPub3D does.
///
/// @discussion	After a LOCAL line, later lines of its kind in the same step
/// 			also hold for that step only.
///
//==============================================================================
static void ReadMetaLine(LDrawDirective		*directive,
						 LDrawDirective		*__strong *carried,
						 LDrawDirective		*__strong *local)
{
	if (*local != nil || ScopeOfDirective(directive) == LPubMetaScopeLocal) {
		*local = directive;
	}
	else {
		*carried = directive;
	}

}//end ReadMetaLine


//========== FrameInsetForPointsPerPageInch() ==================================
///
/// @abstract	How far the frame sits in from the host's corner. On the page,
/// 			LPub3D's margin.
///
/// @discussion	`pointsPerPageInch` is 0 off the page.
///
//==============================================================================
static double FrameInsetForPointsPerPageInch(double pointsPerPageInch)
{
	return (pointsPerPageInch > 0.0) ? LPUB_MARGIN_INCHES * pointsPerPageInch : VIEWPORT_MARGIN;

}//end FrameInsetForPointsPerPageInch


//========== AllowedFramePoints() ==============================================
///
/// @abstract	The longest the frame may be along one side of the host: the
/// 			page less its margins, else a share of the view.
///
//==============================================================================
static double AllowedFramePoints(double hostLength, double fraction, double pointsPerPageInch)
{
	if (pointsPerPageInch > 0.0) {
		return hostLength - 2.0 * FrameInsetForPointsPerPageInch(pointsPerPageInch);
	}

	return hostLength * fraction;

}//end AllowedFramePoints


//========== InchesRoundedUpToWritten() ========================================
///
/// @abstract	Inches rounded up to the step CONSTRAIN is written with.
///
/// @discussion	At least half a step up, so saving and reading back never
/// 			moves the last part to a new shelf.
///
//==============================================================================
static double InchesRoundedUpToWritten(double inches)
{
	return ceil(inches / WRITTEN_INCHES_STEP + 0.5) * WRITTEN_INCHES_STEP;

}//end InchesRoundedUpToWritten


//========== PageRatioForPointsPerPageInch() ===================================
///
/// @abstract	How many points on this page one default metric point covers.
///
/// @discussion	A metric point is one LDU at the default scale, so on the page
/// 			it covers one LDU of paper.
///
//==============================================================================
static double PageRatioForPointsPerPageInch(double pointsPerPageInch)
{
	if (pointsPerPageInch <= 0.0) {
		return 0.0;
	}

	return pointsPerPageInch * [LPubModelScale inchesPerLDU]
		   / [LDrawStepPartListLayout defaultMetrics].baseScale;

}//end PageRatioForPointsPerPageInch


@implementation LDrawStepPartListPolicy


// MARK: - PLACEMENT -


//---------- frameRectForFrameSize:inHostSize:pointsPerPageInch: -----[static]--
///
/// @abstract	The top-left corner of the host, inset by the margin.
///
//------------------------------------------------------------------------------
+ (Box2) frameRectForFrameSize:(Size2)frameSize
					inHostSize:(Size2)hostSize
			 pointsPerPageInch:(double)pointsPerPageInch
{
	double margin = FrameInsetForPointsPerPageInch(pointsPerPageInch);

	// A viewport too small for the margins must still give a box with a size
	// above zero.
	double width  = MIN(frameSize.width,  MAX(0.0, hostSize.width  - 2.0 * margin));
	double height = MIN(frameSize.height, MAX(0.0, hostSize.height - 2.0 * margin));

	return V2MakeBox(margin, margin, width, height);

}//end frameRectForFrameSize:inHostSize:pointsPerPageInch:


// MARK: - FITTING THE HOST -


//---------- metrics:fittingHostSize:pointsPerPageInch: --------------[static]--
///
/// @abstract	The same metrics, with the height budget taken from the host.
///
/// @discussion	The budget is content height, so it leaves room for the margins
/// 			and for the padding these metrics carry.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListMetrics) metrics:(LDrawStepPartListMetrics)metrics
					 fittingHostSize:(Size2)hostSize
				   pointsPerPageInch:(double)pointsPerPageInch
{
	double available = AllowedFramePoints(hostSize.height, MAXIMUM_VIEWPORT_HEIGHT_FRACTION,
										  pointsPerPageInch)
					 - 2.0 * metrics.framePadding;

	// The packer reads 0 as no limit, so a host with no room left gives the
	// smallest budget instead.
	metrics.maximumHeight = (hostSize.height > 0.0) ? MAX(1.0, available) : 0.0;

	return metrics;

}//end metrics:fittingHostSize:pointsPerPageInch:


//---------- constraint:clampedToHostSize:pointsPerInch:pointsPerPageInch: --[static]--
///
/// @abstract	Narrows a pinned width that would cover too much of the host.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListConstraint) constraint:(LDrawStepPartListConstraint)constraint
						 clampedToHostSize:(Size2)hostSize
							 pointsPerInch:(double)pointsPerInch
						 pointsPerPageInch:(double)pointsPerPageInch
{
	if (constraint.mode != LPubPliConstrainModeWidth || pointsPerInch <= 0.0) {
		return constraint;
	}

	double allowedPoints = AllowedFramePoints(hostSize.width, MAXIMUM_VIEWPORT_WIDTH_FRACTION,
											  pointsPerPageInch);

	if (allowedPoints <= 0.0) {
		return constraint;
	}

	double allowedInches = allowedPoints / pointsPerInch;

	if ((double)constraint.inches > allowedInches) {
		constraint.inches = (float)allowedInches;
	}

	return constraint;

}//end constraint:clampedToHostSize:pointsPerInch:pointsPerPageInch:


// MARK: - DRAWING VALUES -


//---------- defaultChrome -------------------------------------------[static]--
///
/// @abstract	The values the frame is drawn with.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListChrome) defaultChrome
{
	return DEFAULT_CHROME;

}//end defaultChrome


//---------- getListBackgroundRGBA:forViewportRGBA: ------------------[static]--
///
/// @abstract	The frame's background, a little away from the viewport's.
///
/// @discussion	Mixed by hand in sRGB: AppKit's own blend works in another
/// 			color space and comes out slightly weaker.
///
//------------------------------------------------------------------------------
+ (void) getListBackgroundRGBA:(double *)outRGBA forViewportRGBA:(const double *)viewportRGBA
{
	double brightness	= 0.299 * viewportRGBA[0] + 0.587 * viewportRGBA[1] + 0.114 * viewportRGBA[2];
	double targetLevel	= (brightness < 0.5) ? 1.0 : 0.0;

	for (NSUInteger channel = 0; channel < 3; channel++) {
		outRGBA[channel] = viewportRGBA[channel]
						 + (targetLevel - viewportRGBA[channel]) * BACKGROUND_CONTRAST;
	}
	outRGBA[3] = 1.0;

}//end getListBackgroundRGBA:forViewportRGBA:


//---------- badgeStyleForScaledDownPart:chrome: ---------------------[static]--
///
/// @abstract	The colors of a size badge.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListBadgeStyle) badgeStyleForScaledDownPart:(BOOL)isScaledDown
													 chrome:(LDrawStepPartListChrome)chrome
{
	LDrawStepPartListBadgeStyle style;

	for (NSUInteger channel = 0; channel < 4; channel++) {
		style.fillRGBA[channel]		= isScaledDown ? chrome.markerRGBA[channel] : chrome.annotationFillRGBA[channel];
		style.borderRGBA[channel]	= isScaledDown ? chrome.markerRGBA[channel] : chrome.annotationBorderRGBA[channel];
		style.textRGBA[channel]		= isScaledDown ? chrome.annotationFillRGBA[channel] : chrome.annotationTextRGBA[channel];
	}

	return style;

}//end badgeStyleForScaledDownPart:chrome:


//---------- overflowNoticeRectForContentWidth:chrome: ---------------[static]--
///
/// @abstract	Where the notice of parts left out goes.
///
//------------------------------------------------------------------------------
+ (Box2) overflowNoticeRectForContentWidth:(double)contentWidth chrome:(LDrawStepPartListChrome)chrome
{
	return V2MakeBox(0.0, 0.0, contentWidth, chrome.labelPointSize + 2.0);

}//end overflowNoticeRectForContentWidth:chrome:


// MARK: - RESIZING -


//---------- handleAtPoint:inFrame: ----------------------------------[static]--
///
/// @abstract	What a drag starting at this point would resize.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListHandle) handleAtPoint:(Point2)point inFrame:(Box2)frame
{
	if (frame.size.width <= 0.0 || frame.size.height <= 0.0) {
		return LDrawStepPartListHandleNone;
	}

	double	thickness	= RESIZE_HANDLE_THICKNESS;
	double	maxX		= frame.origin.x + frame.size.width;
	double	maxY		= frame.origin.y + frame.size.height;

	// The same distance inside and outside the edge. Kept thin, so clicks on
	// the content still reach the model.
	BOOL nearRight	= (point.x >= maxX - thickness && point.x <= maxX + thickness);
	BOOL nearBottom	= (point.y >= maxY - thickness && point.y <= maxY + thickness);

	// Along the edge, not merely level with it.
	BOOL withinRows		= (point.y >= frame.origin.y - thickness && point.y <= maxY + thickness);
	BOOL withinColumns	= (point.x >= frame.origin.x - thickness && point.x <= maxX + thickness);

	if (nearRight && nearBottom) {
		// A CONSTRAIN holds one size, so the corner goes to the nearer edge.
		return (fabs(point.x - maxX) <= fabs(point.y - maxY))
			 ? LDrawStepPartListHandleWidth
			 : LDrawStepPartListHandleHeight;
	}
	if (nearRight && withinRows) {
		return LDrawStepPartListHandleWidth;
	}
	if (nearBottom && withinColumns) {
		return LDrawStepPartListHandleHeight;
	}

	return LDrawStepPartListHandleNone;

}//end handleAtPoint:inFrame:


//---------- pinRectForAxis:inFrame: ---------------------------------[static]--
///
/// @abstract	Where an axis's indicator pin sits.
///
//------------------------------------------------------------------------------
+ (Box2) pinRectForAxis:(LPubPliAxis)axis inFrame:(Box2)frame
{
	Point2 center = (axis == LPubPliAxisWidth)
				  ? V2Make(V2BoxMaxX(frame), V2BoxMidY(frame))
				  : V2Make(V2BoxMidX(frame), V2BoxMaxY(frame));

	return V2SizeCenteredOnPoint(V2MakeSize(PIN_SIDE, PIN_SIDE), center);

}//end pinRectForAxis:inFrame:


//---------- controlAtPoint:inFrame:widthPinned:heightPinned: --------[static]--
///
/// @abstract	The control under this point.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListControl) controlAtPoint:(Point2)point
									inFrame:(Box2)frame
								widthPinned:(BOOL)widthPinned
							   heightPinned:(BOOL)heightPinned
{
	if (V2BoxWidth(frame) <= 0.0 || V2BoxHeight(frame) <= 0.0) {
		return LDrawStepPartListControlNone;
	}

	// The pins sit on the edges, so they are asked first.
	if (widthPinned && V2BoxContains([self pinRectForAxis:LPubPliAxisWidth inFrame:frame], point)) {
		return LDrawStepPartListControlWidthPin;
	}
	if (heightPinned && V2BoxContains([self pinRectForAxis:LPubPliAxisHeight inFrame:frame], point)) {
		return LDrawStepPartListControlHeightPin;
	}

	switch ([self handleAtPoint:point inFrame:frame]) {
		case LDrawStepPartListHandleWidth:	return LDrawStepPartListControlWidthEdge;
		case LDrawStepPartListHandleHeight:	return LDrawStepPartListControlHeightEdge;
		case LDrawStepPartListHandleNone:	break;
	}

	return LDrawStepPartListControlNone;

}//end controlAtPoint:inFrame:widthPinned:heightPinned:


//---------- dragOriginForAxis:grabbedAtPoint:layout: ----------------[static]--
///
/// @abstract	The point a drag grabbed here measures from, so the grab alone
/// 			asks for the size the list packs the same at.
///
/// @discussion	Rounded up to what CONSTRAIN writes, so a grab that has not
/// 			moved never wraps a part.
///
//------------------------------------------------------------------------------
+ (Point2) dragOriginForAxis:(LPubPliAxis)axis
			  grabbedAtPoint:(Point2)point
					  layout:(nullable LDrawStepPartListLayout *)layout
{
	if (layout == nil || layout.pointsPerInch <= 0.0) {
		return point;
	}

	double	pointsPerInch	= layout.pointsPerInch;
	BOOL	isWidth			= (axis == LPubPliAxisWidth);
	double	start			= isWidth ? layout.resizeStartSize.width : layout.resizeStartSize.height;
	double	startPoints		= InchesRoundedUpToWritten(start / pointsPerInch) * pointsPerInch;

	return isWidth ? V2Make(point.x - startPoints, point.y) : V2Make(point.x, point.y - startPoints);

}//end dragOriginForAxis:grabbedAtPoint:layout:


//---------- inchesForDraggingAxis:toPoint:fromOrigin:layout:… -------[static]--
///
/// @abstract	The frame size, in inches, that a drag to this point asks for,
/// 			clamped to what can be written and then to what can be drawn.
///
/// @discussion	The new size is the distance from `origin` to the pointer. Near
/// 			the inherited size it snaps to it.
///
//------------------------------------------------------------------------------
+ (double) inchesForDraggingAxis:(LPubPliAxis)axis
						 toPoint:(Point2)point
					  fromOrigin:(Point2)origin
						  layout:(nullable LDrawStepPartListLayout *)layout
						hostSize:(Size2)hostSize
			   pointsPerPageInch:(double)pointsPerPageInch
				 inheritedInches:(double)inheritedInches
{
	if (layout == nil || layout.pointsPerInch <= 0.0) {
		return 0.0;
	}

	double	pointsPerInch	= layout.pointsPerInch;
	BOOL	isWidth			= (axis == LPubPliAxisWidth);
	double	inches			= (isWidth ? point.x - origin.x : point.y - origin.y) / pointsPerInch;

	// A height may go lower than a width, because it only sets the height of
	// the columns. On the page only the paper limits the top.
	double minimum = isWidth ? [LDrawStepPartList minimumWidthInInches] : [LDrawStepPartList minimumHeightInInches];
	double maximum = (pointsPerPageInch > 0.0) ? DBL_MAX : [LDrawStepPartList maximumWidthInInches];

	// Past these sizes the frame is drawn the same, or its icons shrink.
	double room = AllowedFramePoints(isWidth ? hostSize.width : hostSize.height,
									 isWidth ? MAXIMUM_VIEWPORT_WIDTH_FRACTION : MAXIMUM_VIEWPORT_HEIGHT_FRACTION,
									 pointsPerPageInch);
	double largestUsefulPoints = isWidth ? layout.oneRowFrameWidth : layout.tallestFrameHeight;

	if (room > 0.0) {
		maximum = MIN(maximum, room / pointsPerInch);
	}
	if (largestUsefulPoints > 0.0) {
		maximum = MIN(maximum, InchesRoundedUpToWritten(largestUsefulPoints / pointsPerInch));
	}

	// Below one shelf no HEIGHT fits, and the one shelf is drawn.
	if (isWidth == NO && layout.oneRowFrameHeight > 0.0) {
		minimum = MAX(minimum, InchesRoundedUpToWritten(layout.oneRowFrameHeight / pointsPerInch));
	}

	// Floors first, so a ceiling always wins.
	double clampedInches = MIN(MAX(inches, minimum), maximum);

	// Exactly the inherited size, so letting go there removes the step's line.
	// Only between the stops, because a stop wins.
	BOOL inheritedIsBetweenStops = (inheritedInches > 0.0
									&& inheritedInches >= MIN(minimum, maximum)
									&& inheritedInches <= maximum);

	if (inheritedIsBetweenStops
		&& fabs(clampedInches - inheritedInches) * pointsPerInch <= INHERITED_SNAP_DISTANCE) {
		return inheritedInches;
	}

	return clampedInches;

}//end inchesForDraggingAxis:toPoint:fromOrigin:layout:hostSize:pointsPerPageInch:inheritedInches:


// MARK: - PINS -


//---------- constrainDirectiveInStep: -------------------------------[static]--
///
/// @abstract	The step's own CONSTRAIN, or nil: its last CONSTRAIN, when that
/// 			line holds for this step alone.
///
/// @discussion	A line holds for the step alone when it or an earlier CONSTRAIN
/// 			in the step is LOCAL. Any other line carries on to later steps,
/// 			so it is never this step's to edit or clear.
///
//------------------------------------------------------------------------------
+ (nullable LPubPliConstrain *) constrainDirectiveInStep:(nullable LDrawStep *)step
{
	return [self constrainDirectiveInStep:step excluding:nil];

}//end constrainDirectiveInStep:


//---------- constrainDirectiveInStep:excluding: ---------------------[static]--
///
/// @abstract	The step's own CONSTRAIN, reading `excluded` as if it were not
/// 			there.
///
//------------------------------------------------------------------------------
+ (nullable LPubPliConstrain *) constrainDirectiveInStep:(nullable LDrawStep *)step
											   excluding:(nullable LDrawDirective *)excluded
{
	LPubPliConstrain	*last		= nil;
	BOOL				 localOpen	= NO;

	for (LDrawDirective *directive in [step subdirectives]) {
		if (directive != excluded && [directive isKindOfClass:[LPubPliConstrain class]]) {
			last		= (LPubPliConstrain *)directive;
			localOpen	|= (last.scope == LPubMetaScopeLocal);
		}
	}

	return localOpen ? last : nil;

}//end constrainDirectiveInStep:excluding:


//---------- constraintForVisibleStepOfModel: ------------------------[static]--
///
/// @abstract	How the visible step's list is packed on the page: the CONSTRAIN
/// 			in force for the step, else AREA, as in LPub3D.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListConstraint) constraintForVisibleStepOfModel:(nullable LDrawModel *)model
{
	LPubPliConstrain *directive = [self constrainInForceForStep:[model visibleStep] excluding:nil];

	return [LDrawStepPartListLayout constraintForDirective:directive];

}//end constraintForVisibleStepOfModel:


//---------- viewportConstraintForHostSize:pointsPerInch: ------------[static]--
///
/// @abstract	How the list is packed off the page: shelves as wide as the
/// 			view's width share.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListConstraint) viewportConstraintForHostSize:(Size2)hostSize
												pointsPerInch:(double)pointsPerInch
{
	LDrawStepPartListConstraint constraint = [LDrawStepPartListLayout defaultConstraint];

	if (pointsPerInch > 0.0) {
		constraint.mode		= LPubPliConstrainModeWidth;
		constraint.inches	= (float)(AllowedFramePoints(hostSize.width, MAXIMUM_VIEWPORT_WIDTH_FRACTION, 0.0)
									  / pointsPerInch);
	}

	return constraint;

}//end viewportConstraintForHostSize:pointsPerInch:


//---------- inheritedInchesForAxis:inModel: -------------------------[static]--
///
/// @abstract	The size the visible step is pinned to on this axis without its
/// 			own line: the CONSTRAIN in force with that line left out, if it
/// 			pins the axis, else 0 for none.
///
/// @discussion	A drag to this size removes the step's own line instead of
/// 			writing the same size again.
///
//------------------------------------------------------------------------------
+ (double) inheritedInchesForAxis:(LPubPliAxis)axis inModel:(nullable LDrawModel *)model
{
	LDrawStep			*step		= [model visibleStep];
	LPubPliConstrain	*inherited	= [self constrainInForceForStep:step
														  excluding:[self constrainDirectiveInStep:step]];

	return (inherited != nil && inherited.mode == LPubPliConstrainModeForAxis(axis))
		 ? (double)inherited.inches
		 : 0.0;

}//end inheritedInchesForAxis:inModel:


// MARK: - METAS IN FORCE -


//---------- directiveInForceForStep:excluding:matching: -------------[static]--
///
/// @abstract	The line of one kind in force for a step, read as LPub3D reads
/// 			it, or nil.
///
/// @discussion	A submodel starts from what held where it is first placed, so
/// 			the walk starts at the file's first model when the step is in
/// 			another one.
///
//------------------------------------------------------------------------------
+ (nullable __kindof LDrawDirective *) directiveInForceForStep:(nullable LDrawStep *)step
													excluding:(nullable LDrawDirective *)excluded
													 matching:(BOOL (NS_NOESCAPE ^)(LDrawDirective *directive))predicate
{
	LDrawModel		*model		= [step enclosingModel];
	LDrawDirective	*carried	= nil;
	LDrawDirective	*local		= nil;

	// The metas on the way to the model's first placement, one group per step.
	// A model placed nowhere starts from nothing.
	for (NSArray<LDrawDirective *> *group in [self pathToModel:model]) {
		LDrawDirective *passedLocal = nil;

		for (LDrawDirective *directive in group) {
			if (predicate(directive)) {
				ReadMetaLine(directive, &carried, &passedLocal);
			}
		}
	}

	NSArray *steps = (model != nil) ? [model steps] : (step != nil ? @[step] : @[]);

	for (LDrawStep *current in steps) {

		local = nil;

		for (LDrawDirective *directive in [current subdirectives]) {
			if (directive != excluded && predicate(directive)) {
				ReadMetaLine(directive, &carried, &local);
			}
		}

		if (current == step) {
			break;
		}
	}

	return local ?: carried;

}//end directiveInForceForStep:excluding:matching:


//---------- performWithCachedLookups: -------------------------------[static]--
///
/// @abstract	Runs the block with the walk into each submodel kept, so the many
/// 			lookups of one redraw walk the file once.
///
/// @discussion	Only for the length of the block: the kept walk goes stale when
/// 			the file changes.
///
//------------------------------------------------------------------------------
+ (void) performWithCachedLookups:(void (NS_NOESCAPE ^)(void))block
{
	if (PathCacheDepth == 0) {
		PathCache = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality
										  valueOptions:NSMapTableStrongMemory];
	}
	PathCacheDepth += 1;

	block();

	PathCacheDepth -= 1;
	if (PathCacheDepth == 0) {
		PathCache = nil;
	}

}//end performWithCachedLookups:


//---------- pathToModel: --------------------------------------------[static]--
///
/// @abstract	The LPub metas a lookup passes on its way to the model's first
/// 			placement, one group per step, or nil when it is placed nowhere.
///
/// @discussion	Empty for the file's first model. The walk starts there, so a
/// 			submodel starts from what held where it is first placed.
///
//------------------------------------------------------------------------------
+ (nullable NSArray<NSArray<LDrawDirective *> *> *) pathToModel:(nullable LDrawModel *)model
{
	LDrawModel *first = [[model enclosingFile] firstModel];

	if (model == nil || first == nil || first == model) {
		return @[];
	}

	id kept = [PathCache objectForKey:model];

	if (kept != nil) {
		return (kept == [NSNull null]) ? nil : kept;
	}

	NSMutableArray	*groups			= [NSMutableArray array];
	NSHashTable		*visitedModels	= [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
	BOOL			 found			= [self collectPathThroughModel:first
															toModel:model
													  visitedModels:visitedModels
														 intoGroups:groups];
	NSArray			*path			= found ? groups : nil;

	[PathCache setObject:(path ?: [NSNull null]) forKey:model];

	return path;

}//end pathToModel:


//---------- collectPathThroughModel:toModel:visitedModels:intoGroups: --[static]--
///
/// @abstract	Walks a model toward the target's first placement, adding one
/// 			group of LPub metas per step. YES when the placement is found.
///
/// @discussion	A submodel that does not lead to the target is dropped from
/// 			the path, since its lines never reach its parent. LPub3D does not
/// 			follow a placement inside PART BEGIN IGN.
///
//------------------------------------------------------------------------------
+ (BOOL) collectPathThroughModel:(LDrawModel *)model
						 toModel:(LDrawModel *)target
				   visitedModels:(NSHashTable *)visitedModels
					  intoGroups:(NSMutableArray<NSArray<LDrawDirective *> *> *)groups
{
	BOOL ignoring = NO;

	[visitedModels addObject:model];

	for (LDrawStep *step in [model steps]) {

		NSMutableArray<LDrawDirective *> *group = [NSMutableArray array];

		[groups addObject:group];

		for (LDrawDirective *directive in [step subdirectives]) {

			if ([directive isKindOfClass:[LPubPliIgnore class]]
				&& ((LPubPliIgnore *)directive).branch == LPubPliIgnoreBranchPart) {
				ignoring = ((LPubPliIgnore *)directive).beginsRange;
			}
			else if ([directive isKindOfClass:[LDrawPart class]]) {
				LDrawModel *placed = (ignoring == NO) ? [(LDrawPart *)directive referencedMPDSubmodel] : nil;

				if (placed != nil && placed == target) {
					return YES;
				}

				if (placed != nil && [visitedModels containsObject:placed] == NO) {
					NSUInteger before = groups.count;

					if ([self collectPathThroughModel:placed
											  toModel:target
										visitedModels:visitedModels
										   intoGroups:groups]) {
						return YES;
					}
					[groups removeObjectsInRange:NSMakeRange(before, groups.count - before)];
				}
			}
			else if ([directive isKindOfClass:[LPubCommand class]]) {
				[group addObject:directive];
			}
		}
	}

	return NO;

}//end collectPathThroughModel:toModel:visitedModels:intoGroups:


//---------- constrainInForceForStep:excluding: ----------------------[static]--
///
/// @abstract	The CONSTRAIN in force for a step, or nil.
///
//------------------------------------------------------------------------------
+ (nullable LPubPliConstrain *) constrainInForceForStep:(nullable LDrawStep *)step
											  excluding:(nullable LDrawDirective *)excluded
{
	return [self directiveInForceForStep:step
							   excluding:excluded
								matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPliConstrain class]];
	}];

}//end constrainInForceForStep:excluding:


//---------- partListViewTransformInModel: ---------------------------[static]--
///
/// @abstract	The view LPub3D would draw this step's parts list icons from,
/// 			PART_ROTATION included.
///
/// @discussion	Not Bricksmith's 3D view. That view is LPub3D's assembly
/// 			default of 23, 45, while a parts list uses 23, -45: the same
/// 			tilt from the other side. Using the wrong one mirrors every
/// 			icon.
///
//------------------------------------------------------------------------------
+ (Matrix4) partListViewTransformInModel:(nullable LDrawModel *)model
{
	LDrawStep *step = [model visibleStep];

	LPubPliCameraAngles *angles = [self directiveInForceForStep:step
													  excluding:nil
													   matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPliCameraAngles class]];
	}];

	LPubPliPartRotation *rotation = [self directiveInForceForStep:step
														excluding:nil
														 matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPliPartRotation class]];
	}];

	double latitude		= (angles != nil) ? angles.latitude  : [LPubPliCameraAngles defaultLatitude];
	double longitude	= (angles != nil) ? angles.longitude : [LPubPliCameraAngles defaultLongitude];

	// An ABS rotation is the whole view, so the camera looks straight on. A
	// custom viewpoint keeps its angles.
	if (rotation.type == LPubPliPartRotationTypeAbsolute && angles.isCustomViewpoint == NO) {
		latitude	= 0.0;
		longitude	= 0.0;
	}

	Matrix4 camera = [LDrawStepPartListLayout viewTransformForLatitude:latitude longitude:longitude];

	// The part is turned first, then seen.
	return (rotation != nil) ? Matrix4Multiply(rotation.rotationMatrix, camera) : camera;

}//end partListViewTransformInModel:


//---------- viewTransformForVisibleStepOfModel: ---------------------[static]--
///
/// @abstract	The angle the icons are drawn at.
///
/// @discussion	By default the step's own rotation, so the icons match the
/// 			assembly beside them. The preference switches to the parts list
/// 			angle LPub3D would use.
///
//------------------------------------------------------------------------------
+ (Matrix4) viewTransformForVisibleStepOfModel:(nullable LDrawModel *)model
{
	if (model == nil || [LDrawStepPartList followsStepRotation] == NO) {
		return [self partListViewTransformInModel:model];
	}

	Tuple3 angle = [model rotationAngleForStepAtIndex:[model maximumStepIndexForStepDisplay]];

	return [LDrawStepPartListLayout viewTransformForAngle:angle];

}//end viewTransformForVisibleStepOfModel:


//---------- modelScaleForBranch:inModel: ----------------------------[static]--
///
/// @abstract	The scale a document sets for one kind of picture, or 1.
///
/// @discussion	Each branch is read on its own, since files often set PLI,
/// 			ASSEM and BOM to different values.
///
//------------------------------------------------------------------------------
+ (float) modelScaleForBranch:(LPubModelScaleBranch)branch inModel:(nullable LDrawModel *)model
{
	LPubModelScale *scaleDirective = [self directiveInForceForStep:[model visibleStep]
														 excluding:nil
														  matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubModelScale class]]
			&& ((LPubModelScale *)directive).branch == branch;
	}];

	return (scaleDirective != nil) ? scaleDirective.scale : 1.0;

}//end modelScaleForBranch:inModel:


//---------- pageSizeInInchesInModel: --------------------------------[static]--
///
/// @abstract	The page LPub3D would print this document on, in inches.
///
/// @discussion	PAGE SIZE is written in the document's own unit and as the page
/// 			stands; ORIENTATION is what turns it on its side, so the two
/// 			are read together. Answers zero when the document does not
/// 			measure its page.
///
//------------------------------------------------------------------------------
+ (Size2) pageSizeInInchesInModel:(nullable LDrawModel *)model
{
	LDrawStep *step = [model visibleStep];

	LPubPageSize *size = [self directiveInForceForStep:step
											 excluding:nil
											  matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPageSize class]];
	}];

	if (size == nil) {
		return ZeroSize2;
	}

	LPubPageOrientation *orientation = [self directiveInForceForStep:step
														   excluding:nil
															matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPageOrientation class]];
	}];

	// A document written in centimeters measures its page in them too.
	LPubResolution	*resolution		= [self resolutionInModel:model];
	double			 inchesPerUnit	= (resolution != nil) ? resolution.inchesPerUnit : 1.0;

	// Nothing said, so the measurements stand as written.
	if (orientation == nil) {
		return V2MakeSize(size.width * inchesPerUnit, size.height * inchesPerUnit);
	}

	double	shorter	= MIN(size.width, size.height) * inchesPerUnit;
	double	longer	= MAX(size.width, size.height) * inchesPerUnit;

	// Files disagree on which measurement comes first, so the orientation is
	// read as naming the long side. That way a turned page is not turned
	// again.
	if (orientation.isLandscape) {
		return V2MakeSize(longer, shorter);
	}

	return V2MakeSize(shorter, longer);

}//end pageSizeInInchesInModel:


//---------- resolutionInModel: --------------------------------------[static]--
///
/// @abstract	The RESOLUTION in force, or nil. Read only for the unit the
/// 			page size is written in.
///
//------------------------------------------------------------------------------
+ (nullable LPubResolution *) resolutionInModel:(nullable LDrawModel *)model
{
	return [self directiveInForceForStep:[model visibleStep]
							   excluding:nil
								matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubResolution class]];
	}];

}//end resolutionInModel:


// MARK: - PAGE SPACE -


//---------- pointsPerPageInchForAssemblyScale:inModel: --------------[static]--
///
/// @abstract	How many points one page inch covers, when the viewport draws
/// 			the assembly at `pointsPerLDU`.
///
/// @discussion	LPub3D draws one LDU of an assembly at `inchesPerLDU` times the
/// 			ASSEM MODEL_SCALE. Read the other way, a viewport at a given
/// 			points per LDU shows the page at this many points to the inch.
///
//------------------------------------------------------------------------------
+ (double) pointsPerPageInchForAssemblyScale:(double)pointsPerLDU inModel:(nullable LDrawModel *)model
{
	double inchesPerLDU = [LPubModelScale inchesPerLDU]
						* [self modelScaleForBranch:LPubModelScaleBranchAssembly inModel:model];

	if (pointsPerLDU <= 0.0 || inchesPerLDU <= 0.0) {
		return 0.0;
	}

	return pointsPerLDU / inchesPerLDU;

}//end pointsPerPageInchForAssemblyScale:inModel:


//---------- partListScaleForAssemblyScale:inModel: ------------------[static]--
///
/// @abstract	Points per LDU for the parts list's icons, so they keep their
/// 			size next to the assembly at every zoom.
///
//------------------------------------------------------------------------------
+ (double) partListScaleForAssemblyScale:(double)pointsPerLDU inModel:(nullable LDrawModel *)model
{
	double assemblyScale = [self modelScaleForBranch:LPubModelScaleBranchAssembly inModel:model];

	if (pointsPerLDU <= 0.0 || assemblyScale <= 0.0) {
		return 0.0;
	}

	return pointsPerLDU * [self modelScaleForBranch:LPubModelScaleBranchPli inModel:model] / assemblyScale;

}//end partListScaleForAssemblyScale:inModel:


//---------- assemblyScaleFittingPageInHostSize:inModel: -------------[static]--
///
/// @abstract	Points per LDU at which the whole page fits in the host, as
/// 			LPub3D's Fit Page does.
///
/// @discussion	The page touches the host's sides or its top and bottom, less a
/// 			small margin, whichever comes first.
///
//------------------------------------------------------------------------------
+ (double) assemblyScaleFittingPageInHostSize:(Size2)hostSize inModel:(nullable LDrawModel *)model
{
	Size2	page	= [self pageSizeInInchesInModel:model];
	double	width	= hostSize.width - 2.0 * PAGE_FIT_MARGIN;
	double	height	= hostSize.height - 2.0 * PAGE_FIT_MARGIN;

	if (page.width <= 0.0 || page.height <= 0.0 || width <= 0.0 || height <= 0.0) {
		return 0.0;
	}

	return MIN(width / page.width, height / page.height)
		 * [LPubModelScale inchesPerLDU]
		 * [self modelScaleForBranch:LPubModelScaleBranchAssembly inModel:model];

}//end assemblyScaleFittingPageInHostSize:inModel:


//---------- pageAnchorInModel: --------------------------------------[static]--
///
/// @abstract	The model point the page is centered on.
///
/// @discussion	`ZeroPoint3` for a model with nothing to measure.
///
//------------------------------------------------------------------------------
+ (Point3) pageAnchorInModel:(nullable LDrawModel *)model
{
	Box3 bounds = InvalidBox;

	// Removed groups report no bounds, so bring them up to date first.
	[model updateGroupSuppressionIfNeeded];

	for (LDrawStep *step in [model steps]) {
		bounds = V3UnionBox(bounds, [step boundingBox3]);
	}

	if (V3EqualBoxes(bounds, InvalidBox)) {
		return ZeroPoint3;
	}

	return V3Midpoint(bounds.min, bounds.max);

}//end pageAnchorInModel:


//---------- drawsPageInModel: ---------------------------------------[static]--
///
/// @abstract	Whether the step on display is drawn on LPub3D's page.
///
/// @discussion	PLI SHOW is not read: LPub3D prints the page either way.
///
//------------------------------------------------------------------------------
+ (BOOL) drawsPageInModel:(nullable LDrawModel *)model
{
	if (model == nil
		|| [model stepDisplay] == NO
		|| [LDrawStepPartList isEnabled] == NO
		|| [LDrawStepPartList usesLPubScale] == NO) {
		return NO;
	}

	Size2 page = [self pageSizeInInchesInModel:model];

	return (page.width > 0.0 && page.height > 0.0);

}//end drawsPageInModel:


//---------- showsListOrPageInModel: ---------------------------------[static]--
///
/// @abstract	Whether the host shows the step's list, its page, or both.
///
//------------------------------------------------------------------------------
+ (BOOL) showsListOrPageInModel:(nullable LDrawModel *)model
{
	return [model stepDisplay]
		&& ([LDrawStepPartList isShownForVisibleStepOfModel:model] || [self drawsPageInModel:model]);

}//end showsListOrPageInModel:


//---------- pageRectCenteredOn:assemblyScale:inModel: ---------------[static]--
///
/// @abstract	The page at the size the zoom gives it, centered on `center`.
///
/// @discussion	Where LPub3D puts the assembly on its page is not copied: the
/// 			outline shows whether the step fits a page, not where on the
/// 			page it sits.
///
//------------------------------------------------------------------------------
+ (Box2) pageRectCenteredOn:(Point2)center
			  assemblyScale:(double)pointsPerLDU
					inModel:(nullable LDrawModel *)model
{
	Size2	page		= [self pageSizeInInchesInModel:model];
	double	pointsPerPageInch	= [self pointsPerPageInchForAssemblyScale:pointsPerLDU inModel:model];

	if (page.width <= 0.0 || page.height <= 0.0 || pointsPerPageInch <= 0.0) {
		return ZeroBox2;
	}

	return V2SizeCenteredOnPoint(V2MakeSize(page.width * pointsPerPageInch,
											page.height * pointsPerPageInch),
								 center);

}//end pageRectCenteredOn:assemblyScale:inModel:


//---------- metrics:scaledToPointsPerPageInch: ----------------------[static]--
///
/// @abstract	The metrics restated in the page's inches.
///
/// @discussion	`maximumCellWidthFraction` is a fraction, so it is not scaled.
/// 			`maximumHeight` is not touched: fit it to the host afterwards.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListMetrics) metrics:(LDrawStepPartListMetrics)metrics
		   scaledToPointsPerPageInch:(double)pointsPerPageInch
{
	double ratio = PageRatioForPointsPerPageInch(pointsPerPageInch);

	if (ratio <= 0.0) {
		return metrics;
	}

	metrics.pointsPerInch				= pointsPerPageInch;

	metrics.minimumScale				*= ratio;
	metrics.cellPadding					*= ratio;
	metrics.labelHeight					*= ratio;
	metrics.annotationHeight			*= ratio;
	metrics.labelCharacterWidth			*= ratio;
	metrics.annotationCharacterWidth	*= ratio;
	metrics.decorationGap				*= ratio;
	metrics.rowGap						*= ratio;

	// LPub3D pads the list by its border margin and line.
	metrics.framePadding				= (LPUB_MARGIN_INCHES + LPUB_BORDER_INCHES) * pointsPerPageInch;

	return metrics;

}//end metrics:scaledToPointsPerPageInch:


//---------- chrome:scaledToPointsPerPageInch: -----------------------[static]--
///
/// @abstract	The chrome restated in the page's inches.
///
/// @discussion	The packer keeps room for the text and the view draws it, so
/// 			both are scaled by the same ratio. The lines are LPub3D's.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListChrome) chrome:(LDrawStepPartListChrome)chrome
		 scaledToPointsPerPageInch:(double)pointsPerPageInch
{
	double ratio = PageRatioForPointsPerPageInch(pointsPerPageInch);

	if (ratio <= 0.0) {
		return chrome;
	}

	chrome.labelPointSize		*= ratio;
	chrome.annotationPointSize	*= ratio;
	chrome.pageDashLength		*= ratio;

	// LPub3D's default border is square.
	chrome.borderWidth			= LPUB_BORDER_INCHES * pointsPerPageInch;
	chrome.cornerRadius			= 0.0;
	chrome.pageLineWidth		= LPUB_PAGE_GUIDE_INCHES * pointsPerPageInch;

	return chrome;

}//end chrome:scaledToPointsPerPageInch:


//---------- isAxis:pinnedInStep: ------------------------------------[static]--
///
/// @abstract	Whether the step's own CONSTRAIN pins this axis.
///
/// @discussion	A line that carries on to later steps pins nothing here. COLS,
/// 			AREA and SQUARE pin neither edge.
///
//------------------------------------------------------------------------------
+ (BOOL) isAxis:(LPubPliAxis)axis pinnedInStep:(nullable LDrawStep *)step
{
	LPubPliConstrain *local = [self constrainDirectiveInStep:step];

	return (local != nil && local.mode == LPubPliConstrainModeForAxis(axis));

}//end isAxis:pinnedInStep:


@end
