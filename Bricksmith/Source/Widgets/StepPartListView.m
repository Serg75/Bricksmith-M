//==============================================================================
//
// File:		StepPartListView.m
//
// Purpose:		The framed parts list that hovers over the main 3D viewport.
//
// Notes:		Three layers, bottom to top: this view draws the frame, a nested
//				3D view draws the part icons, and a chrome view draws the labels
//				over them.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import "StepPartListView.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>
#import <LDrawFeatures/LDrawStepPartListResizeTracker.h>

#import "LDrawView.h"
#import "LDrawViewerContainer.h"
#import "StepPartListChromeView.h"


//========== ClipViewToBounds ==================================================
///
/// @abstract	Makes a view clip its subviews, whatever the deployment target.
///
/// @discussion	Without this a panned frame spills its icons over the viewport.
///				Use it on the overlay only: a layer on the 3D container can
///				leave its surface blank.
///
//==============================================================================
static void ClipViewToBounds(NSView *view)
{
	if (@available(macOS 14.0, *)) {
		view.clipsToBounds = YES;
	}
	else {
		view.wantsLayer = YES;
		view.layer.masksToBounds = YES;
	}

}//end ClipViewToBounds


@interface StepPartListView ()

@property (nonatomic, strong, nullable) LDrawViewerContainer			*iconContainer;
@property (nonatomic, strong, nullable) StepPartListChromeView			*chromeView;
/// What is on show. Nil when there is nothing.
@property (nonatomic, strong, nullable) LDrawStepPartListPresentation	*presentation;
/// The tint, worked out once from the viewport's color preference. Nil until
/// asked for, and cleared when that preference changes.
@property (nonatomic, strong, nullable) NSColor							*cachedListBackgroundColor;

// Resize tracking
/// The press in progress on the frame's controls.
@property (nonatomic, strong) LDrawStepPartListResizeTracker			*resizeTracker;

@end


@implementation StepPartListView


// MARK: - INITIALIZATION -


//========== initWithFrame: ====================================================
///
/// @abstract	Sets up an empty overlay. The child layers are built once there
///				is a layout to show.
///
//==============================================================================
- (instancetype) initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		self->_resizeTracker = [[LDrawStepPartListResizeTracker alloc] init];

		ClipViewToBounds(self);

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(backgroundColorDidChange:)
													 name:LDrawViewBackgroundColorDidChangeNotification
												   object:nil];
	}
	return self;

}//end initWithFrame:


//========== dealloc ===========================================================
- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

}//end dealloc


//========== backgroundColorDidChange: =========================================
///
/// @abstract	Re-tints the frame when the viewport's color preference
///				changes.
///
/// @discussion	The nested 3D view answers the same notification and takes the
///				plain preference color, which overwrites the tint. The order
///				of the two is not fixed, so the tint is applied again on the
///				next pass of the run loop.
///
//==============================================================================
- (void) backgroundColorDidChange:(NSNotification *)notification
{
	self.cachedListBackgroundColor = nil;

	dispatch_async(dispatch_get_main_queue(), ^{
		[self applyListBackgroundColor];
	});

}//end backgroundColorDidChange:


// MARK: - ACCESSORS -


//========== isFlipped =========================================================
///
/// @abstract	The layout and the policy measure y downward, so this view does
///				too and their rectangles need no conversion.
///
//==============================================================================
- (BOOL) isFlipped
{
	return YES;

}//end isFlipped


//========== isResizing ========================================================
- (BOOL) isResizing
{
	return self.resizeTracker.isResizing;

}//end isResizing


// MARK: - CONTENT -


//========== showPresentation: =================================================
///
/// @abstract	Shows what the presentation says, or nothing when passed nil.
///
//==============================================================================
- (void) showPresentation:(nullable LDrawStepPartListPresentation *)presentation
{
	self.presentation = presentation;

	[self.chromeView setChrome:[self chrome]];
	[self setNeedsDisplay:YES];

	NSRect contentRect = StepPartListRectFromBox(presentation.contentRect);

	if (NSIsEmptyRect(contentRect)) {
		[self tearDownContentLayers];
		return;
	}

	[self buildContentLayersWithFrame:contentRect];

	// Hidden while its size, model and camera change, so it cannot redraw
	// halfway through.
	[self.iconContainer setHidden:YES];

	[self.iconContainer setFrame:contentRect];
	[self.chromeView setFrame:contentRect];

	// Lay out now: the camera takes its size from the 3D view, and the zoom
	// below needs the right size.
	[self layoutSubtreeIfNeeded];

	LDrawView *iconView = [self.iconContainer glView];

	[iconView setLDrawDirective:presentation.iconModel];

	// The camera stays unrotated. Each part already carries the viewing angle,
	// and the layout positions are screen positions.
	[iconView setViewingAngle:ZeroPoint3];
	[iconView setZoomPercentage:presentation.iconZoomPercentage];
	[iconView scrollCenterToModelPoint:presentation.iconCenter];

	[self.iconContainer setHidden:NO];

	// Before the draw, so the icons are drawn on the frame's color.
	[self applyListBackgroundColor];

	// Draw now, so the window never shows the last step's icons with this
	// step's frame and labels.
	[iconView draw];

	[self.chromeView setLayout:presentation.layout];

}//end showPresentation:


//========== buildContentLayersWithFrame: ======================================
///
/// @abstract	Creates the 3D view and the chrome view, if they do not exist
///				yet.
///
/// @discussion	Made only once a real rectangle is known: a camera raises an
///				assertion for a zero-size view.
///
//==============================================================================
- (void) buildContentLayersWithFrame:(NSRect)contentRect
{
	if (self.iconContainer != nil) {
		return;
	}

	LDrawViewerContainer *container = [[LDrawViewerContainer alloc] initWithFrame:contentRect];

	// No clip here: the 3D view always fills the container exactly, and a layer
	// on the container can leave its surface blank. The overlay clips instead.
	[container setShowsScrollbars:NO];
	[self addSubview:container];
	self.iconContainer = container;

	LDrawView *iconView = [container glView];

#ifdef METAL
	// The labels are drawn over this view, so its picture must reach the
	// screen in the same pass as they do.
	[iconView setPresentsWithTransaction:YES];
#endif

	// It is a picture, not a viewport, so it never takes focus or answers a
	// click.
	[iconView setAcceptsFirstResponder:NO];
	[iconView setFocusRingVisible:NO];
	[iconView setProjectionMode:LDrawProjectionModeOrthographic];

	StepPartListChromeView *chromeView = [[StepPartListChromeView alloc] initWithFrame:contentRect];

	[chromeView setChrome:[self chrome]];
	[self addSubview:chromeView];
	self.chromeView = chromeView;

}//end buildContentLayersWithFrame:


//========== tearDownContentLayers =============================================
///
/// @abstract	Removes the 3D view, releasing its surface.
///
/// @discussion	Removed rather than hidden, so a document with no list costs
///				nothing and the view is never left at a size its camera cannot
///				handle.
///
//==============================================================================
- (void) tearDownContentLayers
{
	[[self.iconContainer glView] setLDrawDirective:nil];
	[self.iconContainer removeFromSuperview];
	self.iconContainer = nil;

	[self.chromeView setLayout:nil];
	[self.chromeView removeFromSuperview];
	self.chromeView = nil;

}//end tearDownContentLayers


// MARK: - DRAWING -


//========== drawRect: =========================================================
///
/// @abstract	Draws the frame's background, border and pins.
///
/// @discussion	The nested 3D view covers the icon area and clears to the same
///				color, so this fill only shows in the padding.
///
//==============================================================================
- (void) drawRect:(NSRect)dirtyRect
{
	NSRect frameRect = StepPartListRectFromBox(self.presentation.frameRect);

	[self drawPageOutline];

	if (NSIsEmptyRect(frameRect)) {
		return;
	}

	// Inset by half the line, so the border is drawn inside the frame.
	LDrawStepPartListChrome	chrome	= [self chrome];
	CGFloat					inset	= chrome.borderWidth / 2.0;
	NSBezierPath			*path	= [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frameRect, inset, inset)
																	  xRadius:chrome.cornerRadius
																	  yRadius:chrome.cornerRadius];

	[[self listBackgroundColor] set];
	[path fill];

	[StepPartListColorFromRGBA(chrome.borderRGBA) set];
	[path setLineWidth:chrome.borderWidth];
	[path stroke];

	[self drawPinForAxis:LPubPliAxisWidth];
	[self drawPinForAxis:LPubPliAxisHeight];

}//end drawRect:


//========== drawPageOutline ===================================================
///
/// @abstract	Draws the page LPub3D would print this step on, and dims what
///				falls outside it.
///
/// @discussion	Dashed and pale, so it reads as a margin mark and not as part
///				of the model. Dimming the outside shows which side is the paper.
///
//==============================================================================
- (void) drawPageOutline
{
	NSRect					pageRect	= StepPartListRectFromBox(self.presentation.pageRect);
	LDrawStepPartListChrome	chrome		= [self chrome];

	if (NSIsEmptyRect(pageRect)) {
		return;
	}

	// The whole view with the page cut out of it, which is what the even-odd
	// rule does with two nested rectangles.
	NSBezierPath *surround = [NSBezierPath bezierPathWithRect:self.bounds];

	[surround appendBezierPathWithRect:pageRect];
	[surround setWindingRule:NSWindingRuleEvenOdd];

	[StepPartListColorFromRGBA(chrome.pageSurroundRGBA) set];
	[surround fill];

	CGFloat			inset	= chrome.pageLineWidth / 2.0;
	CGFloat			dashes[]= { chrome.pageDashLength, chrome.pageDashLength };
	NSBezierPath	*path	= [NSBezierPath bezierPathWithRect:NSInsetRect(pageRect, inset, inset)];

	[path setLineWidth:chrome.pageLineWidth];
	[path setLineDash:dashes count:2 phase:0.0];

	[StepPartListColorFromRGBA(chrome.pageRGBA) set];
	[path stroke];

}//end drawPageOutline


//========== drawPinForAxis: ===================================================
///
/// @abstract	Draws the pin on an axis this step sets the size of itself.
///
//==============================================================================
- (void) drawPinForAxis:(LPubPliAxis)axis
{
	if ([self isAxisPinned:axis] == NO) {
		return;
	}

	NSRect			rect	= StepPartListRectFromBox([LDrawStepPartListPolicy pinRectForAxis:axis
																					  inFrame:[self frameBox]]);
	NSBezierPath	*path	= [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.0, 1.0)];

	[[NSColor controlAccentColor] set];
	[path fill];

}//end drawPinForAxis:


//========== listBackgroundColor ===============================================
///
/// @abstract	The frame's own background: the viewport's color, moved a
///				little away from it.
///
/// @discussion	It moves toward white over a dark viewport and toward black over
///				a light one. Cached, because reading the preference unarchives
///				a color.
///
//==============================================================================
- (NSColor *) listBackgroundColor
{
	if (self.cachedListBackgroundColor != nil) {
		return self.cachedListBackgroundColor;
	}

	NSColor *viewportColor	= [LDrawView backgroundColorFromUserDefaults];
	NSColor *listColor		= viewportColor;
	NSColor *rgb			= [viewportColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];

	if (rgb != nil) {
		double viewportRGBA[4]	= { rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent };
		double listRGBA[4]		= { 0.0, 0.0, 0.0, 1.0 };

		[LDrawStepPartListPolicy getListBackgroundRGBA:listRGBA forViewportRGBA:viewportRGBA];

		listColor = StepPartListColorFromRGBA(listRGBA);
	}

	self.cachedListBackgroundColor = listColor;

	return listColor;

}//end listBackgroundColor


//========== applyListBackgroundColor ==========================================
///
/// @abstract	Gives the nested 3D view the frame's background and redraws.
///
/// @discussion	The 3D view covers the icon area and clears to its own color,
///				so without this the frame's fill would show only in the
///				padding.
///
//==============================================================================
- (void) applyListBackgroundColor
{
	[[self.iconContainer glView] setBackgroundColor:[self listBackgroundColor]];
	[self setNeedsDisplay:YES];

}//end applyListBackgroundColor


// MARK: - INTERACTION -


//========== cursorAtPoint: ====================================================
///
/// @abstract	The cursor for the frame's control under this point, or nil when
///				there is none.
///
/// @discussion	A resize cursor over an edge, and a pointing hand over a pin
///				that clicking would clear.
///
//==============================================================================
- (NSCursor *) cursorAtPoint:(NSPoint)point
{
	switch ([self controlAtPoint:point]) {
		case LDrawStepPartListControlWidthPin:
		case LDrawStepPartListControlHeightPin:		return [NSCursor pointingHandCursor];
		case LDrawStepPartListControlWidthEdge:		return [NSCursor resizeLeftRightCursor];
		case LDrawStepPartListControlHeightEdge:	return [NSCursor resizeUpDownCursor];
		case LDrawStepPartListControlNone:			break;
	}

	return nil;

}//end cursorAtPoint:


//========== beginInteractionAtPoint: ==========================================
///
/// @abstract	A mouse-down here: clears a pin or starts a resize.
///
/// @return		Whether the frame took the click. NO means the point is not on
///				one of its controls, and the click belongs to the model.
///
//==============================================================================
- (BOOL) beginInteractionAtPoint:(NSPoint)point
{
	switch ([self.resizeTracker beginAtPoint:[self point2ForViewPoint:point] presentation:self.presentation]) {
		case LDrawStepPartListControlWidthPin:
			[self.delegate partListView:self didClickPinForAxis:LPubPliAxisWidth];
			return YES;

		case LDrawStepPartListControlHeightPin:
			[self.delegate partListView:self didClickPinForAxis:LPubPliAxisHeight];
			return YES;

		case LDrawStepPartListControlWidthEdge:
		case LDrawStepPartListControlHeightEdge:
			return YES;

		case LDrawStepPartListControlNone:
			return NO;
	}

	return NO;

}//end beginInteractionAtPoint:


//========== continueResizingAtPoint: ==========================================
///
/// @abstract	Repacks the frame under the pointer. The document is untouched
///				until the drag is let go.
///
//==============================================================================
- (void) continueResizingAtPoint:(NSPoint)point
{
	LDrawStepPartListResizeTracker *tracker = self.resizeTracker;

	if (tracker.isResizing == NO || self.presentation.layout == nil) {
		return;
	}

	double inches = [tracker inchesForDragToPoint:[self point2ForViewPoint:point] presentation:self.presentation];

	[self.delegate partListView:self previewingAxis:tracker.axis atInches:inches];

}//end continueResizingAtPoint:


//========== endResizingCommitting: ============================================
///
/// @abstract	Ends a drag. The previewed size becomes one undoable edit, or is
///				dropped, leaving the document as it was.
///
//==============================================================================
- (void) endResizingCommitting:(BOOL)shouldCommit
{
	if (self.isResizing == NO) {
		return;
	}

	[self.resizeTracker end];

	if (shouldCommit) {
		[self.delegate partListViewDidFinishResizing:self];
	}
	else {
		[self.delegate partListViewDidCancelResizing:self];
	}

}//end endResizingCommitting:


// MARK: - UTILITIES -


//========== chrome ============================================================
- (LDrawStepPartListChrome) chrome
{
	return (self.presentation != nil) ? self.presentation.chrome : [LDrawStepPartListPolicy defaultChrome];

}//end chrome


//========== isAxisPinned: =====================================================
- (BOOL) isAxisPinned:(LPubPliAxis)axis
{
	return (axis == LPubPliAxisWidth) ? self.presentation.widthPinned : self.presentation.heightPinned;

}//end isAxisPinned:


//========== controlAtPoint: ===================================================
- (LDrawStepPartListControl) controlAtPoint:(NSPoint)point
{
	return [LDrawStepPartListPolicy controlAtPoint:[self point2ForViewPoint:point]
										   inFrame:[self frameBox]
									   widthPinned:self.presentation.widthPinned
									  heightPinned:self.presentation.heightPinned];

}//end controlAtPoint:


//========== frameBox ==========================================================
- (Box2) frameBox
{
	return self.presentation.frameRect;

}//end frameBox


//========== point2ForViewPoint: ===============================================
- (Point2) point2ForViewPoint:(NSPoint)point
{
	return V2Make(point.x, point.y);

}//end point2ForViewPoint:


@end
