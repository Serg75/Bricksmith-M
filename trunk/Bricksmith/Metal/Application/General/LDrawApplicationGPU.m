//==============================================================================
//
//	LDrawApplicationGPU.m
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Note:		Do not confuse this class with BricksmithApplication, which is
//				an NSApplication subclass.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawApplicationGPU.h"

@implementation LDrawApplication (Metal)

#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

////---------- openGLPixelFormat ---------------------------------------[static]--
////
//// Purpose:		Returns the pixel format used in Bricksmith OpenGL views.
////
////------------------------------------------------------------------------------
//+ (NSOpenGLPixelFormat *) openGLPixelFormat
//{
//	NSOpenGLPixelFormat				*pixelFormat		= nil;
//	NSOpenGLPixelFormatAttribute	pixelAttributes[]	= {
//															NSOpenGLPFANoRecovery, // Enable automatic use of OpenGL "share" contexts for Core Animation.
//															NSOpenGLPFADoubleBuffer,
//															NSOpenGLPFADepthSize,		32,
//															NSOpenGLPFASampleBuffers,	1, // enable line antialiasing
//															NSOpenGLPFASamples,			4, // antialiasing beauty
//															0};
//
//	pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes: pixelAttributes];
//	return pixelFormat;
//}

+ (void) makeCurrentSharedContext { }

////---------- sharedOpenGLContext -------------------------------------[static]--
////
//// Purpose:		Returns the OpenGLContext which unifies our display-list tags.
////				Every LDrawGLView should share this context.
////
////------------------------------------------------------------------------------
//+ (NSOpenGLContext *) sharedOpenGLContext
//{
//	return [LDrawApplication shared]->sharedGLContext;
//
//}//end sharedOpenGLContext


#pragma mark -

-(void) makeSharedContext { }

@end
