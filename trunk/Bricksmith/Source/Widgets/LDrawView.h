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

#import "BricksmithUtilities.h"
#import "ColorLibrary.h"
#import "GPU.h"
#import "LDrawRenderer.h"
#import "LDrawGLCamera.h"
#import "LDrawUtilities.h"
#import "MatrixMath.h"
#import "ToolPalette.h"

//Forward declarations
@class FocusRingView;
@class LDrawDirective;
@class LDrawDragHandle;
@class LDrawRenderer;


////////////////////////////////////////////////////////////////////////////////
//
//		LDrawView
//
////////////////////////////////////////////////////////////////////////////////
@interface LDrawView : GPUView <LDrawColorable, LDrawRendererDelegate, LDrawGLCameraScroller>
{
	// The renderer is responsible for viewport math and OpenGL calls. Because
	// of the latter, there is NO PUBLIC ACCESS, since each OpenGL call must be 
	// preceeded by activating the correct context. Thus any renderer-modifying 
	// calls must pass through the LDrawOpenGLView first. 
	LDrawRenderer			*renderer;
	
@private
	FocusRingView	*focusRingView;
	
	__weak IBOutlet id		delegate;
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
	SelectionModeT			marqueeSelectionMode;
	NSEventType				startingGestureType;
	Vector3					nudgeVector;			// direction of nudge action (valid only in nudgeAction callback)
}

// moved to category
//- (void) internalInit;

// Drawing
- (void) draw;

// Accessors
- (LDrawDirective *) LDrawDirective;
- (Vector3) nudgeVectorForMatrix:(Matrix4)partMatrix;
- (ProjectionModeT) projectionMode;
- (LocationModeT) locationMode;
- (Tuple3) viewingAngle;
- (ViewOrientationT) viewOrientation;
- (CGFloat) zoomPercentage;

- (void) setAcceptsFirstResponder:(BOOL)flag;
- (void) setAutosaveName:(NSString *)newName;
- (void) setBackAction:(SEL)newAction;
// moved to category
//- (void) setBackgroundColor:(NSColor *)newColor;
- (void) setDelegate:(id)object;
- (void) setForwardAction:(SEL)newAction;
- (void) setGridSpacingMode:(gridSpacingModeT)newMode;
- (void) setLDrawDirective:(LDrawDirective *) newFile;
- (void) setNudgeAction:(SEL)newAction;
- (void) setProjectionMode:(ProjectionModeT) newProjectionMode;
- (void) setLocationMode:(LocationModeT) newLocationMode;
- (void) setTarget:(id)target;
// moved to category
//- (void) setViewingAngle:(Tuple3)newAngle;
- (void) setViewOrientation:(ViewOrientationT) newAngle;
- (void) setZoomPercentage:(CGFloat) newPercentage;
- (void) setFocusRingVisible:(BOOL)isVisible;

// Actions
- (IBAction) viewOrientationSelected:(id)sender;
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) zoomToFit:(id)sender;

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

// Utilities
- (void) restoreConfiguration;
- (void) saveConfiguration;
// moved to category
//- (void) saveImageToPath:(NSString *)path;
- (void) scrollCameraVisibleRectToPoint:(Point2)visibleRectOrigin;
- (void) scrollCenterToModelPoint:(Point3)modelPoint;
- (void) takeBackgroundColorFromUserDefaults;

@end



////////////////////////////////////////////////////////////////////////////////
//
//		Delegate Methods
//
////////////////////////////////////////////////////////////////////////////////
@interface NSObject (LDrawViewDelegate)

- (void) LDrawViewBecameFirstResponder:(LDrawView *)glView;

- (BOOL) LDrawView:(LDrawView *)glView writeDirectivesToPasteboard:(NSPasteboard *)pasteboard asCopy:(BOOL)copyFlag;
- (void) LDrawView:(LDrawView *)glView acceptDrop:(id < NSDraggingInfo >)info directives:(NSArray *)directives;
- (void) LDrawViewPartsWereDraggedIntoOblivion:(LDrawView *)glView;
- (void) LDrawViewPartDragEnded:(LDrawView*)glView;

- (TransformComponents) LDrawViewPreferredPartTransform:(LDrawView *)glView;

// Delegate method is called when the user has changed the selection of parts 
// by clicking in the view. This does not actually do any selecting; that is 
// left entirely to the delegate. Some may rightly question the design of this 
// system.
- (void) LDrawView:(LDrawView *)glView wantsToSelectDirective:(LDrawDirective *)directiveToSelect byExtendingSelection:(BOOL) shouldExtend;
- (void) LDrawView:(LDrawView*)glView wantsToSelectDirectives:(NSArray *)directivesToSelect selectionMode:(SelectionModeT) selectionMode;
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
