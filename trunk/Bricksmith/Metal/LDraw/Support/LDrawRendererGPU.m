//==============================================================================
//
//	LDrawRendererGPU.m
//	Bricksmith
//
//	Purpose:	Draws an LDrawFile with OpenGL.
//
//				This class is responsible for all platform-independent logic,
//				including math and OpenGL operations. It also contains a number
//				of methods which would be called in response to events; it is
//				the responsibility of the platform layer to receive and
//				interpret those events and pass them to us.
//
//				The "event" type methods here take high-level parameters. For
//				example, we don't check -- or want to know! -- if the option key
//				is down. The platform layer figures out stuff like that, and
//				more importantly, figures out what it *means*. The *meaning* is
//				what the renderer's methods care about.
//
//	Note:		This file uses manual reference counting.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

@import simd;
@import ModelIO;
@import MetalKit;

#import "LDrawRendererGPU.h"

#import "LDrawShaderRendererMTL.h"
#include "OpenGLUtilities.h"


#define WANT_TWOPASS_BOXTEST		0	// this enables the two-pass box-test.  It is actually faster to _not_ do this now that hit testing is optimized.
#define DEBUG_BOUNDING_BOX			0	// attempts to draw debug bounding box visualization on the model.

#define NEW_RENDERER				1	// runs Ben's new shader-based renderer, not 2.6-era fixed-function renderer.


#define DEBUG_DRAWING				0	// print fps of drawing, and never fall back to bounding boxes no matter how slow.
#define SIMPLIFICATION_THRESHOLD	0.3 // seconds


@interface LDrawRenderer ()
{
	dispatch_semaphore_t _inFlightSemaphore;
	id<MTLDevice>        _device;
	id<MTLCommandQueue>  _commandQueue;
}

@end

@implementation LDrawRenderer (Metal)

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== prepareMetal ======================================================
//
// Purpose:		The context is all set up; this is where we prepare our OpenGL
//				state.
//
//==============================================================================
- (void) prepareMetal
{
//	glEnable(GL_DEPTH_TEST);
//	glEnable(GL_BLEND);
//	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
//	glEnable(GL_MULTISAMPLE); //antialiasing
//
//	glEnable(GL_TEXTURE_2D);
//	glEnable(GL_TEXTURE_GEN_S);
//	glEnable(GL_TEXTURE_GEN_T);
//
//	// This represents the "default" GL state, at least until we change that policy.
//	glEnableClientState(GL_VERTEX_ARRAY);
//	glEnableClientState(GL_NORMAL_ARRAY);
//	glEnableClientState(GL_COLOR_ARRAY);
//
//	// Default color. Our wrapper is responsible from applying the user's
//	// preferred color.
//	NSColor *bgColor = [NSColor.controlBackgroundColor
//						colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]];
//	[self setBackgroundColorRed:bgColor.redComponent
//						  green:bgColor.greenComponent
//						   blue:bgColor.blueComponent]; // window background color

	//
	// Define the lighting.
	//

//	//Our light position is transformed by the modelview matrix. That means
//	// we need to have a standard model matrix loaded to get our light to
//	// land in the right place! But our modelview might have already been
//	// affected by someone calling -setViewOrientation:. So we restore the
//	// default here.
//	glMatrixMode(GL_MODELVIEW);
//	glLoadIdentity();
//	glRotatef(180,1,0,0); //convert to standard, upside-down LDraw orientation.
//
//	//---------- Material ------------------------------------------------------
//
////	GLfloat ambient[4]  = { 0.2, 0.2, 0.2, 1.0 };
////	GLfloat diffuse[4]	= { 0.5, 0.5, 0.5, 1.0 };
//	GLfloat specular[4] = { 0.0, 0.0, 0.0, 1.0 };
//	GLfloat shininess   = 64.0; // range [0-128]
//
////	glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT,	ambient );
////	glMaterialfv( GL_FRONT_AND_BACK, GL_DIFFUSE,	diffuse ); //don't bother; overridden by glColorMaterial
//	glMaterialfv( GL_FRONT_AND_BACK, GL_SPECULAR,	specular );
//	glMaterialf(  GL_FRONT_AND_BACK, GL_SHININESS,	shininess );
//
////	glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE); // this is the default anyway
//
//	glShadeModel(GL_SMOOTH);
//	glEnable(GL_NORMALIZE);
//	glEnable(GL_COLOR_MATERIAL);
//
//
//	//---------- Light Model ---------------------------------------------------
//
//	// The overall scene has ambient light to make the lighting less harsh. But
//	// too much ambient light makes everything washed out.
//	GLfloat lightModelAmbient[4]    = {0.3, 0.3, 0.3, 0.0};
//
//	glLightModelf( GL_LIGHT_MODEL_TWO_SIDE,		GL_FALSE );
//	glLightModelfv(GL_LIGHT_MODEL_AMBIENT,		lightModelAmbient);
//
//
//	//---------- Lights --------------------------------------------------------
//
//	// We are going to have two lights, one in a standard position (LIGHT0) and
//	// another pointing opposite to it (LIGHT1). The second light will
//	// illuminate any inverted normals or backwards polygons.
//	GLfloat position0[] = {0, -0.0, -1.0, 0};
//	GLfloat position1[] = {0,  0.0,  1.0, 0};
//
//	// Lessening the diffuseness also makes lighting less extreme.
//	GLfloat light0Ambient[4]     = { 0.0, 0.0, 0.0, 1.0 };
//	GLfloat light0Diffuse[4]     = { 0.8, 0.8, 0.8, 1.0 };
//	GLfloat light0Specular[4]    = { 0.0, 0.0, 0.0, 1.0 };
//
//	//normal forward light
//	glLightfv(GL_LIGHT0, GL_POSITION, position0);
//	glLightfv(GL_LIGHT0, GL_AMBIENT,  light0Ambient);
//	glLightfv(GL_LIGHT0, GL_DIFFUSE,  light0Diffuse);
//	glLightfv(GL_LIGHT0, GL_SPECULAR, light0Specular);
//
//	glLightf(GL_LIGHT0, GL_CONSTANT_ATTENUATION,	1.0);
//	glLightf(GL_LIGHT0, GL_LINEAR_ATTENUATION,		0.0);
//	glLightf(GL_LIGHT0, GL_QUADRATIC_ATTENUATION,	0.0);
//
//	//opposing light to illuminate backward normals.
//	glLightfv(GL_LIGHT1, GL_POSITION, position1);
//	glLightfv(GL_LIGHT1, GL_AMBIENT,  light0Ambient);
//	glLightfv(GL_LIGHT1, GL_DIFFUSE,  light0Diffuse);
//	glLightfv(GL_LIGHT1, GL_SPECULAR, light0Specular);
//
//	glLightf(GL_LIGHT1, GL_CONSTANT_ATTENUATION,	1.0);
//	glLightf(GL_LIGHT1, GL_LINEAR_ATTENUATION,		0.0);
//	glLightf(GL_LIGHT1, GL_QUADRATIC_ATTENUATION,	0.0);
//
//	glEnable(GL_LIGHTING);
//	glEnable(GL_LIGHT0);
//	glEnable(GL_LIGHT1);
//
//
//	//Now that the light is positioned where we want it, we can restore the
//	// correct viewing angle.
//	[self setViewOrientation:self->viewOrientation];

}//end prepareOpenGL


#pragma mark -
#pragma mark DRAWING
#pragma mark -

//========== draw ==============================================================
//
// Purpose:		Draw the LDraw content of the view.
//
// Notes:		This method is, in theory at least, as thread-safe as Apple's
//				OpenGL implementation is. Which is to say, not very much.
//
//==============================================================================
- (void) drawInMTKView:(nonnull MTKView *)view
{
	NSDate			*startTime			= nil;
	NSUInteger		options 			= DRAW_NO_OPTIONS;
	NSTimeInterval	drawTime			= 0;
	BOOL			considerFastDraw	= NO;
	
//	// TODO: learn more
//
//	// Wait to ensure only a maximum of `AAPLMaxBuffersInFlight` frames are being processed by any
//	// stage in the Metal pipeline (e.g. app, Metal, drivers, GPU, etc.) at any time. This mechanism
//	// prevents the CPU from overwriting dynamic buffer data before the GPU has read it.
//	dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

	startTime	= [NSDate date];

//	// We may need to simplify large models if we are spinning the model
//	// or doing part drag-and-drop.
//	considerFastDraw =		self->isTrackingDrag == YES
//						||	self->isGesturing == YES
//						||	(	[self->fileBeingDrawn respondsToSelector:@selector(draggingDirectives)]
//							 &&	[(id)self->fileBeingDrawn draggingDirectives] != nil
//							);
//#if DEBUG_DRAWING == 0
//	if(considerFastDraw == YES && self->rotationDrawMode == LDrawGLDrawExtremelyFast)
//	{
//		options |= DRAW_BOUNDS_ONLY;
//	}
//#endif //DEBUG_DRAWING
	
//	assert(glCheckInteger(GL_VERTEX_ARRAY_BINDING_APPLE,0));
//	assert(glCheckInteger(GL_ARRAY_BUFFER_BINDING,0));
//	assert(glIsEnabled(GL_VERTEX_ARRAY));
//	assert(glIsEnabled(GL_NORMAL_ARRAY));
//	assert(glIsEnabled(GL_COLOR_ARRAY));

//	id<MTLCommandBuffer> commandBuffer;
//
//	commandBuffer = [_commandQueue commandBuffer];
//	commandBuffer.label = @"Drawable Command Buffer";

	// Add a completion hander that signals `_inFlightSemaphore` when Metal and the GPU have fully
	// finished processing the commands encoded this frame. This indicates that the dynamic bufers,
	// written to this frame, are no longer be needed by Metal or the GPU, meaning that you can
	// change the buffer contents without corrupting any rendering.
//	__block dispatch_semaphore_t block_sema = _inFlightSemaphore;
//	[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
//	{
//		dispatch_semaphore_signal(block_sema);
//	}];

//	//Load the model matrix to make sure we are applying the right stuff.
//	glMatrixMode(GL_MODELVIEW);
//	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
//
//	// Make lines look a little nicer; Max width 1.0; 0.5 at 100% zoom
//	glLineWidth(MIN([self zoomPercentageForGL]/100 * 0.5, 1.0));
//
//	glMatrixMode(GL_PROJECTION);
//	glLoadMatrixf([camera getProjection]);
//	glMatrixMode(GL_MODELVIEW);
//	glLoadMatrixf([camera getModelView]);

//	// DRAW!
//	#if !NEW_RENDERER
//
//		[self->fileBeingDrawn draw:options
//						 viewScale:[self zoomPercentageForGL]/100.
//					   parentColor:color];
//
//	#else

		LDrawShaderRenderer * ren = [[LDrawShaderRenderer alloc] initWithScale:[self zoomPercentageForGL]/100. modelView:[camera getModelView] projection:[camera getProjection]];
		[self->fileBeingDrawn drawSelf:ren];
//		[ren release];

//	#endif
  
//	// We allow primitive drawing to leave their VAO bound to avoid setting the VAO
//	// back to zero between every draw call.  Set it once here to avoid usign some
//	// poor directive to draw!
//	glBindVertexArrayAPPLE(0);

//	assert(glCheckInteger(GL_VERTEX_ARRAY_BINDING_APPLE,0));
//	assert(glCheckInteger(GL_ARRAY_BUFFER_BINDING,0));
//	assert(glIsEnabled(GL_VERTEX_ARRAY));
//	assert(glIsEnabled(GL_NORMAL_ARRAY));
//	assert(glIsEnabled(GL_COLOR_ARRAY));

//	#if DEBUG_BOUNDING_BOX
//	glDepthMask(GL_FALSE);
//	glDisableClientState(GL_COLOR_ARRAY);
//	glDisableClientState(GL_NORMAL_ARRAY);
//	glDisable(GL_LIGHTING);
//	glColor4f(0.5,0.5,0.5,0.1);
//	[self->fileBeingDrawn debugDrawboundingBox];
//	glEnableClientState(GL_COLOR_ARRAY);
//	glEnableClientState(GL_NORMAL_ARRAY);
//	glEnable(GL_LIGHTING);
//	glDepthMask(GL_TRUE);
//	#endif

//	// Marquee selection box -- only if non-zero.
//	if( V2BoxWidth(self->selectionMarquee) != 0 && V2BoxHeight(self->selectionMarquee) != 0)
//	{
//		Point2	from	= self->selectionMarquee.origin;
//		Point2	to		= V2Make( V2BoxMaxX(selectionMarquee), V2BoxMaxY(selectionMarquee) );
//		Point2	p1		= [self convertPointToViewport:from];
//		Point2	p2		= [self convertPointToViewport:to];
//
//		Box2	vp = [self viewport];
//		glMatrixMode(GL_PROJECTION);
//		glPushMatrix();
//		glLoadIdentity();
//		glOrtho(V2BoxMinX(vp),V2BoxMaxX(vp),V2BoxMinY(vp),V2BoxMaxY(vp),-1,1);
//		glMatrixMode(GL_MODELVIEW);
//		glPushMatrix();
//		glLoadIdentity();
//
//		glColor4f(0,0,0,1);
//
//		GLfloat	vertices[8] = {
//							p1.x,p1.y,
//							p2.x,p1.y,
//							p2.x,p2.y,
//							p1.x,p2.y };
//
//
//		glVertexPointer(2, GL_FLOAT, 0, vertices);
//		glDisableClientState(GL_NORMAL_ARRAY);
//		glDisableClientState(GL_COLOR_ARRAY);
//
//		glDrawArrays(GL_LINE_LOOP,0,4);
//		glEnableClientState(GL_NORMAL_ARRAY);
//		glEnableClientState(GL_COLOR_ARRAY);
//
//		glMatrixMode(GL_PROJECTION);
//		glPopMatrix();
//		glMatrixMode(GL_MODELVIEW);
//		glPopMatrix();
//	}
	
//	assert(glCheckInteger(GL_VERTEX_ARRAY_BINDING_APPLE,0));
//	assert(glCheckInteger(GL_ARRAY_BUFFER_BINDING,0));
//	assert(glIsEnabled(GL_VERTEX_ARRAY));
//	assert(glIsEnabled(GL_NORMAL_ARRAY));
//	assert(glIsEnabled(GL_COLOR_ARRAY));
	
	
	[self->delegate LDrawRendererNeedsFlush:self];
	
	// If we just did a full draw, let's see if rotating needs to be
	// done simply.
	drawTime = -[startTime timeIntervalSinceNow];
	if(considerFastDraw == NO)
	{
		if( drawTime > SIMPLIFICATION_THRESHOLD )
			rotationDrawMode = LDrawGLDrawExtremelyFast;
		else
			rotationDrawMode = LDrawGLDrawNormal;
	}

	// Timing info
	framesSinceStartTime++;
//#if DEBUG_DRAWING
//	NSTimeInterval timeSinceMark = [NSDate timeIntervalSinceReferenceDate] - fpsStartTime;
//	if(timeSinceMark > 5)
//	{	// reset periodically
//		fpsStartTime = [NSDate timeIntervalSinceReferenceDate];
//		framesSinceStartTime = 0;
//		NSLog(@"fps = ????????, period = ????????, draw time: %f", drawTime);
//	}
//	else
//	{
//		CGFloat framesPerSecond = framesSinceStartTime / timeSinceMark;
//		CGFloat period = timeSinceMark / framesSinceStartTime;
//		NSLog(@"fps = %f, period = %f, draw time: %f", framesPerSecond, period, drawTime);
//	}
//#endif //DEBUG_DRAWING
	
}//end draw:to


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== setBackgroundColorRed:green:blue: =================================
//
// Purpose:		Sets the canvas background color.
//
//==============================================================================
- (void) setBackgroundColorRed:(float)red green:(float)green blue:(float)blue
{
	glBackgroundColor[0] = red;
	glBackgroundColor[1] = green;
	glBackgroundColor[2] = blue;
	glBackgroundColor[3] = 1.0;

	glClearColor(glBackgroundColor[0],
				 glBackgroundColor[1],
				 glBackgroundColor[2],
				 glBackgroundColor[3] );
				 
	[self->delegate LDrawRendererNeedsRedisplay:self];
}


@end
