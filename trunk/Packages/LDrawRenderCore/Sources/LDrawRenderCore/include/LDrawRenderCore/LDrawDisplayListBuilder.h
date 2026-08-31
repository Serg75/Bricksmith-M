//==============================================================================
//
//  File:       LDrawDisplayListBuilder.h
//  Package:    LDrawRenderCore
//
//  Purpose:    Build-time state shared by the Metal and OpenGL display lists.
//
//  Info:       A builder accumulates primitives into per-texture linked lists
//              carved out of one BDP pool. Baking those lists into GPU buffers
//              stays in LDrawRenderMetal and LDrawRenderOpenGL, since the two
//              have nothing in common there.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#ifndef LDrawDisplayListBuilder_h
#define LDrawDisplayListBuilder_h

#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawRenderCore/LDrawBDPAllocator.h>

#define VERT_STRIDE 10		// Stride of our vertices - we always write X Y Z	NX NY NZ		R G B A

enum {
	dl_has_alpha = 1,		// At least one prim in this DL has translucency.
	dl_has_meta = 2,		// At least one prim in this DL uses a meta-color and thus MIGHT pick up translucency from parent state during draw.
	dl_has_tex = 4,			// At least one real texture is used.
	dl_needs_destroy = 8	// Destroy after drawing - ptr is only around because it is queued!
};


// What a renderer's display lists can carry.  The two backends differ: Metal has
// no quad primitive, so quads have to be split into triangles as they arrive,
// while OpenGL keeps them whole and saves half the vertices.  OpenGL in turn does
// not draw conditional lines, so it drops them rather than storing them.
enum {
	dl_supports_quads				= 1,	// Store quads whole, rather than splitting them into triangles.
	dl_supports_conditional_lines	= 2		// Store conditional lines, rather than discarding them.
};


//---------- LDrawDLSupportedPrimitives -----------------------------------------
//
// Implemented by the renderer package, not here: the builder asks which of the
// dl_supports_* primitives the linked backend draws, so that it knows how to
// store incoming quads and conditional lines.  Whichever lists a backend asks
// for are the ones its LDrawDLBuilderFinish has to read back.
//
//------------------------------------------------------------------------------
int		LDrawDLSupportedPrimitives(void);


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
// since we don't know how many we will have.  Each type of drawing (line, cond_line,
// tri, quad) is kept in a singly linked list of vertex links so that we can copy
// them consecutively when done.
//
// A backend only fills in the lists for the primitives it draws: Metal splits
// quads into tris, OpenGL discards conditional lines.
struct LDrawDLBuilderPerTex {
	struct LDrawDLBuilderPerTex *		next;
	struct LDrawTextureSpec				spec;
	struct LDrawDLBuilderVertexLink *	tri_head;
	struct LDrawDLBuilderVertexLink *	tri_tail;
	struct LDrawDLBuilderVertexLink *	quad_head;
	struct LDrawDLBuilderVertexLink *	quad_tail;
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


static inline void copy_vec3(float d[3], const float s[3]) { d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; }
static inline void copy_vec4(float d[4], const float s[4]) { d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3]; }

#endif /* LDrawDisplayListBuilder_h */
