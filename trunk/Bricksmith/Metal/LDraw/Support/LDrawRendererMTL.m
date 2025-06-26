//==============================================================================
//
//	LDrawRendererMTL.m
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

#import "LDrawRendererMTL.h"

#include "MetalCommonDefinitions.h"

#import "LDrawShaderRendererMTL.h"
#import "MetalGPU.h"
#import "MetalUtilities.h"
#import "SIMDConversions.h"


#define WANT_TWOPASS_BOXTEST		0	// this enables the two-pass box-test.  It is actually faster to _not_ do this now that hit testing is optimized.

#define DEBUG_DRAWING				1	// print fps of drawing, and never fall back to bounding boxes no matter how slow.
#define SIMPLIFICATION_THRESHOLD	0.3 // seconds

static id<MTLCommandQueue>			_commandQueue;
static id<MTLRenderPipelineState>	_pipelineState;
static id<MTLRenderPipelineState>	_marqueePipelineState;
static id<MTLDepthStencilState>		_depthStencilState;
static dispatch_semaphore_t			_inFlightSemaphore;

// Controls the number uniform buffers in flight to prevent the CPU from overwriting GPU resources still in use.
// This is essential for avoiding rendering artefacts, especially on slower systems.
static const NSUInteger				MaxBuffersInFlight = 3;		// The maximum number of command buffers in flight

static id<MTLBuffer>				_vertexUniformBuffers[MaxBuffersInFlight];
static NSUInteger					_currentUniformBufferIndex = 0;


@implementation LDrawRenderer (Metal)

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== prepareMetal ======================================================
//
// Purpose:		Set up Metal for rendering.
//
//==============================================================================
- (void) prepareMetal
{
	id<MTLDevice> device = MetalGPU.device;
	_commandQueue = [device newCommandQueue];
	_commandQueue.label = @"Main Command Queue";
	_inFlightSemaphore = dispatch_semaphore_create(MaxBuffersInFlight);

	// Create a default library
	id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
	
	// Create pipeline state
	MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
	pipelineDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

	// Set up vertex descriptor
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

	vertexDescriptor.layouts[BufferIndexInstanceInvariantData].stride = VERT_STRIDE * sizeof(float);
	vertexDescriptor.layouts[BufferIndexInstanceInvariantData].stepRate = 1;
	vertexDescriptor.layouts[BufferIndexInstanceInvariantData].stepFunction = MTLVertexStepFunctionPerVertex;

	pipelineDescriptor.vertexDescriptor = vertexDescriptor;
	pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
	pipelineDescriptor.sampleCount = MSAASampleCount;

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

	for (NSUInteger i = 0; i < MaxBuffersInFlight; ++i) {
		_vertexUniformBuffers[i] = [device newBufferWithLength:sizeof(struct VertexUniform) options:MTLResourceStorageModeShared];
		_vertexUniformBuffers[i].label = [NSString stringWithFormat:@"Uniform buffer %lu", (unsigned long)i];
	}


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
	light_source0.position			= tuple4_to_float4(position0);
	light_source0.diffuse			= tuple4_to_float4(lightDiffuse);
	struct LightSourceParameters light_source1;
	light_source1.position			= tuple4_to_float4(position1);
	light_source1.diffuse			= tuple4_to_float4(lightDiffuse);
	struct LightModelParameters lightModel;
	lightModel.ambient				= tuple4_to_float4(lightModelAmbient);
	struct FragmentUniform fragmentUniform;
	fragmentUniform.light_source[0]	= light_source0;
	fragmentUniform.light_source[1]	= light_source1;
	fragmentUniform.light_model		= lightModel;

	_fragmentUniformBuffer = [device newBufferWithBytes:&fragmentUniform length:sizeof(fragmentUniform) options:MTLResourceStorageModeShared];

	[self setupMarquee: defaultLibrary];

}//end prepareMetal


//========== setupMarquee: =====================================================
//
// Purpose:		Prepare everything for drawing marquee.
//
//==============================================================================
- (void)setupMarquee:(id<MTLLibrary>)library
{
	if (_marqueePipelineState) { return; }

	MTLRenderPipelineDescriptor *marqueeDesc = [[MTLRenderPipelineDescriptor alloc] init];
	marqueeDesc.vertexFunction = [library newFunctionWithName:@"vertex_shader_2D"];
	marqueeDesc.fragmentFunction = [library newFunctionWithName:@"fragment_shader_2D"];
	marqueeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; // TODO: view.colorPixelFormat;
	marqueeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
	marqueeDesc.sampleCount = MSAASampleCount;

	// Enable blending for transparency
	marqueeDesc.colorAttachments[0].blendingEnabled = YES;
	marqueeDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
	marqueeDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
	marqueeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	marqueeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

	NSError *error = nil;
	_marqueePipelineState = [MetalGPU.device newRenderPipelineStateWithDescriptor:marqueeDesc error:&error];
	if (!_marqueePipelineState) {
		NSLog(@"Error occurred when creating render pipeline state: %@", error);
	}
}//end setupMarquee:


//========== createTexturesForSize: ============================================
//
// Purpose:		Create or update MSAA color and depth textures for the given size.
//
//==============================================================================
- (void) createTexturesForSize:(CGSize)size
{
	if (CGSizeEqualToSize(size, _lastDrawableSize)) { return; }

	id<MTLDevice> device = MetalGPU.device;

	// Multisample color texture
	MTLTextureDescriptor *msaaColorTextureDescriptor =
	[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
													   width:size.width
													  height:size.height
												   mipmapped:NO];
	
	msaaColorTextureDescriptor.sampleCount = MSAASampleCount;
	msaaColorTextureDescriptor.textureType = MTLTextureType2DMultisample;
	msaaColorTextureDescriptor.usage = MTLTextureUsageRenderTarget;
	if (@available(macOS 11.0, *)) {
		if ([device supportsFamily:MTLGPUFamilyApple1]) {
			msaaColorTextureDescriptor.storageMode = MTLStorageModeMemoryless;
		} else {
			msaaColorTextureDescriptor.storageMode = MTLStorageModePrivate;
		}
	} else {
		msaaColorTextureDescriptor.storageMode = MTLStorageModePrivate;
	}

	_msaaColorTexture = [device newTextureWithDescriptor:msaaColorTextureDescriptor];
	_msaaColorTexture.label = @"MSAA Color Texture";
	
	// Depth texture (also multisampled)
	MTLTextureDescriptor *depthTextureDescriptor =
	[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
													   width:size.width
													  height:size.height
												   mipmapped:NO];
	
	depthTextureDescriptor.sampleCount = MSAASampleCount;
	depthTextureDescriptor.textureType = MTLTextureType2DMultisample;
	depthTextureDescriptor.usage = MTLTextureUsageRenderTarget;
	
	if (@available(macOS 11.0, *)) {
		if ([device supportsFamily:MTLGPUFamilyApple1]) {
			depthTextureDescriptor.storageMode = MTLStorageModeMemoryless;
		} else {
			depthTextureDescriptor.storageMode = MTLStorageModePrivate;
		}
	} else {
		depthTextureDescriptor.storageMode = MTLStorageModePrivate;
	}

	_depthTexture = [device newTextureWithDescriptor:depthTextureDescriptor];
	_depthTexture.label = @"Depth Texture";
	
	_lastDrawableSize = size;
}


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

	// Wait to ensure only a maximum of `MaxBuffersInFlight` frames are being processed by the GPU at any time.
	// This prevents the CPU from overwriting buffer data still in use by the GPU, avoiding rendering artefacts.
	dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

	startTime	= [NSDate date];

	id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
	commandBuffer.label = @"Drawable Command Buffer";
	if (!commandBuffer) {
		dispatch_semaphore_signal(_inFlightSemaphore);
		return;
	}

	id<CAMetalDrawable> currentDrawable = view.currentDrawable;
	if (!currentDrawable) {
		dispatch_semaphore_signal(_inFlightSemaphore);
		return;
	}

	// Create or update textures if needed
	[self createTexturesForSize:view.drawableSize];

	MTLRenderPassDescriptor *renderPassDescriptor = MTLRenderPassDescriptor.renderPassDescriptor;
	if (renderPassDescriptor == nil) {
		dispatch_semaphore_signal(_inFlightSemaphore);
		return;
	}

	float bgColor[4];
	if (backgroundColor[3] == 0.0) {
		// Default color. Our wrapper is responsible from applying the user's preferred color.
		NSColor *controlColor = [NSColor.controlBackgroundColor colorUsingColorSpace: NSColorSpace.deviceRGBColorSpace];
		bgColor[0] = controlColor.redComponent;
		bgColor[1] = controlColor.greenComponent;
		bgColor[2] = controlColor.blueComponent;
		bgColor[3] = 1.0;
	} else {
		bgColor[0] = backgroundColor[0];
		bgColor[1] = backgroundColor[1];
		bgColor[2] = backgroundColor[2];
		bgColor[3] = backgroundColor[3];
	}

	renderPassDescriptor.colorAttachments[0].texture = _msaaColorTexture;
	renderPassDescriptor.colorAttachments[0].resolveTexture = currentDrawable.texture;
	renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
	renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(bgColor[0],
																			bgColor[1],
																			bgColor[2],
																			bgColor[3]);

	renderPassDescriptor.depthAttachment.texture = _depthTexture;
	renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
	renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
	renderPassDescriptor.depthAttachment.clearDepth = 1.0;

	id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
	renderEncoder.label = @"Drawable Render Encoder";

	[renderEncoder setRenderPipelineState:_pipelineState];
	[renderEncoder setDepthStencilState:_depthStencilState];

	// Advance the buffer index for multiple buffering
	_currentUniformBufferIndex = (_currentUniformBufferIndex + 1) % MaxBuffersInFlight;
	id<MTLBuffer> vertexUniformBuffer = _vertexUniformBuffers[_currentUniformBufferIndex];

	struct VertexUniform vertexUniform;
	vertexUniform.model_view_matrix	= simd_matrix4x4_from_array_transposed([camera getModelView]);
	vertexUniform.projection_matrix	= simd_matrix4x4_from_array_transposed([camera getProjection]);
	vertexUniform.normal_matrix		= simd_normal_matrix_from_matrix4x4(vertexUniform.model_view_matrix);

	void *vertexUniformBufferPointer = [vertexUniformBuffer contents];
	memcpy(vertexUniformBufferPointer, &vertexUniform, sizeof(vertexUniform));

	[renderEncoder setVertexBuffer:vertexUniformBuffer offset:0 atIndex:BufferIndexVertexUniforms];

	[renderEncoder setFragmentBuffer:_fragmentUniformBuffer offset:0 atIndex:BufferIndexFragmentUniforms];

	// DRAW!

	LDrawShaderRenderer *ren = [[LDrawShaderRenderer alloc] initWithEncoder:renderEncoder
																	  scale:[self zoomPercentageForGL] / 100.
																  modelView:[camera getModelView]
																 projection:[camera getProjection]];

	[self->fileBeingDrawn drawSelf:ren];

	[ren finishDraw];

	[self drawMarqueeWithEncoder:renderEncoder];

	[renderEncoder endEncoding];

	// present the drawable and buffer
	[commandBuffer presentDrawable:currentDrawable];

	// Add a completion handler that signals the semaphore when the GPU is done with this frame.
	// This indicates that we can change the buffer contents without corrupting any rendering.
	// IMPORTANT: This must be added BEFORE commit, not after!
	__block dispatch_semaphore_t block_sema = _inFlightSemaphore;
	[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
		dispatch_semaphore_signal(block_sema);
	}];

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


//========== drawMarqueeWithEncoder: ===========================================
//
// Purpose:		Draws marquee selection box.
//
//==============================================================================
- (void)drawMarqueeWithEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
{
	static id<MTLBuffer> vertexBuffer = nil;

	if (self->selectionMarquee.size.width != 0 &&
		self->selectionMarquee.size.height != 0)
	{
		Point2	from	= self->selectionMarquee.origin;
		Point2	to		= V2Make(V2BoxMaxX(self->selectionMarquee), V2BoxMaxY(self->selectionMarquee));
		Point2	p1		= [self convertPointToViewport:from];
		Point2	p2		= [self convertPointToViewport:to];
		Size2	vpSize	= self.viewport.size;

		float vertices[] = {
			p1.x, p1.y,
			p2.x, p1.y,
			p2.x, p2.y,
			p1.x, p2.y,
			p1.x, p1.y
		};

		// Setup only once
		if (vertexBuffer == nil)
		{
			vertexBuffer = [MetalGPU.device newBufferWithBytes:vertices
														length:sizeof(vertices)
													   options:MTLResourceStorageModeShared];
			vertexBuffer.label = @"Marquee vertex buffer";
		}

		float * vert_data = (float *)vertexBuffer.contents;
		memcpy(vert_data, &vertices, sizeof(vertices));

		[renderEncoder setRenderPipelineState:_marqueePipelineState];

		[renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
		[renderEncoder setVertexBytes:&vpSize length:sizeof(vpSize) atIndex:1];

		[renderEncoder drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:5];
	}
	
}//end drawMarqueeWithEncoder:


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
	backgroundColor[0] = red;
	backgroundColor[1] = green;
	backgroundColor[2] = blue;
	backgroundColor[3] = 1.0;
				 
	[self->delegate LDrawRendererNeedsRedisplay:self];
}


@end
