//==============================================================================
//
// File:		LDrawView.h
//
// Purpose:		This is the intermediary between the operating system (events 
//				and view hierarchy) and the LDrawRenderer (responsible for all 
//				platform-independent drawing logic).
//
// Modified:	4/17/05 Allen Smith. Creation Date.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

#ifdef METAL
@import MetalKit;
#endif

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawFeatures/LDrawGrid.h>
#import <LDrawRenderCore/LDrawCamera.h>
#import <LDrawRenderCore/LDrawRenderer.h>

#import "ToolPalette.h"

NS_ASSUME_NONNULL_BEGIN

//Forward declarations
@class FocusRingView;
@class LDrawDirective;
@class LDrawDragHandle;
@class LDrawRenderer;
@class LDrawSceneController;


////////////////////////////////////////////////////////////////////////////////
//
//		LDrawView
//
////////////////////////////////////////////////////////////////////////////////
#ifdef METAL
@interface LDrawView : MTKView <LDrawColorable, LDrawRendererDelegate, LDrawCameraScroller, NSDraggingSource, NSMenuItemValidation>
#else
@interface LDrawView : NSOpenGLView <LDrawColorable, LDrawRendererDelegate, LDrawCameraScroller, NSDraggingSource, NSMenuItemValidation>
#endif
{
	// The renderer is responsible for viewport math and OpenGL calls. Because
	// of the latter, there is NO PUBLIC ACCESS, since each OpenGL call must be 
	// preceeded by activating the correct context. Thus any renderer-modifying 
	// calls must pass through the LDrawOpenGLView first. 
	LDrawRenderer			*renderer;
	LDrawSceneController	*sceneController;
	
@private
	FocusRingView	*focusRingView;
	
	__weak IBOutlet id		ldrawDelegate;
	__weak id				target;
	SEL						backAction;
	SEL						forwardAction;
	SEL						nudgeAction;
	
	BOOL                    acceptsFirstResponder;	// YES if we can become key
	NSString                *autosaveName;
	
	// Event Tracking
	NSTimer                 *mouseDownTimer;		// countdown to beginning drag-and-drop
	NSTimer					*autoscrollTimer;		// timer to keep autoscroll going when mouse is stationary in scroll zone
	BOOL                    canBeginDragAndDrop;	// the next mouse-dragged will initiate a drag-and-drop.  This is based on the timeout for delayed drag mode.
	BOOL                    dragEndedInOurDocument;	// YES if the drag we initiated ended in the document we display
	BOOL					selectionIsMarquee;		// Remembers when a select-click misses and can thus start a marquee.  Only if we HIT an object can we start dragging.
	LDrawSelectionMode		marqueeSelectionMode;
	NSEventType				startingGestureType;	// the pinch or twist a trackpad gesture began with
	NSEventMask				activeGestures;			// the pinches and twists going on
	Vector3					nudgeVector;			// direction of nudge action (valid only in nudgeAction callback)
	
	NSArray					*topLevelObjects;		// holds NIB objects

	Box2					lastReportedVisibleRect;	// last camera rect a change notification was posted for
}

/// The color the view is cleared to behind the model instead of the user's,
/// such as the color of a printed page. Nil for the user's.
@property (nonatomic, copy, nullable) NSColor *pageBackgroundColor;

/// How wide the parts are outlined, in points, as on a printed page. 0 for
/// the usual edge lines.
@property (nonatomic) CGFloat outlineWidth;

/// A plain drag pans, as the hand tool does, and selects nothing. Set while
/// the step's assembly is arranged on LPub3D's page, where parts are not
/// edited.
@property (nonatomic) BOOL plainDragPans;

/// Parts can be selected but not moved: a drag on them, a drag handle and the
/// arrow keys leave them where they are. Set on LPub3D's page.
@property (nonatomic) BOOL locksParts;

/// The view does not turn by the mouse, the trackpad, the orientation keys or
/// the orientation menu. Set on LPub3D's page while the step is not arranged.
@property (nonatomic) BOOL locksTurning;

/// While turning is locked, the cursor the Spin tool shows over a rect of the
/// view instead of the arrow, such as one that says a Command-click on the page
/// starts arranging. Nil shows the arrow everywhere.
@property (nonatomic, readonly, nullable) NSCursor *lockedTurnCursor;
@property (nonatomic, readonly) NSRect lockedTurnCursorRect;
- (void) setLockedTurnCursor:(nullable NSCursor *)cursor inRect:(NSRect)rect;

// Accessors
- (nullable LDrawDirective *) LDrawDirective;
- (Vector3) nudgeVectorForMatrix:(Matrix4)partMatrix;
- (LDrawProjectionMode) projectionMode;
- (LDrawLocationMode) locationMode;
- (Tuple3) viewingAngle;
- (LDrawViewOrientation) viewOrientation;
- (CGFloat) zoomPercentage;

- (void) setAcceptsFirstResponder:(BOOL)flag;
- (void) setAutosaveName:(nullable NSString *)newName;
- (void) setBackAction:(nullable SEL)newAction;
- (void) setLDrawDelegate:(nullable id)object;
- (void) setForwardAction:(nullable SEL)newAction;
- (void) setGridSpacingMode:(LDrawGridSpacingMode)newMode;
- (void) setLDrawDirective:(nullable LDrawDirective *) newFile;
- (void) setNudgeAction:(nullable SEL)newAction;
- (void) setProjectionMode:(LDrawProjectionMode) newProjectionMode;
- (void) setLocationMode:(LDrawLocationMode) newLocationMode;
- (void) setTarget:(nullable id)target;
- (void) setViewOrientation:(LDrawViewOrientation) newAngle;
- (void) setZoomPercentage:(CGFloat) newPercentage;
- (void) setFocusRingVisible:(BOOL)isVisible;

// Actions
- (IBAction) viewOrientationSelected:(nullable id)sender;
- (IBAction) zoomIn:(nullable id)sender;
- (IBAction) zoomOut:(nullable id)sender;
- (IBAction) zoomToFit:(nullable id)sender;

// Events
- (void) resetCursor;

- (void) nudgeKeyDown:(NSEvent *)theEvent;

- (void) directInteractionDragged:(NSEvent *)theEvent;
- (void) dragAndDropDragged:(NSEvent *)theEvent;
- (void) dragHandleDragged:(NSEvent *)theEvent;

- (void) mousePartSelection:(NSEvent *)theEvent;
- (void) mouseZoomClick:(NSEvent*)theEvent;

- (void) cancelClickAndHoldTimer;

// Notifications

/// Posted when the camera zooms, scrolls or turns, with the view as the object.
/// Overlays placed at model points need to move when it arrives.
extern NSString * const LDrawViewCameraDidChangeNotification;


// Utilities
- (void) restoreConfiguration;
- (void) saveConfiguration;
- (void) scrollCameraVisibleRectToPoint:(Point2)visibleRectOrigin;
- (void) scrollCenterToModelPoint:(Point3)modelPoint;
- (NSPoint) viewPointForModelPoint:(Point3)modelPoint;
- (Point3) modelPointForViewPoint:(NSPoint)viewPoint depthReferencePoint:(Point3)depthPoint;
- (NSRect) viewRectForModelPoints:(NSData *)points;
- (NSData *) viewPointsForModelPoints:(NSData *)points;
- (double) pointsPerLDUAtModelPoint:(Point3)modelPoint;
- (Box3) cameraBounds;
- (void) setCameraBounds:(Box3)bounds;
- (void) scrollModelPoint:(Point3)modelPoint toViewPoint:(NSPoint)viewPoint;
+ (NSColor *) backgroundColorFromUserDefaults;
- (void) takeBackgroundColorFromUserDefaults;

@end


@interface LDrawView (SharedGPUContext)
/// Draw the view now instead of at the next display pass.
- (void)draw;
- (void)setBackgroundColor:(nullable NSColor *)newColor;
- (void)setViewingAngle:(Tuple3)newAngle;
/// Activate this view's OpenGL context, or no-op on Metal.
- (void)makeCurrentContext;
/// Bracket block with the OpenGL context lock, or run immediately on Metal.
- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block;
@end



////////////////////////////////////////////////////////////////////////////////
//
//		Delegate Methods
//
////////////////////////////////////////////////////////////////////////////////
@interface NSObject (LDrawViewDelegate)

- (void) LDrawViewBecameFirstResponder:(LDrawView *)glView;

/// Return YES if the delegate did the Zoom to Fit itself, NO to let the view
/// fit the model as usual.
- (BOOL) LDrawViewZoomToFit:(LDrawView *)view;

/// Return YES if the delegate did Zoom In or Zoom Out itself, NO to let the
/// view zoom by the factor as usual.
- (BOOL) LDrawView:(LDrawView *)view zoomByFactor:(CGFloat)factor;

- (BOOL) LDrawView:(LDrawView *)glView writeDirectivesToPasteboard:(NSPasteboard *)pasteboard asCopy:(BOOL)copyFlag;
- (void) LDrawView:(LDrawView *)glView acceptDrop:(id < NSDraggingInfo >)info directives:(NSArray *)directives;
- (void) LDrawViewPartsWereDraggedIntoOblivion:(LDrawView *)glView;
- (void) LDrawViewPartDragEnded:(LDrawView*)glView;

- (TransformComponents) LDrawViewPreferredPartTransform:(LDrawView *)glView;

// Delegate method is called when the user has changed the selection of parts 
// by clicking in the view. This does not actually do any selecting; that is 
// left entirely to the delegate. Some may rightly question the design of this 
// system.
- (void) LDrawView:(LDrawView *)glView wantsToSelectDirective:(nullable LDrawDirective *)directiveToSelect byExtendingSelection:(BOOL) shouldExtend;
- (void) LDrawView:(LDrawView*)glView wantsToSelectDirectives:(NSArray *)directivesToSelect selectionMode:(LDrawSelectionMode) selectionMode;
- (void) LDrawView:(LDrawView *)glView willBeginDraggingHandle:(LDrawDragHandle *)dragHandle;
- (void) LDrawView:(LDrawView *)glView dragHandleDidMove:(LDrawDragHandle *)dragHandle;
- (void) LDrawView:(LDrawView *)glView mouseIsOverPoint:(Point3)modelPoint confidence:(Tuple3)confidence;
- (void) LDrawViewMouseNotPositioning:(LDrawView *)glView;
- (void) markPreviousSelection;
- (void) unmarkPreviousSelection;


@end


////////////////////////////////////////////////////////////////////////////////
//
//		Currently-private API
//		which might just be released in an upcoming OS...
//
////////////////////////////////////////////////////////////////////////////////
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_5
@interface NSEvent (GestureMethods)
- (CGFloat) magnification;
@end
#endif

NS_ASSUME_NONNULL_END
