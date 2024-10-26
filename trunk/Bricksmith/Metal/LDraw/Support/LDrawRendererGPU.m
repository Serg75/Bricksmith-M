//==============================================================================
//
//	LDrawRendererGPU.m
//	Bricksmith
//
//	Purpose:	Draws an LDrawFile with Metal.
//
//				This class is responsible for all platform-independent logic,
//				including math and Metal operations. It also contains a number
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
#import "MetalGPU.h"
#include "OpenGLUtilities.h"
#include "MetalCommonDefinitions.h"


#define WANT_TWOPASS_BOXTEST		0	// this enables the two-pass box-test.  It is actually faster to _not_ do this now that hit testing is optimized.
#define DEBUG_BOUNDING_BOX			0	// attempts to draw debug bounding box visualization on the model.

#define DEBUG_DRAWING				1	// print fps of drawing, and never fall back to bounding boxes no matter how slow.
#define SIMPLIFICATION_THRESHOLD	0.3 // seconds


@interface LDrawRenderer ()
{
	dispatch_semaphore_t _inFlightSemaphore;
}

struct VertexUniform {
	Matrix4				model_view_matrix;
	Matrix4				projection_matrix;
	Matrix3Aligned		normal_matrix;
};

struct LightSourceParameters {
	Tuple4	diffuse;
	Tuple4	position;
};

struct LightModelParameters {
	Tuple4	ambient;
};

struct FragmentUniform {
	struct LightSourceParameters	light_source[2];
	struct LightModelParameters		light_model;
};

@end

@implementation LDrawRenderer (Metal)

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== prepareMetal ======================================================
//
// Purpose:	The context is all set up; this is where we prepare our Metal state.
//
//==============================================================================
- (void) prepareMetal
{
	id<MTLDevice> device = MetalGPU.device;
	_commandQueue = [device newCommandQueue];

	// Load shaders from Metal shader library
	id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
	id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
	id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

	MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];

	vertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
	vertexDescriptor.attributes[VertexAttributePosition].offset = 0;
	vertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexInstanceInvariantData;

	vertexDescriptor.attributes[VertexAttributeNormal].format = MTLVertexFormatFloat3;
	vertexDescriptor.attributes[VertexAttributeNormal].offset = sizeof(float) * 3;
	vertexDescriptor.attributes[VertexAttributeNormal].bufferIndex = BufferIndexInstanceInvariantData;

	vertexDescriptor.attributes[VertexAttributeColor].format = MTLVertexFormatFloat4;
	vertexDescriptor.attributes[VertexAttributeColor].offset = sizeof(float) * 6;
	vertexDescriptor.attributes[VertexAttributeColor].bufferIndex = BufferIndexInstanceInvariantData;

	vertexDescriptor.layouts[BufferIndexInstanceInvariantData].stride = sizeof(float) * 10;
	vertexDescriptor.layouts[BufferIndexInstanceInvariantData].stepFunction = MTLVertexStepFunctionPerVertex;

	// Create pipeline state
	MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = vertexFunction;
	pipelineDescriptor.fragmentFunction = fragmentFunction;
	pipelineDescriptor.vertexDescriptor = vertexDescriptor;
	pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

	// Blending
	MTLRenderPipelineColorAttachmentDescriptor *colorAttachment = pipelineDescriptor.colorAttachments[0];
	colorAttachment.blendingEnabled = YES;
	colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
	colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
	colorAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
	colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;


	NSError *error = nil;
	_pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
	if (!_pipelineState) {
		NSLog(@"Error occurred when creating render pipeline state: %@", error);
	}

	// Create a depth stencil state
	MTLDepthStencilDescriptor *depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
	depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
	depthStencilDescriptor.depthWriteEnabled = YES;
	_depthStencilState = [device newDepthStencilStateWithDescriptor:depthStencilDescriptor];

	_vertexUniformBuffer = [device newBufferWithLength:sizeof(struct VertexUniform) options:MTLResourceStorageModeShared];
	_vertexUniformBuffer.label = @"Uniform buffer";


	//---------- Light Model ---------------------------------------------------

	// The overall scene has ambient light to make the lighting less harsh. But
	// too much ambient light makes everything washed out.
	Tuple4 lightModelAmbient = { 0.3, 0.3, 0.3, 0.0 };

	//---------- Lights --------------------------------------------------------

	// We are going to have two lights, one in a standard position (LIGHT0) and
	// another pointing opposite to it (LIGHT1). The second light will
	// illuminate any inverted normals or backwards polygons.
	Tuple4 position0 = { 0, -0.0, -1.0, 0 };
	Tuple4 position1 = { 0,  0.0,  1.0, 0 };

	// Lessening the diffuseness also makes lighting less extreme.
	Tuple4 lightDiffuse = { 0.8, 0.8, 0.8, 1.0 };

	struct LightSourceParameters light_source0;
	light_source0.position = position0;
	light_source0.diffuse = lightDiffuse;
	struct LightSourceParameters light_source1;
	light_source1.position = position1;
	light_source1.diffuse = lightDiffuse;
	struct LightModelParameters lightModel;
	lightModel.ambient = lightModelAmbient;
	struct FragmentUniform fragmentUniform;
	fragmentUniform.light_source[0] = light_source0;
	fragmentUniform.light_source[1] = light_source1;
	fragmentUniform.light_model = lightModel;

	_fragmentUniformBuffer = [device newBufferWithBytes:&fragmentUniform length:sizeof(fragmentUniform) options:MTLResourceStorageModeShared];

}//end prepareMetal


//========== mtkView:drawableSizeWillChange: ===================================
//
// Purpose:		Called whenever the view orientation, layout, or size changes.
//
//==============================================================================
- (void) mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
	NSSize maxVisibleSize = view.visibleRect.size;

	if(maxVisibleSize.width > 0 && maxVisibleSize.height > 0)
	{
		[self setGraphicsSurfaceSize:V2MakeSize(maxVisibleSize.width, maxVisibleSize.height)];
	}

}//end mtkView:drawableSizeWillChange:


#pragma mark -
#pragma mark DRAWING
#pragma mark -

//========== drawInMTKView: ====================================================
//
// Purpose:		Draw the LDraw content of the view.
//
//==============================================================================
- (void) drawInMTKView:(nonnull MTKView *)view
{
	NSDate			*startTime			= nil;
	NSTimeInterval	drawTime			= 0;
	BOOL			considerFastDraw	= NO;
	
//	// TODO: learn more
//
//	// Wait to ensure only a maximum of `AAPLMaxBuffersInFlight` frames are being processed by any
//	// stage in the Metal pipeline (e.g. app, Metal, drivers, GPU, etc.) at any time. This mechanism
//	// prevents the CPU from overwriting dynamic buffer data before the GPU has read it.
//	dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

	startTime	= [NSDate date];

	// We may need to simplify large models if we are spinning the model
	// or doing part drag-and-drop.
//	considerFastDraw =		self->isTrackingDrag == YES
//						||	self->isGesturing == YES
//						||	(	[self->fileBeingDrawn respondsToSelector:@selector(draggingDirectives)]
//							 &&	[(id)self->fileBeingDrawn draggingDirectives] != nil
//							);
#if DEBUG_DRAWING == 0
	if(considerFastDraw == YES && self->rotationDrawMode == LDrawGLDrawExtremelyFast)
	{
		options |= DRAW_BOUNDS_ONLY;
	}
#endif //DEBUG_DRAWING
	
	id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
	commandBuffer.label = @"Drawable Command Buffer";
	if (!commandBuffer) {
		return;
	}

	id<CAMetalDrawable> currentDrawable = view.currentDrawable;
	if (!currentDrawable) {
		return;
	}

	MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
	if (renderPassDescriptor == nil) {
		return;
	}

	// Default color. Our wrapper is responsible from applying the user's
	// preferred color.
	NSColor *bgColor = [NSColor.controlBackgroundColor
						colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]];

	MTLTextureDescriptor *depthTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
																									  width:view.drawableSize.width
																									 height:view.drawableSize.height
																								  mipmapped:NO];
	depthTextureDescriptor.usage = MTLTextureUsageRenderTarget;
	depthTextureDescriptor.storageMode = MTLStorageModePrivate;

	id<MTLTexture> depthTexture = [MetalGPU.device newTextureWithDescriptor:depthTextureDescriptor];

	renderPassDescriptor.colorAttachments[0].texture = currentDrawable.texture;
	renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
	renderPassDescriptor.colorAttachments[0]
		.clearColor = MTLClearColorMake(bgColor.redComponent, bgColor.greenComponent, bgColor.blueComponent, 1.0);

	renderPassDescriptor.depthAttachment.texture = depthTexture;
	renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
	renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
	renderPassDescriptor.depthAttachment.clearDepth = 1.0;

	id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
	renderEncoder.label = @"Drawable Render Encoder";

	[renderEncoder setRenderPipelineState:_pipelineState];
	[renderEncoder setDepthStencilState:_depthStencilState];

	// Add a completion hander that signals `_inFlightSemaphore` when Metal and the GPU have fully
	// finished processing the commands encoded this frame. This indicates that the dynamic bufers,
	// written to this frame, are no longer be needed by Metal or the GPU, meaning that you can
	// change the buffer contents without corrupting any rendering.
//	__block dispatch_semaphore_t block_sema = _inFlightSemaphore;
//	[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
//	{
//		dispatch_semaphore_signal(block_sema);
//	}];

	struct VertexUniform vertexUniform;
	vertexUniform.model_view_matrix = Matrix4CreateFromGLMatrix4([camera getModelView]);
	vertexUniform.projection_matrix = Matrix4CreateFromGLMatrix4([camera getProjection]);
	Matrix3 normal_matrix = Matrix3MakeNormalTransformFromProjMatrix(vertexUniform.model_view_matrix);
	vertexUniform.normal_matrix = Matrix3AlignedCreate(normal_matrix);

	void *vertexUniformBufferPointer = [_vertexUniformBuffer contents];
	memcpy(vertexUniformBufferPointer, &vertexUniform, sizeof(vertexUniform));

	[renderEncoder setVertexBuffer:_vertexUniformBuffer offset:0 atIndex:BufferIndexVertexUniforms];

	[renderEncoder setFragmentBuffer:_fragmentUniformBuffer offset:0 atIndex:BufferIndexFragmentUniforms];

	// Make lines look a little nicer; Max width 1.0; 0.5 at 100% zoom
//	glLineWidth(MIN([self zoomPercentageForGL]/100 * 0.5, 1.0));

	// DRAW!

	LDrawShaderRenderer *ren = [[LDrawShaderRenderer alloc] initWithEncoder:renderEncoder
																	  scale:[self zoomPercentageForGL] / 100.
																  modelView:[camera getModelView]
																 projection:[camera getProjection]];

	[self->fileBeingDrawn drawSelf:ren];

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
	
	[ren finishDraw];

	[renderEncoder endEncoding];

	// present the drawable and buffer
	[commandBuffer presentDrawable:currentDrawable];

	// send the commands to the GPU
	[commandBuffer commit];

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
#if DEBUG_DRAWING
	NSTimeInterval timeSinceMark = [NSDate timeIntervalSinceReferenceDate] - fpsStartTime;
	if(timeSinceMark > 5)
	{	// reset periodically
		fpsStartTime = [NSDate timeIntervalSinceReferenceDate];
		framesSinceStartTime = 0;
		NSLog(@"fps = ????????, period = ????????, draw time: %f", drawTime);
	}
	else
	{
		CGFloat framesPerSecond = framesSinceStartTime / timeSinceMark;
		CGFloat period = timeSinceMark / framesSinceStartTime;
		NSLog(@"fps = %f, period = %f, draw time: %f", framesPerSecond, period, drawTime);
	}
#endif //DEBUG_DRAWING
	
}//end drawInMTKView:


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
