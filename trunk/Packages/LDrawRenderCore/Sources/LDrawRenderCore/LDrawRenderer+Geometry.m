//==============================================================================
//
//  File:       LDrawRenderer+Geometry.m
//  Package:    LDrawRenderCore
//
//  Purpose:    Viewport / model coordinate conversion for LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import "LDrawRendererInternal.h"

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/MatrixMath.h>


@implementation LDrawRenderer (Geometry)

//========== convertPointFromViewport: =========================================
//
// Purpose:		Converts the point from the viewport coordinate system to the 
//				view bounds' coordinate system. 
//
//==============================================================================
- (Point2)convertPointFromViewport:(Point2)viewportPoint
{
	Point2	point_view = viewportPoint;
	
	// Our host view is always flipped: viewport origin is lower-left, view
	// origin is upper-left.
	point_view.y = V2BoxHeight([self viewport]) - point_view.y;
	
	return point_view;
	
} // end convertPointFromViewport:


//========== convertPointToViewport: ===========================================
//
// Purpose:		Converts the point from the view bounds' coordinate system into 
//				the viewport's coordinate system. 
//
//==============================================================================
- (Point2)convertPointToViewport:(Point2)point_view
{
	Point2	point_viewport		= point_view;

	// Our host view is always flipped: viewport origin is lower-left, view
	// origin is upper-left.
	point_viewport.y = V2BoxHeight([self viewport]) - point_viewport.y;
	
	return point_viewport;
	
} // end convertPointToViewport:


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
- (void)getModelAxesForViewX:(Vector3 *)outModelX
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
	
	// find the vectors in the model which project onto the screen's axes
	// (We only care about x and y because this is a two-dimensional 
	// projection, and the third axis is consquently ambiguous. See below.) 
	unprojectedX = V4MulPointByMatrix(screenX, inversed);
	unprojectedY = V4MulPointByMatrix(screenY, inversed);
	
	// find the actual axes closest to those model vectors
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
	
	if (outModelX != NULL)
		*outModelX = modelX;
	if (outModelY != NULL)
		*outModelY = modelY;
	if (outModelZ != NULL)
		*outModelZ = modelZ;
	
} // end getModelAxesForViewX:Y:Z:


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
- (Point3)modelPointForPoint:(Point2)viewPoint
{
	Point2              viewportPoint           = [self convertPointToViewport:viewPoint];
	float               depth                   = 0.0; 
	TransformComponents partTransform           = IdentityComponents;
	Point3              contextPoint            = ZeroPoint3;
	Point3              modelPoint              = ZeroPoint3;
	
	depth = [self getDepthUnderPoint:viewPoint];
	
	if (depth == 1.0)
	{
		// Error!
		// Maximum depth readings essentially tell us that no pixels were drawn 
		// at this point. So we have to make up a best guess now. This guess 
		// will very likely be wrong, but there is little else which can be 
		// done. 
		
		if ([self->delegate respondsToSelector:@selector(LDrawRendererPreferredPartTransform:)])
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
	
} // end modelPointForPoint:


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
- (Point3)modelPointForPoint:(Point2)viewPoint
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
	if (modelZ.x != 0)
	{
		t = (nearModelPoint.x - depthPoint.x) / (nearModelPoint.x - farModelPoint.x);
	}
	else if (modelZ.y != 0)
	{
		t = (nearModelPoint.y - depthPoint.y) / (nearModelPoint.y - farModelPoint.y);
	}
	else if (modelZ.z != 0)
	{
		t = (nearModelPoint.z - depthPoint.z) / (nearModelPoint.z - farModelPoint.z);
	}
	// Evaluate the equation of the near-to-far line at the parameter for 
	// the depth point. 
	modelPoint.x = LERP(t, nearModelPoint.x, farModelPoint.x);
	modelPoint.y = LERP(t, nearModelPoint.y, farModelPoint.y);
	modelPoint.z = LERP(t, nearModelPoint.z, farModelPoint.z);

	return modelPoint;
	
} // end modelPointForPoint:depthReferencePoint:

@end
