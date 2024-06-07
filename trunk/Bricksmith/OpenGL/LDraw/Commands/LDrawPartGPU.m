//==============================================================================
//
//	LDrawPartGPU.m
//	Bricksmith
//
//	Purpose:	Part command.
//				Inserts a part defined in another LDraw file.
//
//				Line format:
//				1 colour x y z a b c d e f g h i part.dat
//
//				where
//
//				* colour is a colour code: 0-15, 16, 24, 32-47, 256-511
//				* x, y, z is the position of the part
//				* a - i are orientation & scaling parameters
//				* part.dat is the filename of the included file
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-29.
//
//==============================================================================

#import "LDrawPartGPU.h"

#import "LDrawModel.h"
#import "PartLibraryGL.h"

@implementation LDrawPart (OpenGL)

#pragma mark -
#pragma mark DIRECTIVES
#pragma mark -

//========== drawElement:viewScale:withColor: ==================================
//
// Purpose:		Draws the graphic of the element represented. This call is a
//				subroutine of -draw: in LDrawDrawableElement.
//
//==============================================================================
- (void) drawElement:(NSUInteger)optionsMask viewScale:(float)scaleFactor withColor:(LDrawColor *)drawingColor
{
	LDrawDirective  *drawable       = nil;
	BOOL            drawBoundsOnly  = ((optionsMask & DRAW_BOUNDS_ONLY) != 0);
	
	// If the part is selected, we need to give some indication. We do this
	// by drawing it as a wireframe instead of a filled color. This setting
	// also conveniently applies to all referenced parts herein.
	if([self isSelected] == YES)
	{
#if (USE_AUTOMATIC_WIREFRAMES)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
#else
		optionsMask = optionsMask | DRAW_WIREFRAME;
#endif
	}

	// Multithreading finally works with one display list per displayed part
	// AND mutexes around the glCallList. But the mutex contention causes a
	// 50% increase in drawing time. Gah!
	
	glPushMatrix();
	{
		glMultMatrixf(glTransformation);
		
		[self resolvePart];

		drawable = cacheDrawable;

		if (cacheType == PartTypeLibrary && cacheDrawable == nil)
		{
			// Parts assigned to LDrawCurrentColor may get drawn in many
			// different colors in one draw, so we can't cache their
			// optimized drawable. We have to retrieve their optimized
			// drawable on-the-fly.
			
			// Parts that have a SPECIFIC color have been linked DIRECTLY to
			// their specific colored VBO during -optimizeOpenGL.
			
			drawable = [[PartLibraryGL sharedPartLibrary] optimizedDrawableForPart:self color:drawingColor];
		}
		
		if(drawBoundsOnly == NO)
		{
			[drawable draw:optionsMask viewScale:scaleFactor parentColor:drawingColor];
		}
		else
		{
			[self drawBoundsWithColor:drawingColor];
		}
	}
	glPopMatrix();

	// Done drawing a selected part? Then switch back to normal filled drawing.
	if([self isSelected] == YES)
	{
#if (USE_AUTOMATIC_WIREFRAMES)
		glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
#endif
	}

}//end drawElement:parentColor:


//========== debugDrawboundingBox ==============================================
//
// Purpose:		Draw a translucent visualization of our bounding box to test
//				bounding box caching.
//
//==============================================================================
- (void) debugDrawboundingBox
{
	[self resolvePart];
	LDrawModel	*modelToDraw	= cacheModel;
	
	//If the model can't be found, we can't draw good bounds for it!
	if(modelToDraw != nil)
	{
		glPushMatrix();
		glMultMatrixf(glTransformation);
		[modelToDraw debugDrawboundingBox];
		glPopMatrix();
	}
	
	[super debugDrawboundingBox];
}//end debugDrawboundingBox


@end
