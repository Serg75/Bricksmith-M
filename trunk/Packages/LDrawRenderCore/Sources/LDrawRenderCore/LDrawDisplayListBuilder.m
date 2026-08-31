//==============================================================================
//
//  File:       LDrawDisplayListBuilder.m
//  Package:    LDrawRenderCore
//
//  Purpose:    Mesh accumulation shared by the Metal and OpenGL display lists.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawRenderCore/LDrawDisplayListBuilder.h>

#import <LDrawRenderCore/LDrawDisplayList.h>


//========== supported_primitives ================================================
//
// Purpose:	Ask the linked renderer once what its display lists can carry, then
//			remember the answer - this is consulted for every quad we add.
//
//================================================================================
static int	supported_primitives(void)
{
	static int supported = -1;
	if (supported == -1)
		supported = LDrawDLSupportedPrimitives();
	return supported;

} // end supported_primitives


//========== LDrawDLBuilderCreate ================================================
//
// Purpose:	Create a new builder capable of accumulating DL data.
//
//================================================================================
struct LDrawDLBuilder * LDrawDLBuilderCreate(void)
{
	// All allocs for the builder come from one pool.
	struct LDrawPool * alloc = LDrawPoolCreate();

	// Build one tex struct now for the untextured set of meshes, which are the default state.
	struct LDrawDLBuilderPerTex * untex = (struct LDrawDLBuilderPerTex *) LDrawPoolAllocate(alloc,sizeof(struct LDrawDLBuilderPerTex));
	memset((void*)untex, 0, sizeof(struct LDrawDLBuilderPerTex));

	struct LDrawDLBuilder * bld = (struct LDrawDLBuilder *) LDrawPoolAllocate(alloc,sizeof(struct LDrawDLBuilder));
	bld->cur = bld->head = untex;
	
	bld->alloc = alloc;
	bld->flags = 0;
	
	return bld;

} // end LDrawDLBuilderCreate


//========== LDrawDLBuilderSetTex ================================================
//
// Purpose:	Change the current texture we are adding geometry to in a builder.
//
//================================================================================
void LDrawDLBuilderSetTex(struct LDrawDLBuilder * ctx, struct LDrawTextureSpec * spec)
{
	struct LDrawDLBuilderPerTex * prev = ctx->head;
	
	// Walk "cur" down our texture list, stopping if we have a hit.
	for (ctx->cur = ctx->head; ctx->cur; ctx->cur = ctx->cur->next)
	{
		if (memcmp(spec,&ctx->cur->spec,sizeof(struct LDrawTextureSpec)) == 0)
			break;
		prev = ctx->cur;
	}
	
	if (ctx->cur == NULL)
	{
		// If we get here, we have never seen this texture before in this builder and
		// we need to allocate a new per-texture chunk of build state.
		struct LDrawDLBuilderPerTex * new_tex = (struct LDrawDLBuilderPerTex *) LDrawPoolAllocate(ctx->alloc,sizeof(struct LDrawDLBuilderPerTex));
		memset((void*)new_tex, 0, sizeof(struct LDrawDLBuilderPerTex));
		memcpy((void*)&new_tex->spec, (void*)spec, sizeof(struct LDrawTextureSpec));
		prev->next = new_tex;
		ctx->cur = new_tex;
	}
	
} // end LDrawDLBuilderSetTex


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
		 if (c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if (c[3] != 1.0f)	ctx->flags |= dl_has_alpha;
	
	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawPoolAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 3);
	nl->next = NULL;
	nl->vcount = 3;
	for (i = 0; i < 3; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);	// Vertex data is per vertex.
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );	// But color and norm are for the whole tri, for now.  So we replicate it out to get
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );	// a uniform DL.
	}
	
	if (ctx->cur->tri_tail)
	{
		ctx->cur->tri_tail->next = nl;
		ctx->cur->tri_tail = nl;
	}
	else
	{
		ctx->cur->tri_head = nl;
		ctx->cur->tri_tail = nl;
	}

} // end LDrawDLBuilderAddTri


//========== add_quad_as_tris ====================================================
//
// Purpose:	Store a quad as the two triangles that cover it, for a backend with
//			no quad primitive of its own.
//
//================================================================================
static void add_quad_as_tris(struct LDrawDLBuilder * ctx, const float v[12], float n[3], float c[4])
{
	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawPoolAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 3);
	nl->next = NULL;
	nl->vcount = 3;
	for (i = 0; i < 3; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);	// Vertex data is per vertex.
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );	// But color and norm are for the whole tri, for now.  So we replicate it out to get
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );	// a uniform DL.
	}
	
	if (ctx->cur->tri_tail)
	{
		ctx->cur->tri_tail->next = nl;
		ctx->cur->tri_tail = nl;
	}
	else
	{
		ctx->cur->tri_head = nl;
		ctx->cur->tri_tail = nl;
	}

	nl = (struct LDrawDLBuilderVertexLink *) LDrawPoolAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 3);
	nl->next = NULL;
	nl->vcount = 3;
	for (i = 0; i < 3; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i+3,n);	// But color and norm are for the whole tri, for now.  So we replicate it out to get
		copy_vec4(nl->data+VERT_STRIDE*i+6,c);	// a uniform DL.
	}

	copy_vec3(nl->data+VERT_STRIDE*0  ,v  );	// Vertex data is per vertex.
	copy_vec3(nl->data+VERT_STRIDE*1  ,v+6);	// Vertex data is per vertex.
	copy_vec3(nl->data+VERT_STRIDE*2  ,v+9);	// Vertex data is per vertex.
	
	if (ctx->cur->tri_tail)
	{
		ctx->cur->tri_tail->next = nl;
		ctx->cur->tri_tail = nl;
	}
	else
	{
		ctx->cur->tri_head = nl;
		ctx->cur->tri_tail = nl;
	}

} // end add_quad_as_tris


//========== add_quad_as_quad ====================================================
//
// Purpose:	Store a quad whole, for a backend that can draw one.  That is half
//			the vertices of the split form, which is what makes it worth having
//			for vertex-bound big models.
//
//================================================================================
static void add_quad_as_quad(struct LDrawDLBuilder * ctx, const float v[12], float n[3], float c[4])
{
	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawPoolAllocate(
												ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 4);
	nl->next = NULL;
	nl->vcount = 4;
	for (i = 0; i < 4; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );
	}
	
	if (ctx->cur->quad_tail)
	{
		ctx->cur->quad_tail->next = nl;
		ctx->cur->quad_tail = nl;
	}
	else
	{
		ctx->cur->quad_head = nl;
		ctx->cur->quad_tail = nl;
	}

} // end add_quad_as_quad


//========== LDrawDLBuilderAddQuad ===============================================
//
// Purpose:	Add one quad to the current DL builder in the current texture.
//
//================================================================================
void LDrawDLBuilderAddQuad(struct LDrawDLBuilder * ctx, const float v[12], float n[3], float c[4])
{
		 if (c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if (c[3] != 1.0f)	ctx->flags |= dl_has_alpha;

	if (supported_primitives() & dl_supports_quads)
		add_quad_as_quad(ctx,v,n,c);
	else
		add_quad_as_tris(ctx,v,n,c);

} // end LDrawDLBuilderAddQuad


//========== LDrawDLBuilderAddLine ===============================================
//
// Purpose:	Add one line to the current DL builder in the current texture.
//
//================================================================================
void LDrawDLBuilderAddLine(struct LDrawDLBuilder * ctx, const float v[6], float n[3], float c[4])
{
		 if (c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if (c[3] != 1.0f)	ctx->flags |= dl_has_alpha;

	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawPoolAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 2);
	nl->next = NULL;
	nl->vcount = 2;
	for (i = 0; i < 2; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );
	}
	
	if (ctx->cur->line_tail)
	{
		ctx->cur->line_tail->next = nl;
		ctx->cur->line_tail = nl;
	}
	else
	{
		ctx->cur->line_head = nl;
		ctx->cur->line_tail = nl;
	}
	
} // end LDrawDLBuilderAddLine


//========== LDrawDLBuilderAddCondLine ===========================================
//
// Purpose:	Add one conditional line to the current DL builder in the current texture.
//
// Notes:	A backend that does not draw conditional lines drops them here, before
//			the alpha is sniffed, so that they cannot pull translucency flags onto
//			a DL that will never show them.
//
//================================================================================
void LDrawDLBuilderAddCondLine(struct LDrawDLBuilder * ctx, const float v[12], float n[3], float c[4])
{
	if ((supported_primitives() & dl_supports_conditional_lines) == 0)
		return;

		 if (c[3] == 0.0f)	ctx->flags |= dl_has_meta;
	else if (c[3] != 1.0f)	ctx->flags |= dl_has_alpha;

	int i;
	struct LDrawDLBuilderVertexLink * nl = (struct LDrawDLBuilderVertexLink *) LDrawPoolAllocate(ctx->alloc, sizeof(struct LDrawDLBuilderVertexLink) + sizeof(float) * VERT_STRIDE * 4);
	nl->next = NULL;
	nl->vcount = 4;
	for (i = 0; i < 4; ++i)
	{
		copy_vec3(nl->data+VERT_STRIDE*i  ,v+i*3);
		copy_vec3(nl->data+VERT_STRIDE*i+3,n    );
		copy_vec4(nl->data+VERT_STRIDE*i+6,c    );
	}
	
	if (ctx->cur->cond_line_tail)
	{
		ctx->cur->cond_line_tail->next = nl;
		ctx->cur->cond_line_tail = nl;
	}
	else
	{
		ctx->cur->cond_line_head = nl;
		ctx->cur->cond_line_tail = nl;
	}
	
} // end LDrawDLBuilderAddCondLine
