//==============================================================================
//
//  File:       LDrawDisplayListMTL.m
//  Package:    LDrawRenderMetal
//
//  Created by bsupnik on 11/12/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
//==============================================================================

@import MetalKit;
@import simd;

#include <LDrawRenderMetal/MetalCommonDefinitions.h>

#import <LDrawRenderCore/LDrawDisplayList.h>
#import <LDrawRenderCore/LDrawDisplayListBuilder.h>
#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawRenderCore/LDrawPoolAllocator.h>
#import <LDrawRenderCore/LDrawShaderRenderer.h>
#import <LDrawRenderCore/MeshSmooth.h>
#import <LDrawRenderMetal/MetalGPU.h>
#import "LDrawDisplayListMTL.h"
#import "MetalUtilities.h"
#import <LDrawCore/MatrixMath.h>

// This turns on normal smoothing.
#define WANT_SMOOTH 1

// This times smoothing of parts.
#define TIME_SMOOTHING 0

// Number of samples for multisample anti-aliasing (MSAA)
const int MSAASampleCount = 4;


/*

	INSTANCING IMPLEMENTATION NOTES
	
	Instancing is just fancy talk for drawing one thing many times in some efficient way.  Instancing is a good fit for BrickSmith
	because we draw the same bricks over and over and over again.
	
	When we instance, we identify the 'per instance' data - that is, data that is different for every instance.  In the case of
	BrickSmith, the current/complement color and transform are per instance data; the mesh and non-meta colors of the mesh are invariant.
	
	(As an example, when drawing the plate with red wheels, the red color of the wheels and the shape of the part are invariant;
	the current color used for the plate and the location of the whole part are per-instance data.)
	
	"Immediate" instancing means changing per-instance data on the fly for every instance draw.

	"Hardware" instancing implies using instancing API. In this case, we put our instance attributes into their own buffer
	(of consecutive interleaved "instances"), give Metal the base pointer and tell it to draw N copies of our mesh,
	using the instanced data from the buffer.

	When hardware instancing works right, it can lead to much higher throughput than immediate mode, which are faster in turn than uniforms.
	In practice, this is hugely dependent on what driver we're running on.
	
	DEFERRING DRAWING FOR INSTANCING
	
	When a DL can be drawn via hardware instancing, it is not drawn - it is saved on the session; when the session is
	destroyed we draw out every DL we have deferred, in order (e.g. all instances of one DL).
	
	During that deferred draw-out we either build a hardware instance list or simply draw.

	DEFERRED DRAWING FOR TRANSPARENCY

	When a DL has translucency, we always save it to the transparent list.

	Then when the session is destroyed, these DLs are sorted by their local origin and drawn back to front.

*/

#define WANT_STATS 0

#define INST_CUTOFF 0					// Minimum instances to use hardware case, which has higher overhead to set up.
#define INST_MAX_COUNT (1024 * 512)		// Maximum instances to write per draw before going to immediate mode - avoids unbounded VRAM use.

// Previously, using several buffers (one per view) helped avoid rendering artefacts when rapidly selecting
// or deselecting parts on slow computers — this was before the shader address space was fixed.
// With the shader fix in place, this buffer rotation is likely no longer necessary.
#define INST_RING_BUFFER_COUNT 3		// Number of buffers to rotate (aligned with MaxBuffersInFlight)

#define INST_BUFFER_SIZE (1024 * 1024)	// 1MB initial size for instance buffers

struct TexturePlaneData _noTexPlaneData = {.plane_s = {0}, .plane_t = {0}};

id<MTLTexture>	_clearTexture;


static id<MTLBuffer>	inst_vbo_ring[INST_RING_BUFFER_COUNT]		= { nil };		// GPU buffers (private)
static id<MTLBuffer>	inst_vbo_ring_st[INST_RING_BUFFER_COUNT]	= { nil };		// Staging buffers (shared)
static NSUInteger		inst_vbo_sizes[INST_RING_BUFFER_COUNT]		= { 0 };
static int				inst_ring_last								= 0;
static id<MTLCommandQueue>	_blitCommandQueue						= nil;			// Command queue for blit operations

//========== DISPLAY LIST DATA STRUCTURES ========================================

// Per-texture mesh info. Texture spec plus the offset/count into a single buffer for the lines and tris to draw.
// This is used in a finished DL.
struct LDrawDLPerTex {
	struct LDrawTextureSpec	spec;
	uint32_t				line_off;
	uint32_t				line_count;
	uint32_t				cond_line_off;
	uint32_t				cond_line_count;
	uint32_t				cond_quad_off;		// Conditional lines with their control points, in condIndexBuffer.
	uint32_t				cond_quad_count;
	uint32_t				tri_off;
	uint32_t				tri_count;
};

// DL draw instance: this stores one request to draw an un-textured DL for instancing.
// current color/complement color, transform, and a next ptr to build a linked list.
struct LDrawDLInstance {
	struct LDrawDLInstance *next;
	float					color[4];
	float					comp[4];
	float					transform[16];
	BOOL					is_wireframe;
};

// A single DL. A few notes on book-keeping:
// DLs that are drawn deferred+instanced in a session sit in a linked list attached to the session - that's what
// next_dl is for.
// Such DLs also have an instance linked list (instance head/tail/count) for each place they should be drawn.
// All of those get cleared out when DL is not being used in a session.
struct LDrawDL {
	struct LDrawDL *		next_dl;			// Session "linked list of active dLs."
	struct LDrawDLInstance *instance_head;		// Linked list of instances to draw.
	struct LDrawDLInstance *instance_tail;
	int						instance_count;
	int						deferred_count;		// Links in the session's transparent and ghost lists that draw it.
	int						flags;				// See flags defs above.
	id<MTLBuffer> 			vertexBuffer;		// Single buffer containing all geometry in the DL.
#if WANT_SMOOTH
	id<MTLBuffer> 			indexBuffer;		// Single buffer containing all mesh indices.
	id<MTLBuffer>			condIndexBuffer;	// Conditional lines with their two control points, or nil.
#endif
	int						tex_count;			// Number of per-textures; untex case is always first if present.
	#if WANT_STATS
	int						vrt_count;
#if WANT_SMOOTH
	int						idx_count;
#endif	
	#endif
	struct LDrawDLPerTex	texes[0];			// Variable size array of textures - DL is allocated larger as needed.

};

//==========  SESSION DATA STRUCTURES ========================================

// We write all instancing info into a single huge buffer. This avoids the need
// to constantly map/unmap our buffers. As we draw we use a variable sized array
// of "Segments" to track the instancing lists of each brick within the single
// huge instancing data buffer. (The name is taken from "segment buffering" in
// GPU Gems 2.)
struct LDrawDLSegment {
	id<MTLBuffer> 			vertexBuffer;		// Vertex buffer of the brick we are going to draw - contains the actual brick mesh.
#if WANT_SMOOTH
	id<MTLBuffer> 			indexBuffer;
	// Not retained: the DL keeps it, and the session's pool would never release it.
	__unsafe_unretained id<MTLBuffer> condIndexBuffer;
#endif
	struct LDrawDLPerTex *	dl;					// Ptr to the per-tex info for that brick - only untexed bricks get instanced, so we only have one "per tex", by definition.
	float *					inst_base;			// Buffer-relative ptr to the instance data base in the instance buffer.
	int						inst_count;			// Number of instances starting at that offset.
	BOOL					is_wireframe;		// Flag whether this segment should be drawn in wireframe mode
};
	

// The sorted instance link is a 'full' instance (DL, color/comp, transform and texture) used for drawing DLs that are going to be Z sorted.  
// Unlike the faster harder instancing, we keep tex state around because we might draw ANY DL (even a multitextured one) to get the Z sort
// right.
struct LDrawDLSortedInstanceLink {
	union {
		struct LDrawDLSortedInstanceLink *	next;			// DURING draw, we keep a linked list of these guys off of the session as we go.
		float								eval;			// At the end of draw, when we need to sort, we copy to a fixed size array and sort.
	};														// Maybe someday we could merge-sort the linked list, but use qsort for now to get shipped.
	struct	LDrawDL *						dl;
	struct LDrawTextureSpec					spec;
	float									color[4];
	float									comp[4];
	float									transform[16];
	int										ghost_id;			// Non-zero for ghosts; all DLs of one ghosted part share an id.
	float									ghost_alpha;		// Alpha scale for the above; 1 for a plain transparent part.
};


// One drawing session.
struct LDrawDLSession {
	#if WANT_STATS
	struct {
		int								num_btch_imm;		// Immediate drawing batches and verts
		int								num_vert_imm;		
		int								num_btch_srt;		// Sorted drawin batches and verts.
		int								num_vert_srt;
		int								num_btch_att;		// Attribute instancing: batches, verts, instances
		int								num_vert_att;
		int								num_inst_att;
		int								num_work_att;
		int								num_btch_ins;		// Hardare instancing: batches, verts, instances
		int								num_vert_ins;
		int								num_inst_ins;
		int								num_work_ins;
	} stats;
	#endif
	struct LDrawPool *					alloc;					// Pool allocator for the session to rapidly save linked lists of 'stuff'.
	struct LDrawDL *					dl_head;				// Linked list of all DLs that will be instance-drawn, with count.
	int									dl_count;
	int									total_instance_count;	// Used in calculation the size of instance buffer

	struct LDrawDLSortedInstanceLink *	sorted_head;			// Linked list + count for DLs being drawn later to Z sort.
	int									sort_count;

	struct LDrawDLSortedInstanceLink *	ghost_head;				// Linked list + count for ghosted DLs, drawn dead last with a
	int									ghost_count;			// depth prepass so their interiors do not show through.

	float								model_view[16];			// Model-view matrix, used to Z sort translucent objects.
	unsigned int						inst_ring;				// If using more than one instancing buffer, this tells which one we use.

	struct LDrawDLWideLines				wide_lines;				// Edge and conditional lines as quads, when asked for.

	BOOL								transparent_bias;		// Transparent faces get more depth bias.

	id<MTLTexture>						current_bound_texture;
};



// MARK: - Internal functions -

//========== getInstanceBuffer ===================================================
//
// Purpose:	Get or create an instance buffer of appropriate size for hardware
//			instancing.
//
// Notes:	We create a new buffer with double the required size or minimum size.
//			This helps reduce reallocations and improves performance by reusing
//			buffers when possible.
//
//			PERFORMANCE OPTIMIZATION: Uses private storage for GPU buffers with
//			staging buffers for CPU writes to eliminate CPU-GPU synchronization overhead.
//
//================================================================================
static id<MTLBuffer> getInstanceBuffer(NSUInteger requiredSize, int ringIndex)
{
	// If we don't have a buffer or it's too small, create a new one
	if (inst_vbo_ring[ringIndex] == nil || inst_vbo_sizes[ringIndex] < requiredSize)
	{
		NSUInteger newSize = MAX(INST_BUFFER_SIZE, requiredSize * 2);
		id<MTLDevice> device = MetalGPU.device;

		// Create staging buffer (shared) for CPU writes
		id<MTLBuffer> stagingBuffer = [device newBufferWithLength:newSize
														  options:MTLResourceStorageModeShared];
		stagingBuffer.label = [NSString stringWithFormat:@"Staging instance buffer %d", ringIndex];

		// Create GPU buffer (private) for optimal GPU access
		id<MTLBuffer> gpuBuffer = [device newBufferWithLength:newSize
													  options:MTLResourceStorageModePrivate];
		gpuBuffer.label = [NSString stringWithFormat:@"Instance buffer %d", ringIndex];

		// Store both buffers and size
		inst_vbo_ring_st[ringIndex] = stagingBuffer;
		inst_vbo_ring[ringIndex] = gpuBuffer;
		inst_vbo_sizes[ringIndex] = newSize;
	}
	return inst_vbo_ring_st[ringIndex];  // Return staging buffer for writing

} // end getInstanceBuffer


//========== setup_tex_spec ======================================================
//
// Purpose:	Set up the Metal with texturing info.
//
// Notes:	DL implementation uses object-plane coordinate generation; when a
//			sub-DL inherits a projection, that projection is transformed with the
//			sub-DL to keep things in sync.
//
//			The attr_texture_mix attribute controls whether the texture is visible
//			or not - a temporary hack until we can get a clear texture.
//
//================================================================================
static void setup_tex_spec(struct LDrawTextureSpec * spec,
						   struct LDrawDLSession * session,
						   id<MTLRenderCommandEncoder> encoder)
{
	if (spec && spec->tex_obj)
	{
		struct TexturePlaneData texPlaneData;
		texPlaneData.plane_s = simd_make_float4(spec->plane_s[0], spec->plane_s[1], spec->plane_s[2], spec->plane_s[3]);
		texPlaneData.plane_t = simd_make_float4(spec->plane_t[0], spec->plane_t[1], spec->plane_t[2], spec->plane_t[3]);

		[encoder setVertexBytes:&texPlaneData length:64 atIndex:BufferIndexTexturePlane];

		id<MTLTexture> tex = (__bridge id<MTLTexture>)spec->tex_obj;
		if (session->current_bound_texture != tex)
		{
			[encoder setFragmentTexture:tex atIndex:0];
			session->current_bound_texture = tex;
		}
	}
	else
	{
		if (_clearTexture == nil)
		{
			MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
			textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
			textureDescriptor.width = 1;
			textureDescriptor.height = 1;
			textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

			_clearTexture = [MetalGPU.device newTextureWithDescriptor:textureDescriptor];

			uint8_t zeroData[4] = {0, 0, 0, 0};  // RGBA (0, 0, 0, 0)
			MTLRegion region = MTLRegionMake2D(0, 0, 1, 1);
			[_clearTexture replaceRegion:region mipmapLevel:0 withBytes:zeroData bytesPerRow:4];
		}

		[encoder setVertexBytes:&_noTexPlaneData length:64 atIndex:BufferIndexTexturePlane];

		if (session->current_bound_texture != _clearTexture)
		{
			[encoder setFragmentTexture:_clearTexture atIndex:0];
			session->current_bound_texture = _clearTexture;
		}
	}

} // end setup_tex_spec


//========== compare_sorted_link =================================================
//
// Purpose:	Functor to compare two sorted instances by their "eval" value, which
//			is eye space Z right now. API fits C qsort.
//
// Notes:	Compared, not subtracted: the difference would be cut to an int,
//			and parts less than 1 apart would not sort.
//
//================================================================================
static int compare_sorted_link(const void * lhs, const void * rhs)
{
	const struct LDrawDLSortedInstanceLink * a = (const struct LDrawDLSortedInstanceLink *) lhs;
	const struct LDrawDLSortedInstanceLink * b = (const struct LDrawDLSortedInstanceLink *) rhs;

	return (a->eval < b->eval) ? -1 : ((a->eval > b->eval) ? 1 : 0);

} // end compare_sorted_link


//========== newDepthState =======================================================
//
// Purpose:	A depth state that compares with this function and writes depth or
//			not. The states below each keep one.
//
//================================================================================
static id<MTLDepthStencilState> newDepthState(MTLCompareFunction compare, BOOL writes)
{
	MTLDepthStencilDescriptor *descriptor = [[MTLDepthStencilDescriptor alloc] init];

	descriptor.depthCompareFunction = compare;
	descriptor.depthWriteEnabled = writes;

	return [MetalGPU.device newDepthStencilStateWithDescriptor:descriptor];

} // end newDepthState


//========== defaultDepthState ===================================================
//
// Purpose:	The renderer's normal depth behavior, rebuilt here for the ghost
//			depth prepass and for restoring the encoder afterwards.
//
//================================================================================
static id<MTLDepthStencilState> defaultDepthState(void)
{
	static id<MTLDepthStencilState> state = nil;
	if (state == nil)
		state = newDepthState(MTLCompareFunctionLess, YES);
	return state;

} // end defaultDepthState


//========== transparentDepthState ===============================================
//
// Purpose:	Depth state for transparent parts: what is opaque hides them, but
//			they hide nothing, not even their own faces.
//
//================================================================================
static id<MTLDepthStencilState> transparentDepthState(void)
{
	static id<MTLDepthStencilState> state = nil;
	if (state == nil)
		state = newDepthState(MTLCompareFunctionLess, NO);
	return state;

} // end transparentDepthState


//========== ghostBlendDepthState ================================================
//
// Purpose:	Depth state for the ghost blend pass: only fragments at exactly the
//			depth the prepass wrote survive, so each ghost blends once.
//
//================================================================================
static id<MTLDepthStencilState> ghostBlendDepthState(void)
{
	static id<MTLDepthStencilState> state = nil;
	if (state == nil)
		state = newDepthState(MTLCompareFunctionEqual, NO);
	return state;

} // end ghostBlendDepthState


//========== compare_ghost_link ==================================================
//
// Purpose:	Sort ghost instances into contiguous runs, one run per ghosted part,
//			each run ordered far to near.
//
//================================================================================
static int compare_ghost_link(const void * lhs, const void * rhs)
{
	const struct LDrawDLSortedInstanceLink * a = (const struct LDrawDLSortedInstanceLink *) lhs;
	const struct LDrawDLSortedInstanceLink * b = (const struct LDrawDLSortedInstanceLink *) rhs;

	if (a->ghost_id != b->ghost_id)
		return (a->ghost_id < b->ghost_id) ? -1 : 1;

	return (a->eval > b->eval) ? -1 : ((a->eval < b->eval) ? 1 : 0);

} // end compare_ghost_link


// The part of the faces' depth bias that does not depend on their slope, in
// the depth buffer's smallest steps. It keeps a line on a face turned straight
// to the eye in front of that face.
static const float FACE_DEPTH_BIAS = 2.0f;

// How much further back transparent faces go than opaque ones, in the depth
// buffer's smallest steps. One that lies on an opaque face, such as the inside
// of a plate on the studs below it, is then hidden by it everywhere rather
// than in a speckle. None of it scales with slope: a face seen almost edge on
// would go behind what is close behind it. Metal biases only triangles, so
// thin lines drawn with it keep their depth.
static const float TRANSPARENT_FACE_DEPTH_BIAS = 16.0f;

// The largest of the depth buffer's smallest steps, between depths of 0.5 and
// 1, as a depth.
static const float DEPTH_LARGEST_STEP = 1.0f / 16777216.0f;

//========== setFaceDepthBias ====================================================
//
// Purpose:	With wide lines, pushes the faces back by the depth they cover
//			across half a line, so the lines on their edges stay whole. A face
//			turned toward the eye moves least, so it still hides the lines
//			behind it. Transparent faces go a little further.
//
// Notes:	No more than half a line: two faces that meet at different slopes
//			can swap places within that distance, and there the line covers
//			them. A face seen almost edge on is pushed back only as far as the
//			clamp lets it, so it cannot slip behind what it touches.
//
//			The clamp is a depth, and a steep face reaches it by its slope
//			alone. So it goes up with the transparent faces' extra bias, or
//			they would get no more than opaque faces there.
//
//================================================================================
static void setFaceDepthBias(id<MTLRenderCommandEncoder> renderEncoder, struct LDrawDLSession * session)
{
	float	bias	= 0.0f;
	float	slope	= 0.0f;
	float	clamp	= 0.0f;

	if (session->wide_lines.line_pipeline)
	{
		bias	= FACE_DEPTH_BIAS;
		slope	= session->wide_lines.width * 0.5f;
		clamp	= session->wide_lines.face_bias_clamp;
	}

	if (session->transparent_bias)
	{
		bias += TRANSPARENT_FACE_DEPTH_BIAS;

		// A clamp of 0 is no limit.
		if (clamp > 0.0f)
			clamp += TRANSPARENT_FACE_DEPTH_BIAS * DEPTH_LARGEST_STEP;
	}

	[renderEncoder setDepthBias:bias slopeScale:slope clamp:clamp];

} // end setFaceDepthBias


#if WANT_SMOOTH

//========== beginWideLines ======================================================
//
// Purpose:	Switches the encoder from faces to wide lines, which are drawn at
//			their own depth.
//
//================================================================================
static void beginWideLines(id<MTLRenderCommandEncoder> renderEncoder, struct LDrawDLSession * session)
{
	[renderEncoder setRenderPipelineState:session->wide_lines.line_pipeline];
	[renderEncoder setDepthBias:0.0f slopeScale:0.0f clamp:0.0f];

} // end beginWideLines


//========== endWideLines ========================================================
//
// Purpose:	Switches the encoder back to faces after wide lines.
//
//================================================================================
static void endWideLines(id<MTLRenderCommandEncoder> renderEncoder, struct LDrawDLSession * session)
{
	[renderEncoder setRenderPipelineState:session->wide_lines.face_pipeline];
	setFaceDepthBias(renderEncoder, session);

} // end endWideLines


//========== drawWideLines =======================================================
//
// Purpose:	Draws a mesh's edge and conditional lines as quads.
//
// Notes:	The caller sets the line pipeline. Six vertices make one line's
//			quad.
//
//================================================================================
static void drawWideLines(id<MTLRenderCommandEncoder>	renderEncoder,
						  struct LDrawDLSession *		session,
						  id<MTLBuffer>					indexBuffer,
						  id<MTLBuffer>					condIndexBuffer,
						  struct LDrawDLPerTex *		tptr,
						  NSUInteger					instanceCount)
{
	struct LDrawDLWideLines *	wide	= &session->wide_lines;
	struct LineUniform			line	= { .viewport_size	= wide->viewport_size,
											.width			= wide->width,
											.conditional	= 0 };

	if (tptr->line_count)
	{
		[renderEncoder setVertexBytes:&line length:sizeof(line) atIndex:BufferIndexLineUniforms];
		[renderEncoder setVertexBuffer:indexBuffer
								offset:tptr->line_off * sizeof(uint32_t)
							   atIndex:BufferIndexLineIndices];
		[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
						  vertexStart:0
						  vertexCount:tptr->line_count / 2 * 6
						instanceCount:instanceCount];
	}

	if (tptr->cond_quad_count)
	{
		line.conditional = 1;

		[renderEncoder setVertexBytes:&line length:sizeof(line) atIndex:BufferIndexLineUniforms];
		[renderEncoder setVertexBuffer:condIndexBuffer
								offset:tptr->cond_quad_off * sizeof(uint32_t)
							   atIndex:BufferIndexLineIndices];
		[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
						  vertexStart:0
						  vertexCount:tptr->cond_quad_count / 4 * 6
						instanceCount:instanceCount];
	}

} // end drawWideLines


//========== drawLines ===========================================================
//
// Purpose:	Draws a mesh's edge lines a pixel wide, or its edge and conditional
//			lines as quads when the session asks for wide lines.
//
//================================================================================
static void drawLines(id<MTLRenderCommandEncoder>	renderEncoder,
					  struct LDrawDLSession *		session,
					  struct LDrawDL *				dl,
					  struct LDrawDLPerTex *		tptr,
					  NSUInteger					instanceCount)
{
	struct LDrawDLWideLines * wide = &session->wide_lines;

	if (wide->line_pipeline == nil)
	{
		if (tptr->line_count)
			[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
									  indexCount:tptr->line_count
									   indexType:MTLIndexTypeUInt32
									 indexBuffer:dl->indexBuffer
							   indexBufferOffset:tptr->line_off * sizeof(uint32_t)
								   instanceCount:instanceCount];
	}
	else if (tptr->line_count || tptr->cond_quad_count)
	{
		beginWideLines(renderEncoder, session);
		drawWideLines(renderEncoder, session, dl->indexBuffer, dl->condIndexBuffer, tptr, instanceCount);
		endWideLines(renderEncoder, session);
	}

} // end drawLines

#endif


//========== drawDeferredInstance =================================================
//
// Purpose:	Draw one deferred instance -- a transparent part or a ghost -- one
//			at a time, rather than through the instancing fast path.
//
// Notes:	The alpha scale goes to the shader rather than into the colors here,
//			because a mesh can carry colors of its own that color_current never
//			reaches -- printed parts, stickers, anything multi-colored in the
//			part file. See the vertex shader.
//
//			depthOnly is for the ghost depth prepass: scaling to zero makes the
//			fragment add nothing to the color buffer -- the blend is
//			src*0 + dst*1 -- while depth still writes, so no second pipeline
//			state is needed. It reaches every fragment, baked colors included,
//			so nothing leaks through the prepass.
//
//================================================================================
static void drawDeferredInstance(id<MTLRenderCommandEncoder>			renderEncoder,
								 struct LDrawDLSession *				session,
								 struct LDrawDLSortedInstanceLink *		l,
								 BOOL									depthOnly)
{
	struct InstanceInput	instData;
	struct LDrawDL *		dl	= l->dl;
	float					alpha_scale	= depthOnly ? 0.0f : l->ghost_alpha;

	instData.transform_x = simd_make_float4(l->transform[0], l->transform[4], l->transform[8],  l->transform[12]);
	instData.transform_y = simd_make_float4(l->transform[1], l->transform[5], l->transform[9],  l->transform[13]);
	instData.transform_z = simd_make_float4(l->transform[2], l->transform[6], l->transform[10], l->transform[14]);
	instData.transform_w = simd_make_float4(l->transform[3], l->transform[7], l->transform[11], l->transform[15]);
	copy_vec4((float *)&instData.color_current, l->color);
	copy_vec4((float *)&instData.color_complement, l->comp);

	[renderEncoder setVertexBytes:&alpha_scale
						   length:sizeof(alpha_scale)
						  atIndex:BufferIndexGhostAlpha];

	[renderEncoder setVertexBytes:&instData
						   length:sizeof(instData)
						  atIndex:BufferIndexPerInstanceData];

	[renderEncoder setVertexBuffer:dl->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];

	struct LDrawDLPerTex *	tptr	= dl->texes;
	int						t;

	for (t = 0; t < dl->tex_count; ++t, ++tptr)
	{
		if (tptr->spec.tex_obj)
			setup_tex_spec(&tptr->spec, session, renderEncoder);
		else
			setup_tex_spec(&l->spec, session, renderEncoder);

		#if WANT_SMOOTH
		drawLines(renderEncoder, session, dl, tptr, 1);

		if (tptr->tri_count)
			[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
									  indexCount:tptr->tri_count
									   indexType:MTLIndexTypeUInt32
									 indexBuffer:dl->indexBuffer
							   indexBufferOffset:tptr->tri_off * sizeof(uint32_t)
								   instanceCount:1];
		#else
		if (tptr->line_count)
			[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
							  vertexStart:tptr->line_off
							  vertexCount:tptr->line_count];

		if (tptr->tri_count)
			[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
							  vertexStart:tptr->tri_off
							  vertexCount:tptr->tri_count];
		#endif
	}

} // end drawDeferredInstance


//========== copyWithEyeDepth ====================================================
//
// Purpose:	Copies a list of deferred instances into an array from the
//			session's pool, each with the eye-space Z of its origin as its
//			eval, for sorting.
//
// Notes:	The copy carries everything across; only eval, which shares
//			storage with the list pointer, is new.
//
//================================================================================
static struct LDrawDLSortedInstanceLink * copyWithEyeDepth(struct LDrawDLSession *				session,
														   struct LDrawDLSortedInstanceLink *	head,
														   int									count)
{
	struct LDrawDLSortedInstanceLink *	arr			= LDrawPoolAllocate(session->alloc, sizeof(*arr) * count);
	struct LDrawDLSortedInstanceLink *	p			= arr;
	simd_float4x4						modelView	= simd_matrix4x4_from_array(session->model_view);
	struct LDrawDLSortedInstanceLink *	l;

	for (l = head; l; l = l->next, ++p)
	{
		simd_float4 origin = simd_make_float4(l->transform[12], l->transform[13], l->transform[14], 1.0f);

		memcpy(p, l, sizeof(*p));
		p->eval = simd_mul(modelView, origin).z;
	}

	return arr;

} // end copyWithEyeDepth


//========== drawTransparentSorted ===============================================
//
// Purpose:	Blends the transparent parts one at a time, far to near by their
//			origins.
//
// Notes:	They do not write depth, so a part hides neither its own faces nor
//			the parts behind it. Parts that overlap can blend in the wrong
//			order, and lines that lie on each other blend twice. Lines that
//			wrote depth would hide the faces drawn after them, which shows as
//			a light seam along every line.
//
//================================================================================
static void drawTransparentSorted(id<MTLRenderCommandEncoder> renderEncoder, struct LDrawDLSession * session)
{
	struct LDrawDLSortedInstanceLink * arr = copyWithEyeDepth(session, session->sorted_head, session->sort_count);

	// Now: sort our array ascending to get far to near in eye space.
	qsort(arr,session->sort_count,sizeof(struct LDrawDLSortedInstanceLink),compare_sorted_link);

	[renderEncoder setDepthStencilState:transparentDepthState()];
	session->transparent_bias = YES;
	setFaceDepthBias(renderEncoder, session);

	// NOW we can walk our sorted array and draw each brick, 1x1.
	int lc;
	for (lc = 0; lc < session->sort_count; ++lc)
		drawDeferredInstance(renderEncoder, session, arr + lc, NO);

	[renderEncoder setDepthStencilState:defaultDepthState()];
	session->transparent_bias = NO;
	setFaceDepthBias(renderEncoder, session);

} // end drawTransparentSorted


//========== saveForDeferredDraw =================================================
//
// Purpose:	Save a DL to be drawn one-at-a-time later, rather than through the
//			instancing fast path.
//
//			A non-zero ghost_id defers it to the ghost pass; otherwise it goes
//			to the Z-sorted pass used for transparent parts. Both carry the same
//			payload -- DL, colors, transform and texture -- so they share a
//			link type and this function.
//
//================================================================================
static void saveForDeferredDraw(struct LDrawDLSession *		session,
								struct LDrawDL *			dl,
								struct LDrawTextureSpec *	spec,
								const float 				cur_color[4],
								const float 				cmp_color[4],
								const float					transform[16],
								int							ghost_id,
								float						ghost_alpha)
{
	struct LDrawDLSortedInstanceLink * link = LDrawPoolAllocate(session->alloc, sizeof(struct LDrawDLSortedInstanceLink));

	if (ghost_id != 0)
	{
		link->next = session->ghost_head;
		session->ghost_head = link;
		session->ghost_count++;
	}
	else
	{
		#if WANT_STATS
			session->stats.num_btch_srt++;
			session->stats.num_vert_srt += dl->vrt_count;
		#endif

		link->next = session->sorted_head;
		session->sorted_head = link;
		session->sort_count++;
	}

	link->dl = dl;
	++dl->deferred_count;
	link->ghost_id = ghost_id;
	link->ghost_alpha = ghost_alpha;
	memcpy(link->color,cur_color,sizeof(float)*4);
	memcpy(link->comp,cmp_color,sizeof(float)*4);
	memcpy(link->transform,transform,sizeof(float)*16);

	if (spec)
		memcpy((void*)&link->spec, (void*)spec, sizeof(struct LDrawTextureSpec));
	else
		memset((void*)&link->spec, 0, sizeof(struct LDrawTextureSpec));

} // end saveForDeferredDraw


//========== endDeferredUse ======================================================
//
// Purpose:	Notes that the transparent or ghost pass is done with a DL. One its
//			owner destroyed while it was queued goes on the list to destroy,
//			once nothing draws it any more.
//
//================================================================================
static void endDeferredUse(struct LDrawDL * dl, struct LDrawDL ** doomed_head)
{
	if (--dl->deferred_count == 0 && (dl->flags & dl_needs_destroy))
	{
		dl->next_dl = *doomed_head;
		*doomed_head = dl;
	}

} // end endDeferredUse


//========== saveForInstanceDraw =================================================
//
// Purpose:	Save DL for later instance drawing.
//
//================================================================================
static void saveForInstanceDraw(struct LDrawDLSession *	session,
								struct LDrawDL *		dl,
								const float 			cur_color[4],
								const float 			cmp_color[4],
								const float				transform[16],
								BOOL					is_wireframe)
{
	// assert(dl->next_dl == NULL || session->dl_head != NULL);

	// This is the first deferred instance for this DL - link this DL into our session so that we can find it later.
	if (dl->instance_head == NULL)
	{
		session->dl_count++;
		dl->next_dl = session->dl_head;
		session->dl_head = dl;
	}
	// Copy our instance data into a LDrawDLInstance and link that into the DL for later use.
	struct LDrawDLInstance * inst = (struct LDrawDLInstance *) LDrawPoolAllocate(session->alloc,sizeof(struct LDrawDLInstance));
	{
		if (dl->instance_head == NULL)
		{
			dl->instance_head = inst;
			dl->instance_tail = inst;
		}
		else
		{
			dl->instance_tail->next = inst;
			dl->instance_tail = inst;
		}
		inst->next = NULL;
		++dl->instance_count;
		++session->total_instance_count;

		memcpy(inst->color,cur_color,sizeof(float)*4);
		memcpy(inst->comp,cmp_color,sizeof(float)*4);
		memcpy(inst->transform,transform,sizeof(float)*16);
		inst->is_wireframe = is_wireframe;
	}

} // end saveForInstanceDraw


//========== immediateDraw =======================================================
//
// Purpose:	IMMEDIATE MODE DRAW CASE!
//          We are going to draw this DL right now at this position.
//
//================================================================================
static void immediateDraw(id<MTLRenderCommandEncoder>	renderEncoder,
						  struct LDrawDLSession *		session,
						  struct LDrawDL *				dl,
						  struct LDrawTextureSpec *		spec,
						  const float	 				cur_color[4],
						  const float 					cmp_color[4],
						  const float					transform[16],
						  BOOL							is_wire_frame)
{
	#if WANT_STATS
		session->stats.num_btch_imm++;
		session->stats.num_vert_imm += dl->vrt_count;
	#endif

	struct InstanceInput instData;
	instData.transform_x = simd_make_float4(transform[0], transform[4], transform[8],  transform[12]);
	instData.transform_y = simd_make_float4(transform[1], transform[5], transform[9],  transform[13]);
	instData.transform_z = simd_make_float4(transform[2], transform[6], transform[10], transform[14]);
	instData.transform_w = simd_make_float4(transform[3], transform[7], transform[11], transform[15]);
	copy_vec4((float *)&instData.color_current, cur_color);
	copy_vec4((float *)&instData.color_complement, cmp_color);

	[renderEncoder setVertexBytes:&instData
						   length:sizeof(instData)
						  atIndex:BufferIndexPerInstanceData];

	assert(dl->tex_count > 0);

	// Bind our DL buffer and set up ptrs.
	[renderEncoder setVertexBuffer:dl->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];

	struct LDrawDLPerTex * tptr = dl->texes;

	if (is_wire_frame || (dl->tex_count == 1 && tptr->spec.tex_obj == NULL && (spec == NULL || spec->tex_obj == NULL)))
	{
		// Special case: wireframe or one untextured mesh - just draw.

		setup_tex_spec(NULL, session, renderEncoder);

		#if WANT_SMOOTH
		if (tptr->line_count)
			[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
									  indexCount:tptr->line_count
									   indexType:MTLIndexTypeUInt32
									 indexBuffer:dl->indexBuffer
							   indexBufferOffset:tptr->line_off * sizeof(uint32_t)
								   instanceCount:1];

		if (tptr->cond_line_count)
			[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
									  indexCount:tptr->cond_line_count
									   indexType:MTLIndexTypeUInt32
									 indexBuffer:dl->indexBuffer
							   indexBufferOffset:tptr->cond_line_off * sizeof(uint32_t)
								   instanceCount:1];
		#else
		if (tptr->line_count)
			[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
							  vertexStart:tptr->line_off
							  vertexCount:tptr->line_count];
		#endif
	}
	else
	{
		// Textured case - for each texture set up the DL texture (or current
		// texture if none), then draw.
		int t;
		for (t = 0; t < dl->tex_count; ++t, ++tptr)
		{
			if (tptr->spec.tex_obj)
			{
				setup_tex_spec(&tptr->spec, session, renderEncoder);
			}
			else
				setup_tex_spec(spec, session, renderEncoder);

			#if WANT_SMOOTH
			drawLines(renderEncoder, session, dl, tptr, 1);

			if (tptr->tri_count)
				[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
										  indexCount:tptr->tri_count
										   indexType:MTLIndexTypeUInt32
										 indexBuffer:dl->indexBuffer
								   indexBufferOffset:tptr->tri_off * sizeof(uint32_t)];
			#else
			if (tptr->line_count)
				[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
								  vertexStart:tptr->line_off
								  vertexCount:tptr->line_count];

			if (tptr->tri_count)
				[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
								  vertexStart:tptr->tri_off
								  vertexCount:tptr->tri_count];
			#endif
		}

		setup_tex_spec(spec, session, renderEncoder);
	}
} // end immediateDraw


//========== writeHardwareInstanceData ===========================================
//
// Purpose:	Write per-instance transform and color data for a DL into the
//			instance buffer for use with hardware instancing.
//
//================================================================================
static void writeHardwareInstanceData(struct LDrawDLSegment	*	segment,
									  struct LDrawDL *			dl,
									  const float *				inst_base,
									  float *					inst_data,
									  BOOL 						is_wireframe)
{
	struct LDrawDLInstance *inst;
	int inst_count = 0;

	segment->is_wireframe = is_wireframe;
	segment->inst_base = NULL;
	segment->inst_base += (inst_data - inst_base);

	// Now walk the instance list, copying the instances into the instance buffer one by one.

	for (inst = dl->instance_head; inst != NULL; inst = inst->next)
	{
		if (inst->is_wireframe != is_wireframe) {
			continue;
		}
		// Copy on transpose to get matrix into right form!
		copy_matrix_transposed(inst_data, inst->transform);
		copy_vec4(inst_data + 16, inst->color);
		copy_vec4(inst_data + 20, inst->comp);
		inst_data += InstanceInputLength;
		++inst_count;
	}
	segment->inst_count = inst_count;

	if (inst_count > 0) {
		if (segment->vertexBuffer != dl->vertexBuffer) segment->vertexBuffer = dl->vertexBuffer;
#if WANT_SMOOTH
		segment->indexBuffer = dl->indexBuffer;
		segment->condIndexBuffer = dl->condIndexBuffer;
#endif
		segment->dl = &dl->texes[0];
	}

} // end writeHardwareInstanceData


// MARK: - Display list creation API -


//========== LDrawDLSupportedPrimitives ==========================================
//
// Purpose:	Tell the shared builder what our display lists carry.
//
// Notes:	Metal has no quad primitive, so we take quads pre-split into tris and
//			never read the builder's quad lists below.  Conditional lines we do
//			draw, so we ask for them.
//
//================================================================================
int LDrawDLSupportedPrimitives(void)
{
	return dl_supports_conditional_lines;

} // end LDrawDLSupportedPrimitives


//========== LDrawDLBuilderFinish ================================================
//
// Purpose:	Take all of the accumulated data in a DL and bake it down to one
//			final form.
//
// Notes:	The DL is, while being built, a series of linked lists in a BDP for
//			speed. The finished DL is a malloc'd block of memory, pre-sized to
//			fit the DL perfectly, and one buffer. So this routine does the counting,
//			final allocations, and copying.
//
//================================================================================
struct LDrawDL * LDrawDLBuilderFinish(struct LDrawDLBuilder * ctx)
{
#if WANT_SMOOTH
	MeshSmoothSetHasQuads(LDrawDLSupportedPrimitives() & dl_supports_quads);

	#if TIME_SMOOTHING
	NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
	#endif

	int total_texes = 0;
	int total_tris = 0;
	int total_quads = 0;
	int total_lines = 0;
	int total_cond_lines = 0;


	struct LDrawDLBuilderVertexLink * l;
	struct LDrawDLBuilderPerTex * s;

	// Count up the total vertices we will need, for buffer space, as well
	// as the total distinct non-empty textures.
	for (s = ctx->head; s; s = s->next)
	{
		if (s->tri_head || s->line_head || s->cond_line_head)
			++total_texes;

		for (l = s->tri_head; l; l = l->next)
		{
			total_tris++;
		}
		for (l = s->line_head; l; l = l->next)
		{
			total_lines++;
		}
		for (l = s->cond_line_head; l; l = l->next)
		{
			total_cond_lines++;
		}
	}

	// No non-empty textures?  Bail out early - nuke our
	// context and get out.  Client code knows we get NO DL, rather than
	// an empty one.
	if (total_texes == 0)
	{
		LDrawPoolDestroy(ctx->alloc);
		return NULL;
	}

	// Alloc DL structure with extra storage for variable-sized tex array.
	// Use calloc to prevent undefined values and EXC_BAD_ACCESS issue.
	struct LDrawDL * dl = (struct LDrawDL *) calloc(1, sizeof(struct LDrawDL) + sizeof(struct LDrawDLPerTex) * total_texes);

	// All per-session linked list ptrs start null.
	dl->next_dl = NULL;
	dl->instance_head = NULL;
	dl->instance_tail = NULL;
	dl->instance_count = 0;
	dl->deferred_count = 0;

	dl->tex_count = total_texes;

	struct LDrawDLPerTex * cur_tex = dl->texes;
	dl->flags = ctx->flags;

	// We use one mesh for the entire DL, even if it has multiple textures.  We have to
	// do this because we want smoothing across triangles that do not share the same
	// texture.  (Key use case: minifig faces are part textured, part untextured.)
	//
	// So instead each face gets a texture ID (tid), which is an index that we will tie
	// to our texture list.  The mesh smoother remembers this and dumps out the tris in
	// tid order later.

	struct Mesh * M = create_mesh(total_tris, total_quads, total_lines, total_cond_lines);


	// Now: walk our building textures - for each non-empty one, we will copy it into
	// the tex array and push its vertices.
	int ti = 0;
	for (s = ctx->head; s; s = s->next)
	{
		if (s->tri_head == NULL && s->line_head == NULL && s->cond_line_head == NULL)
			continue;

		if (s->spec.tex_obj != NULL)
			dl->flags |= dl_has_tex;

		for (l = s->tri_head; l; l = l->next)
		{
			add_face(M,
				l->data, l->data+10,l->data+20,NULL,
				l->data+6,ti);
		}

		++ti;
	}

	ti = 0;
	for (s = ctx->head; s; s = s->next)
	{
		if (s->tri_head == NULL && s->line_head == NULL && s->cond_line_head == NULL)
			continue;

		if (s->spec.tex_obj != NULL)
			dl->flags |= dl_has_tex;

		for (l = s->line_head; l; l = l->next)
		{
			add_face(M,l->data,l->data+10,NULL,NULL,l->data+6,ti);
		}

		for (l = s->cond_line_head; l; l = l->next)
		{
			add_face(M,l->data,l->data+10,l->data+20,l->data+30,l->data+6,ti);
		}

		++ti;
	}


	finish_faces_and_sort(M);
	add_creases(M);
	find_and_remove_t_junctions(M);
	finish_creases_and_join(M);
	smooth_vertices(M);
	merge_vertices(M);

	int total_vertices, total_indices;
	get_final_mesh_counts(M,&total_vertices,&total_indices);

	id<MTLDevice> device = MetalGPU.device;

	// PERFORMANCE OPTIMIZATION: Use private storage for GPU buffers with staging buffers for CPU writes
	// This eliminates CPU-GPU synchronization overhead and improves cache performance.

	// Create staging buffers (shared) for CPU writes

	NSUInteger vertexBufferSize	= total_vertices * sizeof(float) * VERT_STRIDE;
	NSUInteger indexBufferSize	= total_indices * sizeof(uint32_t);

	id<MTLBuffer> stagingVertexBuffer = [device newBufferWithLength:vertexBufferSize
															options:MTLResourceStorageModeShared];
	stagingVertexBuffer.label = @"Staging vertex buffer";
	
	id<MTLBuffer> stagingIndexBuffer = [device newBufferWithLength:indexBufferSize
														   options:MTLResourceStorageModeShared];
	stagingIndexBuffer.label = @"Staging index buffer";


	// Create GPU buffers (private) for optimal GPU access

	id<MTLBuffer> vertexBuffer = [device newBufferWithLength:vertexBufferSize
													 options:MTLResourceStorageModePrivate];
	vertexBuffer.label = @"Vertex buffer";
	
	id<MTLBuffer> indexBuffer = [device newBufferWithLength:indexBufferSize
													options:MTLResourceStorageModePrivate];
	indexBuffer.label = @"Index buffer";
	
	dl->vertexBuffer = vertexBuffer;
	dl->indexBuffer = indexBuffer;


	// Write data to staging buffers

	volatile float		*vertex_ptr	= (volatile float *)[stagingVertexBuffer contents];
	volatile uint32_t	*index_ptr	= (volatile uint32_t *)[stagingIndexBuffer contents];


	// Grab variable size arrays for the start/offsets of each sub-part of our big pile-o-mesh...
	// the mesher will give us back our tris sorted by texture.

	int * line_start	= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * line_count	= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * cond_line_start = (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * cond_line_count = (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * tri_start		= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * tri_count		= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * quad_start	= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * quad_count	= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);

	write_indexed_mesh(
		M,
		total_vertices,
		vertex_ptr,
		total_indices,
		index_ptr,
		0,
		line_start,
		line_count,
		cond_line_start,
		cond_line_count,
		tri_start,
		tri_count,
		quad_start,
		quad_count);

	// Wide conditional lines need their control points, so they keep all four
	// indices in a buffer of their own. Below, the index buffer keeps only the
	// ends, for a wireframe.
	int *			cond_quad_start			= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int *			cond_quad_count			= (int *) LDrawPoolAllocate(ctx->alloc, sizeof(int) * total_texes);
	int				total_cond_indices		= 0;
	id<MTLBuffer>	stagingCondIndexBuffer	= nil;

	for (ti = 0; ti < total_texes; ++ti)
	{
		cond_quad_start[ti] = total_cond_indices;
		cond_quad_count[ti] = cond_line_count[ti];
		total_cond_indices += cond_line_count[ti];
	}

	if (total_cond_indices > 0)
	{
		NSUInteger condIndexBufferSize = total_cond_indices * sizeof(uint32_t);

		stagingCondIndexBuffer = [device newBufferWithLength:condIndexBufferSize
													 options:MTLResourceStorageModeShared];
		stagingCondIndexBuffer.label = @"Staging conditional line index buffer";

		uint32_t * cond_ptr = (uint32_t *)[stagingCondIndexBuffer contents];

		for (ti = 0; ti < total_texes; ++ti)
		{
			for (int i = 0; i < cond_line_count[ti]; ++i)
				*cond_ptr++ = index_ptr[cond_line_start[ti] + i];
		}

		dl->condIndexBuffer = [device newBufferWithLength:condIndexBufferSize
												  options:MTLResourceStorageModePrivate];
		dl->condIndexBuffer.label = @"Conditional line index buffer";
	}

	if (*cond_line_count > 0) {
		volatile uint32_t * in_ptr = index_ptr + *cond_line_start;
		volatile uint32_t * out_ptr = in_ptr;
		for (int i = 0; i < *cond_line_count; i += 4) {
			*out_ptr++ = *in_ptr++;
			*out_ptr++ = *in_ptr++;
			in_ptr++;
			in_ptr++;
		}
		*cond_line_count /= 2;
	}

	// PERFORMANCE OPTIMIZATION: Copy data from staging buffers to GPU buffers using blit encoder
	// This ensures data is in GPU-optimal memory (private storage) for fast access.
	// Reuse existing blit command queue instead of creating a new one each time.
	if (_blitCommandQueue == nil) {
		_blitCommandQueue = [device newCommandQueue];
		_blitCommandQueue.label = @"Blit Command Queue";
	}
	
	id<MTLCommandBuffer> copyCommandBuffer = [_blitCommandQueue commandBuffer];
	copyCommandBuffer.label = @"DL Buffer Copy";
	
	id<MTLBlitCommandEncoder> blitEncoder	= [copyCommandBuffer blitCommandEncoder];
	blitEncoder.label = @"DL Buffer Blit";
	
	// Copy vertex data from staging to GPU buffer
	[blitEncoder copyFromBuffer:stagingVertexBuffer
				   sourceOffset:0
					   toBuffer:vertexBuffer
			  destinationOffset:0
						   size:vertexBufferSize];

	// Copy index data from staging to GPU buffer
	[blitEncoder copyFromBuffer:stagingIndexBuffer
				   sourceOffset:0
					   toBuffer:indexBuffer
			  destinationOffset:0
						   size:indexBufferSize];

	if (stagingCondIndexBuffer != nil)
		[blitEncoder copyFromBuffer:stagingCondIndexBuffer
					   sourceOffset:0
						   toBuffer:dl->condIndexBuffer
				  destinationOffset:0
							   size:stagingCondIndexBuffer.length];

	[blitEncoder endEncoding];
	[copyCommandBuffer commit];
	[copyCommandBuffer waitUntilCompleted];
	
	// Staging buffers will be released when they go out of scope

	ti = 0;

	for (s = ctx->head; s; s = s->next)
	{
		if (s->tri_head == NULL && s->line_head == NULL && s->cond_line_head == NULL)
			continue;

		memcpy((void*)&cur_tex->spec, (void*)&s->spec, sizeof(struct LDrawTextureSpec));

		cur_tex->line_off			= line_start[ti];
		cur_tex->cond_line_off		= cond_line_start[ti];
		cur_tex->tri_off			= tri_start[ti];
		cur_tex->line_count			= line_count[ti];
		cur_tex->cond_line_count	= cond_line_count[ti];
		cur_tex->cond_quad_off		= cond_quad_start[ti];
		cur_tex->cond_quad_count	= cond_quad_count[ti];
		cur_tex->tri_count			= tri_count[ti];

		++ti;
		++cur_tex;
	}

	destroy_mesh(M);

	#if WANT_STATS
	dl->vrt_count = total_vertices;
	dl->idx_count = total_indices;
	#endif

	// Release the BDP that contains all of the build-related junk.
	LDrawPoolDestroy(ctx->alloc);

	#if TIME_SMOOTHING
	NSTimeInterval endTime = [NSDate timeIntervalSinceReferenceDate];
	#if WANT_STATS
	printf("Optimize took %f seconds for %d indices, %d vertices.\n",  endTime - startTime, dl->idx_count, dl->vrt_count);
	#else
	printf("Optimize took %f seconds.\n",  endTime - startTime);
	#endif
	#endif

	return dl;
#else
	int total_texes = 0;
	int total_vertices = 0;

	struct LDrawDLBuilderVertexLink * l;
	struct LDrawDLBuilderPerTex * s;

	// Count up the total vertices we will need, for buffer space, as well
	// as the total distinct non-empty textures.
	for (s = ctx->head; s; s = s->next)
	{
		if (s->tri_head || s->line_head)
			++total_texes;
		for (l = s->tri_head; l; l = l->next)
			total_vertices += l->vcount;
		for (l = s->line_head; l; l = l->next)
			total_vertices += l->vcount;
	}

	// No non-empty textures?  Bail out early - nuke our
	// context and get out.  Client code knows we get NO DL, rather than
	// an empty one.
	if (total_texes == 0)
	{
		LDrawPoolDestroy(ctx->alloc);
		return NULL;
	}

	// Malloc DL structure with extra storage for variable-sized tex array.
	struct LDrawDL * dl = (struct LDrawDL *) malloc(sizeof(struct LDrawDL) + sizeof(struct LDrawDLPerTex) * total_texes);

	// All per-session linked list ptrs start null.
	dl->next_dl = NULL;
	dl->instance_head = NULL;
	dl->instance_tail = NULL;
	dl->instance_count = 0;
	dl->deferred_count = 0;

	dl->tex_count = total_texes;

	#if WANT_STATS
	dl->vrt_count = total_vertices;
	#endif

	// Generate and map a buffer for our mesh data.
	// PERFORMANCE OPTIMIZATION: Use private storage for GPU buffers with staging buffers for CPU writes

	id<MTLDevice> device		= MetalGPU.device;
	NSUInteger vertexBufferSize	= total_vertices * sizeof(float) * VERT_STRIDE;

	// Create staging buffer (shared) for CPU writes
	id<MTLBuffer> stagingVertexBuffer = [device newBufferWithLength:vertexBufferSize
															options:MTLResourceStorageModeShared];
	stagingVertexBuffer.label = @"Staging vertex buffer";
	
	// Create GPU buffer (private) for optimal GPU access
	id<MTLBuffer> vertexBuffer = [device newBufferWithLength:vertexBufferSize
													 options:MTLResourceStorageModePrivate];
	vertexBuffer.label = @"Vertex buffer";
	
	dl->vertexBuffer = vertexBuffer;

	// Write data to staging buffer

	volatile float * buf_ptr = (volatile float *)[stagingVertexBuffer contents];

	int cur_v = 0;
	struct LDrawDLPerTex * cur_tex = dl->texes;
	dl->flags = ctx->flags;

	// Now: walk our building textures - for each non-empty one, we will copy it into
	// the tex array and push its vertices.
	for (s = ctx->head; s; s = s->next)
	{
		if (s->tri_head == NULL && s->line_head == NULL)
			continue;
		if (s->spec.tex_obj != NULL)
			dl->flags |= dl_has_tex;
		memcpy(&cur_tex->spec, &s->spec, sizeof(struct LDrawTextureSpec));
		cur_tex->line_off = cur_v;
		cur_tex->line_count = 0;

		// These loops copy the actual geometry (in linked lists of data) into the buffer.

		for (l = s->line_head; l; l = l->next)
		{
			memcpy(buf_ptr,l->data,VERT_STRIDE * sizeof(float) * l->vcount);
			cur_tex->line_count += l->vcount;
			cur_v += l->vcount;
			buf_ptr += (VERT_STRIDE * l->vcount);
		}

		cur_tex->tri_off = cur_v;
		cur_tex->tri_count = 0;

		for (l = s->tri_head; l; l = l->next)
		{
			memcpy(buf_ptr,l->data,VERT_STRIDE * sizeof(float) * l->vcount);
			cur_tex->tri_count += l->vcount;
			cur_v += l->vcount;
			buf_ptr += (VERT_STRIDE * l->vcount);
		}

		++cur_tex;
	}

	// PERFORMANCE OPTIMIZATION: Copy data from staging buffer to GPU buffer using blit encoder
	// This ensures data is in GPU-optimal memory (private storage) for fast access.
	// Reuse existing blit command queue instead of creating a new one each time.
	if (_blitCommandQueue == nil) {
		_blitCommandQueue = [device newCommandQueue];
		_blitCommandQueue.label = @"Blit Command Queue";
	}
	
	id<MTLCommandBuffer> copyCommandBuffer = [_blitCommandQueue commandBuffer];
	copyCommandBuffer.label = @"DL Buffer Copy";
	
	id<MTLBlitCommandEncoder> blitEncoder	= [copyCommandBuffer blitCommandEncoder];
	blitEncoder.label = @"DL Buffer Blit";
	
	// Copy vertex data from staging to GPU buffer
	[blitEncoder copyFromBuffer:stagingVertexBuffer
				   sourceOffset:0
					   toBuffer:vertexBuffer
			  destinationOffset:0
						   size:vertexBufferSize];
	
	[blitEncoder endEncoding];
	[copyCommandBuffer commit];
	[copyCommandBuffer waitUntilCompleted];
	
	// Staging buffer will be released when it goes out of scope

	// Release the BDP that contains all of the build-related junk.
	LDrawPoolDestroy(ctx->alloc);

	return dl;

#endif
} // end LDrawDLBuilderFinish



//========== LDrawDLDestroy ======================================================
//
// Purpose: free a display list - release GL and system memory.
//
//================================================================================
void LDrawDLDestroy(struct LDrawDL * dl)
{
	if (dl->instance_head != NULL || dl->deferred_count > 0)
	{
		// Special case: if our DL is destroyed WHILE a session is using it for
		// deferred drawing, we do NOT destroy it - we mark it for destruction
		// later and the session nukes it.  This is needed for the case where
		// client code creates a DL, draws it, and immediately destroys it, as
		// a silly way to get 'immediate' drawing.  In this case, the session
		// may have intentionally deferred the DL, for instancing or for the
		// transparent or ghost pass.
		dl->flags |= dl_needs_destroy;
		return;
	}
	// Make sure that no instances from a session are queued to this list; if we
	// are in Q and run now, we'll cause seg faults later.  This assert hits
	// when: (1) we build a temp DL and don't mark it as temp or (2) we for some
	// reason inval a DL mid-draw, which is usually a sign of coding error.
	assert(dl->instance_head == NULL);

	// free() does not release the buffers.
	dl->vertexBuffer = nil;
#if WANT_SMOOTH
	dl->indexBuffer = nil;
	dl->condIndexBuffer = nil;
#endif

	free(dl);

} // end LDrawDLDestroy


// MARK: - Display list mesh accumulation APIs -


// MARK: - Session/drawing APIs -


//========== LDrawDLSessionCreate ================================================
//
// Purpose:	Create a new drawing session.  Drawing sessions sit entirely in a BDP
//			for speed - most of our linked lists are just NULL.
//
//================================================================================
struct LDrawDLSession * LDrawDLSessionCreate(const float model_view[16])
{
	struct LDrawPool * alloc = LDrawPoolCreate();
	struct LDrawDLSession * session = (struct LDrawDLSession *) LDrawPoolAllocate(alloc,sizeof(struct LDrawDLSession));
	session->alloc = alloc;
	session->dl_head = NULL;
	session->dl_count = 0;
	session->total_instance_count = 0;
	session->sorted_head = NULL;
	session->ghost_head = NULL;
	session->ghost_count = 0;
	session->sort_count = 0;
	#if WANT_STATS
	memset(&session->stats,0,sizeof(session->stats));
	#endif
	memcpy(session->model_view,model_view,sizeof(float)*16);
	memset(&session->wide_lines, 0, sizeof(session->wide_lines));
	session->transparent_bias = NO;
	session->inst_ring = inst_ring_last;
	// each session picks up a new buffer in the ring of instance buffers.
	inst_ring_last = (inst_ring_last+1)%INST_RING_BUFFER_COUNT;
	return session;
} // end LDrawDLSessionCreate


//========== LDrawDLSessionSetWideLines ==========================================
//
// Purpose:	Draws the session's edge and conditional lines as quads, so they
//			can be wider than a pixel. A nil line pipeline goes back to edge
//			lines a pixel wide and no conditional lines.
//
// Notes:	Call it before anything is drawn: a textured part draws its faces
//			at once, and they need the face depth bias.
//
//================================================================================
void LDrawDLSessionSetWideLines(id<MTLRenderCommandEncoder>		renderEncoder,
								struct LDrawDLSession *			session,
								const struct LDrawDLWideLines *	lines)
{
	session->wide_lines = *lines;

	#if WANT_SMOOTH
	if (lines->line_pipeline)
		setFaceDepthBias(renderEncoder, session);
	#endif

} // end LDrawDLSessionSetWideLines


//========== LDrawDLSessionDrawAndDestroy ========================================
//
// Purpose:	Draw any DLs that were deferred during drawing, then nuke the
//			session object.
//
//================================================================================
void LDrawDLSessionDrawAndDestroy(id<MTLRenderCommandEncoder> renderEncoder, struct LDrawDLSession * session)
{
	struct LDrawDLInstance * inst;
	struct LDrawDL * dl;

	// DLs their owner destroyed while they were queued. The segments, the
	// transparent pass and the ghost pass still read them, so they go last.
	struct LDrawDL * doomed_head = NULL;

	// INSTANCED DRAWING CASE

	if (session->dl_head)
	{
		// Build a var-sized array of segments to record our instances for hardware instancing.  We may not need it for every DL but that's okay.
		// We need twice the space because each DL can have both wireframe and non-wireframe instances that need to be drawn separately.
		size_t segmentsSize = sizeof(struct LDrawDLSegment) * session->dl_count * 2;
		struct LDrawDLSegment * segments = (struct LDrawDLSegment *) LDrawPoolAllocate(session->alloc, segmentsSize);
		struct LDrawDLSegment * cur_segment = segments;

		// Get or create an instance buffer of appropriate size
		NSUInteger requiredSize = session->total_instance_count * InstanceInputStructSize;
		id<MTLBuffer> stagingInstanceBuffer = getInstanceBuffer(requiredSize, session->inst_ring);
		id<MTLBuffer> gpuInstanceBuffer = inst_vbo_ring[session->inst_ring];
            
		// Map our staging instance buffer so we can write instancing data.
        float * inst_base = (float *) [stagingInstanceBuffer contents];
		float * inst_data = inst_base;
		int 	inst_count = 0;
		int		inst_remain = INST_MAX_COUNT;

		// Main loop 1: we will walk every instanced DL and either accumulate its instances (for hardware instancing)
		// or just draw now (for immediate instancing).
		while (session->dl_head)
		{
			dl = session->dl_head;

			if (dl->instance_count >= INST_CUTOFF && inst_remain >= dl->instance_count)
			{
				// If we have capacity for hw instancing and this DL is used enough, create a segment record and fill it out.

				#if WANT_STATS
					session->stats.num_btch_ins++;
					session->stats.num_inst_ins += (dl->instance_count);
					session->stats.num_vert_ins += (dl->instance_count * dl->vrt_count);
					session->stats.num_work_ins += dl->vrt_count;
				#endif

				writeHardwareInstanceData(cur_segment, dl, inst_base, inst_data, NO);
				inst_count += cur_segment->inst_count;
				inst_remain -= cur_segment->inst_count;
				inst_data += InstanceInputLength * cur_segment->inst_count;
				if (cur_segment->inst_count > 0) ++cur_segment;

				writeHardwareInstanceData(cur_segment, dl, inst_base, inst_data, YES);
				inst_count += cur_segment->inst_count;
				inst_remain -= cur_segment->inst_count;
				inst_data += InstanceInputLength * cur_segment->inst_count;
				if (cur_segment->inst_count > 0) ++cur_segment;
			}
			else
			{
				#if WANT_STATS
					session->stats.num_btch_att++;
					session->stats.num_inst_att += (dl->instance_count);
					session->stats.num_vert_att += (dl->instance_count * dl->vrt_count);
					session->stats.num_work_att += dl->vrt_count;
				#endif
			
				// Immediate mode instancing - we draw now!  So bind up the mesh of this DL.
				[renderEncoder setVertexBuffer:dl->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];

				// Now walk the instance list...push instance data as set of bytes (which is faster than setting a real buffer) and draw.
				for (inst = dl->instance_head; inst; inst = inst->next)
				{
					struct InstanceInput instData;
					instData.transform_x = simd_make_float4(inst->transform[0], inst->transform[4], inst->transform[8],  inst->transform[12]);
					instData.transform_y = simd_make_float4(inst->transform[1], inst->transform[5], inst->transform[9],  inst->transform[13]);
					instData.transform_z = simd_make_float4(inst->transform[2], inst->transform[6], inst->transform[10], inst->transform[14]);
					instData.transform_w = simd_make_float4(inst->transform[3], inst->transform[7], inst->transform[11], inst->transform[15]);
					copy_vec4((float *)&instData.color_current, inst->color);
					copy_vec4((float *)&instData.color_complement, inst->comp);

					[renderEncoder setVertexBytes:&instData
										   length:sizeof(instData)
										  atIndex:BufferIndexPerInstanceData];

					struct LDrawDLPerTex * tptr = dl->texes;

					setup_tex_spec(NULL, session, renderEncoder);

					#if WANT_SMOOTH
					drawLines(renderEncoder, session, dl, tptr, 1);

					if (tptr->tri_count)
						[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
												  indexCount:tptr->tri_count
												   indexType:MTLIndexTypeUInt32
												 indexBuffer:dl->indexBuffer
										   indexBufferOffset:tptr->tri_off * sizeof(uint32_t)
											   instanceCount:1];
					#else
					if (tptr->line_count)
						[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
										  vertexStart:tptr->line_off
										  vertexCount:tptr->line_count];

					if (tptr->tri_count)
						[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
										  vertexStart:tptr->tri_off
										  vertexCount:tptr->tri_count];
					#endif
				}
			}
			
			dl->instance_head = dl->instance_tail = NULL;			
			dl->instance_count = 0;
			// Bug fix: bump the list head FIRST (pop front) before we blow things up, lest we use freed memory.
			session->dl_head = dl->next_dl;
			// One the transparent or ghost pass still draws waits for it.
			if ((dl->flags & dl_needs_destroy) && dl->deferred_count == 0)
			{
				dl->next_dl = doomed_head;
				doomed_head = dl;
			}
			else
			{
				dl->next_dl = NULL;
			}
		}

		// PERFORMANCE OPTIMIZATION: Copy data from staging buffer to GPU buffer using blit encoder
		// This ensures data is in GPU-optimal memory (private storage) for fast access.
		// Note: We use a separate command buffer because we can't create a blit encoder
		// while a render encoder is active.

		if (inst_count > 0)
		{
			// Create blit command queue if needed (reused across frames)
			if (_blitCommandQueue == nil)
			{
				_blitCommandQueue = [MetalGPU.device newCommandQueue];
				_blitCommandQueue.label = @"Blit Command Queue";
			}
			
			id<MTLCommandBuffer> blitCommandBuffer = [_blitCommandQueue commandBuffer];
			blitCommandBuffer.label = @"Instance Buffer Copy";
			
			id<MTLBlitCommandEncoder> blitEncoder = [blitCommandBuffer blitCommandEncoder];
			blitEncoder.label = @"Instance Buffer Blit";
			
			[blitEncoder copyFromBuffer:stagingInstanceBuffer
						   sourceOffset:0
							   toBuffer:gpuInstanceBuffer
					  destinationOffset:0
								   size:inst_count * InstanceInputStructSize];

			[blitEncoder endEncoding];
			[blitCommandBuffer commit];
			[blitCommandBuffer waitUntilCompleted];
		}

		// Hardware instancing

		if (segments != cur_segment)
		{
			// Main loop 2 over DLs - for each DL that had hw-instances we built a segment
			// in our array.  Bind the DL itself, as well as the instance pointers, and do an instanced-draw.

			setup_tex_spec(NULL, session, renderEncoder);

			[renderEncoder setVertexBuffer:gpuInstanceBuffer offset:0 atIndex:BufferIndexPerInstanceData];

			struct LDrawDLSegment * s;
			for (s = segments; s < cur_segment; ++s)
			{
				[renderEncoder setVertexBuffer:s->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];
				[renderEncoder setVertexBufferOffset:(NSUInteger)s->inst_base atIndex:BufferIndexPerInstanceData];

				#if WANT_SMOOTH	
				// Wide lines are drawn after every segment's faces, below.
				if (s->dl->line_count && (s->is_wireframe || session->wide_lines.line_pipeline == nil))
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
											  indexCount:s->dl->line_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:s->indexBuffer
									   indexBufferOffset:s->dl->line_off * sizeof(uint32_t)
										   instanceCount:s->inst_count];

				if (s->dl->cond_line_count && s->is_wireframe)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
											  indexCount:s->dl->cond_line_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:s->indexBuffer
									   indexBufferOffset:s->dl->cond_line_off * sizeof(uint32_t)
										   instanceCount:s->inst_count];

				if (s->dl->tri_count && !s->is_wireframe)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
											  indexCount:s->dl->tri_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:s->indexBuffer
									   indexBufferOffset:s->dl->tri_off * sizeof(uint32_t)
										   instanceCount:s->inst_count];
				#else
				if (s->dl->line_count)
				   [renderEncoder drawPrimitives:MTLPrimitiveTypeLine
									 vertexStart:s->dl->line_off
									 vertexCount:s->dl->line_count
								   instanceCount:s->inst_count];

				if (s->dl->tri_count)
					[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
									  vertexStart:s->dl->tri_off
									  vertexCount:s->dl->tri_count
									instanceCount:s->inst_count];
				#endif
			}

			#if WANT_SMOOTH
			// One switch to the line pipeline for all of them. A wireframe
			// keeps its thin lines.
			if (session->wide_lines.line_pipeline)
			{
				beginWideLines(renderEncoder, session);

				for (s = segments; s < cur_segment; ++s)
				{
					if (s->is_wireframe)
						continue;

					[renderEncoder setVertexBuffer:s->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];
					[renderEncoder setVertexBufferOffset:(NSUInteger)s->inst_base atIndex:BufferIndexPerInstanceData];

					drawWideLines(renderEncoder, session, s->indexBuffer, s->condIndexBuffer, s->dl, s->inst_count);
				}

				endWideLines(renderEncoder, session);
			}
			#endif
		}
	}

	// MAIN LOOP 3: transparent parts.

	struct LDrawDLSortedInstanceLink * l;
	if (session->sorted_head)
		drawTransparentSorted(renderEncoder, session);

	// MAIN LOOP 4: ghosted parts (removed MLCAD groups).
	//
	// A ghost must read as an ordinary part that happens to be see-through, not
	// as a transparent brick: blending every surface would show its studs and
	// inner walls. So each ghost is drawn twice --
	//
	//	1. A depth prepass establishing its nearest surface. Scaling alpha to 0
	//	   makes the fragment contribute nothing to the color buffer (the blend
	//	   is src*0 + dst*1) while depth still writes, so no extra pipeline
	//	   state is needed. The scale is applied in the shader, so this holds
	//	   for colors baked into a mesh as well as the meta ones.
	//	2. A blend pass with depth compare Equal and depth writes off, so only
	//	   the frontmost fragment survives and blends once.
	//
	// Both passes span the WHOLE ghosted part. A ghosted submodel reference is
	// a couple of dozen separate DLs, and prepassing them one at a time would
	// give each brick its own shell -- so you would still see right through the
	// assembly. Hence the ghost id: instances sharing one are prepassed
	// together and blended together.
	//
	// Drawn last. Between ghosts, ordering does not matter: a ghost behind
	// another loses its prepass on the Less test and is occluded, the same way
	// solid parts occlude each other.
	if (session->ghost_head)
	{
		struct LDrawDLSortedInstanceLink * arr = copyWithEyeDepth(session, session->ghost_head, session->ghost_count);

		qsort(arr,session->ghost_count,sizeof(struct LDrawDLSortedInstanceLink),compare_ghost_link);

		int run_start = 0;

		while (run_start < session->ghost_count)
		{
			int run_end = run_start + 1;
            while (run_end < session->ghost_count && arr[run_end].ghost_id == arr[run_start].ghost_id) {
                ++run_end;
            }

			int pass;
			for (pass = 0; pass < 2; ++pass)
			{
				BOOL isPrepass = (pass == 0);

				[renderEncoder setDepthStencilState:isPrepass ? defaultDepthState() : ghostBlendDepthState()];

				int i;
                for (i = run_start; i < run_end; ++i) {
                    drawDeferredInstance(renderEncoder, session, arr + i, isPrepass);
                }
			}

			run_start = run_end;
		}

		// Hand the encoder back the way we found it.
		[renderEncoder setDepthStencilState:defaultDepthState()];

		float noGhost = 1.0f;
		[renderEncoder setVertexBytes:&noGhost length:sizeof(noGhost) atIndex:BufferIndexGhostAlpha];
	}

	for (l = session->sorted_head; l; l = l->next)
		endDeferredUse(l->dl, &doomed_head);

	for (l = session->ghost_head; l; l = l->next)
		endDeferredUse(l->dl, &doomed_head);

	// The encoder keeps the buffers it was given until the GPU is done.
	while (doomed_head)
	{
		dl = doomed_head;
		doomed_head = dl->next_dl;
		LDrawDLDestroy(dl);
	}

	#if WANT_STATS
		printf("Immediate drawing: %d batches, %d vertices.\n",session->stats.num_btch_imm, session->stats.num_vert_imm);
		printf("Sorted drawing: %d batches, %d vertices.\n",session->stats.num_btch_srt, session->stats.num_vert_srt);
		printf("Attribute instancing: %d batches, %d instances, %d (%d) vertices.\n", session->stats.num_btch_att, session->stats.num_inst_att, session->stats.num_work_att, session->stats.num_vert_att);
		printf("Hardware instancing: %d batches, %d instances, %d (%d) vertices.\n", session->stats.num_btch_ins, session->stats.num_inst_ins, session->stats.num_work_ins, session->stats.num_vert_ins);
		printf("Working set estimate (MB): %zd\n", 
					(session->stats.num_vert_srt + 
					 session->stats.num_vert_imm + 
					 session->stats.num_work_ins +
					 session->stats.num_work_att) * VERT_STRIDE * sizeof(float) / (1024 * 1024));
	#endif

	// What is drawn after the session, such as drag handles, has no bias.
	if (session->wide_lines.line_pipeline)
		[renderEncoder setDepthBias:0.0f slopeScale:0.0f clamp:0.0f];

	// Finally done - all allocations for session (including our own obj) come from a BDP, so cleanup is quick.
	// Instance buffer remains to be reused.
	// DLs themselves live on beyond session.
	LDrawPoolDestroy(session->alloc);
	
} // end LDrawDLSessionDrawAndDestroy


//========== LDrawDLDraw =========================================================
//
// Purpose:	Draw a DL, or save it for later drawing.
//
// Notes:	This routine takes all of the current 'state' and draws or records
//			an instance.
//
//			Passing is_wire_frame as true will FORCE immediate drawing and disable
//			all of the instancing/sorting stuff.
//
// Parameters:
//          - ghost_id = non-zero when this DL belongs to a ghost, identifying
//			which one; every DL of one ghosted part shares an id.  See the ghost
//			pass in LDrawDLSessionDrawAndDestroy.
//			- ghost_alpha = scales the alpha of every fragment the DL produces,
//			baked-in mesh colors included.  1 for everything that is not a ghost.
//
//================================================================================
void LDrawDLDraw(id<MTLRenderCommandEncoder>	renderEncoder,
				 struct LDrawDLSession *		session,
				 struct LDrawDL *				dl,
				 struct LDrawTextureSpec *		spec,
				 const float 					cur_color[4],
				 const float 					cmp_color[4],
				 const float					transform[16],
				 BOOL							is_wire_frame,
				 int							ghost_id,
				 float							ghost_alpha)
{
	// A ghost gets its own pass: it is drawn like an ordinary part and blended
	// as a whole, so its interior does not show through the way a transparent
	// brick's does. Wireframe wins, since that is the selection cue -- and it
	// draws at full strength, because a faint cue is no cue.
	if (ghost_id != 0 && !is_wire_frame)
	{
		saveForDeferredDraw(session, dl, spec, cur_color, cmp_color, transform, ghost_id, ghost_alpha);
		return;
	}

	if (!is_wire_frame)
	{
		int want_sort = (dl->flags & dl_has_alpha) || ((dl->flags & dl_has_meta) && (cur_color[3] < 1.0f || cmp_color[3] < 1.0f));
		if (want_sort)
		{
			// Sort case.  We want sort if:
			// 1. There is alpha baked into our meshes permanently or
			// 2. Our mesh uses meta colors and the current meta colors have alpha.

			saveForDeferredDraw(session, dl, spec, cur_color, cmp_color, transform, 0, 1.0f);
			return;
		}

		if ((spec == NULL || spec->tex_obj == NULL) && (dl->flags & dl_has_tex) == 0)
		{
			// We can instance if:
			// 1. No texture is being applied to us AND
			// 2. There isn't any texturing baked into the DL.

			saveForInstanceDraw(session, dl, cur_color, cmp_color, transform, NO);
			return;
		}
	}

	if (is_wire_frame) {
		saveForInstanceDraw(session, dl, cur_color, cmp_color, transform, YES);
	} else {
		immediateDraw(renderEncoder, session, dl, spec, cur_color, cmp_color, transform, NO);
	}

} // end LDrawDLDraw
