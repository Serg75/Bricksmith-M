//
//  LDrawDisplayList.m
//  Bricksmith
//
//  Created by bsupnik on 11/12/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

@import MetalKit;
@import simd;

#include "MetalCommonDefinitions.h"

#import "LDrawDisplayList.h"
#import "LDrawCoreRenderer.h"
#import "LDrawBDPAllocator.h"
#import "LDrawShaderRenderer.h"
#import "MeshSmooth.h"
#import "MetalGPU.h"
#import "MetalUtilities.h"
#import "MatrixMath.h"

// This turns on normal smoothing.
#define WANT_SMOOTH 1

// This times smoothing of parts.
#define TIME_SMOOTHING 0

#if WANT_SMOOTH
static const uint32_t * idx_null = NULL;
#endif

// The number of float values in InstanceInput struct declared in Metal shader
const int InstanceInputLength = 24;
// The size in bytes of InstanceInput struct declared in Metal shader
const int InstanceInputStructSize = InstanceInputLength * sizeof(float);
// Number of samples for multisample anti-aliasing (MSAA)
const int MSAASampleCount = 4;


/*

	INSTANCING IMPLEMENTATION NOTES
	
	Instancing is just fancy talk for drawing one thing many times in some efficient way.  Instancing is a good fit for BrickSmith
	because we draw the same bricks over and over and over again.
	
	When we instance, we identify the 'per instance' data - that is, data that is different for every instance.  In the case of
	BrickSmith, the current/compliment color and transform are per instance data; the mesh and non-meta colors of the mesh are invariant.
	
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

	DEFERRED DARWING FOR Z SORTING
	
	When a DL does not have to be drawn immediately and has translucency, we always try to save it to the sorted list.
	
	Then when the session is destroyed, we sort all of these "sort-deferred" DLs by their local origin and draw back to front.
	This helps keep translucency looking good.

*/

#define WANT_STATS 0

#define VERT_STRIDE 10					// Stride of our vertices - we always write  X Y Z   NX NY NZ   R G B A
#define INST_CUTOFF 0					// Minimum instances to use hardware case, which has higher overhead to set up.
#define INST_MAX_COUNT (1024 * 128)		// Maximum instances to write per draw before going to immediate mode - avoids unbounded VRAM use.
#define INST_RING_BUFFER_COUNT 1		// Number of buffers to rotate for hardware instancing - doesn't actually help, it turns out.

enum {
	dl_has_alpha = 1,		// At least one prim in this DL has translucency.
	dl_has_meta = 2,		// At least one prim in this DL uses a meta-color and thus MIGHT pick up translucency from parent state during draw.
	dl_has_tex = 4,			// At least one real texture is used.
	dl_needs_destroy = 8	// Destroy after drawing - ptr is only around because it is queued!
};


struct InstanceData {
	Point4	transform_x;
	Point4	transform_y;
	Point4	transform_z;
	Point4	transform_w;
	Point4	color_current;
	Point4	color_compliment;
};


struct TexturePlaneData {
	Point4		planeS;
	Point4		planeT;
};

struct TexturePlaneData _noTexPlaneData = {.planeS = {0}, .planeT = {0}};

id<MTLTexture>	_clearTexture;


static void copy_vec3(float d[3], const float s[3]) { d[0] = s[0]; d[1] = s[1]; d[2] = s[2];			  }
static void copy_vec4(float d[4], const float s[4]) { d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3]; }

static id<MTLBuffer> inst_vbo_ring[INST_RING_BUFFER_COUNT] = { nil };
static int inst_ring_last = 0;


//========== DISPLAY LIST DATA STRUCTURES ========================================

// Per-texture mesh info. Texture spec plus the offset/count into a single buffer for the lines and tris to draw.
// This is used in a finished DL.
struct LDrawDLPerTex {
	struct LDrawTextureSpec	spec;
	uint32_t				line_off;
	uint32_t				line_count;
	uint32_t				cond_line_off;
	uint32_t				cond_line_count;
	uint32_t				tri_off;
	uint32_t				tri_count;
};

// DL draw instance: this stores one request to draw an un-textured DL for instancing.
// current color/compliment color, transform, and a next ptr to build a linked list.
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
	int						flags;				// See flags defs above.
	id<MTLBuffer> 			vertexBuffer;		// Single buffer containing all geometry in the DL.
#if WANT_SMOOTH
	id<MTLBuffer> 			indexBuffer;		// Single buffer containing all mesh indices.
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
	struct LDrawBDP *					alloc;					// Pool allocator for the session to rapidly save linked lists of 'stuff'.
	struct LDrawDL *					dl_head;				// Linked list of all DLs that will be instance-drawn, with count.
	int									dl_count;
	int									total_instance_count;	// Used in calculation the size of instance buffer

	struct LDrawDLSortedInstanceLink *	sorted_head;			// Linked list + count for DLs being drawn later to Z sort.
	int									sort_count;

	float								model_view[16];			// Model-view matrix, used to Z sort translucent objects.
	unsigned int						inst_ring;				// If using more than one instancing buffer, this tells which one we use.

	id<MTLTexture>						current_bound_texture;
};



//========== Structures for BUILDING a buffer =============================


// As we build our buffer, we keep sets of vertices in a linked list. When done
// we copy them into our buffer. The linked list lets us add vertices a little
// at a time without expensive array resizes. Since the linked list comes
// from a BDP locality is actually pretty good.
//
// Our link has a vertex count followed by VERT_STRIDE * vcount floats.
struct	LDrawDLBuilderVertexLink {
	struct LDrawDLBuilderVertexLink * next;
	int		vcount;
	float	data[0];
};


// Build structure per texture.  Textures are kept in a linked list during build
// since we don't know how many we will have.  Each type of drawing (line, cond_line, tri)
// is kept in a singly linked list of vertex links so that we can copy them consecutively when done.
struct LDrawDLBuilderPerTex {
	struct LDrawDLBuilderPerTex *		next;
	struct LDrawTextureSpec				spec;
	struct LDrawDLBuilderVertexLink *	tri_head;
	struct LDrawDLBuilderVertexLink *	tri_tail;
	struct LDrawDLBuilderVertexLink *	line_head;
	struct LDrawDLBuilderVertexLink *	line_tail;
	struct LDrawDLBuilderVertexLink *	cond_line_head;
	struct LDrawDLBuilderVertexLink *	cond_line_tail;
};


// LDrawBuilder: our build structure contains a BDP for temporary allocations and a
// linked list of textures (which in turn contain the geometry.  So the entire
// structure just accumulates data in a set of linked lists, then cleans and saves
// the data carefully when we are done.
struct	LDrawDLBuilder {
	int								flags;
	struct LDrawBDP *				alloc;
	struct LDrawDLBuilderPerTex *	head;
	struct LDrawDLBuilderPerTex *	cur;
};


// MARK: - Internal functions -

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
	if(spec && spec->tex_obj)
	{
		struct TexturePlaneData texPlaneData;
		texPlaneData.planeS = V4Make(spec->plane_s[0], spec->plane_s[1], spec->plane_s[2], spec->plane_s[3]);
		texPlaneData.planeT = V4Make(spec->plane_t[0], spec->plane_t[1], spec->plane_t[2], spec->plane_t[3]);

		[encoder setVertexBytes:&texPlaneData length:64 atIndex:BufferIndexTexturePlane];

		if (session->current_bound_texture != spec->tex_obj)
		{
			[encoder setFragmentTexture:spec->tex_obj atIndex:0];
			session->current_bound_texture = spec->tex_obj;
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

}//end setup_tex_spec


//========== compare_sorted_link =================================================
//
// Purpose:	Functor to compare two sorted instances by their "eval" value, which
//			is eye space Z right now. API fits C qsort.
//
//================================================================================
static int compare_sorted_link(const void * lhs, const void * rhs)
{
	const struct LDrawDLSortedInstanceLink * a = (const struct LDrawDLSortedInstanceLink *) lhs;
	const struct LDrawDLSortedInstanceLink * b = (const struct LDrawDLSortedInstanceLink *) rhs;
	return a->eval - b->eval;

}//end compare_sorted_link


//========== saveForSortDraw =====================================================
//
// Purpose:	Save DL for later sorting drawing.
//          We use sorting drawing for transparent parts.
//
//================================================================================
static void saveForSortDraw(struct LDrawDLSession *		session,
							struct LDrawDL *			dl,
							struct LDrawTextureSpec *	spec,
							const float 				cur_color[4],
							const float 				cmp_color[4],
							const float					transform[16])
{
#if WANT_STATS
	session->stats.num_btch_srt++;
	session->stats.num_vert_srt += dl->vrt_count;
#endif

	// Build a sorted link, copy the instance data to it, and link it up to our session for later processing.
	struct LDrawDLSortedInstanceLink * link = LDrawBDPAllocate(session->alloc, sizeof(struct LDrawDLSortedInstanceLink));
	link->next = session->sorted_head;
	session->sorted_head = link;
	link->dl = dl;
	memcpy(link->color,cur_color,sizeof(float)*4);
	memcpy(link->comp,cmp_color,sizeof(float)*4);
	memcpy(link->transform,transform,sizeof(float)*16);
	session->sort_count++;
	if(spec)
		memcpy((void*)&link->spec, (void*)spec, sizeof(struct LDrawTextureSpec));
	else
		memset((void*)&link->spec, 0, sizeof(struct LDrawTextureSpec));

}//end saveForSortDraw


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
	//assert(dl->next_dl == NULL || session->dl_head != NULL);

	// This is the first deferred instance for this DL - link this DL into our session so that we can find it later.
	if(dl->instance_head == NULL)
	{
		session->dl_count++;
		dl->next_dl = session->dl_head;
		session->dl_head = dl;
	}
	// Copy our instance data into a LDrawDLInstance and link that into the DL for later use.
	struct LDrawDLInstance * inst = (struct LDrawDLInstance *) LDrawBDPAllocate(session->alloc,sizeof(struct LDrawDLInstance));
	{
		if(dl->instance_head == NULL)
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

}//end saveForInstanceDraw


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

	struct InstanceData instData;
	instData.transform_x = V4Make(transform[0], transform[4], transform[8],  transform[12]);
	instData.transform_y = V4Make(transform[1], transform[5], transform[9],  transform[13]);
	instData.transform_z = V4Make(transform[2], transform[6], transform[10], transform[14]);
	instData.transform_w = V4Make(transform[3], transform[7], transform[11], transform[15]);
	copy_vec4((float *)&instData.color_current, cur_color);
	copy_vec4((float *)&instData.color_compliment, cmp_color);

	[renderEncoder setVertexBytes:&instData
						   length:sizeof(instData)
						  atIndex:BufferIndexPerInstanceData];

	assert(dl->tex_count > 0);

	// Bind our DL buffer and set up ptrs.
	[renderEncoder setVertexBuffer:dl->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];

	struct LDrawDLPerTex * tptr = dl->texes;

	if(is_wire_frame || (dl->tex_count == 1 && tptr->spec.tex_obj == nil && (spec == NULL || spec->tex_obj == nil)))
	{
		// Special case: wireframe or one untextured mesh - just draw.

		setup_tex_spec(NULL, session, renderEncoder);

		#if WANT_SMOOTH
		if(tptr->line_count)
			[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
									  indexCount:tptr->line_count
									   indexType:MTLIndexTypeUInt32
									 indexBuffer:dl->indexBuffer
							   indexBufferOffset:idx_null+tptr->line_off
								   instanceCount:1];

		if(tptr->cond_line_count)
			[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
									  indexCount:tptr->cond_line_count
									   indexType:MTLIndexTypeUInt32
									 indexBuffer:dl->indexBuffer
							   indexBufferOffset:idx_null+tptr->cond_line_off
								   instanceCount:1];
		#else
		if(tptr->line_count)
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
		for(t = 0; t < dl->tex_count; ++t, ++tptr)
		{
			if(tptr->spec.tex_obj)
			{
				setup_tex_spec(&tptr->spec, session, renderEncoder);
			}
			else
				setup_tex_spec(spec, session, renderEncoder);

			#if WANT_SMOOTH
			if(tptr->line_count)
				[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
										  indexCount:tptr->line_count
										   indexType:MTLIndexTypeUInt32
										 indexBuffer:dl->indexBuffer
								   indexBufferOffset:idx_null+tptr->line_off
									   instanceCount:1];

			if(tptr->tri_count)
				[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
										  indexCount:tptr->tri_count
										   indexType:MTLIndexTypeUInt32
										 indexBuffer:dl->indexBuffer
								   indexBufferOffset:idx_null+tptr->tri_off];
			#else
			if(tptr->line_count)
				[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
								  vertexStart:tptr->line_off
								  vertexCount:tptr->line_count];

			if(tptr->tri_count)
				[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
								  vertexStart:tptr->tri_off
								  vertexCount:tptr->tri_count];
			#endif
		}

		setup_tex_spec(spec, session, renderEncoder);
	}
}//end immediateDraw


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
		inst_data[0] = inst->transform[0];		// Note: copy on transpose to get matrix into right form!
		inst_data[1] = inst->transform[4];
		inst_data[2] = inst->transform[8];
		inst_data[3] = inst->transform[12];
		inst_data[4] = inst->transform[1];
		inst_data[5] = inst->transform[5];
		inst_data[6] = inst->transform[9];
		inst_data[7] = inst->transform[13];
		inst_data[8] = inst->transform[2];
		inst_data[9] = inst->transform[6];
		inst_data[10] = inst->transform[10];
		inst_data[11] = inst->transform[14];
		inst_data[12] = inst->transform[3];
		inst_data[13] = inst->transform[7];
		inst_data[14] = inst->transform[11];
		inst_data[15] = inst->transform[15];
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
#endif
		segment->dl = &dl->texes[0];
	}

}//end writeHardwareInstanceData


// MARK: - Display list creation API -


//========== LDrawDLBuilderCreate ================================================
//
// Purpose:	Create a new builder capable of accumulating DL data.
//
//================================================================================
struct LDrawDLBuilder * LDrawDLBuilderCreate()
{
	// All allocs for the builder come from one pool.
	struct LDrawBDP * alloc = LDrawBDPCreate();

	// Build one tex struct now for the untextured set of meshes, which are the default state.
	struct LDrawDLBuilderPerTex * untex = (struct LDrawDLBuilderPerTex *) LDrawBDPAllocate(alloc,sizeof(struct LDrawDLBuilderPerTex));
	memset((void*)untex, 0, sizeof(struct LDrawDLBuilderPerTex));

	struct LDrawDLBuilder * bld = (struct LDrawDLBuilder *) LDrawBDPAllocate(alloc,sizeof(struct LDrawDLBuilder));
	bld->cur = bld->head = untex;
	
	bld->alloc = alloc;
	bld->flags = 0;
	
	return bld;

}//end LDrawDLBuilderCreate


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
	for(s = ctx->head; s; s = s->next)
	{
		if(s->tri_head || s->line_head || s->cond_line_head)
			++total_texes;

		for(l = s->tri_head; l; l = l->next)
		{
			total_tris++;
		}
		for(l = s->line_head; l; l = l->next)
		{
			total_lines++;
		}
		for(l = s->cond_line_head; l; l = l->next)
		{
			total_cond_lines++;
		}
	}

	// No non-empty textures?  Bail out early - nuke our
	// context and get out.  Client code knows we get NO DL, rather than
	// an empty one.
	if(total_texes == 0)
	{
		LDrawBDPDestroy(ctx->alloc);
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
	for(s = ctx->head; s; s = s->next)
	{
		if(s->tri_head == NULL && s->line_head == NULL && s->cond_line_head == NULL)
			continue;

		if(s->spec.tex_obj != nil)
			dl->flags |= dl_has_tex;

		for(l = s->tri_head; l; l = l->next)
		{
			add_face(M,
				l->data, l->data+10,l->data+20,NULL,
				l->data+6,ti);
		}

		++ti;
	}

	ti = 0;
	for(s = ctx->head; s; s = s->next)
	{
		if(s->tri_head == NULL && s->line_head == NULL && s->cond_line_head == NULL)
			continue;

		if(s->spec.tex_obj != nil)
			dl->flags |= dl_has_tex;

		for(l = s->line_head; l; l = l->next)
		{
			add_face(M,l->data,l->data+10,NULL,NULL,l->data+6,ti);
		}

		for(l = s->cond_line_head; l; l = l->next)
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

	id<MTLBuffer> vertexBuffer = [device newBufferWithLength:total_vertices * sizeof(float) * VERT_STRIDE options:MTLResourceStorageModeShared];
	vertexBuffer.label = @"Vertex buffer";

	id<MTLBuffer> indexBuffer = [device newBufferWithLength:total_indices * sizeof(uint32_t) options:MTLResourceStorageModeShared];
	indexBuffer.label = @"Index buffer";

	dl->vertexBuffer = vertexBuffer;
	dl->indexBuffer = indexBuffer;

	volatile float * vertex_ptr = (volatile float *)[dl->vertexBuffer contents];
	volatile uint32_t * index_ptr = (volatile uint32_t *)[dl->indexBuffer contents];


	// Grab variable size arrays for the start/offsets of each sub-part of our big pile-o-mesh...
	// the mesher will give us back our tris sorted by texture.

	int * line_start	= (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * line_count	= (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * cond_line_start = (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * cond_line_count = (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * tri_start		= (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * tri_count		= (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * quad_start	= (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);
	int * quad_count	= (int *) LDrawBDPAllocate(ctx->alloc, sizeof(int) * total_texes);

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

	ti = 0;

	for(s = ctx->head; s; s = s->next)
	{
		if(s->tri_head == NULL && s->line_head == NULL && s->cond_line_head == NULL)
			continue;

		memcpy((void*)&cur_tex->spec, (void*)&s->spec, sizeof(struct LDrawTextureSpec));

		cur_tex->line_off			= line_start[ti];
		cur_tex->cond_line_off		= cond_line_start[ti];
		cur_tex->tri_off			= tri_start[ti];
		cur_tex->line_count			= line_count[ti];
		cur_tex->cond_line_count	= cond_line_count[ti];
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
	LDrawBDPDestroy(ctx->alloc);

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
	for(s = ctx->head; s; s = s->next)
	{
		if(s->tri_head || s->line_head)
			++total_texes;
		for(l = s->tri_head; l; l = l->next)
			total_vertices += l->vcount;
		for(l = s->line_head; l; l = l->next)
			total_vertices += l->vcount;
	}

	// No non-empty textures?  Bail out early - nuke our
	// context and get out.  Client code knows we get NO DL, rather than
	// an empty one.
	if(total_texes == 0)
	{
		LDrawBDPDestroy(ctx->alloc);
		return NULL;
	}

	// Malloc DL structure with extra storage for variable-sized tex array.
	struct LDrawDL * dl = (struct LDrawDL *) malloc(sizeof(struct LDrawDL) + sizeof(struct LDrawDLPerTex) * total_texes);

	// All per-session linked list ptrs start null.
	dl->next_dl = NULL;
	dl->instance_head = NULL;
	dl->instance_tail = NULL;
	dl->instance_count = 0;

	dl->tex_count = total_texes;

	#if WANT_STATS
	dl->vrt_count = total_vertices;
	#endif

	// Generate and map a buffer for our mesh data.

	id<MTLBuffer> vertexBuffer = [MetalGPU.device newBufferWithLength:total_vertices * sizeof(float) * VERT_STRIDE options:MTLResourceStorageModeShared];
	vertexBuffer.label = @"Vertex buffer";

	dl->vertexBuffer = vertexBuffer;

	volatile float * buf_ptr = (volatile float *)[dl->vertexBuffer contents];

	int cur_v = 0;
	struct LDrawDLPerTex * cur_tex = dl->texes;
	dl->flags = ctx->flags;

	// Now: walk our building textures - for each non-empty one, we will copy it into
	// the tex array and push its vertices.
	for(s = ctx->head; s; s = s->next)
	{
		if(s->tri_head == NULL && s->line_head == NULL)
			continue;
		if(s->spec.tex_obj != nil)
			dl->flags |= dl_has_tex;
		memcpy(&cur_tex->spec, &s->spec, sizeof(struct LDrawTextureSpec));
		cur_tex->line_off = cur_v;
		cur_tex->line_count = 0;

		// These loops copy the actual geometry (in linked lists of data) into the buffer.

		for(l = s->line_head; l; l = l->next)
		{
			memcpy(buf_ptr,l->data,VERT_STRIDE * sizeof(float) * l->vcount);
			cur_tex->line_count += l->vcount;
			cur_v += l->vcount;
			buf_ptr += (VERT_STRIDE * l->vcount);
		}

		cur_tex->tri_off = cur_v;
		cur_tex->tri_count = 0;

		for(l = s->tri_head; l; l = l->next)
		{
			memcpy(buf_ptr,l->data,VERT_STRIDE * sizeof(float) * l->vcount);
			cur_tex->tri_count += l->vcount;
			cur_v += l->vcount;
			buf_ptr += (VERT_STRIDE * l->vcount);
		}

		++cur_tex;
	}

	// Release the BDP that contains all of the build-related junk.
	LDrawBDPDestroy(ctx->alloc);

	return dl;

#endif
}//end LDrawDLBuilderFinish



//========== LDrawDLDestroy ======================================================
//
// Purpose: free a display list - release GL and system memory.
//
//================================================================================
void LDrawDLDestroy(struct LDrawDL * dl)
{
	if(dl->instance_head != NULL)
	{
		// Special case: if our DL is destroyed WHILE a session is using it for
		// deferred drawing, we do NOT destroy it - we mark it for destruction
		// later and the session nukes it.  This is needed for the case where
		// client code creates a DL, draws it, and immediately destroys it, as
		// a silly way to get 'immediate' drawing.  In this case, the session
		// may have intentionally deferred the DL.
		dl->flags |= dl_needs_destroy;
		return;
	}
	// Make sure that no instances from a session are queued to this list; if we
	// are in Q and run now, we'll cause seg faults later.  This assert hits
	// when: (1) we build a temp DL and don't mark it as temp or (2) we for some
	// reason inval a DL mid-draw, which is usually a sign of coding error.
	assert(dl->instance_head == NULL);

	free(dl);

}//end LDrawDLDestroy


// MARK: - Display list mesh accumulation APIs -


//========== LDrawDLBuilderSetTex ================================================
//
// Purpose:	Change the current texture we are adding geometry to in a builder.
//
//================================================================================
void LDrawDLBuilderSetTex(struct LDrawDLBuilder * ctx, struct LDrawTextureSpec * spec)
{
	struct LDrawDLBuilderPerTex * prev = ctx->head;
	
	// Walk "cur" down our texture list, stopping if we have a hit.
	for(ctx->cur = ctx->head; ctx->cur; ctx->cur = ctx->cur->next)
	{
		if(memcmp(spec,&ctx->cur->spec,sizeof(struct LDrawTextureSpec)) == 0)
			break;
		prev = ctx->cur;
	}
	
	if(ctx->cur == NULL)
	{
		// If we get here, we have never seen this texture before in this builder and
		// we need to allocate a new per-texture chunk of build state.
		struct LDrawDLBuilderPerTex * new_tex = (struct LDrawDLBuilderPerTex *) LDrawBDPAllocate(ctx->alloc,sizeof(struct LDrawDLBuilderPerTex));
		memset((void*)new_tex, 0, sizeof(struct LDrawDLBuilderPerTex));
		memcpy((void*)&new_tex->spec, (void*)spec, sizeof(struct LDrawTextureSpec));
		prev->next = new_tex;
		ctx->cur = new_tex;
	}
	
}//end LDrawDLBuilderSetTex


//========== LDrawDLBuilderAddTri ================================================
//
// Purpose: Add one triangle to our DL using the current texture.
//
// Notes:	This routine 'sniffs' the alpha as it goes by and keeps the DL flags
//			correct - this is how a DL "knows" if it is translucent.
//
//			We accumulate the tri by allocating a 3-vertex DL link and queueing it
//			onto the triangle list for the current texture.
//
//================================================================================
void LDrawDLBuilderAddTri(struct LDrawDLBuilder * ctx, const float v[9], float n[3], float c[4])
{
	// Alpha = 0 means meta color.  0 < Alpha < 1 means translucency.	
		 if(c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if(c[3] != 1.0f)	ctx->flags |= dl_has_alpha;
	
	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawBDPAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 3);
	nl->next = NULL;
	nl->vcount = 3;
	for(i = 0; i < 3; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);	// Vertex data is per vertex.
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );	// But color and norm are for the whole tri, for now.  So we replicate it out to get
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );	// a uniform DL.
	}
	
	if(ctx->cur->tri_tail)
	{
		ctx->cur->tri_tail->next = nl;
		ctx->cur->tri_tail = nl;
	}
	else
	{
		ctx->cur->tri_head = nl;
		ctx->cur->tri_tail = nl;
	}

}//end LDrawDLBuilderAddTri


//========== LDrawDLBuilderAddQuad ===============================================
//
// Purpose:	Add one quad to the current DL builder in the current texture.
//
//================================================================================
void LDrawDLBuilderAddQuad(struct LDrawDLBuilder * ctx, const float v[12], float n[3], float c[4])
{
		 if(c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if(c[3] != 1.0f)	ctx->flags |= dl_has_alpha;

	// Convert quad to triangles

	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawBDPAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 3);
	nl->next = NULL;
	nl->vcount = 3;
	for(i = 0; i < 3; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);	// Vertex data is per vertex.
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );	// But color and norm are for the whole tri, for now.  So we replicate it out to get
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );	// a uniform DL.
	}
	
	if(ctx->cur->tri_tail)
	{
		ctx->cur->tri_tail->next = nl;
		ctx->cur->tri_tail = nl;
	}
	else
	{
		ctx->cur->tri_head = nl;
		ctx->cur->tri_tail = nl;
	}


	nl = (struct LDrawDLBuilderVertexLink *) LDrawBDPAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 3);
	nl->next = NULL;
	nl->vcount = 3;
	for(i = 0; i < 3; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );	// But color and norm are for the whole tri, for now.  So we replicate it out to get
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );	// a uniform DL.
	}

	copy_vec3(nl->data+VERT_STRIDE*0  ,v  );	// Vertex data is per vertex.
	copy_vec3(nl->data+VERT_STRIDE*1  ,v+6);	// Vertex data is per vertex.
	copy_vec3(nl->data+VERT_STRIDE*2  ,v+9);	// Vertex data is per vertex.
	
	if(ctx->cur->tri_tail)
	{
		ctx->cur->tri_tail->next = nl;
		ctx->cur->tri_tail = nl;
	}
	else
	{
		ctx->cur->tri_head = nl;
		ctx->cur->tri_tail = nl;
	}

}//end LDrawDLBuilderAddQuad


//========== LDrawDLBuilderAddLine ===============================================
//
// Purpose:	Add one line to the current DL builder in the current texture.
//
//================================================================================
void LDrawDLBuilderAddLine(struct LDrawDLBuilder * ctx, const float v[6], float n[3], float c[4])
{
		 if(c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if(c[3] != 1.0f)	ctx->flags |= dl_has_alpha;

	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawBDPAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 2);
	nl->next = NULL;
	nl->vcount = 2;
	for(i = 0; i < 2; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );
	}
	
	if(ctx->cur->line_tail)
	{
		ctx->cur->line_tail->next = nl;
		ctx->cur->line_tail = nl;
	}
	else
	{
		ctx->cur->line_head = nl;
		ctx->cur->line_tail = nl;
	}
	
}//end LDrawDLBuilderAddLine


//========== LDrawDLBuilderAddCondLine ===========================================
//
// Purpose:	Add one conditional line to the current DL builder in the current texture.
//
//================================================================================
void LDrawDLBuilderAddCondLine(struct LDrawDLBuilder * ctx, const float v[12], float n[3], float c[4])
{
		 if(c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if(c[3] != 1.0f)	ctx->flags |= dl_has_alpha;

	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawBDPAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 4);
	nl->next = NULL;
	nl->vcount = 4;
	for(i = 0; i < 4; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );
	}
	
	if(ctx->cur->cond_line_tail)
	{
		ctx->cur->cond_line_tail->next = nl;
		ctx->cur->cond_line_tail = nl;
	}
	else
	{
		ctx->cur->cond_line_head = nl;
		ctx->cur->cond_line_tail = nl;
	}
	
}//end LDrawDLBuilderAddCondLine


// MARK: - Session/drawing APIs -


//========== LDrawDLSessionCreate ================================================
//
// Purpose:	Create a new drawing session.  Drawing sessions sit entirely in a BDP
//			for speed - most of our linked lists are just NULL.
//
//================================================================================
struct LDrawDLSession * LDrawDLSessionCreate(const float model_view[16])
{
	struct LDrawBDP * alloc = LDrawBDPCreate();
	struct LDrawDLSession * session = (struct LDrawDLSession *) LDrawBDPAllocate(alloc,sizeof(struct LDrawDLSession));
	session->alloc = alloc;
	session->dl_head = NULL;
	session->dl_count = 0;
	session->total_instance_count = 0;
	session->sorted_head = NULL;
	session->sort_count = 0;
	#if WANT_STATS
	memset(&session->stats,0,sizeof(session->stats));
	#endif
	memcpy(session->model_view,model_view,sizeof(float)*16);
	session->inst_ring = inst_ring_last;
	// each session picks up a new buffer in the ring of instance buffers.
	inst_ring_last = (inst_ring_last+1)%INST_RING_BUFFER_COUNT;
	return session;
}//end LDrawDLSessionCreate


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

	// INSTANCED DRAWING CASE

	if(session->dl_head)
	{
		// Build a var-sized array of segments to record our instances for hardware instancing.  We may not need it for every DL but that's okay.
		// We need twice the space because each DL can have both wireframe and non-wireframe instances that need to be drawn separately.
		struct LDrawDLSegment * segments = (struct LDrawDLSegment *) LDrawBDPAllocate(session->alloc, sizeof(struct LDrawDLSegment) * session->dl_count * 2);
		struct LDrawDLSegment * cur_segment = segments;

		// If we do not yet have a buffer for instancing, build one now.
//		if(inst_vbo_ring[session->inst_ring] == nil)
		{
			id<MTLBuffer> instanceBuffer = [MetalGPU.device newBufferWithLength:session->total_instance_count * InstanceInputStructSize
																		options:MTLResourceStorageModeManaged];
			instanceBuffer.label = @"Instance buffer";
			inst_vbo_ring[session->inst_ring] = instanceBuffer;
		}

			
		// Map our instance buffer so we can write instancing data.
		float * inst_base = (float *) [inst_vbo_ring[session->inst_ring] contents];
		float * inst_data = inst_base;
		int 	inst_count = 0;
		int		inst_remain = INST_MAX_COUNT;

		// Main loop 1: we will walk every instanced DL and either accumulate its instances (for hardware instancing)
		// or just draw now (for immediate instancing).
		while(session->dl_head)
		{
			dl = session->dl_head;

			if(dl->instance_count >= INST_CUTOFF && inst_remain >= dl->instance_count)
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
				for(inst = dl->instance_head; inst; inst = inst->next)
				{
					struct InstanceData instData;
					instData.transform_x = V4Make(inst->transform[0], inst->transform[4], inst->transform[8],  inst->transform[12]);
					instData.transform_y = V4Make(inst->transform[1], inst->transform[5], inst->transform[9],  inst->transform[13]);
					instData.transform_z = V4Make(inst->transform[2], inst->transform[6], inst->transform[10], inst->transform[14]);
					instData.transform_w = V4Make(inst->transform[3], inst->transform[7], inst->transform[11], inst->transform[15]);
					copy_vec4((float *)&instData.color_current, inst->color);
					copy_vec4((float *)&instData.color_compliment, inst->comp);

					[renderEncoder setVertexBytes:&instData
										   length:sizeof(instData)
										  atIndex:BufferIndexPerInstanceData];

					struct LDrawDLPerTex * tptr = dl->texes;

					setup_tex_spec(NULL, session, renderEncoder);

					#if WANT_SMOOTH
					if(tptr->line_count)
						[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
												  indexCount:tptr->line_count
												   indexType:MTLIndexTypeUInt32
												 indexBuffer:dl->indexBuffer
										   indexBufferOffset:idx_null+tptr->line_off];

					if(tptr->tri_count)
						[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
												  indexCount:tptr->tri_count
												   indexType:MTLIndexTypeUInt32
												 indexBuffer:dl->indexBuffer
										   indexBufferOffset:idx_null+tptr->tri_off
										   instanceCount:1];
					#else
					if(tptr->line_count)
						[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
										  vertexStart:tptr->line_off
										  vertexCount:tptr->line_count];

					if(tptr->tri_count)
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
			if(dl->flags & dl_needs_destroy)
			{
				LDrawDLDestroy(dl);
			}
			else
			{
				dl->next_dl = NULL;
			}
		}

		[inst_vbo_ring[session->inst_ring] didModifyRange:NSMakeRange(0, inst_count * InstanceInputStructSize)];

		// Hardware instancing

		if(segments != cur_segment)
		{
			// Main loop 2 over DLs - for each DL that had hw-instances we built a segment
			// in our array.  Bind the DL itself, as well as the instance pointers, and do an instanced-draw.

			setup_tex_spec(NULL, session, renderEncoder);

			[renderEncoder setVertexBuffer:inst_vbo_ring[session->inst_ring] offset:0 atIndex:BufferIndexPerInstanceData];

			struct LDrawDLSegment * s;
			for(s = segments; s < cur_segment; ++s)
			{
				[renderEncoder setVertexBuffer:s->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];
				[renderEncoder setVertexBufferOffset:s->inst_base atIndex:BufferIndexPerInstanceData];

				#if WANT_SMOOTH	
				if(s->dl->line_count)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
											  indexCount:s->dl->line_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:s->indexBuffer
									   indexBufferOffset:idx_null+s->dl->line_off
										   instanceCount:s->inst_count];

				if(s->dl->cond_line_count && s->is_wireframe)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
											  indexCount:s->dl->cond_line_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:s->indexBuffer
									   indexBufferOffset:idx_null+s->dl->cond_line_off
										   instanceCount:s->inst_count];

				if(s->dl->tri_count && !s->is_wireframe)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
											  indexCount:s->dl->tri_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:s->indexBuffer
									   indexBufferOffset:idx_null+s->dl->tri_off
										   instanceCount:s->inst_count];
				#else
				if(s->dl->line_count)
				   [renderEncoder drawPrimitives:MTLPrimitiveTypeLine
									 vertexStart:s->dl->line_off
									 vertexCount:s->dl->line_count
								   instanceCount:s->inst_count];

				if(s->dl->tri_count)
					[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
									  vertexStart:s->dl->tri_off
									  vertexCount:s->dl->tri_count
									instanceCount:s->inst_count];
				#endif
			}
		}
	}

	// MAIN LOOP 3: sorted deferred drawing (!)
	// transparent parts

	struct LDrawDLSortedInstanceLink * l;
	if(session->sorted_head)
	{
		// If we have any sorting to do, allocate an array of the size of all sorted geometry for sorting purposes.
		struct LDrawDLSortedInstanceLink * arr = (struct LDrawDLSortedInstanceLink *) LDrawBDPAllocate(session->alloc,sizeof(struct LDrawDLSortedInstanceLink) * session->sort_count);
		struct LDrawDLSortedInstanceLink * p = arr;		
		
		// Copy each sorted instance into our array.  "Eval" is the measurement of distance - calculate eye-space Z and use that.
		for(l = session->sorted_head; l; l = l->next)
		{
			memcpy((void*)p, (void*)l, sizeof(struct LDrawDLSortedInstanceLink));

			simd_float4x4 modelView = simd_matrix_from_array(session->model_view);
			simd_float4 v = simd_make_float4(l->transform[12],
											 l->transform[13],
											 l->transform[14], 1.0f);

			simd_float4 v_eye = simd_mul(modelView, v);

			p->eval = v_eye.z;
			++p;
		}
		
		// Now: sort our array ascending to get far to near in eye space.
		qsort(arr,session->sort_count,sizeof(struct LDrawDLSortedInstanceLink),compare_sorted_link);

		struct InstanceData instData;

		// NOW we can walk our sorted array and draw each brick, 1x1.  This code is a rehash of the "draw now" 
		// code in LDrawDLDraw and could be factored.
		l = arr;
		int lc;
		for(lc = 0; lc < session->sort_count; ++lc)
		{
			instData.transform_x = V4Make(l->transform[0], l->transform[4], l->transform[8],  l->transform[12]);
			instData.transform_y = V4Make(l->transform[1], l->transform[5], l->transform[9],  l->transform[13]);
			instData.transform_z = V4Make(l->transform[2], l->transform[6], l->transform[10], l->transform[14]);
			instData.transform_w = V4Make(l->transform[3], l->transform[7], l->transform[11], l->transform[15]);
			copy_vec4((float *)&instData.color_current, l->color);
			copy_vec4((float *)&instData.color_compliment, l->comp);

			[renderEncoder setVertexBytes:&instData
								   length:sizeof(instData)
								  atIndex:BufferIndexPerInstanceData];

			dl = l->dl;
			[renderEncoder setVertexBuffer:dl->vertexBuffer offset:0 atIndex:BufferIndexInstanceInvariantData];

			struct LDrawDLPerTex * tptr = dl->texes;
			
			int t;
			for(t = 0; t < dl->tex_count; ++t, ++tptr)
			{
				if(tptr->spec.tex_obj)
				{
					setup_tex_spec(&tptr->spec, session, renderEncoder);
				}
				else 
					setup_tex_spec(&l->spec, session, renderEncoder);

				#if WANT_SMOOTH
				if(tptr->line_count)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
											  indexCount:tptr->line_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:dl->indexBuffer
									   indexBufferOffset:idx_null+tptr->line_off
										   instanceCount:1];

				if(tptr->tri_count)
					[renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
											  indexCount:tptr->tri_count
											   indexType:MTLIndexTypeUInt32
											 indexBuffer:dl->indexBuffer
									   indexBufferOffset:idx_null+tptr->tri_off
										   instanceCount:1];
				#else
				if(tptr->line_count)
					[renderEncoder drawPrimitives:MTLPrimitiveTypeLine
									  vertexStart:tptr->line_off
									  vertexCount:tptr->line_count];

				if(tptr->tri_count)
					[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
									  vertexStart:tptr->tri_off
									  vertexCount:tptr->tri_count];
				#endif
			}
			++l;
		}
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
	
	// Finally done - all allocations for session (including our own obj) come from a BDP, so cleanup is quick.  
	// Instance buffer remains to be reused.
	// DLs themselves live on beyond session.
	LDrawBDPDestroy(session->alloc);
	
}//end LDrawDLSessionDrawAndDestroy


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
//================================================================================
void LDrawDLDraw(id<MTLRenderCommandEncoder>	renderEncoder,
				 struct LDrawDLSession *		session,
				 struct LDrawDL *				dl,
				 struct LDrawTextureSpec *		spec,
				 const float 					cur_color[4],
				 const float 					cmp_color[4],
				 const float					transform[16],
				 BOOL							is_wire_frame)
{
	if(!is_wire_frame)
	{
		int want_sort = (dl->flags & dl_has_alpha) || ((dl->flags & dl_has_meta) && (cur_color[3] < 1.0f || cmp_color[3] < 1.0f));
		if(want_sort)
		{
			// Sort case.  We want sort if:
			// 1. There is alpha baked into our meshes permanently or
			// 2. Our mesh uses meta colors and the current meta colors have alpha.

			saveForSortDraw(session, dl, spec, cur_color, cmp_color, transform);
			return;
		}

		if((spec == NULL || spec->tex_obj == nil) && (dl->flags & dl_has_tex) == 0)
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

}//end LDrawDLDraw
