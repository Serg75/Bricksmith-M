//==============================================================================
//
//  File:       LDrawStepCalloutTracker.h
//  Package:    LDrawStepEditing
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawModel;
@class LDrawStep;
@class LDrawStepCallout;
@class LDrawStepCalloutBox;
@class LDrawStepCalloutEdit;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepCalloutTrackerResult
///
/// @abstract   What an event means for the host.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepCalloutTrackerResult) {
	/// The event is for neither a callout nor the button that leads back.
	LDrawStepCalloutTrackerResultNone			= 0,
	/// The event belongs to the gesture, and there is nothing to do for it.
	LDrawStepCalloutTrackerResultUsed			= 1,
	/// A drag moved the box: lay the step out again, with the drag as a
	/// preview.
	LDrawStepCalloutTrackerResultMoved			= 2,
	/// A drag ended: apply `edit` when there is one, and lay the step out again.
	LDrawStepCalloutTrackerResultDropped		= 3,
	/// A callout's box was clicked: show `chosenSubmodel` of `chosenCallout`.
	LDrawStepCalloutTrackerResultChoseCallout	= 4,
	/// The button that leads back was clicked.
	LDrawStepCalloutTrackerResultChoseReturn	= 5
};


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutTracker
///
/// @abstract   Follows one press on a callout's box or on the button that
///             leads back: a click that follows it, or a drag that moves the
///             box.
///
/// @discussion The host passes points of the view and does what the answers
///             say. The document is not touched here.
///
///             A press and its release must be on the same thing, like a
///             button. Only a box on the page that the file places can be
///             dragged. The drag is shown as a preview, and becomes one edit
///             when it is let go.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutTracker : NSObject

/// Tells the tracker what is on show: the step's callout boxes as they were
/// laid out, whether that was on LPub3D's page, the size of the view, and
/// where the button that leads back is, or an empty box for none. Call it
/// after every layout, before the next event.
- (void) showBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
			onPage:(BOOL)isOnPage
		  viewSize:(Size2)viewSize
  returnButtonRect:(Box2)returnButtonRect
	NS_SWIFT_NAME(show(_:onPage:viewSize:returnButtonRect:));

/// Whether a click at this point follows something: a callout's box or the
/// button.
- (BOOL) isLinkAtPoint:(Point2)point NS_SWIFT_NAME(isLink(at:));

/// A press at this point. YES when it is on a callout's box or on the button.
/// The rest of the gesture then belongs to the tracker.
- (BOOL) beginAtPoint:(Point2)point NS_SWIFT_NAME(begin(at:));

/// The pointer moved with the button down. Once it has gone far enough for
/// the press to be a drag, the box follows it.
- (LDrawStepCalloutTrackerResult) dragToPoint:(Point2)point NS_SWIFT_NAME(drag(to:));

/// The button came up at this point. `step` is the step on display, which a
/// dropped box's edit is for.
- (LDrawStepCalloutTrackerResult) endAtPoint:(Point2)point inStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(end(at:inStep:));

/// Abandons a drag, as Escape does. Returns YES when there was one: lay the
/// step out again. The rest of the gesture still belongs to the tracker,
/// until the button comes up.
- (BOOL) abandonDrag;

/// Forgets the gesture in progress.
- (void) reset;

/// A drag in progress, which box of the step it moves, and where the box's
/// corner is held, in the view. The host lays the step out with these as the
/// preview.
@property (nonatomic, readonly) BOOL isDragging;
@property (nonatomic, readonly) NSUInteger draggedBoxIndex;
@property (nonatomic, readonly) Point2 dragOrigin;

/// What the last `Dropped` writes. Nil when the drag was abandoned.
@property (nonatomic, readonly, nullable) LDrawStepCalloutEdit *edit;

/// The callout the last `ChoseCallout` is for, and the submodel its box shows
/// where the click was.
@property (nonatomic, readonly, nullable) LDrawStepCallout *chosenCallout;
@property (nonatomic, readonly, nullable) LDrawModel *chosenSubmodel;

@end

NS_ASSUME_NONNULL_END
