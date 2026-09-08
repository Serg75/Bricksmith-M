//==============================================================================
//
//  File:       LDrawShaderRenderer.h
//  Package:    LDrawRenderCore
//
//  Created by bsupnik on 11/5/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawRenderCore/LDrawRenderTypes.h>

NS_ASSUME_NONNULL_BEGIN

/*

	LDrawShaderRenderer - an implementation of the LDrawCoreRenderer API using shaders.

	The renderer maintains a stack view of OpenGL state; as directives push their
	info to the renderer, containing LDraw parts push and pop state to affect the
	child parts that are drawn via the depth-first traversal.


*/

enum {
	attr_position = 0,		// This defines the attribute indices for our particular shader.
	attr_normal,			// This must be kept in sync with the string list in the .m file.
	attr_color,
	attr_transform_x,
	attr_transform_y,
	attr_transform_z,
	attr_transform_w,
	attr_color_current,
	attr_color_complement,
	attr_texture_mix,
	attr_ghost_alpha,		// Scales the vertex color's alpha, baked-in mesh colors included;
							// 1 for everything that is not a ghost.
	attr_count
};


// Drag handle linked list.  When we get drag handle requests we transform the location into eye-space (to 'capture' the
// drag handle location, then we draw it later when our coordinate system isn't possibly scaled.
struct	LDrawDragHandleInstance {
	struct LDrawDragHandleInstance * _Nullable next;
	float	xyz[3];
	float	size;
};


// Stack depths for renderer.
#define COLOR_STACK_DEPTH 64		
#define TEXTURE_STACK_DEPTH 128
#define TRANSFORM_STACK_DEPTH 64
#define DL_STACK_DEPTH 64

struct	LDrawDLBuilder;
struct	LDrawPool;
struct	LDrawDragHandleInstance;

//------------------------------------------------------------------------------
///
/// @class      LDrawShaderRenderer
///
/// @abstract   LDrawCoreRenderer that accumulates draw calls through a shader
///             session. Directives push and pop color, texture, and transform
///             state during the depth-first traversal.
///
//------------------------------------------------------------------------------
@interface LDrawShaderRenderer : NSObject<LDrawCoreRenderer,LDrawCollector> {

	struct LDrawDLSession * _Nullable	session;									// DL session - this accumulates draw calls and sorts them.
	struct LDrawPool * _Nullable	pool;

	float							color_now[4];									// Color stack.
	float							compl_now[4];
	float							color_stack[COLOR_STACK_DEPTH*4];
	int								color_stack_top;

	int								wire_frame_count;								// wire frame stack is just a count.
	BOOL							boundsOnlyDrawing;								// fast interaction: draw AABBs only.


	struct LDrawTextureSpec			tex_stack[TEXTURE_STACK_DEPTH];					// Texture stack from push/pop texture.
	int								texture_stack_top;
	struct LDrawTextureSpec			tex_now;

	float							transform_stack[TRANSFORM_STACK_DEPTH*16];		// Transform stack from push/pop matrix.
	int								transform_stack_top;
	float							transform_now[16];
	float							cull_now[16];

	struct LDrawDLBuilder * _Nullable dl_stack[DL_STACK_DEPTH];						// DL stack from begin/end DL builds.
	int								dl_stack_top;
	struct LDrawDLBuilder* _Nullable dl_now;										// This is the DL being built "right now".

	float							mvp[16];										// Cached MVP from when shader is built.

	struct LDrawDragHandleInstance * _Nullable drag_handles;						// List of drag handles - deferred to draw at the end for perf and correct scaling.
	float							scale;											// Needed to code Allen's res-independent drag handles...someday get this from viewport?

    // Ghost stack, for drawing removed MLCAD groups translucent.  Each frame holds the running
    // product of the alpha factors pushed so far -- products rather than raw factors, so an empty
    // stack needs no initialization, which matters because each backend seeds its own state in its
    // own -init -- and the id of the ghost the frame belongs to.  The id lets the DL layer
    // depth-prepass a whole ghosted part, which may be a submodel of many separate DLs, as one
    // solid object rather than one shell per brick.
    struct {
        float                        alpha;
        int                            ghost_id;
    }                                ghost_stack[COLOR_STACK_DEPTH];

    int                                ghost_stack_top;
    int                                ghost_serial;

	// Metal
	LDrawRenderEncoder				_Nullable _renderEncoder;
}

- (void)setBoundsOnlyDrawing:(BOOL)boundsOnly;

@end

NS_ASSUME_NONNULL_END
