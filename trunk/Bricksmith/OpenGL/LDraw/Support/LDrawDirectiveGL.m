//==============================================================================
//
//	LDrawDirectiveGL.m
//	Bricksmith
//
//	Purpose:	Base class for all LDraw objects provides a few basic utilities.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-10.
//
//==============================================================================

#import "LDrawDirectiveGL.h"

#include OPEN_GL_HEADER

@implementation LDrawDirective (OpenGL)

//========== debugDrawBoundingBox ==============================================
//
// Purpose:		Draw a translucent visualization of our bounding box to test
//				bounding box caching.
//
// Notes:		The base class draws the geometry; derived classes can add
//				iteration to sub-directives and transforms.
//
//				The calling code gets us into our GL state ahead of time.
//
//==============================================================================
- (void) debugDrawBoundingBox
{
	Box3	my_bounds = [self boundingBox3];
	if(my_bounds.min.x <= my_bounds.max.x &&
	   my_bounds.min.y <= my_bounds.max.y &&
	   my_bounds.min.z <= my_bounds.max.z)
	{
		GLfloat	verts[6*4*3] = {
			my_bounds.min.x,	my_bounds.min.y,	my_bounds.min.z,
			my_bounds.min.x,	my_bounds.min.y,	my_bounds.max.z,
			my_bounds.min.x,	my_bounds.max.y,	my_bounds.max.z,
			my_bounds.min.x,	my_bounds.max.y,	my_bounds.min.z,

			my_bounds.max.x,	my_bounds.min.y,	my_bounds.min.z,
			my_bounds.max.x,	my_bounds.min.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.max.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.max.y,	my_bounds.min.z,


			my_bounds.min.x,	my_bounds.min.y,	my_bounds.min.z,
			my_bounds.min.x,	my_bounds.max.y,	my_bounds.min.z,
			my_bounds.max.x,	my_bounds.max.y,	my_bounds.min.z,
			my_bounds.max.x,	my_bounds.min.y,	my_bounds.min.z,

			my_bounds.min.x,	my_bounds.min.y,	my_bounds.max.z,
			my_bounds.min.x,	my_bounds.max.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.max.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.min.y,	my_bounds.max.z,


			my_bounds.min.x,	my_bounds.min.y,	my_bounds.min.z,
			my_bounds.min.x,	my_bounds.min.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.min.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.min.y,	my_bounds.min.z,

			my_bounds.min.x,	my_bounds.max.y,	my_bounds.min.z,
			my_bounds.min.x,	my_bounds.max.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.max.y,	my_bounds.max.z,
			my_bounds.max.x,	my_bounds.max.y,	my_bounds.min.z };
		
		glVertexPointer(3, GL_FLOAT, 0, verts);
		glDrawArrays(GL_QUADS,0,24);
	}
}//end debugDrawBoundingBox


@end
