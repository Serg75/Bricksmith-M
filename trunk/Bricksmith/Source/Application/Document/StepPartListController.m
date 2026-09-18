//==============================================================================
//
// File:		StepPartListController.m
//
// Purpose:		Owns the step parts list overlay for one document.
//
// Notes:		The decisions are made in LDrawFeatures. What is left here is
//				the AppKit part: attaching a view, watching notifications and
//				coalescing reloads.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import "StepPartListController.h"

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>

#import "LDrawView.h"
#import "OverlayViewCategory.h"
#import "StepPartListView.h"


@interface StepPartListController () <StepPartListViewDelegate>

/// The viewport the overlay is attached to, if any.
@property (nonatomic, weak, nullable) LDrawView				*hostView;
@property (nonatomic, strong, nullable) StepPartListView	*overlayView;

/// During a drag the frame is packed from this instead of the document, so
/// nothing is written until the drag is let go.
@property (nonatomic) BOOL				hasPreview;
@property (nonatomic) LPubPliAxis		previewAxis;
@property (nonatomic) double			previewInches;

/// What the last reload showed. Its page state gates the mouse and the
/// camera, so they need no lookup of their own.
@property (nonatomic, strong, nullable) LDrawStepPartListPresentation	*presentation;

/// The document window's events, watched while the overlay is attached.
@property (nonatomic, strong, nullable) id	eventMonitor;

/// The mouse-down was on the frame's controls, so its drag and mouse-up go to
/// the frame too, even after Escape.
@property (nonatomic) BOOL					ownsGesture;

/// This controller set the cursor, so the viewport's own must be put back when
/// the pointer leaves the frame's controls.
@property (nonatomic) BOOL					showsControlCursor;

/// Recollects, repacks and redraws. Safe to call when not attached.
- (void) reload;

@end


@implementation StepPartListController


// MARK: - INITIALIZATION -


- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_pageAnchor = [[LDrawStepPartListPageAnchor alloc] init];
		[self subscribeToChanges];
	}
	return self;

}//end init


- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self detach];

}//end dealloc


// MARK: - ATTACHMENT -


//========== attachToView: =====================================================
///
/// @abstract	Puts the overlay on a viewport.
///
/// @discussion	The overlay goes in a child window, which is the only reliable
///				way to draw over a GL or Metal surface. That window follows the
///				viewport, so the overlay is always viewport-sized.
///
//==============================================================================
- (void) attachToView:(LDrawView *)view
{
	if (view == self.hostView) {
		[self reload];
		return;
	}

	[self detach];

	if (view == nil) {
		return;
	}

	self.hostView = view;
	self.overlayView = [[StepPartListView alloc] initWithFrame:[view bounds]];
	self.overlayView.delegate = self;

	// The overlay is 1x1 until its window starts following the viewport, and
	// the layout depends on that size, so repack whenever it changes.
	[self.overlayView setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(setNeedsReloadForNotification:)
												 name:NSViewFrameDidChangeNotification
											   object:self.overlayView];

	// On LPub3D's page the frame and the outline are pinned to the model, so a
	// zoom, a scroll or a turn changes the layout.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(cameraDidChange:)
												 name:LDrawViewCameraDidChangeNotification
											   object:view];

	[view addOverlayView:self.overlayView];

	// The overlay's window ignores the mouse, so its controls are driven from
	// the document window's events.
	[self startWatchingEvents];

	[self reload];

}//end attachToView:


//========== detach ============================================================
///
/// @abstract	Takes the overlay down and releases its 3D surface.
///
//==============================================================================
- (void) detach
{
	[self stopWatchingEvents];

	if (self.hostView != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:LDrawViewCameraDidChangeNotification
													  object:self.hostView];
	}

	if (self.overlayView != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:NSViewFrameDidChangeNotification
													  object:self.overlayView];

		if (self.hostView != nil) {
			[self.hostView removeOverlayView:self.overlayView];
		}
	}

	self.overlayView	= nil;
	self.hostView		= nil;
	self.presentation	= nil;

}//end detach


// MARK: - ACCESSORS -


- (void) setModel:(LDrawModel *)model
{
	if (self->_model != model) {
		self->_model = model;
		[self setNeedsReload];
	}

}//end setModel:


// MARK: - RELOADING -


//========== reload ============================================================
///
/// @abstract	Recollects, repacks and redraws.
///
//==============================================================================
- (void) reload
{
	// This reload covers any coalesced one still queued.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];

	StepPartListView *overlay = self.overlayView;

	if (overlay == nil) {
		return;
	}

	// One walk of the file for all the lookups of this redraw.
	[LDrawStepPartListPolicy performWithCachedLookups:^{
		self.presentation = [LDrawStepPartListPresentation presentationForModel:self.model
																		   host:[self hostState]];
	}];

	[overlay showPresentation:self.presentation];

}//end reload


// MARK: - RESIZING -


//========== partListView:previewingAxis:atInches: =============================
///
/// @abstract	The drag moved. Repack at the new size without touching the
///				document.
///
//==============================================================================
- (void) partListView:(StepPartListView *)view
	   previewingAxis:(LPubPliAxis)axis
			 atInches:(double)inches
{
	self.hasPreview		= YES;
	self.previewAxis	= axis;
	self.previewInches	= inches;

	// At once, not coalesced: the frame has to keep up with the pointer.
	[self reload];

}//end partListView:previewingAxis:atInches:


//========== partListViewDidFinishResizing: ====================================
///
/// @abstract	The drag ended. One undoable edit, or none at all if the size
///				did not really change.
///
//==============================================================================
- (void) partListViewDidFinishResizing:(StepPartListView *)view
{
	if (self.hasPreview == NO) {
		return;
	}

	LDrawStep				*step	= [self.model visibleStep];
	LDrawStepPartListEdit	*edit	= [self previewEdit];

	self.hasPreview = NO;

	[self.delegate stepPartListController:self applyEdit:edit toStep:step];
	[self reload];

}//end partListViewDidFinishResizing:


//========== partListViewDidCancelResizing: ====================================
///
/// @abstract	The drag was abandoned. Nothing was written, so dropping the
///				preview undoes it.
///
//==============================================================================
- (void) partListViewDidCancelResizing:(StepPartListView *)view
{
	self.hasPreview = NO;
	[self reload];

}//end partListViewDidCancelResizing:


//========== partListView:didClickPinForAxis: ==================================
///
/// @abstract	A local pin was clicked: give the axis back to whatever it
///				inherits.
///
//==============================================================================
- (void) partListView:(StepPartListView *)view didClickPinForAxis:(LPubPliAxis)axis
{
	LDrawStep				*step	= [self.model visibleStep];
	LDrawStepPartListEdit	*edit	= [LDrawStepPartListEdit editClearingAxis:axis inStep:step];

	[self.delegate stepPartListController:self applyEdit:edit toStep:step];
	[self reload];

}//end partListView:didClickPinForAxis:


//========== previewEdit =======================================================
///
/// @abstract	The edit that letting go of the drag now would make.
///
//==============================================================================
- (LDrawStepPartListEdit *) previewEdit
{
	return [LDrawStepPartListEdit editForDraggingAxis:self.previewAxis
											 toInches:self.previewInches
											  inModel:self.model];

}//end previewEdit


//========== setNeedsReload ====================================================
///
/// @abstract	Coalesces a burst of change notifications into one reload.
///
/// @discussion	Stepping through a model, or one edit touching several
///				directives, sends a run of notifications.
///
//==============================================================================
- (void) setNeedsReload
{
	if (self.overlayView == nil) {
		return;
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
	[self performSelector:@selector(reload) withObject:nil afterDelay:0.0];

}//end setNeedsReload


// MARK: - EVENTS -


//========== startWatchingEvents ===============================================
///
/// @abstract	Routes the document window's events on the frame's controls to
///				the overlay.
///
/// @discussion	The overlay's window ignores the mouse so the model stays
///				clickable. This monitor sees the events first and keeps the ones
///				on an edge or a pin.
///
//==============================================================================
- (void) startWatchingEvents
{
	if (self.eventMonitor != nil) {
		return;
	}

	NSEventMask mask = NSEventMaskLeftMouseDown
					 | NSEventMaskLeftMouseDragged
					 | NSEventMaskLeftMouseUp
					 | NSEventMaskMouseMoved
					 | NSEventMaskKeyDown;

	__weak StepPartListController *weakSelf = self;

	self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
															  handler:^NSEvent *(NSEvent *event) {
		StepPartListController *controller = weakSelf;

		return (controller != nil) ? [controller handleEvent:event] : event;
	}];

}//end startWatchingEvents


//========== stopWatchingEvents ================================================
///
/// @abstract	Stops watching, abandoning any gesture in progress.
///
/// @discussion	Such a drag was never written to the document, so dropping the
///				preview cancels it.
///
//==============================================================================
- (void) stopWatchingEvents
{
	if (self.eventMonitor != nil) {
		[NSEvent removeMonitor:self.eventMonitor];
		self.eventMonitor = nil;
	}

	self.ownsGesture	= NO;
	self.hasPreview		= NO;

	[self restoreHostCursor];

}//end stopWatchingEvents


//========== handleEvent: ======================================================
///
/// @abstract	Takes the events that belong to the frame and passes on the
///				rest.
///
/// @return		nil when the frame used the event, so the viewport never sees
///				it. Otherwise the event itself.
///
//==============================================================================
- (NSEvent *) handleEvent:(NSEvent *)event
{
	StepPartListView	*overlay	= self.overlayView;
	NSWindow			*window		= [self.hostView window];

	if (overlay == nil || window == nil) {
		return event;
	}

	// Off the page the frame is not editable, so every event belongs to the
	// model. Any cursor this controller set is given back.
	if (self.presentation.isOnPage == NO) {
		[self restoreHostCursor];
		return event;
	}

	// A gesture that started on the frame stays with it, wherever the pointer
	// goes. Anything else counts only in this document's window.
	if (self.ownsGesture == NO && event.window != window) {
		return event;
	}

	switch (event.type) {

		case NSEventTypeMouseMoved:
			return [self updateCursorForEvent:event] ? nil : event;

		case NSEventTypeLeftMouseDown: {
			NSPoint point = [self overlayPointForEvent:event];

			if (NSPointInRect(point, overlay.bounds) == NO
				|| [overlay beginInteractionAtPoint:point] == NO) {
				return event;
			}

			// The viewport never sees this click, so give it the focus here.
			// A click on the frame would otherwise leave the focus wherever it
			// was, and the view's own menu commands would stay disabled.
			[window makeFirstResponder:self.hostView];

			self.ownsGesture = YES;
			return nil;
		}

		case NSEventTypeLeftMouseDragged:
			if (self.ownsGesture == NO) {
				return event;
			}
			[overlay continueResizingAtPoint:[self overlayPointForEvent:event]];
			return nil;

		case NSEventTypeLeftMouseUp:
			if (self.ownsGesture == NO) {
				return event;
			}
			self.ownsGesture = NO;
			[overlay endResizingCommitting:YES];
			[self updateCursorForEvent:event];
			return nil;

		case NSEventTypeKeyDown:
			// Escape abandons the drag. The rest of the gesture is still
			// swallowed, until the mouse comes up.
			if (overlay.isResizing && event.keyCode == 53) {
				[overlay endResizingCommitting:NO];
				return nil;
			}
			return event;

		default:
			return event;
	}

}//end handleEvent:


//========== overlayPointForEvent: =============================================
///
/// @abstract	Where an event happened, in the overlay view's coordinates.
///
/// @discussion	The event belongs to the document window and the overlay is in
///				a child window, so the point goes through the screen.
///
//==============================================================================
- (NSPoint) overlayPointForEvent:(NSEvent *)event
{
	StepPartListView	*overlay	= self.overlayView;
	NSPoint				 onScreen	= (event.window != nil)
									? [event.window convertPointToScreen:event.locationInWindow]
									: event.locationInWindow;
	NSPoint				 inWindow	= [[overlay window] convertPointFromScreen:onScreen];

	return [overlay convertPoint:inWindow fromView:nil];

}//end overlayPointForEvent:


//========== updateCursorForEvent: =============================================
///
/// @abstract	A resize cursor over an edge, a pointing hand over a clearable
///				pin, and the viewport's own cursor back once the pointer leaves
///				them.
///
/// @return		Whether the pointer is over one of the frame's controls.
///
/// @discussion	The overlay's window ignores the mouse, so the cursor is set by
///				hand. The viewport sets its own on entry only, so a cursor set
///				here stays until -resetCursor puts the viewport's back.
///
//==============================================================================
- (BOOL) updateCursorForEvent:(NSEvent *)event
{
	StepPartListView	*overlay	= self.overlayView;
	NSPoint				 point		= [self overlayPointForEvent:event];
	BOOL				 onOverlay	= NSPointInRect(point, overlay.bounds);
	NSCursor			*cursor		= onOverlay ? [overlay cursorAtPoint:point] : nil;

	if (cursor != nil) {
		[cursor set];
		self.showsControlCursor = YES;
		return YES;
	}

	[self restoreHostCursor];
	return NO;

}//end updateCursorForEvent:


//========== restoreHostCursor =================================================
///
/// @abstract	Gives the viewport its own cursor back, if this controller had
///				replaced it.
///
//==============================================================================
- (void) restoreHostCursor
{
	if (self.showsControlCursor == NO) {
		return;
	}

	self.showsControlCursor = NO;
	[self.hostView resetCursor];

}//end restoreHostCursor


// MARK: - UTILITIES -


//========== assemblyScale =====================================================
///
/// @abstract	Points per LDU the viewport is drawing the model at.
///
/// @discussion	A perspective view draws a near part larger than the zoom alone
///				says, so the page is sized from the scale the model is drawn at
///				beside the anchor. The ratio between the two is measured once
///				and kept, or every step's rotation would resize the page.
///
//==============================================================================
- (double) assemblyScale
{
	LDrawStepPartListPageAnchor	*pageAnchor	= self.pageAnchor;
	double						 zoomScale	= [self.hostView zoomPercentage] / 100.0;

	if (pageAnchor.needsDrawnScale) {
		Point3 anchor = [pageAnchor anchorForModel:self.model];

		[pageAnchor noteDrawnPointsPerLDU:[self.hostView pointsPerLDUAtModelPoint:anchor]
							  atZoomScale:zoomScale];
	}

	return [pageAnchor assemblyScaleForZoomScale:zoomScale];

}//end assemblyScale


//========== hostState =========================================================
///
/// @abstract	What only the view can tell the package: its size, the scale the
///				model is drawn at, where the page anchor lands, and any drag.
///
//==============================================================================
- (LDrawStepPartListHostState) hostState
{
	LDrawStepPartListHostState	host	= {0};
	NSSize						size	= self.overlayView.bounds.size;

	host.viewSize		= V2MakeSize(size.width, size.height);
	host.hasPreview		= self.hasPreview;
	host.previewAxis	= self.previewAxis;
	host.previewInches	= self.previewInches;

	// Measuring projects through the camera, so only when there is a page.
	if ([LDrawStepPartListPolicy drawsPageInModel:self.model] && self.hostView != nil) {
		Point3	anchor			= [self.pageAnchor anchorForModel:self.model];
		NSPoint	anchorViewPoint	= [self.hostView viewPointForModelPoint:anchor];

		host.assemblyScale	= [self assemblyScale];
		host.anchorInView	= V2Make(anchorViewPoint.x, anchorViewPoint.y);
	}

	return host;

}//end hostState


//========== subscribeToChanges ================================================
///
/// @abstract	Everything that can change what the list should say.
///
//==============================================================================
- (void) subscribeToChanges
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

	for (NSString *name in @[LDrawDirectiveDidChangeNotification,
							 LDrawStepDidChangeNotification,
							 LDrawGroupSuppressionDidChangeNotification,
							 LDrawPartLibraryDidChangeNotification]) {

		[center addObserver:self
				   selector:@selector(setNeedsReloadForNotification:)
					   name:name
					 object:nil];
	}

}//end subscribeToChanges


//========== setNeedsReloadForNotification: ====================================
///
/// @abstract	Something the list depends on changed: the content, or the
///				overlay's size.
///
/// @discussion	These are observed for every document, so a change to a
///				directive in another file is ignored.
///
//==============================================================================
- (void) setNeedsReloadForNotification:(NSNotification *)notification
{
	id object = notification.object;

	if ([object isKindOfClass:[LDrawDirective class]]) {

		LDrawFile *file = [(LDrawDirective *)object enclosingFile];

		if (file != nil && file != [self.model enclosingFile]) {
			return;
		}
	}

	[self setNeedsReload];

}//end setNeedsReloadForNotification:


//========== cameraDidChange: ==================================================
///
/// @abstract	The viewport zoomed, scrolled or turned.
///
/// @discussion	Only the page and the frame on it follow the camera, so off the
///				page there is nothing to redo.
///
//==============================================================================
- (void) cameraDidChange:(NSNotification *)notification
{
	if (self.presentation.isOnPage == NO) {
		return;
	}

	[self setNeedsReload];

}//end cameraDidChange:


@end
