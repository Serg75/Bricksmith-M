//==============================================================================
//
// File:		LDrawRenderer.m
//
// Purpose:		Draws an LDrawFile with OpenGL.
//
//				This class is responsible for all platform-independent logic, 
//				including math and OpenGL operations. It also contains a number 
//				of methods which would be called in response to events; it is 
//				the responsibility of the platform layer to receive and 
//				interpret those events and pass them to us. 
//
//				The "event" type methods here take high-level parameters. For 
//				example, we don't check -- or want to know! -- if the option key 
//				is down. The platform layer figures out stuff like that, and 
//				more importantly, figures out what it *means*. The *meaning* is 
//				what the renderer's methods care about.
//
// Note:		This file uses manual reference counting.
//
//  Created by Allen Smith on 4/17/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "LDrawRenderer.h"

#import "LDrawColor.h"
#import "LDrawDirective.h"
#import "LDrawDragHandle.h"
#import "LDrawFile.h"
#import "LDrawModel.h"
#import "LDrawMPDModel.h"
#import "LDrawPart.h"
#import "LDrawStep.h"
#import "LDrawUtilities.h"
#import "LDrawShaderRendererGPU.h"
#include "MacLDraw.h"

#define TIME_BOXTEST				0	// output timing data for how long box tests and marquee drags take.
#define HANDLE_SIZE 3

@interface LDrawRenderer ()
{
	id<LDrawCameraScroller>	scroller;
	id						target;
	BOOL					allowsEditing;

	// Drawing Environment
	LDrawColor				*color;					// default color to draw parts if none is specified

	// Event Tracking
	float					gridSpacing;

	BOOL					isStartingDrag;			// this is the first event in a drag
	NSTimer                 *mouseDownTimer;		// countdown to beginning drag-and-drop
	BOOL                    canBeginDragAndDrop;	// the next mouse-dragged will initiate a drag-and-drop.
	BOOL                    didPartSelection;		// tried part selection during this click
	BOOL                    dragEndedInOurDocument;	// YES if the drag we initiated ended in the document we display
	Vector3                 draggingOffset;			// displacement between part 0's position and the initial click point of the drag
	Point3                  initialDragLocation;	// point in model where part was positioned at draggingEntered
	LDrawDragHandle			*activeDragHandle;		// drag handle hit on last mouse-down (or nil)
}
@end

@implementation LDrawRenderer

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== init ==============================================================
//
// Purpose:		Initialize the object.
//
//==============================================================================
- (id) initWithBounds:(NSSize)boundsIn
{
	self = [super init];
	
	//---------- Initialize instance variables ---------------------------------
	
	[self setLDrawColor:[[ColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor]];
	
	camera = [[LDrawCamera alloc] init];
	camera.graphicsSurfaceSize = V2MakeSize(boundsIn.width, boundsIn.height);

	isTrackingDrag					= NO;
	selectionMarquee				= ZeroBox2;
	rotationDrawMode				= LDrawGLDrawNormal;
	gridSpacing 					= 20.0;
		
	[self setViewOrientation:ViewOrientation3D];
	
	return self;
	
}//end initWithFrame:


#pragma mark -
#pragma mark DRAWING
#pragma mark -

//========== isFlipped =========================================================
//
// Purpose:		This lets us appear in the upper-left of scroll views rather 
//				than the bottom. The view should draw just fine whether or not 
//				it is flipped, though.
//
//==============================================================================
- (BOOL) isFlipped
{
	return YES;
	
}//end isFlipped


//========== isOpaque ==========================================================
//
// Note:		Our content completely covers this view. (This is just here as a 
//				reminder; NSOpenGLViews are opaque by default.) 
//
//==============================================================================
- (BOOL) isOpaque
{
	return YES;
}


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== activeDragHandle ==================================================
//
// Purpose:		Returns a drag handle if we are currently locked into a 
//				drag-handle drag. Otherwise returns nil. 
//
//==============================================================================
- (LDrawDragHandle*) activeDragHandle
{
	return self->activeDragHandle;
}


//========== didPartSelection ==================================================
//
// Purpose:		Returns whether the most-recent mouseDown resulted in a 
//				part-selection attempt. This is only valid when called during a 
//				mouse click. 
//
//==============================================================================
- (BOOL) didPartSelection
{
	return self->didPartSelection;
}


//========== getInverseMatrix ==================================================
//
// Purpose:		Returns the inverse of the current modelview matrix. You can 
//				multiply points by this matrix to convert screen locations (or 
//				vectors) to model points.
//
// Note:		This function filters out the translation which is caused by 
//				"moving" the camera with gluLookAt. That allows us to continue 
//				working with the model as if it's positioned at the origin, 
//				which means that points we generate with this matrix will 
//				correspond to points in the LDraw model itself.
//
//==============================================================================
- (Matrix4) getInverseMatrix
{
	Matrix4	transformation	= Matrix4CreateFromGLMatrix4([camera getModelView]);
	Matrix4	inversed		= Matrix4Invert(transformation);
	
	return inversed;
	
}//end getInverseMatrix


//========== getMatrix =========================================================
//
// Purpose:		Returns the the current modelview matrix, basically.
//
// Note:		This function filters out the translation which is caused by 
//				"moving" the camera with gluLookAt. That allows us to continue 
//				working with the model as if it's positioned at the origin, 
//				which means that points we generate with this matrix will 
//				correspond to points in the LDraw model itself. 
//
//==============================================================================
- (Matrix4) getMatrix
{
	return Matrix4CreateFromGLMatrix4([camera getModelView]);
	
}//end getMatrix


//========== isTrackingDrag ====================================================
//
// Purpose:		Returns YES if a mouse-drag is currently in progress.
//
//==============================================================================
- (BOOL) isTrackingDrag
{
	return self->isTrackingDrag;
}


//========== LDrawColor ========================================================
//
// Purpose:		Returns the LDraw color code of the receiver.
//
//==============================================================================
-(LDrawColor *) LDrawColor
{
	return self->color;
	
}//end color


//========== LDrawDirective ====================================================
//
// Purpose:		Returns the file or model being drawn by this view.
//
//==============================================================================
- (LDrawDirective *) LDrawDirective
{
	return self->fileBeingDrawn;
	
}//end LDrawDirective


//========== projectionMode ====================================================
//
// Purpose:		Returns the current projection mode (perspective or 
//				orthographic) used in the view.
//
//==============================================================================
- (ProjectionModeT) projectionMode
{
	return [camera projectionMode];
	
}//end projectionMode


//========== locationMode ====================================================
//
// Purpose:		Returns the current location mode (model or walkthrough).
//
//==============================================================================
- (LocationModeT) locationMode
{
	return [camera locationMode];
	
}//end locationMode


//========== selectionMarquee ==================================================
//==============================================================================
- (Box2) selectionMarquee
{
	return self->selectionMarquee;
}


//========== viewingAngle ======================================================
//
// Purpose:		Returns the modelview rotation, in degrees.
//
// Notes:		These numbers do *not* include the fact that LDraw has an 
//				upside-down coordinate system. So if this method returns 
//				(0,0,0), that means "Front, looking right-side up." 
//				
//==============================================================================
- (Tuple3) viewingAngle
{
	return [camera viewingAngle];

}//end viewingAngle


//========== viewOrientation ===================================================
//
// Purpose:		Returns the current camera orientation for this view.
//
//==============================================================================
- (ViewOrientationT) viewOrientation
{
	return self->viewOrientation;
	
}//end viewOrientation


//========== viewport ==========================================================
//
// Purpose:		Returns the viewport. Origin is the lower-left.
//
//==============================================================================
- (Box2) viewport
{
	Box2	viewport = ZeroBox2;
	viewport.size = camera.graphicsSurfaceSize;
	return viewport;
}


//========== zoomPercentage ====================================================
//
// Purpose:		Returns the percentage magnification being applied to the 
//				receiver. (200 means 2x magnification.)  This is the 'nominal'
//				zoom the user sees - it should be used by UI and tool code.
//
//==============================================================================
- (CGFloat) zoomPercentage
{
	return [camera zoomPercentage];
	
}//end zoomPercentage


//========== zoomPercentage ====================================================
//
// Purpose:		Returns the percentage magnification being applied to drawing;
//				this represents the scale from GL viewport coordinates (which
//				are always window manager pixels) to NS document coordinates 
//				(which DO get scaled).
//
//				Use this routine to convert between NS view and GL viewport 
//				coordinates.
//
// Notes:		When walk-through is engaged, zoom controls the camera FOV but
//				leaves the document untouched at window size.  So this routine
//				checks the camera mode and just returns 100.0.
//
//==============================================================================
- (CGFloat) zoomPercentageForGL
{
	if([self locationMode] == LocationModeWalkthrough)
		return 100.0;
	return [camera zoomPercentage];
	
}//end zoomPercentageForGL


#pragma mark -

//========== setAllowsEditing: =================================================
//
// Purpose:		Sets whether the renderer supports part selection and dragging.
//
// Notes:		Querying a delegate isn't sufficient.
//
//==============================================================================
- (void) setAllowsEditing:(BOOL)flag
{
	self->allowsEditing = flag;
}


//========== setDelegate: ======================================================
//
// Purpose:		Sets the object that acts as the delegate for the receiver. 
//
//				This object relies on the the delegate to interface with the 
//				window manager to do things like scrolling. 
//
//==============================================================================
- (void) setDelegate:(id<LDrawRendererDelegate>)object withScroller:(id<LDrawCameraScroller>)newScroller
{
	// weak link.
	self->delegate = object;
	self->scroller = newScroller;
	[self->camera setScroller:newScroller];

}//end setDelegate:


//========== setDragEndedInOurDocument: ========================================
//
// Purpose:		When a dragging operation we initiated ends outside the 
//				originating document, we need to know about it so that we can 
//				tell the document to completely delete the directives it started 
//				dragging. (They are merely hidden during the drag.) However, 
//				each document can be represented by multiple views, so it is 
//				insufficient to simply test whether the drag ended within this 
//				view. 
//
//				So, when a drag ends in any LDrawView, it inspects the 
//				dragging source to see if it represents the same document. If it 
//				does, it sends the source this message. If this message hasn't 
//				been received by the time the drag ends, this view will 
//				automatically instruct its document to purge the source 
//				directives, since the directives were actually dragged out of 
//				their document. 
//
//==============================================================================
- (void) setDragEndedInOurDocument:(BOOL)flag
{
	self->dragEndedInOurDocument = flag;
	
}//end setDragEndedInOurDocument:


//========== setDraggingOffset: ================================================
//
// Purpose:		Sets the offset to apply to the first drag-and-drop part's 
//				position. This is used when initiating drag-and-drop while 
//				clicking on a point other than the exact center of the part. We 
//				want to maintain the clicked point under the cursor, but it is 
//				internally easier to move the part's centerpoint. This offset 
//				allows us to translate between the two. 
//
//==============================================================================
- (void) setDraggingOffset:(Vector3)offsetIn
{
	self->draggingOffset = offsetIn;
}


//========== setGridSpacing: ===================================================
//
// Purpose:		Sets the grid amount by which things are dragged.
//
//==============================================================================
- (void) setGridSpacing:(float)newValue
{
	self->gridSpacing = newValue;
}


//========== setLDrawColor: ====================================================
//
// Purpose:		Sets the base color for parts drawn by this view which have no 
//				color themselves.
//
//==============================================================================
-(void) setLDrawColor:(LDrawColor *)newColor
{
#ifndef METAL
	[newColor retain];
	[self->color release];
#endif
	self->color = newColor;
	
	[self->delegate LDrawRendererNeedsRedisplay:self];

}//end setColor


//========== LDrawDirective: ===================================================
//
// Purpose:		Sets the file being drawn in this view.
//
//				We also do other housekeeping here associated with tracking the 
//				model. We also automatically center the model in the view.
//
//==============================================================================
- (void) setLDrawDirective:(LDrawDirective *)newFile
{
	BOOL    virginView  = (self->fileBeingDrawn == nil);
	Box3	bounds		= InvalidBox;
	
	//Update our variable.
#ifndef METAL
	[newFile retain];
	[self->fileBeingDrawn release];
#endif
	self->fileBeingDrawn = newFile;
	
	if(newFile)
	{
		bounds = [newFile boundingBox3];
		[camera setModelSize:bounds];
	}

	[self->delegate LDrawRendererNeedsRedisplay:self];
	
	if(virginView == YES)
	{
		[self scrollModelPoint:ZeroPoint3 toViewportProportionalPoint:V2Make(0.5,0.5)];
	}

	//Register for important notifications.
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LDrawDirectiveDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LDrawFileActiveModelDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LDrawModelRotationCenterDidChangeNotification object:nil];
	
	if(self->fileBeingDrawn != nil)
	{	
		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(displayNeedsUpdating:)
					   name:LDrawDirectiveDidChangeNotification
					 object:self->fileBeingDrawn ];
		
		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(activeModelDidChange:)
					   name:LDrawFileActiveModelDidChangeNotification
					 object:self->fileBeingDrawn ];
		
		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(rotationCenterChanged:)
					   name:LDrawModelRotationCenterDidChangeNotification
					 object:self->fileBeingDrawn ];
	}
	
	[self updateRotationCenter];
	
}//end setLDrawDirective:


//========== setGraphicsSurfaceSize: ===========================================
///
/// @abstract	Sets the size of the view which will be rendered with the 3D
/// 			engine. This should be in screen coordinates.
///
//==============================================================================
- (void) setGraphicsSurfaceSize:(Size2)size
{
	[camera setGraphicsSurfaceSize:size];
	[self->delegate LDrawRendererNeedsRedisplay:self];
}


//========== setProjectionMode: ================================================
//
// Purpose:		Sets the projection used when drawing the receiver:
//					- orthographic is like a Mercator map; it distorts deeper 
//									objects.
//					- perspective draws deeper objects toward a vanishing point; 
//									this is how humans see the world.
//
//==============================================================================
- (void) setProjectionMode:(ProjectionModeT)newProjectionMode
{
	[camera setProjectionMode:newProjectionMode];
	
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} //end setProjectionMode:


//========== setLocationMode: ================================================
//
// Purpose:		Sets the location mode used when drawing the receiver.
//					- model points the camera at the model center from a distance.
//					- walk-through puts the camera _on_ the model center.
//
//==============================================================================
- (void) setLocationMode:(LocationModeT)newLocationMode
{
	[camera setLocationMode:newLocationMode];
	
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} //end setLocationMode:


//========== setSelectionMarquee: ==============================================
//
// Purpose:		The box (in view coordinates) in which to draw the selection 
//				marquee. 
//
//==============================================================================
- (void) setSelectionMarquee:(Box2)newBox_view
{
	self->selectionMarquee = newBox_view;
}


//========== setTarget: ========================================================
//
// Purpose:		Sets the object which is the receiver of this view's action 
//				methods. 
//
//==============================================================================
- (void) setTarget:(id)newTarget
{
	self->target = newTarget;
	
}//end setTarget:


//========== setViewingAngle: ==================================================
//
// Purpose:		Sets the modelview rotation, in degrees. The angle is applied in 
//				x-y-z order. 
//
// Notes:		These numbers do *not* include the fact that LDraw has an 
//				upside-down coordinate system. So if this method returns 
//				(0,0,0), that means "Front, looking right-side up." 
//
//==============================================================================
- (void) setViewingAngle:(Tuple3)newAngle
{
	[camera setViewingAngle:newAngle];
	[self->delegate LDrawRendererNeedsRedisplay:self];

}//end setViewingAngle:


//========== setViewOrientation: ===============================================
//
// Purpose:		Changes the camera position from which we view the model. 
//				i.e., ViewOrientationFront means we see the model head-on.
//
//==============================================================================
- (void) setViewOrientation:(ViewOrientationT)newOrientation
{
	Tuple3	newAngle	= [LDrawUtilities angleForViewOrientation:newOrientation];

	self->viewOrientation = newOrientation;
		
	// Apply the angle itself.
	[self setViewingAngle:newAngle];
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
}//end setViewOrientation:


//========== setZoomPercentage: ================================================
//
// Purpose:		Enlarges (or reduces) the magnification on this view. The center 
//				point of the original magnification remains the center point of 
//				the new magnification. Does absolutely nothing if this view 
//				isn't contained within a scroll view.
//
// Parameters:	newPercentage: new zoom; pass 100 for 100%, etc. Automatically 
//				constrained to a minimum of 1%. 
//
//==============================================================================
- (void) setZoomPercentage:(CGFloat)newPercentage
{
	[camera setZoomPercentage:newPercentage];
	[delegate LDrawRendererNeedsRedisplay:self];
}


//========== moveCamera: =======================================================
//
// Purpose:		Moves the camera's rotation center by a fixed offset.  Used to
//				walk around the walk-through camera, or to change the model's
//				center of rotation for the model camera.
//
//==============================================================================
- (void) moveCamera:(Vector3)delta
{
	[camera setRotationCenter:V3Add([camera rotationCenter], delta)];
	[delegate LDrawRendererNeedsRedisplay:self];
}//end moveCamera


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== zoomIn: ===========================================================
//
// Purpose:		Enlarge the scale of the current LDraw view.
//
//==============================================================================
- (IBAction) zoomIn:(id)sender
{
	CGFloat currentZoom	= [self zoomPercentage];
	CGFloat newZoom		= currentZoom * 2;
	
	[self setZoomPercentage:newZoom];
	
}//end zoomIn:


//========== zoomOut: ==========================================================
//
// Purpose:		Shrink the scale of the current LDraw view.
//
//==============================================================================
- (IBAction) zoomOut:(id)sender
{
	CGFloat currentZoom	= [self zoomPercentage];
	CGFloat newZoom		= currentZoom / 2;
	
	[self setZoomPercentage:newZoom];
	
}//end zoomOut:


//========== zoomToFit: ========================================================
//
// Purpose:		Enlarge or shrink the zoom and scroll the model such that its 
//				image perfectly fills the visible area of the view 
//
//==============================================================================
- (IBAction) zoomToFit:(id)sender
{
	Size2   maxContentSize          = ZeroSize2;
	Box3    boundingBox             = InvalidBox;
	Point3  center                  = ZeroPoint3;
	Matrix4 modelView               = IdentityMatrix4;
	Matrix4 projection              = IdentityMatrix4;
	Box2    viewport                = [self viewport];
	Box3    projectedBounds         = InvalidBox;
	Box2    projectionRect          = ZeroBox2;
	Size2   zoomScale2D             = ZeroSize2;
	CGFloat zoomScaleFactor         = 0.0;
	
	// How many onscreen pixels do we have to work with?
	maxContentSize = viewport.size;
//	NSLog(@"windowVisibleRect = %@", NSStringFromRect(windowVisibleRect));
//	NSLog(@"maxContentSize = %@", NSStringFromSize(maxContentSize));
	
	// Get bounds
	if([self->fileBeingDrawn respondsToSelector:@selector(boundingBox3)] )
	{
		boundingBox = [(id)self->fileBeingDrawn boundingBox3];
		if(V3EqualBoxes(boundingBox, InvalidBox) == NO)
		{		
			// Project the bounds onto the 2D "canvas"
			modelView   = Matrix4CreateFromGLMatrix4([camera getModelView]);
			projection  = Matrix4CreateFromGLMatrix4([camera getProjection]);

			projectedBounds = [(id)self->fileBeingDrawn
									   projectedBoundingBoxWithModelView:modelView
															  projection:projection
																	view:viewport ];
			projectionRect  = V2MakeBox(projectedBounds.min.x, projectedBounds.min.y,   // origin
										projectedBounds.max.x - projectedBounds.min.x,  // width
										projectedBounds.max.y - projectedBounds.min.y); // height
										
			
			//---------- Find zoom scale -----------------------------------
			// Completely fill the viewport with the image
			
			zoomScale2D.width   = maxContentSize.width  / V2BoxWidth(projectionRect);
			zoomScale2D.height  = maxContentSize.height / V2BoxHeight(projectionRect);
			
			zoomScaleFactor		= MIN(zoomScale2D.width, zoomScale2D.height);
			
			
			//---------- Find visual center point --------------------------
			// One might think this would be V3CenterOfBox(bounds). But it's 
			// not. It seems perspective distortion can cause the visual 
			// center of the model to be someplace else. 
			
			Point2	graphicalCenter_viewport	= V2BoxMid(projectionRect);
			Point2	graphicalCenter_view		= [self convertPointFromViewport:graphicalCenter_viewport];
			Point3	graphicalCenter_model		= ZeroPoint3;

			graphicalCenter_model       = [self modelPointForPoint:graphicalCenter_view
											   depthReferencePoint:center];
			
			
			//---------- Zoom to Fit! --------------------------------------
			
			[self setZoomPercentage:([self zoomPercentage] * zoomScaleFactor)];
			[self scrollCenterToModelPoint:graphicalCenter_model];
		}
	}
	
}//end zoomToFit:



#pragma mark -
#pragma mark EVENTS
#pragma mark -

//========== mouseMoved: =======================================================
//
// Purpose:		Mouse has moved to the given view point. (This method is 
//				optional.) 
//
//==============================================================================
- (void) mouseMoved:(Point2)point_view
{
	[self publishMouseOverPoint:point_view];
}


//========== mouseDown =========================================================
//
// Purpose:		Signals that a mouse-down has been received; clear various state 
//				flags in preparation for selection or dragging. 
//
// Note:		Our platform view is responsible for correct interpretation of 
//				the event and routing it to the appropriate methods in the 
//				renderer class. 
//
//==============================================================================
- (void) mouseDown
{
	// Reset event tracking flags.
	self->isTrackingDrag	= NO;
	self->didPartSelection	= NO;
	
	// This might be the start of a new drag; start collecting frames per second
	fpsStartTime = [NSDate timeIntervalSinceReferenceDate];
	framesSinceStartTime = 0;
	
	[self->delegate markPreviousSelection:self];	
}


//========== mousedDragged =====================================================
//
// Purpose:		Signals that a mouse-drag has been received; clear various state 
//				flags in preparation for selection or dragging. 
//
// Note:		Our platform view is responsible for correct interpretation of 
//				the event and routing it to the appropriate methods in the 
//				renderer class. 
//
//==============================================================================
- (void) mouseDragged
{
	self->isStartingDrag    = (self->isTrackingDrag == NO); // first drag if none to date
	self->isTrackingDrag    = YES;
}


//========== mouseUp ===========================================================
//
// Purpose:		Signals that a mouse-up has been received; clear various state 
//				flags in preparation for selection or dragging. 
//
// Note:		Our platform view is responsible for correct interpretation of 
//				the event and routing it to the appropriate methods in the 
//				renderer class. 
//
//==============================================================================
- (void) mouseUp
{
	// Redraw from our dragging operations, if necessary.
	if(		(self->isTrackingDrag == YES && rotationDrawMode == LDrawGLDrawExtremelyFast)
	   ||	V2BoxWidth(self->selectionMarquee) || V2BoxHeight(self->selectionMarquee) )
	{
		[self->delegate LDrawRendererNeedsRedisplay:self];
	}
	
	self->activeDragHandle = nil;
	self->isTrackingDrag = NO; //not anymore.
	self->selectionMarquee = ZeroBox2;

	[self->delegate unmarkPreviousSelection:self];
}


#pragma mark - Clicking

//========== mouseCenterClick: =================================================
//
// Purpose:		We have received a mouseDown event which is intended to center 
//				our view on the point clicked.
//
//==============================================================================
- (void) mouseCenterClick:(Point2)viewClickedPoint
{
	// Ben says: this function used to have a special case for ortho-viewing.
	// But since perspective-case code is fully general, we just now use it alway.
	

	// Perspective distortion makes this more complicated. The camera is in 
	// a fixed position, but the frustum changes with the scrollbars. 
	// We need to calculate the world point we just clicked on, then derive 
	// a new frustum projection centered on that point. 
	Point3  clickedPointInModel = ZeroPoint3;
	
	// Find the point we clicked on. It would be more accurate to use 
	// -getDirectivesUnderMouse:::, but it has to actually draw parts, which 
	// can be slow. 
	clickedPointInModel = [self modelPointForPoint:viewClickedPoint];
	
	[self scrollCenterToModelPoint:clickedPointInModel];
	
}//end mouseCenterClick:


//========== mouseSelectionClick:extendSelection: ==============================
//
// Purpose:		Time to see if we should select something in the model. We 
//				search the model geometry for intersection with the click point. 
//				Our delegate is responsible for managing the actual selection. 
//
//				This function returns whether it hit something - calling code can
//				then do a part drag or marquee based on whether the user clicked
//				on a part or on empty space.
//
//==============================================================================
- (BOOL) mouseSelectionClick:(Point2)point_view
			   selectionMode:(SelectionModeT)selectionMode
{
	LDrawDirective	*clickedDirective	= nil;
	
	self->selectionMarquee = V2MakeBox(point_view.x, point_view.y, 0, 0);

	// Only try to select if we are actually drawing something, and can actually 
	// select it. 
	if(		self->fileBeingDrawn != nil
	   &&	self->allowsEditing == YES
	   &&	[self->delegate respondsToSelector:@selector(LDrawRenderer:wantsToSelectDirective:byExtendingSelection:)] )
	{
		Point2	point_viewport	= [self convertPointToViewport:point_view];
		Point2	bl				= V2Make(point_viewport.x-HANDLE_SIZE,point_viewport.y-HANDLE_SIZE);
		Point2	tr				= V2Make(point_viewport.x+HANDLE_SIZE,point_viewport.y+HANDLE_SIZE);
		float depth				= 1.0;

		Box2	viewport		= [self viewport];
		// Get view and projection
		Point2 point_clip = V2Make( (point_viewport.x - viewport.origin.x) * 2.0 / V2BoxWidth(viewport)  - 1.0,
								    (point_viewport.y - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0 );

		float x1 = (MIN(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float x2 = (MAX(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float y1 = (MIN(bl.y,tr.y) - viewport.origin.x) * 2.0 / V2BoxHeight(viewport) - 1.0;
		float y2 = (MAX(bl.y,tr.y) - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0;
		
		Box2 test_box = V2MakeBoxFromPoints( V2Make(x1, y1), V2Make(x2, y2) );

		Matrix4	mvp =			Matrix4Multiply(
										Matrix4CreateFromGLMatrix4([camera getModelView]),
										Matrix4CreateFromGLMatrix4([camera getProjection]));
					
		id bestObject = nil;
		[fileBeingDrawn depthTest:point_clip inBox:test_box transform:mvp creditObject:nil bestObject:&bestObject bestDepth:&depth];
																				
		clickedDirective = bestObject;
			
		// Primitive manipulation?
		if([clickedDirective isKindOfClass:[LDrawDragHandle class]])
		{
			self->activeDragHandle = (LDrawDragHandle*)clickedDirective;
		}
		else
		{
			// Normal selection
			self->activeDragHandle = nil;
			
			// If we end up actually selecting some single thing, the extension happens if we are intersection (option-shift) or extend (shift).
			BOOL extendSelection = selectionMode == SelectionExtend || selectionMode == SelectionIntersection;
			
			BOOL has_sel_directive = clickedDirective != nil &&  [clickedDirective isSelected];
			BOOL has_any_directive = clickedDirective != nil;
			
			switch(selectionMode)
			{
				case SelectionReplace:				
					// Replacement mode?  Select unless we hit an already hit one - we do not "deselect others" on a click.
					if(!has_sel_directive)
						[self->delegate LDrawRenderer:self wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection ];
					break;
				
				case SelectionExtend:
					// Extended selection.  If we hit a part, toggle it - if we miss a part, don't do anything, nothing to do.
					if(has_any_directive)
						[self->delegate LDrawRenderer:self wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection ];
					break;
				
				case SelectionIntersection:
					// Intersection.  If we hit an unselected directive, do the select to grab it - this will grab it (via option-shift).
					// Then we copy.  If we have no directive, the whole sel clears, which is the correct start for an intersection (since the
					// marquee is empty).
					if(!has_sel_directive)
						[self->delegate LDrawRenderer:self wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection ];
					break;
				
				case SelectionSubtract:
					// Subtraction.  If we have an UNSELECTED directive, we have to grab it.  If we have a selected directive  we do nothing so
					// we can option-drag-copy thes el.  And if we just miss everything, the subtraction hasn't nuked anything yet...again we do nothing.
					if(has_any_directive && !has_sel_directive)
						[self->delegate LDrawRenderer:self wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection ];
					break;
			}
		}
	}

	self->didPartSelection = YES;
	
	return (clickedDirective == nil) ? NO : YES;
	
}//end mousePartSelection:


//========== mouseZoomInClick: =================================================
//
// Purpose:		Depending on the tool mode, we want to zoom in or out. We also 
//				want to center the view on whatever we clicked on.
//
//==============================================================================
- (void) mouseZoomInClick:(Point2)viewClickedPoint
{
	CGFloat     currentZoom         = [self zoomPercentage];
	CGFloat     newZoom             = currentZoom * 2;
	
	[self setZoomPercentage:newZoom preservePoint:viewClickedPoint];
	
}//end mouseZoomInClick:


//========== mouseZoomOutClick: ================================================
//
// Purpose:		Depending on the tool mode, we want to zoom in or out. We also 
//				want to center the view on whatever we clicked on.
//
//==============================================================================
- (void) mouseZoomOutClick:(Point2)viewClickedPoint
{
	CGFloat     currentZoom         = [self zoomPercentage];
	CGFloat     newZoom             = currentZoom / 2;
	
	[self setZoomPercentage:newZoom preservePoint:viewClickedPoint];
	
}//end mouseZoomOutClick:


#pragma mark - Dragging

//========== dragHandleDragged: ================================================
//
// Purpose:		Move the active drag handle
//
//==============================================================================
- (void) dragHandleDraggedToPoint:(Point2)point_view
				constrainDragAxis:(BOOL)constrainDragAxis
{
	Point3	modelReferencePoint = [self->activeDragHandle position];
	BOOL	moved				= NO;

	[self publishMouseOverPoint:point_view];

	// Give the document controller an opportunity for undo management!
	if(self->isStartingDrag && [self->delegate respondsToSelector:@selector(LDrawRenderer:willBeginDraggingHandle:)])
	{
		[self->delegate LDrawRenderer:self willBeginDraggingHandle:self->activeDragHandle];
	}

	// Update with new position
	moved = [self updateDirectives:[NSArray arrayWithObject:self->activeDragHandle]
				  withDragPosition:point_view
			   depthReferencePoint:modelReferencePoint
					 constrainAxis:constrainDragAxis];
					 
	if(moved)
	{
		[self->fileBeingDrawn noteNeedsDisplay];

		if([self->delegate respondsToSelector:@selector(LDrawRenderer:dragHandleDidMove:)])
		{
			[self->delegate LDrawRenderer:self dragHandleDidMove:self->activeDragHandle];
		}
	}

}//end dragHandleDragged:


//========== panDragged:location: ==============================================
//
// Purpose:		Scroll the view as the mouse is dragged across it. 
//
//==============================================================================
- (void) panDragged:(Vector2)viewDirection location:(Point2)point_view
{
	if(isStartingDrag)
	{
		self->initialDragLocation = [self modelPointForPoint:point_view];
	}
	
	Box2	viewport		= [self viewport];
	Point2	point_viewport	= [self convertPointToViewport:point_view];
	Point2	proportion		= V2Make(point_viewport.x, point_viewport.y);
	
	proportion.x /= V2BoxWidth(viewport);
	proportion.y /= V2BoxHeight(viewport);
	
	if([self->delegate respondsToSelector:@selector(LDrawRendererMouseNotPositioning:)])
		[self->delegate LDrawRendererMouseNotPositioning:self];
	
	[self scrollModelPoint:self->initialDragLocation toViewportProportionalPoint:proportion];
	
}//end panDragged:


//========== rotationDragged: ==================================================
//
// Purpose:		Tis time to rotate the object!
//
//				We need to translate horizontal and vertical 2-dimensional mouse 
//				drags into 3-dimensional rotations.
//
//		 +---------------------------------+       ///  /- -\ \\\   (This thing is a sphere.)
//		 |             y /|\               |      /     /   \    \				.
//		 |                |                |    //      /   \     \\			.
//		 |                |vertical        |    |   /--+-----+-\   |
//		 |                |motion (around x)   |///    |     |   \\\|
//		 |                |              x |   |       |     |      |
//		 |<---------------+--------------->|   |       |     |      |
//		 |                |     horizontal |   |\\\    |     |   ///|
//		 |                |     motion     |    |   \--+-----+-/   |
//		 |                |    (around y)  |    \\     |     |    //
//		 |                |                |      \     \   /    /
//		 |               \|/               |       \\\  \   / ///
//		 +---------------------------------+          --------
//
//				But 2D motion is not 3D motion! We can't just say that 
//				horizontal drag = rotation around y (up) axis. Why? Because the 
//				y-axis may be laying horizontally due to the rotation!
//
//				The trick is to convert the y-axis *on the projection screen* 
//				back to a *vector in the model*. Then we can just call glRotate 
//				around that vector. The result that the model is rotated in the 
//				direction we dragged, no matter what its orientation!
//
//				Last Note: A horizontal drag from left-to-right is a 
//					counterclockwise rotation around the projection's y axis.
//					This means a positive number of degrees caused by a positive 
//					mouse displacement.
//					But, a vertical drag from bottom-to-top is a clockwise 
//					rotation around the projection's x-axis. That means a 
//					negative number of degrees cause by a positive mouse 
//					displacement. That means we must multiply our x-rotation by 
//					-1 in order to make it go the right direction.
//
//==============================================================================
- (void) rotationDragged:(Vector2)viewDirection
{
	if([self projectionMode] != ProjectionModePerspective)
	{
		[self setProjectionMode:ProjectionModePerspective];
		self->viewOrientation = ViewOrientation3D;
	}

	[camera rotationDragged:viewDirection];
	
	if([self->delegate respondsToSelector:@selector(LDrawRendererMouseNotPositioning:)])
		[self->delegate LDrawRendererMouseNotPositioning:self];
	
	[self->delegate LDrawRendererNeedsRedisplay:self];
		
	
}//end rotationDragged

//========== zoomDragged: ======================================================
//
// Purpose:		Drag up means zoom in, drag down means zoom out. 1 px = 1 %.
//
//==============================================================================
- (void) zoomDragged:(Vector2)viewDirection
{
	CGFloat pixelChange     = -viewDirection.y;			// Negative means down
	CGFloat magnification   = pixelChange/100;			// 1 px = 1%
	CGFloat zoomChange      = 1.0 + magnification;
	CGFloat currentZoom     = [self zoomPercentage];
	
	[self setZoomPercentage:(currentZoom * zoomChange)];
	
	if([self->delegate respondsToSelector:@selector(LDrawRendererMouseNotPositioning:)])
		[self->delegate LDrawRendererMouseNotPositioning:self];
	
}//end zoomDragged:


//========== mouseSelectionDragToPoint:extendSelection: ========================
//
// Purpose:		Selects objects under the dragged rectangle.  Caller code tracks
//				the rectangle itself.
//
//==============================================================================
- (void) mouseSelectionDragToPoint:(Point2)point_view
				   selectionMode:(SelectionModeT) selectionMode
{
#if TIME_BOXTEST
	NSDate * startTime	= [NSDate date];	
#endif

	NSArray			*fineDrawParts		= nil;
	
	self->selectionMarquee = V2MakeBoxFromPoints(selectionMarquee.origin, point_view);

	// Only try to select if we are actually drawing something, and can actually 
	// select it. 
	if(		self->fileBeingDrawn != nil
	   &&	self->allowsEditing == YES
	   &&	[self->delegate respondsToSelector:@selector(LDrawRenderer:wantsToSelectDirective:byExtendingSelection:)] )
	{
		// First do hit-testing on nothing but the bounding boxes; that is very 
		// fast and likely eliminates a lot of parts. 

		fineDrawParts = [self getDirectivesUnderRect:self->selectionMarquee
									 amongDirectives:[NSArray arrayWithObject:self->fileBeingDrawn]
											fastDraw:NO];
		[self->delegate LDrawRenderer:self
			  wantsToSelectDirectives:fineDrawParts
						selectionMode:selectionMode ];
		
	}

#if TIME_BOXTEST
	NSTimeInterval drawTime = -[startTime timeIntervalSinceNow];
	printf("Box: %lf\n", drawTime);
#endif

	self->didPartSelection = YES;
	
}//end mouseSelectionDrag:to:extendSelection:


#pragma mark -
#pragma mark Gestures

//========== beginGesture ======================================================
//
// Purpose:		Our platform host view is informing us that it is starting 
//				gesture tracking. 
//
//==============================================================================
- (void) beginGesture
{
	self->isGesturing = YES;
}


//========== endGesture ========================================================
//
// Purpose:		Our platform host view is informing us that it is ending 
//				gesture tracking. 
//
//==============================================================================
- (void) endGesture
{
	self->isGesturing = NO;
	
	if(self->rotationDrawMode == LDrawGLDrawExtremelyFast)
	{
		[self->delegate LDrawRendererNeedsRedisplay:self];
	}
}


//========== rotateWithEvent: ==================================================
//
// Purpose:		User is doing the twist (rotate) trackpad gesture. Rotate 
//				counterclockwise by the given degrees. 
//
//				I have decided to interpret this as spinning the "baseplate" 
//				plane of the model (that is, spinning around -y). 
//
//==============================================================================
- (void) rotateByDegrees:(float)angle
{
	if([self projectionMode] != ProjectionModePerspective)
	{
		[self setProjectionMode:ProjectionModePerspective];
		self->viewOrientation = ViewOrientation3D;
	}

	[camera rotateByDegrees:angle];
	[self->delegate LDrawRendererNeedsRedisplay:self];

}//end rotateWithEvent:


#pragma mark -
#pragma mark DRAG AND DROP
#pragma mark -

//========== draggingEnteredAtPoint: ===========================================
//
// Purpose:		A drag-and-drop part operation entered this view. We need to 
//			    initiate interactive dragging. 
//
//==============================================================================
- (void) draggingEnteredAtPoint:(Point2)point_view
					 directives:(NSArray *)directives
				   setTransform:(BOOL)setTransform
			  originatedLocally:(BOOL)originatedLocally
{
	LDrawDrawableElement	*firstDirective 	= [directives objectAtIndex:0];
	LDrawPart				*newPart			= nil;
	TransformComponents 	partTransform		= IdentityComponents;
	Point3					modelReferencePoint = ZeroPoint3;
	
	//---------- Initialize New Part? ------------------------------------------
	
	if(setTransform == YES)
	{
		// Uninitialized elements are always new parts from the part browser.
		newPart = [directives objectAtIndex:0];
	
		// Ask the delegate roughly where it wants us to be.
		// We get a full transform here so that when we drag in new parts, they 
		// will be rotated the same as whatever part we were using last. 
		if([self->delegate respondsToSelector:@selector(LDrawRendererPreferredPartTransform:)])
		{
			partTransform = [self->delegate LDrawRendererPreferredPartTransform:self];
			[newPart setTransformComponents:partTransform];
		}
	}
	
	
	//---------- Find Location -------------------------------------------------
	// We need to map our 2-D mouse coordinate into a point in the model's 3-D 
	// space.
	
	modelReferencePoint	= [firstDirective position];
	
	// Apply the initial offset.
	// This is the difference between the position of part 0 and the actual 
	// clicked point. We do this so that the point you clicked always remains 
	// directly under the mouse.
	//
	// Only applicable if dragging into the source view. Other views may have 
	// different orientations. We might be able to remove that requirement by 
	// zeroing the inapplicable component. 
	if(originatedLocally == YES)
	{
		modelReferencePoint = V3Add(modelReferencePoint, self->draggingOffset);
	}
	else
	{
		[self setDraggingOffset:ZeroPoint3]; // no offset for future updates either
	}

	// For constrained dragging, we care only about the initial, unmodified 
	// postion. 
	self->initialDragLocation = modelReferencePoint;
	
	// Move the parts
	[self updateDirectives:directives
		  withDragPosition:point_view
	   depthReferencePoint:modelReferencePoint
			 constrainAxis:NO];
	
	// The drag has begun!
	if([self->fileBeingDrawn respondsToSelector:@selector(setDraggingDirectives:)])
	{
		[(id)self->fileBeingDrawn setDraggingDirectives:directives];
		
		[self->fileBeingDrawn noteNeedsDisplay];
	}
	
}//end draggingEntered:


//========== endDragging =======================================================
//
// Purpose:		Ends part drag-and-drop.
//
//==============================================================================
- (void) endDragging
{
	if([self->fileBeingDrawn respondsToSelector:@selector(setDraggingDirectives:)])
	{
		[(id)self->fileBeingDrawn setDraggingDirectives:nil];
		
		[self->fileBeingDrawn noteNeedsDisplay];
	}
}


//========== updateDragWithPosition:constrainAxis: =============================
//
// Purpose:		Adjusts the directives so they align with the given drag 
//				location, in window coordinates. 
//
//==============================================================================
- (void) updateDragWithPosition:(Point2)point_view
				  constrainAxis:(BOOL)constrainAxis
{
	NSArray 				*directives 			= nil;
	Point3					modelReferencePoint 	= ZeroPoint3;
	LDrawDrawableElement	*firstDirective 		= nil;
	BOOL					moved					= NO;
	
	[self publishMouseOverPoint:point_view];
	
	if([self->fileBeingDrawn respondsToSelector:@selector(draggingDirectives)])
	{
		directives			= [(id)self->fileBeingDrawn draggingDirectives];
		firstDirective		= [directives objectAtIndex:0];
		modelReferencePoint = [firstDirective position];
		modelReferencePoint = V3Add(modelReferencePoint, self->draggingOffset);
		
		moved = [self updateDirectives:directives
					  withDragPosition:point_view
				   depthReferencePoint:modelReferencePoint
						 constrainAxis:constrainAxis];
		if(moved)
		{
			[self->fileBeingDrawn noteNeedsDisplay];
		}
	}
	
}//end updateDirectives:withDragPosition:


//========== updateDirectives:withDragPosition: ================================
//
// Purpose:		Adjusts the directives so they align with the given drag 
//				location, in window coordinates. 
//
//==============================================================================
- (BOOL) updateDirectives:(NSArray *)directives
		 withDragPosition:(Point2)point_view
	  depthReferencePoint:(Point3)modelReferencePoint
			constrainAxis:(BOOL)constrainAxis
{
	LDrawDrawableElement	*firstDirective 		= nil;
	Point3					modelPoint				= ZeroPoint3;
	Point3					oldPosition 			= ZeroPoint3;
	Point3					constrainedPosition 	= ZeroPoint3;
	Vector3 				displacement			= ZeroPoint3;
	Vector3 				cumulativeDisplacement	= ZeroPoint3;
	NSUInteger				counter 				= 0;
	BOOL					moved					= NO;
	
	firstDirective	= [directives objectAtIndex:0];
	
	
	//---------- Find Location ---------------------------------------------
	
	// Where are we?
	oldPosition				= modelReferencePoint;
	
	// and adjust.
	modelPoint              = [self modelPointForPoint:point_view depthReferencePoint:modelReferencePoint];
	displacement            = V3Sub(modelPoint, oldPosition);
	cumulativeDisplacement  = V3Sub(modelPoint, self->initialDragLocation);
	
	
	//---------- Find Actual Displacement ----------------------------------
	// When dragging, we want to move IN grid increments, not move TO grid 
	// increments. That means we snap the displacement vector itself to the 
	// grid, not part's location. That's because the part may not have been 
	// grid-aligned to begin with. 
	
	// As is conventional in graphics programs, we allow dragging to be 
	// constrained to a single axis. We will pick that axis that is furthest 
	// from the initial drag location. 
	if(constrainAxis == YES)
	{
		// Find the part's position along the constrained axis.
		cumulativeDisplacement	= V3IsolateGreatestComponent(cumulativeDisplacement);
		constrainedPosition		= V3Add(self->initialDragLocation, cumulativeDisplacement);
		
		// Get the displacement from the part's current position to the 
		// constrained one. 
		displacement = V3Sub(constrainedPosition, oldPosition);
	}
	
	// Snap the displacement to the grid.
	displacement			= [firstDirective position:displacement snappedToGrid:self->gridSpacing];
	
	//---------- Update the parts' positions  ------------------------------
	
	if(V3EqualPoints(displacement, ZeroPoint3) == NO)
	{
		// Move all the parts by that amount.
		for(counter = 0; counter < [directives count]; counter++)
		{
			[[directives objectAtIndex:counter] moveBy:displacement];
		}
		
		moved = YES;
	}
	
	return moved;
	
}//end updateDirectives:withDragPosition:


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== activeModelDidChange: =============================================
//
// Purpose:		The selected MPD model changed.
//
//==============================================================================
- (void) activeModelDidChange:(NSNotification *)notification
{
	[self updateRotationCenter];
	if(fileBeingDrawn != nil)
		[camera setModelSize:[fileBeingDrawn boundingBox3]];

	[self->delegate LDrawRendererNeedsRedisplay:self];
	
}//end displayNeedsUpdating



//========== displayNeedsUpdating: =============================================
//
// Purpose:		Someone (likely our file) has notified us that it has changed, 
//				and thus we need to redraw.
//
//				We also use this opportunity to grow the canvas if necessary.
//
//==============================================================================
- (void) displayNeedsUpdating:(NSNotification *)notification
{
	[camera setModelSize:[fileBeingDrawn boundingBox3]];
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
}//end displayNeedsUpdating


//========== rotationCenterChanged: ============================================
//
// Purpose:		The active model changed the point around which it is to be spun.
//
//==============================================================================
- (void) rotationCenterChanged:(NSNotification *)notification
{
	[self updateRotationCenter];

	[self->delegate LDrawRendererNeedsRedisplay:self];

}//end rotationCenterChanged:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== autoscrollPoint:relativeToRect: ===================================
///
/// @abstract	If the point is outside the given view rect, this will scroll
/// 			the view by the amount the point is outside.
///
//==============================================================================
- (BOOL) autoscrollPoint:(Point2)point_view
		  relativeToRect:(Box2)viewRect
{
	BOOL didScroll = NO;
	
	if( V2BoxContains(viewRect, point_view) == NO )
	{
		// Amount to offset origin
		Vector2 scrollVector = ZeroPoint2;
		
		// x
		if(point_view.x < V2BoxMinX(viewRect))
		{
			scrollVector.x = point_view.x - V2BoxMinX(viewRect);
		}
		else if(point_view.x > V2BoxMaxX(viewRect))
		{
			scrollVector.x = point_view.x - V2BoxMaxX(viewRect);
		}
		
		// y
		if(point_view.y < V2BoxMinY(viewRect))
		{
			scrollVector.y = point_view.y - V2BoxMinY(viewRect);
		}
		else if(point_view.y > V2BoxMaxY(viewRect))
		{
			scrollVector.y = point_view.y - V2BoxMaxY(viewRect);
		}
		
		[self scrollBy:scrollVector];
		didScroll = YES;
	}
	
	return didScroll;
}

//========== getDepthUnderPoint: ===============================================
//
// Purpose:		Returns the depth component of the nearest object under the view 
//				point. 
//
//				Returns 1.0 if there is no object under the point.
//
//==============================================================================
- (float) getDepthUnderPoint:(Point2)point_view
{
	Point2	point_viewport	= [self convertPointToViewport:point_view];
	Point2	bl				= V2Make(point_viewport.x-HANDLE_SIZE,point_viewport.y-HANDLE_SIZE);
	Point2	tr				= V2Make(point_viewport.x+HANDLE_SIZE,point_viewport.y+HANDLE_SIZE);
	float	depth			= 1.0;

	Box2	viewport		= [self viewport];

	Point2 point_clip = {
				(point_viewport.x - viewport.origin.x) * 2.0 / V2BoxWidth(viewport) - 1.0,
				(point_viewport.y - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0 };

		float x1 = (MIN(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float x2 = (MAX(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float y1 = (MIN(bl.y,tr.y) - viewport.origin.x) * 2.0 / V2BoxHeight(viewport) - 1.0;
		float y2 = (MAX(bl.y,tr.y) - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0;

		Box2	test_box = V2MakeBox(x1,y1,x2-x1,y2-y1);

	Matrix4	mvp =			Matrix4Multiply(
									Matrix4CreateFromGLMatrix4([camera getModelView]),
									Matrix4CreateFromGLMatrix4([camera getProjection]));
				
	id bestObject = nil;
	[fileBeingDrawn depthTest:point_clip inBox:test_box transform:mvp creditObject:nil bestObject:&bestObject bestDepth:&depth];
																			
	return depth * 0.5 + 0.5;

}//end getDepthUnderPoint


//========== getDirectivesUnderMouse:amongDirectives:fastDraw: =================
//
// Purpose:		Finds the directives under a given mouse-click. This method is 
//				written so that the caller can optimize its hit-detection by 
//				doing a preliminary test on just the bounding boxes.
//
// Parameters:	theEvent	= mouse-click event
//				directives	= the directives under consideration for being 
//								clicked. This may be the whole File directive, 
//								or a smaller subset we have already determined 
//								(by a previous call) is in the area.
//				fastDraw	= consider only bounding boxes for hit-detection.
//
// Returns:		Array of clicked parts; the closest one -- and the only one we 
//				ultimately care about -- is always the 0th element.
//
//==============================================================================
#if 0	// replaced by direct depthTest.
- (NSArray *) getDirectivesUnderPoint:(Point2)point_view
					  amongDirectives:(NSArray *)directives
							 fastDraw:(BOOL)fastDraw
{
	NSArray	*clickedDirectives	= nil;
	
	if([directives count] == 0)
	{
		// If there's nothing to test in, there's no work to do!
		clickedDirectives = [NSArray array];
	}
	else
	{
		Point2              point_viewport          = [self convertPointToViewport:point_view];
		Point3              contextNear             = ZeroPoint3;
		Point3              contextFar              = ZeroPoint3;
		Ray3                pickRay                 = {{0}};
		Point3              pickRay_end             = ZeroPoint3;
		Box2				viewport	            = [self viewport];
		NSMutableDictionary *hits                   = [NSMutableDictionary dictionary];
		NSUInteger          counter                 = 0;

		// convert to 3D viewport coordinates
		contextNear		= V3Make(point_viewport.x, point_viewport.y, 0.0);
		contextFar		= V3Make(point_viewport.x, point_viewport.y, 1.0);
		
		// Pick Ray
		pickRay.origin      = V3Unproject(contextNear,
										  Matrix4CreateFromGLMatrix4([camera getModelView]),
										  Matrix4CreateFromGLMatrix4([camera getProjection]),
										  viewport);
		pickRay_end         = V3Unproject(contextFar,
										  Matrix4CreateFromGLMatrix4([camera getModelView]),
										  Matrix4CreateFromGLMatrix4([camera getProjection]),
										  viewport);
		pickRay.direction   = V3Sub(pickRay_end, pickRay.origin);
		pickRay.direction	= V3Normalize(pickRay.direction);
		
		// Do hit test
		for(counter = 0; counter < [directives count]; counter++)
		{
			[[directives objectAtIndex:counter] hitTest:pickRay
											  transform:IdentityMatrix4
											  viewScale:[self zoomPercentageForGL]/100.
											 boundsOnly:fastDraw
										   creditObject:nil
												   hits:hits];
		}
		
		clickedDirectives = [self getPartsFromHits:hits];
	}

	return clickedDirectives;
	
}//end getDirectivesUnderMouse:amongDirectives:fastDraw:
#endif


//========== getDirectivesUnderRect:amongDirectives:fastDraw: ==================
//
// Purpose:		Finds the directives under a given mouse-recangle.  This
//				does a two-pass search so that clients can do a bounding box
//				test first.
//
// Parameters:	bottom_left, top_right = the rectangle (in viewport space) in 
//										 which to test.
//				directives	= the directives under consideration for being 
//								clicked. This may be the whole File directive, 
//								or a smaller subset we have already determined 
//								(by a previous call) is in the area.
//				fastDraw	= consider only bounding boxes for hit-detection.
//
// Returns:		Array of all parts that are at least partly inside the rectangle
//				in screen space.
//
//==============================================================================
- (NSArray *) getDirectivesUnderRect:(Box2)rect_view 
					 amongDirectives:(NSArray *)directives
							fastDraw:(BOOL)fastDraw
{
	NSArray	*clickedDirectives	= nil;
	
	if([directives count] == 0)
	{
		// If there's nothing to test in, there's no work to do!
		clickedDirectives = [NSArray array];
	}
	else
	{
		Point2			bottom_left 			= rect_view.origin;
		Point2			top_right				= V2Make( V2BoxMaxX(rect_view), V2BoxMaxY(rect_view) );
		Point2			bl						= [self convertPointToViewport:bottom_left];
		Point2			tr						= [self convertPointToViewport:top_right];
		Box2			viewport				= [self viewport];
		NSMutableSet	*hits					= [NSMutableSet set];
		NSUInteger		counter 				= 0;
		
		float x1 = (MIN(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float x2 = (MAX(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float y1 = (MIN(bl.y,tr.y) - viewport.origin.x) * 2.0 / V2BoxHeight(viewport) - 1.0;
		float y2 = (MAX(bl.y,tr.y) - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0;

		Box2	test_box = V2MakeBox(x1,y1,x2-x1,y2-y1);
		
		Matrix4	mvp =			Matrix4Multiply(
									  Matrix4CreateFromGLMatrix4([camera getModelView]),
									  Matrix4CreateFromGLMatrix4([camera getProjection]));
										
		// Do hit test
		for(counter = 0; counter < [directives count]; counter++)
		{
			[[directives objectAtIndex:counter] boxTest:test_box
											  transform:mvp 
											 boundsOnly:fastDraw
										   creditObject:nil
												   hits:hits];
		}

		NSMutableArray * collected = [NSMutableArray arrayWithCapacity:[hits count]];
		clickedDirectives = collected;
		
		for(NSValue *key in hits)
		{
			LDrawDirective * currentDirective    = [key pointerValue];
			[collected addObject:currentDirective];
		}
	}

	return clickedDirectives;
	
}//end getDirectivesUnderMouse:amongDirectives:fastDraw


//========== getPartFromHits:hitCount: =========================================
//
// Purpose:		Deduce the parts that were clicked on, given the selection data 
//				returned from -[LDrawDirective hitTest:...]
//
//				Each time something's geometry intersects our pick ray under the 
//				mouse (and it has a different name), it generates a hit record. 
//				So we have to investigate our hits and figure out which hit was 
//				the nearest to the front (smallest minimum depth); that is the 
//				one we clicked on. 
//
// Returns:		Array of all the parts under the click. The nearest part is 
//				guaranteed to be the first entry in the array. There is no 
//				defined order for the rest of the parts.
//
//==============================================================================
#if 0
// not used due to depth test
- (NSArray *) getPartsFromHits:(NSDictionary *)hits
{
	NSMutableArray  *clickedDirectives  = [NSMutableArray arrayWithCapacity:[hits count]];
	LDrawDirective  *currentDirective   = nil;
	float           minimumDepth        = INFINITY;
	float           currentDepth        = 0;
	
	// The hit record depths are mapped as depths along the pick ray. We are 
	// looking for the shallowest point, because that's what we clicked on. 
	
	for(NSValue *key in hits)
	{
		currentDirective    = [key pointerValue];
		currentDepth        = [[hits objectForKey:key] floatValue];
		
//		NSLog(@"Hit depth %f %@", currentDepth, currentDirective);
		
		if(currentDepth < minimumDepth)
		{
			// guarantee shallowest object is first in array
			[clickedDirectives insertObject:currentDirective atIndex:0];
			minimumDepth = currentDepth;
		}
		else
		{
			[clickedDirectives addObject:currentDirective];
		}
	}
//	NSLog(@"===============================================");
	
	return clickedDirectives;
	
}//end getPartFromHits:hitCount:
#endif


//========== publishMouseOverPoint: ============================================
//
// Purpose:		Informs the delegate that the mouse is hovering over the model 
//				point under the view point. 
//
//==============================================================================
- (void) publishMouseOverPoint:(Point2)point_view
{
	Point3		modelPoint			= ZeroPoint3;
	Vector3		modelAxisForX		= ZeroPoint3;
	Vector3		modelAxisForY		= ZeroPoint3;
	Vector3		modelAxisForZ		= ZeroPoint3;
	Vector3		confidence			= ZeroPoint3;
	
	if([self->delegate respondsToSelector:@selector(LDrawRenderer:mouseIsOverPoint:confidence:)])
	{
		modelPoint = [self modelPointForPoint:point_view];
		
		if([self projectionMode] == ProjectionModeOrthographic)
		{
			[self getModelAxesForViewX:&modelAxisForX Y:&modelAxisForY Z:&modelAxisForZ];
			
			confidence = V3Add(modelAxisForX, modelAxisForY);
		}
		
		[self->delegate LDrawRenderer:self mouseIsOverPoint:modelPoint confidence:confidence];
	}
}


//========== setZoomPercentage:preservePoint: ==================================
//
// Purpose:		Performs cursor-centric zooming on the given point, in view 
//				coordinates. After the new zoom is applied, the 3D point 
//				projected at viewPoint will still be in the same projected 
//				location. 
//
//==============================================================================
- (void) setZoomPercentage:(CGFloat)newPercentage
			 preservePoint:(Point2)viewPoint
{
	Point3 modelPoint = [self modelPointForPoint:viewPoint];

	[camera setZoomPercentage:newPercentage preservePoint:modelPoint];
	[self->delegate LDrawRendererNeedsRedisplay:self];

}//end setZoomPercentage:preservePoint:


//========== scrollBy: =========================================================
///
/// @abstract	Apply a scroll delta (as delivered from an NSEvent)
///
/// @param 		scrollDelta_viewport The scroll offset to apply to the origin,
/// 								 in the coordinate system of the viewport.
/// 								 (Origin lower-left, size =
/// 								 self.viewportSize) The camera will adjust
/// 								 the requested delta by the current zoom
/// 								 factor.
///
//==============================================================================
- (void) scrollBy:(Vector2)scrollDelta_viewport
{
	[camera scrollBy:scrollDelta_viewport];
	[self->delegate LDrawRendererNeedsRedisplay:self];
}


//========== scrollCameraVisibleRectToPoint: ===================================
///
/// @abstract	Scrolls so the given point is the origin of the camera's
/// 			visibleRect. This is in the coordinate system of the boxes
/// 			passed to -reflectLogicalDocumentRect:visibleRect:.
///
//==============================================================================
- (void) scrollCameraVisibleRectToPoint:(Point2)visibleRectOrigin
{
	[self->camera scrollToPoint:visibleRectOrigin];
	[self->delegate LDrawRendererNeedsRedisplay:self];
}


//========== scrollCenterToModelPoint: =========================================
//
// Purpose:		Scrolls the receiver (if it is inside a scroll view) so that 
//				newCenter is at the center of the viewing area. newCenter is 
//				given in LDraw model coordinates.
//
//==============================================================================
- (void) scrollCenterToModelPoint:(Point3)modelPoint
{
	[self scrollModelPoint:modelPoint toViewportProportionalPoint:V2Make(0.5, 0.5)];
}


//========== scrollModelPoint:toViewportProportionalPoint: =====================
//
// Purpose:		Scrolls viewport so the projection of the given 3D point appears 
//				at the given fraction of the viewport. (0,0) means the 
//				bottom-right corner of the viewport; (0.5, 0.5) means the 
//				center; (1.0, 1.0) means the top-right. 
//
//==============================================================================
- (void)     scrollModelPoint:(Point3)modelPoint
  toViewportProportionalPoint:(Point2)viewportPoint
{
	[camera scrollModelPoint:modelPoint  toViewportProportionalPoint:viewportPoint];
	[self->delegate LDrawRendererNeedsRedisplay:self];

}//end scrollCenterToModelPoint:


//========== updateRotationCenter ==============================================
//
// Purpose:		Resync our copy of the rotationCenter with the one used by the 
//				model. 
//
//==============================================================================
- (void) updateRotationCenter
{
	Point3	point		= ZeroPoint3;
	
	if([fileBeingDrawn isKindOfClass:[LDrawFile class]])
	{
		point = [[(LDrawFile*)fileBeingDrawn activeModel] rotationCenter];
	}
	else if([fileBeingDrawn isKindOfClass:[LDrawModel class]])
	{
		point = [(LDrawModel*)fileBeingDrawn rotationCenter];
	}
	
	[camera setRotationCenter:point];	
	[self->delegate LDrawRendererNeedsRedisplay:self];
}

#pragma mark -
#pragma mark Geometry

//========== convertPointFromViewport: =========================================
//
// Purpose:		Converts the point from the viewport coordinate system to the 
//				view bounds' coordinate system. 
//
//==============================================================================
- (Point2) convertPointFromViewport:(Point2)viewportPoint
{
	Point2	point_view = viewportPoint;
	
	// Flip the coordinates
	if([self isFlipped])
	{
		// The origin of the viewport is in the lower-left corner.
		// The origin of the view is in the upper right (it is flipped)
		point_view.y = V2BoxHeight([self viewport]) - point_view.y;
	}
	
	return point_view;
	
}//end convertPointFromViewport:


//========== convertPointToViewport: ===========================================
//
// Purpose:		Converts the point from the view bounds' coordinate system into 
//				the viewport's coordinate system. 
//
//==============================================================================
- (Point2) convertPointToViewport:(Point2)point_view
{
	Point2	point_viewport		= point_view;

	// Flip the coordinates
	if([self isFlipped])
	{
		// The origin of the viewport is in the lower-left corner.
		// The origin of the view is in the upper right (it is flipped)
		point_viewport.y = V2BoxHeight([self viewport]) - point_viewport.y;
	}
	
	return point_viewport;
	
}//end convertPointToViewport:


//========== getModelAxesForViewX:Y:Z: =========================================
//
// Purpose:		Finds the axes in the model coordinate system which most closely 
//			    project onto the X, Y, Z axes of the view. 
//
// Notes:		The screen coordinate system is right-handed:
//
//					 +y
//					|
//					|
//					*-- +x
//				   /
//				  +z
//
//				The choice between what is the "closest" axis in the model is 
//			    often arbitrary, but it will always be a unique and 
//			    sensible-looking choice. 
//
//==============================================================================
- (void) getModelAxesForViewX:(Vector3 *)outModelX
							Y:(Vector3 *)outModelY
							Z:(Vector3 *)outModelZ
{
	Vector4 screenX		= {1,0,0,0};
	Vector4 screenY		= {0,1,0,0};
	Vector4 unprojectedX, unprojectedY; //the vectors in the model which are projected onto x,y on screen
	Vector3 modelX, modelY, modelZ; //the closest model axes to which the screen's x,y,z align
	
	// Translate the x, y, and z vectors on the surface of the screen into the 
	// axes to which they most closely align in the model itself. 
	// This requires the inverse of the current transformation matrix, so we can 
	// convert projection-coordinates back to the model coordinates they are 
	// displaying. 
	Matrix4 inversed = [self getInverseMatrix];
	
	//find the vectors in the model which project onto the screen's axes
	// (We only care about x and y because this is a two-dimensional 
	// projection, and the third axis is consquently ambiguous. See below.) 
	unprojectedX = V4MulPointByMatrix(screenX, inversed);
	unprojectedY = V4MulPointByMatrix(screenY, inversed);
	
	//find the actual axes closest to those model vectors
	modelX	= V3FromV4(unprojectedX);
	modelY	= V3FromV4(unprojectedY);
	
	modelX	= V3IsolateGreatestComponent(modelX);
	modelY	= V3IsolateGreatestComponent(modelY);
	
	modelX	= V3Normalize(modelX);
	modelY	= V3Normalize(modelY);
	
	// The z-axis is often ambiguous because we are working backwards from a 
	// two-dimensional screen. Thankfully, while the process used for deriving 
	// the x and y vectors is perhaps somewhat arbitrary, it always yields 
	// sensible and unique results. Thus we can simply derive the z-vector, 
	// which will be whatever axis x and y *didn't* land on. 
	modelZ = V3Cross(modelX, modelY);
	
	if(outModelX != NULL)
		*outModelX = modelX;
	if(outModelY != NULL)
		*outModelY = modelY;
	if(outModelZ != NULL)
		*outModelZ = modelZ;
	
}//end getModelAxesForViewX:Y:Z:


//========== modelPointForPoint: ===============================================
//
// Purpose:		Unprojects the given point (in view coordinates) back into a 
//			    point in the model which projects there, using existing data in 
//				the depth buffer to infer the location on the z axis. 
//
// Notes:		The depth buffer is not super-accurate, but it's passably 
//				close. But most importantly, it could be faster to read the 
//				depth buffer than to redraw parts of the model under a pick 
//				matrix. 
//
//==============================================================================
- (Point3) modelPointForPoint:(Point2)viewPoint
{
	Point2              viewportPoint           = [self convertPointToViewport:viewPoint];
	float               depth                   = 0.0; 
	TransformComponents partTransform           = IdentityComponents;
	Point3              contextPoint            = ZeroPoint3;
	Point3              modelPoint              = ZeroPoint3;
	
	depth = [self getDepthUnderPoint:viewPoint];
	
	if(depth == 1.0)
	{
		// Error!
		// Maximum depth readings essentially tell us that no pixels were drawn 
		// at this point. So we have to make up a best guess now. This guess 
		// will very likely be wrong, but there is little else which can be 
		// done. 
		
		if([self->delegate respondsToSelector:@selector(LDrawRendererPreferredPartTransform:)])
		{
			partTransform = [self->delegate LDrawRendererPreferredPartTransform:self];
		}

		modelPoint = [self modelPointForPoint:viewPoint
						  depthReferencePoint:partTransform.translate];
	}
	else
	{
		// Convert to 3D viewport coordinates
		contextPoint = V3Make(viewportPoint.x, viewportPoint.y, depth);
	
		// Convert back to a point in the model.
		modelPoint = V3Unproject(contextPoint,
								  Matrix4CreateFromGLMatrix4([camera getModelView]),
								  Matrix4CreateFromGLMatrix4([camera getProjection]),
								 [self viewport]);
	}
	
	return modelPoint;
	
}//end modelPointForPoint:


//========== modelPointForPoint:depthReferencePoint: ===========================
//
// Purpose:		Unprojects the given point (in view coordinates) back into a 
//			    point in the model which projects there, calculating the 
//				location on the z axis using the given depth reference point. 
//
// Notes:		Any point on the screen represents the projected location of an 
//			    infinite number of model points, extending on a line from the 
//			    near to the far clipping plane. 
//
//				It's impossible to boil that down to a single point without 
//			    being given some known point in the model to determine the 
//			    desired depth. (Hence the depthPoint parameter.) The returned 
//			    point will lie on a plane which contains depthPoint and is 
//			    perpendicular to the model axis most closely aligned to the 
//			    computer screen's z-axis. 
//
//										* * * *
//
//				When viewing the model with an orthographic projection and the 
//			    camera pointing parallel to one of the model's coordinate axes, 
//				this method is useful for determining two of the three 
//			    coordinates over which the mouse is hovering. To find which 
//			    coordinate is bogus, we call -getModelAxesForViewX:Y:Z:. The 
//			    returned z-axis indicates the unreliable point. 
//
//==============================================================================
- (Point3) modelPointForPoint:(Point2)viewPoint
		  depthReferencePoint:(Point3)depthPoint
{
	Box2	viewport				= [self viewport];
	
	Point2	contextPoint			= [self convertPointToViewport:viewPoint];
	Point3	nearModelPoint			= ZeroPoint3;
	Point3	farModelPoint			= ZeroPoint3;
	Point3	modelPoint				= ZeroPoint3;
	Vector3 modelZ					= ZeroPoint3;
	float	t						= 0; //parametric variable
	
	// gluUnProject takes a window "z" coordinate. These values range from 
	// 0.0 (on the near clipping plane) to 1.0 (the far clipping plane). 
	
	// - Near clipping plane unprojection
	nearModelPoint = V3Unproject(V3Make(contextPoint.x, contextPoint.y, 0.0),
								  Matrix4CreateFromGLMatrix4([camera getModelView]),
								  Matrix4CreateFromGLMatrix4([camera getProjection]),
								 viewport);
	
	// - Far clipping plane unprojection
	farModelPoint = V3Unproject(V3Make(contextPoint.x, contextPoint.y, 1.0),
								  Matrix4CreateFromGLMatrix4([camera getModelView]),
								  Matrix4CreateFromGLMatrix4([camera getProjection]),
								viewport);
	
	//---------- Derive the actual point from the depth point --------------
	//
	// We now have two accurate unprojected coordinates: the near (P1) and 
	// far (P2) points of the line through 3-D space which projects onto the 
	// single screen point. 
	//
	// The parametric equation for a line given two points is:
	//
	//		 /      \														/
	//	 L = | 1 - t | P  + t P        (see? at t=0, L = P1 and at t=1, L = P2.
	//		 \      /   1      2
	//
	// So for example,	z = (1-t)*z1 + t*z2
	//					z = z1 - t*z1 + t*z2
	//
	//								/       \								/
	//					 z = z  - t | z - z  |
	//						  1     \  1   2/
	//
	//
	//						  z  - z
	//						   1			No need to worry about dividing 
	//					 t = ---------		by 0 because the axis we are 
	//						  z  - z		inspecting will never be 
	//						   1    2		perpendicular to the screen.

	// Which axis are we going to use from the reference point?
	[self getModelAxesForViewX:NULL Y:NULL Z:&modelZ];
	
	// Find the value of the parameter at the depth point.
	if(modelZ.x != 0)
	{
		t = (nearModelPoint.x - depthPoint.x) / (nearModelPoint.x - farModelPoint.x);
	}
	else if(modelZ.y != 0)
	{
		t = (nearModelPoint.y - depthPoint.y) / (nearModelPoint.y - farModelPoint.y);
	}
	else if(modelZ.z != 0)
	{
		t = (nearModelPoint.z - depthPoint.z) / (nearModelPoint.z - farModelPoint.z);
	}
	// Evaluate the equation of the near-to-far line at the parameter for 
	// the depth point. 
	modelPoint.x = LERP(t, nearModelPoint.x, farModelPoint.x);
	modelPoint.y = LERP(t, nearModelPoint.y, farModelPoint.y);
	modelPoint.z = LERP(t, nearModelPoint.z, farModelPoint.z);

	return modelPoint;
	
}//end modelPointForPoint:depthReferencePoint:


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		glFinishForever();
//
//==============================================================================
- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

#ifndef METAL
	[fileBeingDrawn	release];

	[camera release];
	
	[super dealloc];
#endif

}//end dealloc


@end
