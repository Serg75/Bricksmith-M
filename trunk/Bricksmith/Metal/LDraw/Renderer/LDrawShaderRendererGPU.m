//==============================================================================
//
//	LDrawShaderRendererGPU.m
//	Bricksmith
//
//	Purpose:	an implementation of the LDrawCoreRenderer API using GL shaders.
//
//				The renderer maintains a stack view of OpenGL state; as
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

#import "LDrawBDPAllocator.h"
#import "LDrawDisplayList.h"
#import "ColorLibrary.h"
#import "GLMatrixMath.h"
#import "MetalGPU.h"
#import "MetalCommonDefinitions.h"


@implementation LDrawShaderRenderer (Metal)

//========== init: ===============================================================
//
// Purpose: initialize our renderer, and grab all basic OpenGL state we need.
//
//================================================================================
- (id) initWithEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
				 scale:(float)initial_scale
			 modelView:(GLfloat *)mv_matrix
			projection:(GLfloat *)proj_matrix
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

	// "Rip" the MVP matrix from OpenGL.  (TODO: does LDraw just have this info?)
	// We use this for culling.
	multMatrices(mvp,proj_matrix,mv_matrix);
	memcpy(cull_now,mvp,sizeof(mvp));

	// Create a DL session to match our lifetime.
	session = LDrawDLSessionCreate(mv_matrix);

	return self;

}//end init:


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
	static id<MTLBuffer> 		vertexBuffer 	= nil;
	static NSUInteger 			vertexCount 	= 0;

	id<MTLDevice>				device 			= MetalGPU.device;
	id<MTLRenderPipelineState> 	pipelineState 	= nil;
	id<MTLBuffer> 				instanceBuffer 	= nil;

	if (vertexBuffer == nil)
	{
		// Bail if we've already done it.

		int		latitudeSections	= 8;
		int		longitudeSections	= 8;

		float	latitudeRadians		= M_PI / latitudeSections; // lat. wraps halfway around sphere
		float	longitudeRadians	= 2 * M_PI / longitudeSections; // long. wraps all the way
		int		latitudeCount		= 0;
		int		longitudeCount		= 0;
		float	latitude			= 0;
		float	longitude			= 0;
		int		counter = 0;

		//---------- Generate Sphere -----------------------------------------------

		// Each latitude strip begins with two vertexes at the prime meridian, then
		// has two more vertexes per segment thereafter.
		vertexCount = (2 + longitudeSections * 2) * latitudeSections;

		NSMutableData *vertexData = [NSMutableData dataWithLength:vertexCount * sizeof(vector_float3)];
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

				// Ben says: when we are "pushing" vertices into a GL_WRITE_ONLY mapped buffer, we should really
				// never read back from the vertices that we read to - the memory we are writing to often has funky
				// properties like being uncached which make it expensive to do anything other than what we said we'd
				// do (and we said: we are only going to write to them).
				//
				// Mind you it's moot in this case since we only need to write vertices.

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

			// Create a Metal buffer for the vertices
			vertexBuffer = [device newBufferWithBytes:vertexData.bytes
											   length:vertexData.length
											  options:MTLResourceStorageModeShared];
			vertexBuffer.label = @"Drag handle vertex buffer";
		}
	}

	struct LDrawDragHandleInstance * dh;
	vector_float4 color = {0.50, 0.53, 1.00, 1.00};		// Nice lavendar color for the whole sphere.
	int instanceCount = 0;

	// Go through and draw the drag handles...

	for (dh = drag_handles; dh != NULL; dh = dh->next) {
		instanceCount++;
	}

	if (instanceCount == 0) {
		return;
	}

	// Set up the render pipeline
	id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
	id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexDragHandle"];
	id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentDragHandle"];

	MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
	pipelineDescriptor.vertexFunction = vertexFunction;
	pipelineDescriptor.fragmentFunction = fragmentFunction;
	pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

	NSError *error = nil;
	pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
	if (!pipelineState) {
		NSLog(@"Error occurred when creating render pipeline state: %@", error);
	}

	int instanceBufferLength = InstanceInputStructSize * instanceCount;
	instanceBuffer = [device newBufferWithLength:instanceBufferLength options:MTLResourceStorageModeManaged];
	instanceBuffer.label = @"Drag handle instance buffer";

	// Map our instance buffer so we can write instancing data.
	GLfloat * inst_data = (GLfloat *)instanceBuffer.contents;

	for (dh = drag_handles; dh != NULL; dh = dh->next)
	{
		GLfloat s = dh->size / self->scale;
		GLfloat m[16] = {
			s, 0, 0, 0,
			0, s, 0, 0,
			0, 0, s, 0,
			dh->xyz[0], dh->xyz[1],dh->xyz[2], 1.0
		};

		[self pushMatrix:m];

		inst_data[0] = transform_now[0];		// Note: copy on transpose to get matrix into right form!
		inst_data[1] = transform_now[4];
		inst_data[2] = transform_now[8];
		inst_data[3] = transform_now[12];
		inst_data[4] = transform_now[1];
		inst_data[5] = transform_now[5];
		inst_data[6] = transform_now[9];
		inst_data[7] = transform_now[13];
		inst_data[8] = transform_now[2];
		inst_data[9] = transform_now[6];
		inst_data[10] = transform_now[10];
		inst_data[11] = transform_now[14];
		inst_data[12] = transform_now[3];
		inst_data[13] = transform_now[7];
		inst_data[14] = transform_now[11];
		inst_data[15] = transform_now[15];

		[self popMatrix];

		inst_data += InstanceInputLength;
	}

	[instanceBuffer didModifyRange:NSMakeRange(0, instanceBufferLength)];
	[_renderEncoder setVertexBuffer:instanceBuffer
							offset:0
						   atIndex:BufferIndexPerInstanceData];

	[_renderEncoder setRenderPipelineState:pipelineState];
	[_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
	[_renderEncoder setFragmentBytes:&color length:sizeof(color) atIndex:0];

	[_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
					   vertexStart:0
					   vertexCount:vertexCount
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
