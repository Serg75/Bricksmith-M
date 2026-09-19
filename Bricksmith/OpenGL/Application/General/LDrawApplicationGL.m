//==============================================================================
//
//	LDrawApplicationGL.m
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Note:		Do not confuse this class with BricksmithApplication, which is
//				an NSApplication subclass.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-10.
//
//==============================================================================

#import "LDrawApplicationGL.h"

static NSOpenGLContext *SharedGLContext = nil;

@implementation LDrawApplication (OpenGL)

#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//---------- openGLPixelFormat ---------------------------------------[static]--
//
// Purpose:		Returns the pixel format used in Bricksmith OpenGL views.
//
//------------------------------------------------------------------------------
+ (NSOpenGLPixelFormat *) openGLPixelFormat
{
	NSOpenGLPixelFormat				*pixelFormat		= nil;
	NSOpenGLPixelFormatAttribute	pixelAttributes[]	= {
															NSOpenGLPFANoRecovery, // Enable automatic use of OpenGL "share" contexts for Core Animation.
															NSOpenGLPFADoubleBuffer,
															NSOpenGLPFADepthSize,		32,
															NSOpenGLPFASampleBuffers,	1, // enable line antialiasing
															NSOpenGLPFASamples,			4, // antialiasing beauty
															0};

	pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes: pixelAttributes];
	return pixelFormat;
}

//========== makeCurrentSharedContext ==========================================
//
// Purpose:		Activate the application-wide shared OpenGL context so display-
//				list tags and other GL state are consistent across views.
//
//==============================================================================
+ (void) makeCurrentSharedContext
{
	[SharedGLContext makeCurrentContext];
}

//========== makeCurrentSharedContextKeepOriginal: =============================
//
// Purpose:		Activate the shared context for outline-driven selection updates.
//				The original context is restored by the caller when finished.
//
//==============================================================================
+ (void) makeCurrentSharedContextKeepOriginal:(NSOpenGLContext *)originalContext
{
	[SharedGLContext makeCurrentContext];
}

//---------- sharedOpenGLContext -------------------------------------[static]--
//
// Purpose:		Returns the OpenGLContext which unifies our display-list tags.
//				Every LDrawGLView should share this context.
//
//------------------------------------------------------------------------------
+ (NSOpenGLContext *) sharedOpenGLContext
{
	return SharedGLContext;
	
}//end sharedOpenGLContext


#pragma mark -

//========== makeSharedContext =================================================
//
// Purpose:		Create the application-wide shared OpenGL context used to unify
//				display-list tags across all LDraw views.
//
//==============================================================================
-(void) makeSharedContext
{
	NSOpenGLPixelFormat *pixelFormat	= [LDrawApplication openGLPixelFormat];
	SharedGLContext						= [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
	
	[SharedGLContext makeCurrentContext];
}

@end
