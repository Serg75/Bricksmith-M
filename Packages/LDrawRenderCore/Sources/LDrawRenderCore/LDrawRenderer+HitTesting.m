//==============================================================================
//
//  File:       LDrawRenderer+HitTesting.m
//  Package:    LDrawRenderCore
//
//  Purpose:    Viewport hit testing and mouse-over feedback for LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import "LDrawRendererInternal.h"

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/MatrixMath.h>


#define HANDLE_SIZE 3


@implementation LDrawRenderer (HitTesting)

//========== getDepthUnderPoint: ===============================================
//
// Purpose:		Returns the depth component of the nearest object under the view 
//				point. 
//
//				Returns 1.0 if there is no object under the point.
//
//==============================================================================
- (float)getDepthUnderPoint:(Point2)point_view
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
									Matrix4CreateFromFloats([camera modelView]),
									Matrix4CreateFromFloats([camera projection]));
				
	id bestObject = nil;
	[fileBeingDrawn depthTest:point_clip inBox:test_box transform:mvp creditObject:nil bestObject:&bestObject bestDepth:&depth];
																			
	return depth * 0.5 + 0.5;

} // end getDepthUnderPoint


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
- (NSArray *)getDirectivesUnderRect:(Box2)rect_view 
					amongDirectives:(NSArray *)directives
						   fastDraw:(BOOL)fastDraw
{
	NSArray	*clickedDirectives	= nil;
	
	if ([directives count] == 0)
	{
		// If there's nothing to test in, there's no work to do!
		clickedDirectives = @[];
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
									  Matrix4CreateFromFloats([camera modelView]),
									  Matrix4CreateFromFloats([camera projection]));
										
		// Do hit test
		for (counter = 0; counter < [directives count]; counter++)
		{
			[[directives objectAtIndex:counter] boxTest:test_box
											  transform:mvp 
											 boundsOnly:fastDraw
										   creditObject:nil
												   hits:hits];
		}

		NSMutableArray * collected = [NSMutableArray arrayWithCapacity:[hits count]];
		clickedDirectives = collected;
		
		for (NSValue *key in hits)
		{
			LDrawDirective * currentDirective    = [key pointerValue];
			[collected addObject:currentDirective];
		}
	}

	return clickedDirectives;
	
} // end getDirectivesUnderMouse:amongDirectives:fastDraw


//========== publishMouseOverPoint: ============================================
//
// Purpose:		Informs the delegate that the mouse is hovering over the model 
//				point under the view point. 
//
//==============================================================================
- (void)publishMouseOverPoint:(Point2)point_view
{
	Point3		modelPoint			= ZeroPoint3;
	Vector3		modelAxisForX		= ZeroPoint3;
	Vector3		modelAxisForY		= ZeroPoint3;
	Vector3		modelAxisForZ		= ZeroPoint3;
	Vector3		confidence			= ZeroPoint3;
	
	if ([self->delegate respondsToSelector:@selector(LDrawRenderer:mouseIsOverPoint:confidence:)])
	{
		modelPoint = [self modelPointForPoint:point_view];
		
		if ([self projectionMode] == LDrawProjectionModeOrthographic)
		{
			[self getModelAxesForViewX:&modelAxisForX Y:&modelAxisForY Z:&modelAxisForZ];
			
			confidence = V3Add(modelAxisForX, modelAxisForY);
		}
		
		[self->delegate LDrawRenderer:self mouseIsOverPoint:modelPoint confidence:confidence];
	}
}

@end
