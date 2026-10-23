//==============================================================================
//
// File:		StepPartListView.h
//
// Purpose:		The framed parts list that hovers over the top-left of the main
//				3D viewport in Steps mode.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>
#import <LDrawStepRendering/LDrawStepOverlayRenderer.h>

@class LDrawStepCalloutPicture;
@class LDrawStepPartListPresentation;
@class StepPartListView;

NS_ASSUME_NONNULL_BEGIN

/// The color the file gives the page, opaque, or nil for none. The viewport is
/// cleared to it behind the model.
extern NSColor * _Nullable StepPartListPageColor(LDrawStepPartListPresentation * _Nullable presentation);

////////////////////////////////////////////////////////////////////////////////
//
// protocol StepPartListViewDelegate
//
////////////////////////////////////////////////////////////////////////////////

/// The view reports gestures and the delegate decides what they mean. A
/// resize repacks the frame at once, but reaches the document only at the end
/// of the drag.
@protocol StepPartListViewDelegate <NSObject>

/// Repack the frame at this size. Nothing is written to the document yet.
- (void) partListView:(StepPartListView *)view
	   previewingAxis:(LPubPliAxis)axis
			 atInches:(double)inches;

/// The drag ended. The previewed size becomes an edit.
- (void) partListViewDidFinishResizing:(StepPartListView *)view;

/// The drag was abandoned; forget the preview.
- (void) partListViewDidCancelResizing:(StepPartListView *)view;

/// A pin was clicked. Drop the step's own size on this axis, so it falls back
/// to the size in force before this step's own line.
- (void) partListView:(StepPartListView *)view didClickPinForAxis:(LPubPliAxis)axis;

/// The corner pin was clicked. Drop the step's own place for the list, so it
/// goes back to the place in force before this step.
- (void) partListViewDidClickPlacementPin:(StepPartListView *)view;

@end

////////////////////////////////////////////////////////////////////////////////
//
// class StepPartListView
//
////////////////////////////////////////////////////////////////////////////////

/// Added to the main viewport with -addOverlayView:, which puts it in a child
/// window so it draws over the 3D surface. That window covers the whole
/// viewport, so this view does too and draws the frame inside its bounds. It
/// gets no events; StepPartListController drives it.
@interface StepPartListView : NSView

@property (nonatomic, weak, nullable) id<StepPartListViewDelegate> delegate;

/// Shows what the presentation says: the page, the frame, the icons, the
/// labels, the pins and the callouts. Its rectangles are in this view's
/// (flipped) coordinates. Nil shows nothing.
- (void) showPresentation:(nullable LDrawStepPartListPresentation *)presentation;

// MARK: Callouts

/// Each callout's arrows, in this view's coordinates: one block of
/// LDrawStepCalloutArrow values per box, in the order of the presentation's
/// boxes. They are worked out against the viewport's camera. Set them before
/// showing a presentation, and again when the camera moves.
@property (nonatomic, copy, nullable) NSArray<NSData *> *calloutArrows;

/// Forgets the pictures made of the callouts' submodels, so the next
/// presentation draws them again. Call it when what they show may have
/// changed.
- (void) discardCalloutPictures;

/// Forgets which icons are shown, so the next presentation puts its model in
/// the icon view. Call it when what the icons show may have changed.
- (void) forgetIcons;

/// What the way back says, or nil for none. Shown as a button in the view's
/// bottom left corner while a called-out submodel is on display.
@property (nonatomic, copy, nullable) NSString *returnTitle;

/// Draws a dashed line in the accent color around the step, and a line around
/// the page, while it is arranged.
@property (nonatomic) BOOL showsArrangeFrame;

/// The part of the view the viewport's scroll bars leave uncovered. The line
/// around the page stays inside it. An empty rect is the whole view.
@property (nonatomic) NSRect unobscuredRect;

/// Guides on the page, such as those the arranged step or a dragged list
/// meets: Box2 lines in the view, drawn in the accent color.
@property (nonatomic, copy, nullable) NSData *guides;

/// Where the previous step's assembly sat on its page: Point2 values in the
/// view, filled faintly in the accent color.
@property (nonatomic, copy, nullable) NSData *ghostOutline;

/// Shows a picture of the previous step's assembly faintly, in place of its
/// outline's fill. Nil shows the outline. The picture is drawn off screen once
/// for each thing and size it shows.
- (void) showGhostPicture:(nullable LDrawStepCalloutPicture *)picture;

/// The frame of the item the arrow keys move, outlined in the accent color.
/// An empty rect shows none.
@property (nonatomic) NSRect selectionRect;

/// What the strip across the top of the view says while the view is turned
/// away from the step's angle, or nil for no strip, and its buttons' titles.
@property (nonatomic, copy, nullable) NSString *turnedViewText;
@property (nonatomic, copy, nullable) NSString *useAngleTitle;
@property (nonatomic, copy, nullable) NSString *stepAngleTitle;

/// Where the button that leads back is, or an empty rect when there is none.
- (NSRect) returnButtonRect;

/// Where the turned view's strip and its buttons are, or empty rects when
/// there is no strip.
- (NSRect) turnedViewStripRect;
- (NSRect) rectOfTurnedViewButton:(LDrawStepTurnedViewButton)button;

// MARK: Interaction
//
// The overlay window ignores the mouse, so the model under it stays
// clickable and this view never gets an event. StepPartListController watches
// the document window and calls these instead. Points are in this view's
// flipped coordinates.

/// Whether a resize drag is in progress.
@property (nonatomic, readonly) BOOL isResizing;

/// The cursor for the control under this point: a resize cursor over an edge,
/// a pointing hand over a pin. Nil when the point is on neither.
- (nullable NSCursor *) cursorAtPoint:(NSPoint)point;

/// The cursor that says a Command-click on the page starts arranging: the
/// pointing hand with a badge of the dashed frame drawn around a step being
/// arranged, in the accent color.
+ (NSCursor *) arrangeStartCursor;

/// Handles a mouse-down: clears a pin or starts a resize. Returns NO if the
/// click belongs to the model instead.
- (BOOL) beginInteractionAtPoint:(NSPoint)point;

/// Repacks at the new size as the drag moves, without touching the document.
- (void) continueResizingAtPoint:(NSPoint)point;

/// Ends a drag. Committing makes the previewed size one undoable edit;
/// otherwise the preview is dropped and the document is untouched.
- (void) endResizingCommitting:(BOOL)shouldCommit;

@end

NS_ASSUME_NONNULL_END
