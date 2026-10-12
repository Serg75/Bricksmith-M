//==============================================================================
//
// File:		StepPartListController.m
//
// Purpose:		Owns the step parts list overlay for one document.
//
// Notes:		The decisions are made in the packages: the layout in
//				LDrawFeatures and LDrawStepRendering, the edits and the
//				gestures in LDrawStepEditing. What is left here is the AppKit
//				part: attaching a view, watching notifications and events,
//				menus, cursors and coalescing reloads.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import "StepPartListController.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubPliConstrain.h>

#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>

#import <LDrawStepEditing/LDrawStepCalloutEdit.h>
#import <LDrawStepEditing/LDrawStepCalloutMenuItem.h>
#import <LDrawStepEditing/LDrawStepCalloutTracker.h>

#import <LDrawStepRendering/LDrawStepOverlayPresenter.h>

#import "LDrawView.h"
#import "OverlayViewCategory.h"
#import "StepPartListView.h"


// LDrawView already has the camera calls the overlay's layout needs.
@interface LDrawView (StepOverlayCamera) <LDrawStepOverlayCamera>
@end

@implementation LDrawView (StepOverlayCamera)
@end


@interface StepPartListController () <StepPartListViewDelegate>

/// The viewport the overlay is attached to, if any.
@property (nonatomic, weak, nullable) LDrawView				*hostView;
@property (nonatomic, strong, nullable) StepPartListView	*overlayView;

/// Lays the step out against the viewport's camera, and keeps a drag as a
/// preview until it is let go.
@property (nonatomic, strong) LDrawStepOverlayPresenter		*presenter;

/// Follows a press on a callout's box or on the button that leads back.
@property (nonatomic, strong) LDrawStepCalloutTracker		*calloutTracker;

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
		self->_presenter		= [[LDrawStepOverlayPresenter alloc] init];
		self->_calloutTracker	= [[LDrawStepCalloutTracker alloc] init];
		[self subscribeToChanges];
	}
	return self;

}//end init


//========== dealloc ===========================================================
///
/// @abstract	Takes the overlay down with the controller.
///
/// @discussion	A document can be released on another thread, and its controller
///				with it. A window and an event monitor are for the main thread
///				alone, so there they are handed to it. The block holds what it
///				needs and not the controller, which is going away.
///
//==============================================================================
- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if ([NSThread isMainThread]) {
		[self detach];
		return;
	}

	LDrawView			*hostView	= self.hostView;
	StepPartListView	*overlay	= self.overlayView;
	id					 monitor	= self.eventMonitor;

	dispatch_async(dispatch_get_main_queue(), ^{
		if (monitor != nil) {
			[NSEvent removeMonitor:monitor];
		}
		if (overlay != nil) {
			[hostView removeOverlayView:overlay];
		}
	});

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
	self.presenter.camera = view;
	self.overlayView = [[StepPartListView alloc] initWithFrame:[view bounds]];
	self.overlayView.delegate = self;
	self.overlayView.returnTitle = self.returnTitle;

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

	self.overlayView		= nil;
	self.hostView			= nil;
	self.presenter.camera	= nil;
	[self.presenter reset];
	[self showLayoutInTracker];

}//end detach


// MARK: - ACCESSORS -


- (void) setModel:(LDrawModel *)model
{
	if (self->_model != model) {
		self->_model = model;
		self.presenter.model = model;

		// The pictures were kept through changes to the old model alone.
		[self.overlayView discardCalloutPictures];
		[self setNeedsReload];
	}

}//end setModel:


- (void) setReturnTitle:(NSString *)title
{
	self->_returnTitle = [title copy];
	self.overlayView.returnTitle = title;
	[self showLayoutInTracker];

}//end setReturnTitle:


- (LDrawStepPartListPageAnchor *) pageAnchor
{
	return self.presenter.pageAnchor;

}//end pageAnchor


- (void) setPageAnchor:(LDrawStepPartListPageAnchor *)pageAnchor
{
	self.presenter.pageAnchor = pageAnchor;

}//end setPageAnchor:


- (LDrawStepPartListPresentation *) presentation
{
	return self.presenter.presentation;

}//end presentation


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

	StepPartListView			*overlay	= self.overlayView;
	LDrawStepOverlayPresenter	*presenter	= self.presenter;
	LDrawStepCalloutTracker		*tracker	= self.calloutTracker;

	if (overlay == nil) {
		return;
	}

	presenter.viewSize = [self overlaySize];

	// A box that is being dragged is laid out where it is held.
	presenter.hasCalloutPreview		= tracker.isDragging;
	presenter.calloutPreviewBox		= tracker.draggedBoxIndex;
	presenter.calloutPreviewPoint	= tracker.dragOrigin;

	[presenter reload];

	// The arrows first, so the first draw already has them.
	[overlay setCalloutArrows:presenter.calloutArrows];
	[overlay showPresentation:presenter.presentation];

	[self showLayoutInTracker];

}//end reload


//========== overlaySize =======================================================
- (Size2) overlaySize
{
	NSSize size = self.overlayView.bounds.size;

	return V2MakeSize(size.width, size.height);

}//end overlaySize


//========== centerPageOnStep ==================================================
- (void) centerPageOnStep
{
	[self.presenter centerPageOnStep];

}//end centerPageOnStep


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
	self.presenter.hasSizePreview	= YES;
	self.presenter.previewAxis		= axis;
	self.presenter.previewInches	= inches;

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
	if (self.presenter.hasSizePreview == NO) {
		return;
	}

	LDrawStep				*step	= [self.model visibleStep];
	LDrawStepPartListEdit	*edit	= [self previewEdit];

	self.presenter.hasSizePreview = NO;

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
	self.presenter.hasSizePreview = NO;
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
	return [LDrawStepPartListEdit editForDraggingAxis:self.presenter.previewAxis
											 toInches:self.presenter.previewInches
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


// MARK: - CALLOUTS -


//========== menuItemsAtPoint: =================================================
///
/// @abstract	Makes the menu items for a right click at a point of the
///				overlay. Empty when there is nothing to offer there.
///
/// @discussion	LDrawStepEditing decides what to offer. Here each of its items
///				becomes an NSMenuItem with a localized title, and keeps the
///				edit to apply if it is chosen.
///
//==============================================================================
- (NSArray<NSMenuItem *> *) menuItemsAtPoint:(NSPoint)point
{
	NSMutableArray<NSMenuItem *>		*menuItems	= [NSMutableArray array];
	NSArray<LDrawStepCalloutMenuItem *>	*items		= nil;

	items = [LDrawStepCalloutMenuItem itemsAtPoint:V2Make(point.x, point.y)
									  presentation:self.presentation
											 model:self.model];

	for (LDrawStepCalloutMenuItem *item in items) {
		if (item.isSeparator) {
			[menuItems addObject:[NSMenuItem separatorItem]];
			continue;
		}

		NSString	*title		= [item titleFromLocalizedText:NSLocalizedString(item.titleKey, nil)];
		NSMenuItem	*menuItem	= [[NSMenuItem alloc] initWithTitle:title
															 action:@selector(applyEditOfMenuItem:)
													  keyEquivalent:@""];

		menuItem.target				= self;
		menuItem.representedObject	= item.edit;

		[menuItems addObject:menuItem];
	}

	return menuItems;

}//end menuItemsAtPoint:


//========== applyEditOfMenuItem: ==============================================
///
/// @abstract	Runs when one of those menu items is chosen. Applies the item's
///				edit, then lays the step out again to show the change.
///
//==============================================================================
- (void) applyEditOfMenuItem:(NSMenuItem *)item
{
	[self applyCalloutEdit:item.representedObject];
	[self reload];

}//end applyEditOfMenuItem:


//========== applyCalloutEdit: =================================================
///
/// @abstract	Hands an edit to the document, which writes it into the step on
///				display so that it can be undone. Does nothing for nil.
///
//==============================================================================
- (void) applyCalloutEdit:(nullable LDrawStepCalloutEdit *)edit
{
	if (edit != nil) {
		[self.delegate stepPartListController:self applyCalloutEdit:edit toStep:[self.model visibleStep]];
	}

}//end applyCalloutEdit:


//========== showLayoutInTracker ===============================================
///
/// @abstract	Gives the tracker the callout boxes and the button that leads
///				back, as they are laid out now. Runs after every layout, and
///				when the button's title changes.
///
/// @discussion	The tracker follows clicks and drags on callouts. It needs the
///				current layout to know what the next press is on.
///
//==============================================================================
- (void) showLayoutInTracker
{
	NSRect	button		= [self.overlayView returnButtonRect];
	Box2	buttonBox	= V2MakeBox(NSMinX(button), NSMinY(button), NSWidth(button), NSHeight(button));

	[self.calloutTracker showBoxes:self.presentation.calloutBoxes ?: @[]
							onPage:self.presentation.isOnPage
						  viewSize:[self overlaySize]
				  returnButtonRect:buttonBox];

}//end showLayoutInTracker


//========== actOnCalloutResult: ===============================================
///
/// @abstract	Carries out what the tracker decided about a mouse event on a
///				callout.
///
/// @discussion	A box being dragged is laid out again under the pointer. A
///				dropped box has its edit applied. A click is passed to the
///				document, which shows the called-out submodel or goes back.
///
/// @return		YES when the event was used, so the viewport does not get it.
///
//==============================================================================
- (BOOL) actOnCalloutResult:(LDrawStepCalloutTrackerResult)result
{
	LDrawStepCalloutTracker *tracker = self.calloutTracker;

	switch (result) {

		case LDrawStepCalloutTrackerResultNone:
			return NO;

		case LDrawStepCalloutTrackerResultUsed:
			return YES;

		case LDrawStepCalloutTrackerResultMoved:
			[[NSCursor closedHandCursor] set];
			self.showsControlCursor = YES;

			// Reload now, not on the next pass of the run loop, so the box
			// keeps up with the pointer.
			[self reload];
			return YES;

		case LDrawStepCalloutTrackerResultDropped:
			[self applyCalloutEdit:tracker.edit];
			[self restoreHostCursor];
			[self reload];
			return YES;

		case LDrawStepCalloutTrackerResultChoseCallout:
			[self restoreHostCursor];
			[self.delegate stepPartListController:self
								 didChooseCallout:tracker.chosenCallout
										 submodel:tracker.chosenSubmodel];
			return YES;

		case LDrawStepCalloutTrackerResultChoseReturn:
			[self restoreHostCursor];
			[self.delegate stepPartListControllerDidChooseReturn:self];
			return YES;
	}

	return NO;

}//end actOnCalloutResult:


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
					 | NSEventMaskRightMouseDown
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

	self.ownsGesture				= NO;
	self.presenter.hasSizePreview	= NO;
	[self.calloutTracker reset];

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

	// A right click on a submodel in the list or on a callout's box opens a
	// menu, on the page and off it.
	if ([self handleMenuEvent:event]) {
		return nil;
	}

	// A callout's box and the button that leads back answer a click on the
	// page and off it, so they come before the frame's own controls.
	if ([self handleLinkEvent:event]) {
		return nil;
	}

	// Off the page the frame is not editable, so every other event belongs to
	// the model. Any cursor this controller set is given back.
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


//========== handleMenuEvent: ==================================================
///
/// @abstract	Opens a menu for a right click on a submodel's row of the parts
///				list, or on a callout's box or one of the steps in it.
///
/// @return		YES when a menu is opened, so nothing else sees the click.
///
/// @discussion	A click with Control and nothing else counts too, as it does
///				in the viewport. Caps Lock is no part of a click.
///
//==============================================================================
- (BOOL) handleMenuEvent:(NSEvent *)event
{
	NSEventModifierFlags	modifiers	= event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask
										  & ~NSEventModifierFlagCapsLock;
	BOOL					isMenuClick	= (event.type == NSEventTypeRightMouseDown)
									   || (event.type == NSEventTypeLeftMouseDown
										   && modifiers == NSEventModifierFlagControl);
	LDrawView				*hostView	= self.hostView;

	if (isMenuClick == NO || event.window != [hostView window]) {
		return NO;
	}

	NSPoint point = [self overlayPointForEvent:event];

	if (NSPointInRect(point, self.overlayView.bounds) == NO) {
		return NO;
	}

	NSArray<NSMenuItem *> *items = [self menuItemsAtPoint:point];

	if (items.count == 0) {
		return NO;
	}

	NSMenu	*menu		= [[NSMenu alloc] initWithTitle:@""];
	NSPoint	 location	= [hostView convertPoint:event.locationInWindow fromView:nil];

	for (NSMenuItem *item in items) {
		[menu addItem:item];
	}

	// Once this event is done with: a menu runs an event loop of its own.
	dispatch_async(dispatch_get_main_queue(), ^{
		[menu popUpMenuPositioningItem:nil atLocation:location inView:hostView];
	});

	return YES;

}//end handleMenuEvent:


//========== handleLinkEvent: ==================================================
///
/// @abstract	Follows a click on a callout's box or on the button that leads
///				back, and moves a callout's box that is dragged.
///
/// @return		YES when the event was used, so neither the frame nor the
///				viewport should see it.
///
/// @discussion	The tracker decides what each event means. The drag between a
///				press and its release is kept from the viewport, or it would
///				start a selection.
///
//==============================================================================
- (BOOL) handleLinkEvent:(NSEvent *)event
{
	LDrawStepCalloutTracker	*tracker	= self.calloutTracker;
	NSPoint					 viewPoint	= [self overlayPointForEvent:event];
	Point2					 point		= V2Make(viewPoint.x, viewPoint.y);
	BOOL					 isInWindow	= (event.window == [self.hostView window]);

	switch (event.type) {

		case NSEventTypeMouseMoved:
			if (isInWindow == NO || [tracker isLinkAtPoint:point] == NO) {
				return NO;
			}
			[[NSCursor pointingHandCursor] set];
			self.showsControlCursor = YES;
			return YES;

		case NSEventTypeLeftMouseDown:
			if (isInWindow == NO) {
				[tracker reset];
				return NO;
			}
			if ([tracker beginAtPoint:point] == NO) {
				return NO;
			}

			// The viewport never sees this click, so give it the focus here.
			[[self.hostView window] makeFirstResponder:self.hostView];
			return YES;

		case NSEventTypeLeftMouseDragged:
			return [self actOnCalloutResult:[tracker dragToPoint:point]];

		case NSEventTypeLeftMouseUp:
			return [self actOnCalloutResult:[tracker endAtPoint:point inStep:[self.model visibleStep]]];

		case NSEventTypeKeyDown:
			// Escape abandons the drag. The rest of the gesture is still
			// swallowed, until the mouse comes up.
			if (event.keyCode == 53 && [tracker abandonDrag]) {
				[self reload];
				return YES;
			}
			return NO;

		default:
			return NO;
	}

}//end handleLinkEvent:


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
	// A resize of the overlay changes the layout and nothing else.
	if (notification.object != self.overlayView) {
		LDrawStepOverlayChange change = [self.presenter changeForChangedObject:notification.object];

		if (change == LDrawStepOverlayChangeNone) {
			return;
		}

		if (change & LDrawStepOverlayChangePictures) {
			[self.overlayView discardCalloutPictures];
		}
	}

	[self setNeedsReload];

}//end setNeedsReloadForNotification:


//========== cameraDidChange: ==================================================
///
/// @abstract	The viewport zoomed, scrolled or turned.
///
/// @discussion	The page and the frame on it follow the camera. Off the page
///				only the callouts' arrows do, since they point into the model.
///
//==============================================================================
- (void) cameraDidChange:(NSNotification *)notification
{
	LDrawStepOverlayChange change = [self.presenter changeForCameraMove];

	if (change & LDrawStepOverlayChangeLayout) {
		[self setNeedsReload];
	}
	else if (change & LDrawStepOverlayChangeArrows) {
		[self.overlayView setCalloutArrows:self.presenter.calloutArrows];
	}

}//end cameraDidChange:


@end
