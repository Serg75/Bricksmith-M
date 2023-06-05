//==============================================================================
//
//	LDrawApplication.m
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

#import "LDrawApplicationGPU.h"

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

+ (void) makeCurrentSharedContext
{
	[[LDrawApplication shared]->sharedGLContext makeCurrentContext];
}

+ (void) makeCurrentSharedContextKeepOriginal:(NSOpenGLContext *)originalContext
{
	[[LDrawApplication shared]->sharedGLContext makeCurrentContext];
}

//---------- sharedOpenGLContext -------------------------------------[static]--
//
// Purpose:		Returns the OpenGLContext which unifies our display-list tags.
//				Every LDrawGLView should share this context.
//
//------------------------------------------------------------------------------
+ (NSOpenGLContext *) sharedOpenGLContext
{
	return [LDrawApplication shared]->sharedGLContext;
	
}//end sharedOpenGLContext


#pragma mark -

-(void) makeSharedContext
{
	NSOpenGLPixelFormat *pixelFormat	= [LDrawApplication openGLPixelFormat];
	self->sharedGLContext				= [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
	
	[sharedGLContext makeCurrentContext];
}

@end
