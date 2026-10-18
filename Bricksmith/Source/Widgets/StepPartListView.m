//==============================================================================
//
// File:		StepPartListView.m
//
// Purpose:		The framed parts list that hovers over the main 3D viewport.
//
// Notes:		Four layers, bottom to top: this view draws the frame, a nested
//				3D view draws the part icons, a chrome view draws the labels
//				over them, and a top view draws the callouts. What they draw
//				is worked out in LDrawStepRendering.
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
#import <LDrawStepRendering/LDrawStepCalloutPictureStore.h>
#import <LDrawStepRendering/LDrawStepOverlayRenderer.h>

#ifdef METAL
#import <LDrawRenderMetal/LDrawRendererMTL.h>
#endif

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


@class StepPartListTopView;

@interface StepPartListView () <LDrawStepCalloutPictureSource, LDrawStepCalloutPictureStoreDelegate>

@property (nonatomic, strong, nullable) LDrawViewerContainer			*iconContainer;
@property (nonatomic, strong, nullable) StepPartListChromeView			*chromeView;
/// Covers the overlay above the list's two views. The callouts are drawn in
/// it, so a box that reaches over the list is not cut off by the list.
@property (nonatomic, strong) StepPartListTopView						*topView;
/// What is on show. Nil when there is nothing.
@property (nonatomic, strong, nullable) LDrawStepPartListPresentation	*presentation;
/// The tint, worked out once from the viewport's color preference. Nil until
/// asked for, and cleared when that preference changes.
@property (nonatomic, strong, nullable) NSColor							*cachedListBackgroundColor;
/// Draws the frame and the callouts, and keeps the callouts' pictures.
@property (nonatomic, strong) LDrawStepOverlayRenderer					*renderer;
@property (nonatomic, strong) LDrawStepCalloutPictureStore				*pictureStore;

// Resize tracking
/// The press in progress on the frame's controls.
@property (nonatomic, strong) LDrawStepPartListResizeTracker			*resizeTracker;

- (void) drawTopContent;

@end


//------------------------------------------------------------------------------
///
/// @class		StepPartListTopView
///
/// @abstract	The view on top of everything else in the overlay. The overlay
///				draws in it what must not be covered by the parts list.
///
//------------------------------------------------------------------------------
@interface StepPartListTopView : NSView

@property (nonatomic, weak, nullable) StepPartListView *overlay;

@end


@implementation StepPartListTopView

//========== isFlipped =========================================================
///
/// @abstract	Flipped like the overlay, so the two share coordinates.
///
//==============================================================================
- (BOOL) isFlipped
{
	return YES;

}//end isFlipped


//========== drawRect: =========================================================
- (void) drawRect:(NSRect)dirtyRect
{
	[self.overlay drawTopContent];

}//end drawRect:

@end


//========== StepPartListPageColor =============================================
NSColor *StepPartListPageColor(LDrawStepPartListPresentation *presentation)
{
	if (presentation.hasPageColor == NO) {
		return nil;
	}

	double rgba[4];

	LPubColorComponentsGetRGBA(presentation.pageColor, rgba);
	rgba[3] = 1.0;

	return StepPartListColorFromRGBA(rgba);

}//end StepPartListPageColor


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

		self->_pictureStore = [[LDrawStepCalloutPictureStore alloc] init];
		[self->_pictureStore setSource:self];
		[self->_pictureStore setDelegate:self];

		self->_renderer = [[LDrawStepOverlayRenderer alloc] init];
		[self->_renderer setPictureStore:self->_pictureStore];
		[self->_renderer setOverflowFormat:NSLocalizedString(@"StepPartListOverflow", nil)];
		[self->_renderer setStepCountFormat:NSLocalizedString(@"StepCalloutSteps", nil)];

		ClipViewToBounds(self);

		self->_topView = [[StepPartListTopView alloc] initWithFrame:[self bounds]];
		[self->_topView setOverlay:self];
		[self->_topView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
		[self addSubview:self->_topView];

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
	self.renderer.presentation = presentation;

	// Before the list, which returns early when the step has none. While a
	// zoom runs, the pictures on show are stretched.
	[self.pictureStore setScale:[self pictureScale]];
	[self.pictureStore makePicturesForBoxes:presentation.calloutBoxes ?: @[] waitingForZoom:YES];

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

	[self.chromeView setCountText:presentation.countText];
	[self.chromeView setAnnotationText:presentation.annotationText];
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
	[self addSubview:container positioned:NSWindowBelow relativeTo:self.topView];
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

	// Over the icons, under the top view.
	[chromeView setChrome:[self chrome]];
	[self addSubview:chromeView positioned:NSWindowBelow relativeTo:self.topView];
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
/// @abstract	Draws the page, and the frame's background, border and pins.
///
//==============================================================================
- (void) drawRect:(NSRect)dirtyRect
{
	[[self rendererForDrawing] drawPageAndFrameInContext:[[NSGraphicsContext currentContext] CGContext]
												viewSize:[self viewSize]];

}//end drawRect:


//========== drawTopContent ====================================================
///
/// @abstract	Draws what goes on top of the parts list: the callouts, and the
///				button that leads back. The top view asks for it.
///
//==============================================================================
- (void) drawTopContent
{
	[[self rendererForDrawing] drawCalloutsInContext:[[NSGraphicsContext currentContext] CGContext]
											viewSize:[self viewSize]];

}//end drawTopContent


//========== rendererForDrawing ================================================
///
/// @abstract	The renderer, with the colors only AppKit knows. They are read
///				for each draw, because they follow the system's appearance.
///
//==============================================================================
- (LDrawStepOverlayRenderer *) rendererForDrawing
{
	self.renderer.listBackgroundColor	= [[self listBackgroundColor] CGColor];
	self.renderer.pinColor				= [[NSColor controlAccentColor] CGColor];

	return self.renderer;

}//end rendererForDrawing


//========== setNeedsDisplay: ==================================================
///
/// @abstract	Marks the top view as well. It is drawn apart from the overlay,
///				so marking the overlay alone leaves it as it was.
///
//==============================================================================
- (void) setNeedsDisplay:(BOOL)needsDisplay
{
	[super setNeedsDisplay:needsDisplay];
	[self.topView setNeedsDisplay:needsDisplay];

}//end setNeedsDisplay:


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
	[[self.iconContainer glView] setBackgroundColor:[self iconBackgroundColor]];
	[self setNeedsDisplay:YES];

}//end applyListBackgroundColor


//========== iconBackgroundColor ===============================================
///
/// @abstract	What the icons are drawn on: the frame's fill, which on the page
///				is the file's. Under a see-through list, what the viewport is
///				cleared to.
///
//==============================================================================
- (NSColor *) iconBackgroundColor
{
	LDrawStepPartListChrome chrome = [self chrome];

	switch (chrome.fill) {
		case LDrawStepPartListFillColor:
			return StepPartListColorFromRGBA(chrome.fillRGBA);

		case LDrawStepPartListFillClear:
			return StepPartListPageColor(self.presentation) ?: [LDrawView backgroundColorFromUserDefaults];

		default:
			return [self listBackgroundColor];
	}

}//end iconBackgroundColor


// MARK: - CALLOUTS -


//========== calloutArrows =====================================================
- (NSArray<NSData *> *) calloutArrows
{
	return self.renderer.calloutArrows;

}//end calloutArrows


//========== setCalloutArrows: =================================================
- (void) setCalloutArrows:(NSArray<NSData *> *)arrows
{
	self.renderer.calloutArrows = arrows;
	[self setNeedsDisplay:YES];

}//end setCalloutArrows:


//========== discardCalloutPictures ============================================
- (void) discardCalloutPictures
{
	[self.pictureStore discardPictures];

}//end discardCalloutPictures


//========== pictureScale ======================================================
///
/// @abstract	Pixels per point of the screen the overlay is on.
///
//==============================================================================
- (CGFloat) pictureScale
{
	CGFloat scale = [[self window] backingScaleFactor];

	return (scale > 0.0) ? scale : 2.0;

}//end pictureScale


//========== newImageOfModel:center:zoomPercentage:size:scale: =================
///
/// @abstract	Draws a callout's picture off screen. The OpenGL renderer has no
///				way to, so there a box names its submodel instead.
///
//==============================================================================
- (nullable CGImageRef) newImageOfModel:(LDrawModel *)model
								 center:(Point3)center
						 zoomPercentage:(double)zoomPercentage
								   size:(Size2)size
								  scale:(double)scale
{
#ifdef METAL
	return [LDrawRenderer newImageOfDirective:model
									   center:center
							   zoomPercentage:zoomPercentage
										 size:CGSizeMake(size.width, size.height)
										scale:scale];
#else
	return NULL;
#endif

}//end newImageOfModel:center:zoomPercentage:size:scale:


//========== calloutPictureStoreDidUpdatePictures: =============================
- (void) calloutPictureStoreDidUpdatePictures:(LDrawStepCalloutPictureStore *)store
{
	[self setNeedsDisplay:YES];

}//end calloutPictureStoreDidUpdatePictures:


//========== calloutPictureStoreShouldUpdatePictures: ==========================
///
/// @abstract	NO while the overlay is in no window, where no picture can be
///				shown.
///
//==============================================================================
- (BOOL) calloutPictureStoreShouldUpdatePictures:(LDrawStepCalloutPictureStore *)store
{
	return [self window] != nil;

}//end calloutPictureStoreShouldUpdatePictures:


// MARK: - THE WAY BACK -


//========== returnTitle =======================================================
- (NSString *) returnTitle
{
	return self.renderer.returnTitle;

}//end returnTitle


//========== setReturnTitle: ===================================================
- (void) setReturnTitle:(NSString *)title
{
	self.renderer.returnTitle = title;
	[self setNeedsDisplay:YES];

}//end setReturnTitle:


//========== returnButtonRect ==================================================
- (NSRect) returnButtonRect
{
	return StepPartListRectFromBox([self.renderer returnButtonRectForViewSize:[self viewSize]]);

}//end returnButtonRect


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


//========== viewSize ==========================================================
- (Size2) viewSize
{
	return V2MakeSize(NSWidth(self.bounds), NSHeight(self.bounds));

}//end viewSize


//========== controlAtPoint: ===================================================
- (LDrawStepPartListControl) controlAtPoint:(NSPoint)point
{
	return [self.presentation controlAtPoint:[self point2ForViewPoint:point]];

}//end controlAtPoint:


//========== point2ForViewPoint: ===============================================
- (Point2) point2ForViewPoint:(NSPoint)point
{
	return V2Make(point.x, point.y);

}//end point2ForViewPoint:


@end
