//==============================================================================
//
//	LDrawApplicationGL.h
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Info:		This category contains OpenGL-related code. Shared GPU methods
//				(makeCurrentSharedContext, makeSharedContext) are declared on
//				LDrawApplication.
//
//	Created by Sergey Slobodenyuk on 2023-05-10.
//
//==============================================================================

#import "LDrawApplication.h"


@interface LDrawApplication (OpenGL)

+ (NSOpenGLPixelFormat *) openGLPixelFormat;
+ (NSOpenGLContext *) sharedOpenGLContext;

/// Activate the shared context; the caller restores originalContext afterward.
+ (void) makeCurrentSharedContextKeepOriginal:(NSOpenGLContext *)originalContext;

@end
