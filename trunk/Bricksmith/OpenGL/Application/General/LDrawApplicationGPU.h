//==============================================================================
//
//	LDrawApplication.h
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-10.
//
//==============================================================================

#import "LDrawApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawApplication ()
{
	NSOpenGLContext			*sharedGLContext;		// OpenGL variables like display list numbers are shared through this.
}

@end


@interface LDrawApplication (OpenGL)

//Accessors
+ (NSOpenGLPixelFormat *) openGLPixelFormat;
+ (NSOpenGLContext *) sharedOpenGLContext;
+ (void) makeCurrentSharedContext;

-(void) makeSharedContext;

@end

NS_ASSUME_NONNULL_END
