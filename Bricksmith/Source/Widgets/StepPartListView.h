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

@class LDrawStepPartListPresentation;
@class StepPartListView;

NS_ASSUME_NONNULL_BEGIN

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
/// labels and the pins. Its rectangles are in this view's (flipped)
/// coordinates. Nil shows nothing.
- (void) showPresentation:(nullable LDrawStepPartListPresentation *)presentation;

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
