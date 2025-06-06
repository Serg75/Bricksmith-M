//==============================================================================
//
//	LDrawShaderRendererGPU.m
//	Bricksmith
//
//	Purpose:	an implementation of the LDrawCoreRenderer API using Metal
//				shaders.
//
//				The renderer maintains a stack view of GPU state; as
//				directives push their info to the renderer, containing LDraw
//				parts push and pop state to affect the child parts that are
//				drawn via the depth-first traversal.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawShaderRendererGPU.h"

@import MetalKit;
@import simd;

#import "LDrawBDPAllocator.h"
#import "LDrawDisplayList.h"
#import "ColorLibrary.h"
#import "MetalGPU.h"
#import "MetalUtilities.h"
#import "MetalCommonDefinitions.h"


@implementation LDrawShaderRenderer (Metal)

static id<MTLRenderPipelineState>	_dragHandlePipelineState	= nil;
static id<MTLBuffer>				_dragHandleVertexBuffer		= nil;
static NSUInteger					_dragHandleVertexCount		= 0;

//========== init: ===============================================================
//
// Purpose: initialize our renderer, and grab all basic Metal state we need.
//
//================================================================================
- (id) initWithEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
				 scale:(float)initial_scale
			 modelView:(float *)mv_matrix
			projection:(float *)proj_matrix
{
	pool = LDrawBDPCreate();

	self = [super init];

	_renderEncoder = renderEncoder;

	self->scale = initial_scale;

	[[[ColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor] getColorRGBA:color_now];
	complimentColor(color_now, compl_now);

	// Set up the basic transform to be identity - our transform is on top of the MVP matrix.
	memset(transform_now,0,sizeof(transform_now));
	transform_now[0] = transform_now[5] = transform_now[10] = transform_now[15] = 1.0f;

	// "Rip" the MVP matrix from Metal.  (TODO: does LDraw just have this info?)
	// We use this for culling.
	
	matrix_float4x4 projMatrix = simd_matrix4x4_from_array(proj_matrix);
	matrix_float4x4 mvMatrix = simd_matrix4x4_from_array(mv_matrix);
	
	matrix_float4x4 mvpMatrix = simd_mul(projMatrix, mvMatrix);
	
	simd_matrix_to_array(mvpMatrix, mvp);
	memcpy(cull_now, mvp, sizeof(mvp));

	// Create a DL session to match our lifetime.
	session = LDrawDLSessionCreate(mv_matrix);

	// Create drag handle pipeline state if not already created
	if (_dragHandlePipelineState == nil) {
		id<MTLDevice> device = MetalGPU.device;
		id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
		id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexDragHandle"];
		id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentDragHandle"];

		MTLRenderPipelineDescriptor *handlesDesc = [[MTLRenderPipelineDescriptor alloc] init];
		handlesDesc.vertexFunction = vertexFunction;
		handlesDesc.fragmentFunction = fragmentFunction;
		handlesDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
		handlesDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
		handlesDesc.sampleCount = MSAASampleCount;

		NSError *error = nil;
		_dragHandlePipelineState = [device newRenderPipelineStateWithDescriptor:handlesDesc error:&error];
		if (!_dragHandlePipelineState) {
			NSLog(@"Error occurred when creating render pipeline state: %@", error);
		}
	}

	if (_dragHandleVertexBuffer == nil)
	{
		// Bail if we've already done it.

		int		latitudeSections	= 8;
		int		longitudeSections	= 8;

		float	latitudeRadians		= 1 * M_PI / latitudeSections;	// lat. wraps halfway around sphere
		float	longitudeRadians	= 2 * M_PI / longitudeSections;	// long. wraps all the way
		int		latitudeCount		= 0;
		int		longitudeCount		= 0;
		float	latitude			= 0;
		float	longitude			= 0;
		int		counter = 0;

		//---------- Generate Sphere -----------------------------------------------

		// Each latitude strip begins with two vertexes at the prime meridian, then
		// has two more vertexes per segment thereafter.
		_dragHandleVertexCount = (2 + longitudeSections * 2) * latitudeSections;

		NSMutableData *vertexData = [NSMutableData dataWithLength:_dragHandleVertexCount * sizeof(vector_float3)];
		vector_float3 *vertices = (vector_float3 *)vertexData.mutableBytes;

		// Calculate vertexes for each strip of latitude.
		for (latitudeCount = 0; latitudeCount < latitudeSections; latitudeCount += 1)
		{
			latitude = (latitudeCount * latitudeRadians);

			// Include the prime meridian twice; once to start the strip and once to
			// complete the last triangle of the -1 meridian.
			for (longitudeCount = 0; longitudeCount <= longitudeSections; longitudeCount += 1 )
			{
				longitude = longitudeCount * longitudeRadians;

				// Top vertex
				vertices[counter++] = (vector_float3) {
					cos(longitude) * sin(latitude),
					sin(longitude) * sin(latitude),
					cos(latitude)
				};

				// Bottom vertex
				vertices[counter++] = (vector_float3) {
					cos(longitude) * sin(latitude + latitudeRadians),
					sin(longitude) * sin(latitude + latitudeRadians),
					cos(latitude + latitudeRadians)
				};
			}
		}

		// Create a single Metal buffer for all vertices
		_dragHandleVertexBuffer = [MetalGPU.device newBufferWithBytes:vertexData.bytes
															   length:vertexData.length
															  options:MTLResourceStorageModeShared];
		_dragHandleVertexBuffer.label = @"Drag handle vertex buffer";
	}

	return self;

}//end init:


// Suppress warning "Category is implementing a method which will also be implemented by its primary class."
// These two methods have declaration only without implementation in the primary class.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

//========== pushWireFrame: ======================================================
//
// Purpose: push a change to wire frame mode.  This is nested - when the last
//			"wire frame" is popped, we are no longer wire frame.
//
//================================================================================
- (void) pushWireFrame
{
	wire_frame_count++;

}//end pushWireFrame:


//========== popWireFrame: =======================================================
//
// Purpose: undo a previous wire frame command - the push and pops must be
//			balanced.
//
//================================================================================
- (void) popWireFrame
{
	wire_frame_count--;

}//end popWireFrame:

#pragma clang diagnostic pop


//========== drawDragHandles =====================================================
//
// Purpose:	Draw a drag handles
//
// Notes:	The vertex format for the sphere handle is just pure vertices - since
//			the draw routine sets up its own internal format,
//			there's no need to depend on or conform to vertex formats for the rest
//			of the drawing system.
//
//================================================================================
- (void)drawDragHandles
{
	static id<MTLBuffer>	instanceBuffer	= nil;

	struct LDrawDragHandleInstance * dh;
	vector_float4			color			= {0.50, 0.53, 1.00, 1.00};	// Nice lavendar color for the whole sphere.
	int						instanceCount	= 0;

	// Go through and draw the drag handles...

	for (dh = drag_handles; dh != NULL; dh = dh->next) {
		instanceCount++;
	}

	if (instanceCount == 0) {
		return;
	}

	int instanceBufferLength = InstanceInputStructSize * instanceCount;
	if (instanceBuffer == nil || instanceBuffer.length < instanceBufferLength) {
		instanceBuffer = [MetalGPU.device newBufferWithLength:instanceBufferLength
													  options:MTLResourceStorageModeManaged];
		instanceBuffer.label = @"Drag handle instance buffer";
	}

	// Map our instance buffer so we can write instancing data.
	float * inst_data = (float *)instanceBuffer.contents;

	for (dh = drag_handles; dh != NULL; dh = dh->next)
	{
		float s = dh->size / self->scale;
		float m[16] = {
			s, 0, 0, 0,
			0, s, 0, 0,
			0, 0, s, 0,
			dh->xyz[0], dh->xyz[1], dh->xyz[2], 1.0
		};

		[self pushMatrix:m];

		// Copy on transpose to get matrix into right form!
		copy_matrix_transposed(inst_data, transform_now);

		[self popMatrix];

		inst_data += InstanceInputLength;
	}

	[instanceBuffer didModifyRange:NSMakeRange(0, instanceBufferLength)];
	[_renderEncoder setVertexBuffer:instanceBuffer
							 offset:0
							atIndex:BufferIndexPerInstanceData];

	[_renderEncoder setRenderPipelineState:_dragHandlePipelineState];
	[_renderEncoder setVertexBuffer:_dragHandleVertexBuffer offset:0 atIndex:0];
	[_renderEncoder setFragmentBytes:&color length:sizeof(color) atIndex:0];

	[_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
					   vertexStart:0
					   vertexCount:_dragHandleVertexCount
					 instanceCount:instanceCount];

}//end drawDragHandles


- (struct LDrawDL *)builderFinish:(struct LDrawDLBuilder *)ctx
{
	return LDrawDLBuilderFinish(ctx);
}


//========== finishDraw: =========================================================
//
// Purpose: "Triggers" the draw from our display list session that has stored up
//			some of our draw calls.
//
//================================================================================
- (void) finishDraw
{
	LDrawDLSessionDrawAndDestroy(_renderEncoder, session);
	session = nil;
	
	[self drawDragHandles];

	LDrawBDPDestroy(pool);
	
}//end finishDraw:


@end
