//==============================================================================
//
// File:		LDrawRenderer.h
//
// Purpose:		Draws an LDrawFile with OpenGL.
//
// Modified:	4/17/05 Allen Smith. Creation Date.
//
//==============================================================================
#import <Foundation/Foundation.h>

#import "ColorLibrary.h"
#import "MacLDraw.h"
#import "MatrixMath.h"
#import "LDrawCamera.h"
#import "LDrawUtilities.h"

//Forward declarations
@class LDrawDirective;
@class LDrawDragHandle;
@protocol LDrawRendererDelegate;
@protocol LDrawCameraScroller;


////////////////////////////////////////////////////////////////////////////////
//
//		Types
//
////////////////////////////////////////////////////////////////////////////////


// Draw Mode
typedef enum
{
	LDrawGLDrawNormal			= 0,	//full draw
	LDrawGLDrawExtremelyFast	= 1		//bounds only
	
} RotationDrawModeT;


////////////////////////////////////////////////////////////////////////////////
//
//		LDrawRenderer
//
////////////////////////////////////////////////////////////////////////////////
@interface LDrawRenderer : NSObject <LDrawColorable>
{
	id<LDrawRendererDelegate>	delegate;

	LDrawDirective		*fileBeingDrawn;		// Should only be an LDrawFile or LDrawModel.
												// if you want to do anything else, you must
												// tweak the selection code in LDrawDrawableElement
												// and here in -mouseUp: to handle such cases.

	LDrawCamera			*camera;

	float				backgroundColor[4];
	Box2				selectionMarquee;		// in view coordinates. ZeroBox2 means no marquee.
	RotationDrawModeT	rotationDrawMode;		// drawing detail while rotating.
	ViewOrientationT	viewOrientation;		// our orientation
	NSInteger			framesSinceStartTime;
	NSTimeInterval		fpsStartTime;

	// Event Tracking
	BOOL				isGesturing;			// true if performing a multitouch trackpad gesture.
	BOOL				isTrackingDrag;			// true if the last mousedown was followed by a drag, and we're tracking it (drag-and-drop doesn't count)

	// Metal
	CommandQueue	_commandQueue;
	PipelineState	_pipelineState;
	Buffer			_vertexUniformBuffer;
	Buffer			_fragmentUniformBuffer;
	DepthStencilState _depthStencilState;
}

// Initialization
- (id) initWithBounds:(NSSize)boundsIn;

// Accessors
- (LDrawDragHandle*) activeDragHandle;
- (BOOL) didPartSelection;
- (Matrix4) getMatrix;
- (BOOL) isTrackingDrag;
- (LDrawDirective *) LDrawDirective;
- (ProjectionModeT) projectionMode;
- (LocationModeT) locationMode;
- (Box2) selectionMarquee;
- (Tuple3) viewingAngle;
- (ViewOrientationT) viewOrientation;
- (Box2) viewport;
- (CGFloat) zoomPercentage;
- (CGFloat) zoomPercentageForGL;

- (void) setAllowsEditing:(BOOL)flag;
- (void) setDelegate:(id<LDrawRendererDelegate>)object withScroller:(id<LDrawCameraScroller>)scroller;
- (void) setDraggingOffset:(Vector3)offsetIn;
- (void) setGridSpacing:(float)newValue;
- (void) setLDrawDirective:(LDrawDirective *) newFile;
- (void) setGraphicsSurfaceSize:(Size2)size;						// This is how we find out that the visible frame of our window is bigger or smaller
- (void) setProjectionMode:(ProjectionModeT) newProjectionMode;
- (void) setLocationMode:(LocationModeT) newLocationMode;
- (void) setSelectionMarquee:(Box2)newBox;
- (void) setTarget:(id)target;
- (void) setViewingAngle:(Tuple3)newAngle;
- (void) setViewOrientation:(ViewOrientationT) newAngle;
- (void) setZoomPercentage:(CGFloat) newPercentage;
- (void) moveCamera:(Vector3)delta;

// Actions
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) zoomToFit:(id)sender;

// Events
- (void) mouseMoved:(Point2)point_view;
- (void) mouseDown;
- (void) mouseDragged;
- (void) mouseUp;

- (void) mouseCenterClick:(Point2)viewClickedPoint;
- (BOOL) mouseSelectionClick:(Point2)point_view selectionMode:(SelectionModeT)selectionMode;						// Returns TRUE if we hit any parts at all.
- (void) mouseZoomInClick:(Point2)viewClickedPoint;
- (void) mouseZoomOutClick:(Point2)viewClickedPoint;

- (void) dragHandleDraggedToPoint:(Point2)point_view constrainDragAxis:(BOOL)constrainDragAxis;
- (void) panDragged:(Vector2)viewDirection location:(Point2)point_view;
- (void) rotationDragged:(Vector2)viewDirection;																	// This is how we get track-balled
- (void) zoomDragged:(Vector2)viewDirection;
- (void) mouseSelectionDragToPoint:(Point2)point_view selectionMode:(SelectionModeT) selectionMode;
- (void) beginGesture;
- (void) endGesture;
- (void) rotateByDegrees:(float)angle;																				// Track-pad twist gesture

// Drag and Drop
- (void) draggingEnteredAtPoint:(Point2)point_view directives:(NSArray *)directives setTransform:(BOOL)setTransform originatedLocally:(BOOL)originatedLocally;
- (void) endDragging;
- (void) updateDragWithPosition:(Point2)point_view constrainAxis:(BOOL)constrainAxis;
- (BOOL) updateDirectives:(NSArray *)directives withDragPosition:(Point2)point_view depthReferencePoint:(Point3)modelReferencePoint constrainAxis:(BOOL)constrainAxis;

// Notifications
- (void) displayNeedsUpdating:(NSNotification *)notification;

// Utilities
- (BOOL) autoscrollPoint:(Point2)point_view relativeToRect:(Box2)viewRect;
//- (NSArray *) getDirectivesUnderPoint:(Point2)point_view amongDirectives:(NSArray *)directives fastDraw:(BOOL)fastDraw;
- (NSArray *) getDirectivesUnderRect:(Box2)rect_view amongDirectives:(NSArray *)directives fastDraw:(BOOL)fastDraw;
//- (NSArray *) getPartsFromHits:(NSDictionary *)hits;
- (void) publishMouseOverPoint:(Point2)viewPoint;
- (void) setZoomPercentage:(CGFloat)newPercentage preservePoint:(Point2)viewPoint;		// This and setZoomPercentage are how we zoom.
- (void) scrollBy:(Vector2)scrollDelta;
- (void) scrollCameraVisibleRectToPoint:(Point2)visibleRectOrigin;
- (void) scrollCenterToModelPoint:(Point3)modelPoint;									// These two are how we do gesture-based scrolls
- (void) scrollModelPoint:(Point3)modelPoint toViewportProportionalPoint:(Point2)viewportPoint;
- (void) updateRotationCenter;															// A camera "property change"

// - Geometry
- (Point2) convertPointFromViewport:(Point2)viewportPoint;
- (Point2) convertPointToViewport:(Point2)point_view;
- (void) getModelAxesForViewX:(Vector3 *)outModelX Y:(Vector3 *)outModelY Z:(Vector3 *)outModelZ;
- (Point3) modelPointForPoint:(Point2)viewPoint;
- (Point3) modelPointForPoint:(Point2)viewPoint depthReferencePoint:(Point3)depthPoint;

@end


////////////////////////////////////////////////////////////////////////////////
//
//		Delegate Methods
//
////////////////////////////////////////////////////////////////////////////////
@protocol LDrawRendererDelegate <NSObject>

@required
- (void) LDrawRendererNeedsFlush:(LDrawRenderer*)renderer;
- (void) LDrawRendererNeedsRedisplay:(LDrawRenderer*)renderer;

@optional
- (void) LDrawRenderer:(LDrawRenderer*)renderer mouseIsOverPoint:(Point3)modelPoint confidence:(Tuple3)confidence;
- (void) LDrawRendererMouseNotPositioning:(LDrawRenderer*)renderer;

- (TransformComponents) LDrawRendererPreferredPartTransform:(LDrawRenderer*)renderer;

- (void) LDrawRenderer:(LDrawRenderer*)renderer wantsToSelectDirective:(LDrawDirective *)directiveToSelect byExtendingSelection:(BOOL) shouldExtend;
- (void) LDrawRenderer:(LDrawRenderer*)renderer wantsToSelectDirectives:(NSArray *)directivesToSelect selectionMode:(SelectionModeT) selectionMode;
- (void) LDrawRenderer:(LDrawRenderer*)renderer willBeginDraggingHandle:(LDrawDragHandle *)dragHandle;
- (void) LDrawRenderer:(LDrawRenderer*)renderer dragHandleDidMove:(LDrawDragHandle *)dragHandle;

- (void) markPreviousSelection:(LDrawRenderer*)renderer;
- (void) unmarkPreviousSelection:(LDrawRenderer*)renderer;



@end
