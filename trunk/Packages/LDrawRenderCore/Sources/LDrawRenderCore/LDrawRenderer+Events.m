//==============================================================================
//
//  File:       LDrawRenderer+Events.m
//  Package:    LDrawRenderCore
//
//  Purpose:    Mouse, gesture, and model-change notifications for LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import "LDrawRendererInternal.h"

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>


@implementation LDrawRenderer (Events)

//========== mouseMoved: =======================================================
//
// Purpose:		Mouse has moved to the given view point. (This method is 
//				optional.) 
//
//==============================================================================
- (void)mouseMoved:(Point2)point_view
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
- (void)mouseDown
{
	// Reset event tracking flags.
	self->isTrackingDrag	= NO;
	
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
- (void)mouseDragged
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
- (void)mouseUp
{
	// Redraw from our dragging operations, if necessary.
	if (	(self->isTrackingDrag == YES && detailMode == LDrawDetailFast)
	   ||	V2BoxWidth(self->selectionMarquee) || V2BoxHeight(self->selectionMarquee) )
	{
		[self->delegate LDrawRendererNeedsRedisplay:self];
	}
	
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
- (void)mouseCenterClick:(Point2)viewClickedPoint
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
	
} // end mouseCenterClick:


//========== mouseZoomInClick: =================================================
//
// Purpose:		Depending on the tool mode, we want to zoom in or out. We also 
//				want to center the view on whatever we clicked on.
//
//==============================================================================
- (void)mouseZoomInClick:(Point2)viewClickedPoint
{
	CGFloat     currentZoom         = [self zoomPercentage];
	CGFloat     newZoom             = currentZoom * 2;
	
	[self setZoomPercentage:newZoom preservePoint:viewClickedPoint];
	
} // end mouseZoomInClick:


//========== mouseZoomOutClick: ================================================
//
// Purpose:		Depending on the tool mode, we want to zoom in or out. We also 
//				want to center the view on whatever we clicked on.
//
//==============================================================================
- (void)mouseZoomOutClick:(Point2)viewClickedPoint
{
	CGFloat     currentZoom         = [self zoomPercentage];
	CGFloat     newZoom             = currentZoom / 2;
	
	[self setZoomPercentage:newZoom preservePoint:viewClickedPoint];
	
} // end mouseZoomOutClick:


#pragma mark - Dragging

//========== panDragged:location: ==============================================
//
// Purpose:		Scroll the view as the mouse is dragged across it. 
//
//==============================================================================
- (void)panDragged:(Vector2)viewDirection location:(Point2)point_view
{
	if (self->isStartingDrag)
	{
		self->initialDragLocation = [self modelPointForPoint:point_view];
	}
	
	Box2	viewport		= [self viewport];
	Point2	point_viewport	= [self convertPointToViewport:point_view];
	Point2	proportion		= V2Make(point_viewport.x, point_viewport.y);
	
	proportion.x /= V2BoxWidth(viewport);
	proportion.y /= V2BoxHeight(viewport);
	
	if ([self->delegate respondsToSelector:@selector(LDrawRendererMouseNotPositioning:)])
		[self->delegate LDrawRendererMouseNotPositioning:self];
	
	[self scrollModelPoint:self->initialDragLocation toViewportProportionalPoint:proportion];
	
} // end panDragged:


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
- (void)rotationDragged:(Vector2)viewDirection
{
	if ([self projectionMode] != ProjectionModePerspective)
	{
		[self setProjectionMode:ProjectionModePerspective];
		self->viewOrientation = ViewOrientation3D;
	}

	[camera rotationDragged:viewDirection];
	
	if ([self->delegate respondsToSelector:@selector(LDrawRendererMouseNotPositioning:)])
		[self->delegate LDrawRendererMouseNotPositioning:self];
	
	[self->delegate LDrawRendererNeedsRedisplay:self];
		
	
} // end rotationDragged

//========== zoomDragged: ======================================================
//
// Purpose:		Drag up means zoom in, drag down means zoom out. 1 px = 1 %.
//
//==============================================================================
- (void)zoomDragged:(Vector2)viewDirection
{
	CGFloat pixelChange     = -viewDirection.y;			// Negative means down
	CGFloat magnification   = pixelChange/100;			// 1 px = 1%
	CGFloat zoomChange      = 1.0 + magnification;
	CGFloat currentZoom     = [self zoomPercentage];
	
	[self setZoomPercentage:(currentZoom * zoomChange)];
	
	if ([self->delegate respondsToSelector:@selector(LDrawRendererMouseNotPositioning:)])
		[self->delegate LDrawRendererMouseNotPositioning:self];
	
} // end zoomDragged:


#pragma mark -
#pragma mark Gestures

//========== beginGesture ======================================================
//
// Purpose:		Our platform host view is informing us that it is starting 
//				gesture tracking. 
//
//==============================================================================
- (void)beginGesture
{
	self->isGesturing = YES;
}


//========== endGesture ========================================================
//
// Purpose:		Our platform host view is informing us that it is ending 
//				gesture tracking. 
//
//==============================================================================
- (void)endGesture
{
	self->isGesturing = NO;
	
	if (self->detailMode == LDrawDetailFast)
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
- (void)rotateByDegrees:(float)angle
{
	if ([self projectionMode] != ProjectionModePerspective)
	{
		[self setProjectionMode:ProjectionModePerspective];
		self->viewOrientation = ViewOrientation3D;
	}

	[camera rotateByDegrees:angle];
	[self->delegate LDrawRendererNeedsRedisplay:self];

} // end rotateWithEvent:


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== activeModelDidChange: =============================================
//
// Purpose:		The selected MPD model changed.
//
//==============================================================================
- (void)activeModelDidChange:(NSNotification *)notification
{
	[self updateRotationCenter];
	if (fileBeingDrawn != nil)
		[camera setModelSize:[fileBeingDrawn boundingBox3]];

	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} // end displayNeedsUpdating



//========== displayNeedsUpdating: =============================================
//
// Purpose:		Someone (likely our file) has notified us that it has changed, 
//				and thus we need to redraw.
//
//				We also use this opportunity to grow the canvas if necessary.
//
//==============================================================================
- (void)displayNeedsUpdating:(NSNotification *)notification
{
	[camera setModelSize:[fileBeingDrawn boundingBox3]];
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} // end displayNeedsUpdating


//========== rotationCenterChanged: ============================================
//
// Purpose:		The active model changed the point around which it is to be spun.
//
//==============================================================================
- (void)rotationCenterChanged:(NSNotification *)notification
{
	[self updateRotationCenter];

	[self->delegate LDrawRendererNeedsRedisplay:self];

} // end rotationCenterChanged:

@end
