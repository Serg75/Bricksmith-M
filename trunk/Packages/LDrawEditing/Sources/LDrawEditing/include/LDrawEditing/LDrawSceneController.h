//==============================================================================
//
//  File:       LDrawSceneController.h
//  Package:    LDrawEditing
//
//  Purpose:    UI-framework-free controller for editor scene state.
//
//  Info:       Owns selection marquee, drag-handle hit testing, marquee and
//              click hit testing, drag-handle drag, and part drag-and-drop
//              placement. The host view (AppKit or UIKit) forwards normalized
//              2D/3D events to this controller. Camera tools stay on
//              LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/MacLDraw.h>
#import <LDrawRenderCore/LDrawCamera.h>

@class LDrawDirective;
@class LDrawDragHandle;

NS_ASSUME_NONNULL_BEGIN

@protocol LDrawSceneControllerDelegate;
@protocol LDrawSceneControllerRendererBridge;

//------------------------------------------------------------------------------
///
/// @class      LDrawSceneController
///
/// @abstract   Editor-side scene controller. Holds selection / marquee state
///             and consumes the read-only camera + viewport state from
///             `LDrawRenderer` (LDrawRenderCore).
///
//------------------------------------------------------------------------------
@interface LDrawSceneController : NSObject

@property (nonatomic, weak, nullable)   id<LDrawSceneControllerDelegate>          delegate;
@property (nonatomic, weak, nullable)   id<LDrawSceneControllerRendererBridge>    rendererBridge;

@property (nonatomic, readonly)         Box2                                      selectionMarquee;
@property (nonatomic, readonly)         BOOL                                      isTrackingDrag;
@property (nonatomic, readonly)         BOOL                                      didPartSelection;
@property (nonatomic, readonly, nullable) LDrawDragHandle                        *activeDragHandle;

/// Create a scene controller that talks to the renderer through the given
/// bridge. Camera tools stay on LDrawRenderer.
- (instancetype)initWithRendererBridge:(id<LDrawSceneControllerRendererBridge>)bridge NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Selection
/// The box (in view coordinates) in which to draw the selection marquee.
///
/// Also copies the box onto the renderer so the overlay can draw.
- (void)setSelectionMarquee:(Box2)box;

// Mouse events (normalized to view-space points)
/// Mouse is hovering in the view. Forward the point so the host can show
/// model coordinates under the cursor.
- (void)mouseMovedToPoint:(Point2)point_view;

/// Signals that a mouse-down has been received; clear various state flags in
/// preparation for selection or dragging.
///
/// The host view is responsible for correct interpretation of the event and
/// routing it to the appropriate methods here. Camera tools stay on
/// LDrawRenderer.
- (void)mouseDownAtPoint:(Point2)point_view;

/// Signals that a mouse-drag has been received; set tracking flags used to
/// distinguish a click from a drag on mouse-up.
///
/// The host view is responsible for correct interpretation of the event and
/// routing it here.
- (void)mouseDraggedToPoint:(Point2)point_view;

/// Signals that a mouse-up has been received; clear tracking and drag-handle
/// state in preparation for selection or dragging.
///
/// The marquee is left in place. `-[LDrawRenderer mouseUp]` inspects its size
/// to decide whether to redisplay, then zeros it.
- (void)mouseUpAtPoint:(Point2)point_view;

/// Attempt to select the part under the click, or start a zero-size marquee
/// if nothing was hit.
///
/// Hit-tests drag handles first, then the model. The nearest directive is
/// offered to the host via the renderer bridge.
///
/// @return YES if a directive was hit, NO otherwise.
- (BOOL)mouseSelectionClickAtPoint:(Point2)point_view selectionMode:(SelectionModeT)selectionMode;

/// Update the selection marquee to the dragged point and select every
/// directive under the rectangle.
///
/// The host maps modifier keys to selectionMode (replace, extend, subtract,
/// intersection).
- (void)mouseSelectionDragToPoint:(Point2)point_view selectionMode:(SelectionModeT)selectionMode;

/// Move the active drag handle (and its vertex) with the mouse.
///
/// If constrainDragAxis is YES, motion is isolated to the greatest component
/// so the handle tracks one world axis.
- (void)dragHandleDraggedToPoint:(Point2)point_view constrainDragAxis:(BOOL)constrainDragAxis;

// Part drag-and-drop (normalized view-space points). The host still owns
// pasteboard unarchiving; this controller places the parts in the model.
/// Record the offset from the first dragged part to the click, so re-entering
/// the originating view does not snap part 0 under the mouse.
- (void)setDraggingOffset:(Vector3)offset;

/// Place dragged parts in the model at the given view point.
///
/// If setTransform is YES, each part receives the host's preferred transform
/// (identity when the renderer has no delegate). Locally originated drags
/// are a move; others are a copy.
- (void)draggingEnteredAtPoint:(Point2)point_view
					directives:(NSArray *)directives
				  setTransform:(BOOL)setTransform
			 originatedLocally:(BOOL)originatedLocally;

/// Move currently-dragged parts as the mouse moves.
- (void)updateDragWithPosition:(Point2)point_view constrainAxis:(BOOL)constrainAxis;

/// Clear draggingDirectives on the file being drawn and ask the renderer to
/// redisplay.
- (void)endDragging;

@end


//------------------------------------------------------------------------------
///
/// @protocol   LDrawSceneControllerDelegate
///
/// @abstract   Receives selection / drag-handle change notifications.
///
//------------------------------------------------------------------------------
@protocol LDrawSceneControllerDelegate <NSObject>

@optional
/// The scene controller changed the current selection.
- (void)sceneController:(LDrawSceneController *)controller
	 didChangeSelection:(NSArray<LDrawDirective *> *)selection;

/// The user began dragging a vertex handle.
- (void)sceneController:(LDrawSceneController *)controller
 didBeginDraggingHandle:(LDrawDragHandle *)handle;

/// A vertex handle moved during a drag.
- (void)sceneController:(LDrawSceneController *)controller
  didMoveDraggingHandle:(LDrawDragHandle *)handle;

/// The user released a vertex handle.
- (void)sceneController:(LDrawSceneController *)controller
   didEndDraggingHandle:(LDrawDragHandle *)handle;

@end


//------------------------------------------------------------------------------
///
/// @protocol   LDrawSceneControllerRendererBridge
///
/// @abstract   Read-only camera / viewport queries the scene controller needs
///             from the renderer. Implemented by LDrawRenderer (in
///             LDrawRenderCore) so the controller does not pull in the renderer
///             package.
///
//------------------------------------------------------------------------------
@protocol LDrawSceneControllerRendererBridge <NSObject>

@required
- (Box2)viewport;
- (Point2)convertPointToViewport:(Point2)point_view;
- (Point3)modelPointForPoint:(Point2)viewPoint;
- (Point3)modelPointForPoint:(Point2)viewPoint depthReferencePoint:(Point3)depthPoint;
- (NSArray *)getDirectivesUnderRect:(Box2)rect_view amongDirectives:(NSArray *)directives fastDraw:(BOOL)fastDraw;

- (BOOL)allowsEditing;
- (LDrawDirective *)LDrawDirective;
- (LDrawCamera *)camera;
- (float)gridSpacing;
- (void)setSelectionMarquee:(Box2)box;
- (void)publishMouseOverPoint:(Point2)viewPoint;
- (TransformComponents)preferredPartTransform;

- (void)wantsToSelectDirective:(nullable LDrawDirective *)directive byExtendingSelection:(BOOL)shouldExtend;
- (void)wantsToSelectDirectives:(NSArray *)directives selectionMode:(SelectionModeT)selectionMode;
- (void)willBeginDraggingHandle:(LDrawDragHandle *)handle;
- (void)dragHandleDidMove:(LDrawDragHandle *)handle;
- (void)noteNeedsDisplay;

@end

NS_ASSUME_NONNULL_END
