//==============================================================================
//
//  File:       LDrawRenderer+Camera.m
//  Package:    LDrawRenderCore
//
//  Purpose:    Camera zoom and scroll commands for LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import "LDrawRendererInternal.h"

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/MatrixMath.h>


@implementation LDrawRenderer (Camera)

//========== moveCamera: =======================================================
//
// Purpose:		Moves the camera's rotation center by a fixed offset.  Used to
//				walk around the walk-through camera, or to change the model's
//				center of rotation for the model camera.
//
//==============================================================================
- (void)moveCamera:(Vector3)delta
{
	[camera setRotationCenter:V3Add([camera rotationCenter], delta)];
	[delegate LDrawRendererNeedsRedisplay:self];
} // end moveCamera


//========== zoomIn: ===========================================================
//
// Purpose:		Enlarge the scale of the current LDraw view.
//
//==============================================================================
- (IBAction)zoomIn:(id)sender
{
	CGFloat currentZoom	= [self zoomPercentage];
	CGFloat newZoom		= currentZoom * 2;
	
	[self setZoomPercentage:newZoom];
	
} // end zoomIn:


//========== zoomOut: ==========================================================
//
// Purpose:		Shrink the scale of the current LDraw view.
//
//==============================================================================
- (IBAction)zoomOut:(id)sender
{
	CGFloat currentZoom	= [self zoomPercentage];
	CGFloat newZoom		= currentZoom / 2;
	
	[self setZoomPercentage:newZoom];
	
} // end zoomOut:


//========== zoomToFit: ========================================================
//
// Purpose:		Enlarge or shrink the zoom and scroll the model such that its 
//				image perfectly fills the visible area of the view 
//
//==============================================================================
- (IBAction)zoomToFit:(id)sender
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
	if ([self->fileBeingDrawn respondsToSelector:@selector(boundingBox3)] )
	{
		boundingBox = [(id)self->fileBeingDrawn boundingBox3];
		if (V3EqualBoxes(boundingBox, InvalidBox) == NO)
		{		
			// Project the bounds onto the 2D "canvas"
			modelView   = Matrix4CreateFromFloats([camera modelView]);
			projection  = Matrix4CreateFromFloats([camera projection]);

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
	
} // end zoomToFit:


//========== autoscrollPoint:relativeToRect: ===================================
///
/// @abstract	If the point is outside the given view rect, this will scroll
/// 			the view by the amount the point is outside.
///
//==============================================================================
- (BOOL)autoscrollPoint:(Point2)point_view
		 relativeToRect:(Box2)viewRect
{
	BOOL didScroll = NO;
	
	if ( V2BoxContains(viewRect, point_view) == NO )
	{
		// Amount to offset origin
		Vector2 scrollVector = ZeroPoint2;
		
		// x
		if (point_view.x < V2BoxMinX(viewRect))
		{
			scrollVector.x = point_view.x - V2BoxMinX(viewRect);
		}
		else if (point_view.x > V2BoxMaxX(viewRect))
		{
			scrollVector.x = point_view.x - V2BoxMaxX(viewRect);
		}
		
		// y
		if (point_view.y < V2BoxMinY(viewRect))
		{
			scrollVector.y = point_view.y - V2BoxMinY(viewRect);
		}
		else if (point_view.y > V2BoxMaxY(viewRect))
		{
			scrollVector.y = point_view.y - V2BoxMaxY(viewRect);
		}
		
		[self scrollBy:scrollVector];
		didScroll = YES;
	}
	
	return didScroll;
}


//========== setZoomPercentage:preservePoint: ==================================
//
// Purpose:		Performs cursor-centric zooming on the given point, in view 
//				coordinates. After the new zoom is applied, the 3D point 
//				projected at viewPoint will still be in the same projected 
//				location. 
//
//==============================================================================
- (void)setZoomPercentage:(CGFloat)newPercentage
			preservePoint:(Point2)viewPoint
{
	Point3 modelPoint = [self modelPointForPoint:viewPoint];

	[camera setZoomPercentage:newPercentage preservePoint:modelPoint];
	[self->delegate LDrawRendererNeedsRedisplay:self];

} // end setZoomPercentage:preservePoint:


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
- (void)scrollBy:(Vector2)scrollDelta_viewport
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
- (void)scrollCameraVisibleRectToPoint:(Point2)visibleRectOrigin
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
- (void)scrollCenterToModelPoint:(Point3)modelPoint
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

} // end scrollCenterToModelPoint:


//========== updateRotationCenter ==============================================
//
// Purpose:		Resync our copy of the rotationCenter with the one used by the 
//				model. 
//
//==============================================================================
- (void)updateRotationCenter
{
	Point3	point		= ZeroPoint3;
	
	if ([fileBeingDrawn isKindOfClass:[LDrawFile class]])
	{
		point = [[(LDrawFile*)fileBeingDrawn activeModel] rotationCenter];
	}
	else if ([fileBeingDrawn isKindOfClass:[LDrawModel class]])
	{
		point = [(LDrawModel*)fileBeingDrawn rotationCenter];
	}
	
	[camera setRotationCenter:point];	
	[self->delegate LDrawRendererNeedsRedisplay:self];
}

@end
