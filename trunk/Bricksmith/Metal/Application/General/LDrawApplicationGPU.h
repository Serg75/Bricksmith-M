//==============================================================================
//
//	LDrawApplicationGPU.h
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawApplication.h"


@interface LDrawApplication ()
{
//	NSOpenGLContext			*sharedGLContext;		// OpenGL variables like display list numbers are shared through this.
}

@end


@interface LDrawApplication (Metal)

//Accessors
//+ (NSOpenGLPixelFormat *) openGLPixelFormat;
//+ (NSOpenGLContext *) sharedOpenGLContext;
+ (void) makeCurrentSharedContext;

-(void) makeSharedContext;

@end
