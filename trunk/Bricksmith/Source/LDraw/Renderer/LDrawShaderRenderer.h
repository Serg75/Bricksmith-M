//
//  LDrawShaderRenderer.h
//  Bricksmith
//
//  Created by bsupnik on 11/5/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "LDrawCoreRenderer.h"
#import "GPU.h"

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
	attr_color_compliment,
	attr_texture_mix,
	attr_count
};


// Drag handle linked list.  When we get drag handle requests we transform the location into eye-space (to 'capture' the
// drag handle location, then we draw it later when our coordinate system isn't possibly scaled.
struct	LDrawDragHandleInstance {
	struct LDrawDragHandleInstance * next;
	float	xyz[3];
	float	size;
};


// Stack depths for renderer.
#define COLOR_STACK_DEPTH 64		
#define TEXTURE_STACK_DEPTH 128
#define TRANSFORM_STACK_DEPTH 64
#define DL_STACK_DEPTH 64

struct	LDrawDLBuilder;
struct	LDrawBDP;
struct	LDrawDragHandleInstance;

@interface LDrawShaderRenderer : NSObject<LDrawCoreRenderer,LDrawCollector> {

	struct LDrawDLSession *			session;										// DL session - this accumulates draw calls and sorts them.
	struct LDrawBDP *				pool;

	float							color_now[4];									// Color stack.
	float							compl_now[4];
	float							color_stack[COLOR_STACK_DEPTH*4];
	int								color_stack_top;

	int								wire_frame_count;								// wire frame stack is just a count.


	struct LDrawTextureSpec			tex_stack[TEXTURE_STACK_DEPTH];					// Texture stack from push/pop texture.
	int								texture_stack_top;
	struct LDrawTextureSpec			tex_now;

	float							transform_stack[TRANSFORM_STACK_DEPTH*16];		// Transform stack from push/pop matrix.
	int								transform_stack_top;
	float							transform_now[16];
	float							cull_now[16];

	struct LDrawDLBuilder*			dl_stack[DL_STACK_DEPTH];						// DL stack from begin/end DL builds.
	int								dl_stack_top;
	struct LDrawDLBuilder*			dl_now;											// This is the DL being built "right now".

	float							mvp[16];										// Cached MVP from when shader is built.

	struct LDrawDragHandleInstance *drag_handles;									// List of drag handles - deferred to draw at the end for perf and correct scaling.
	float							scale;											// Needed to code Allen's res-independent drag handles...someday get this from viewport?


	// Metal
	RenderEncoder					_renderEncoder;
}

// moved to category
//- (id) initWithScale:(float)scale modelView:(float *)mv_matrix projection:(float *)proj_matrix;

// moved to category
//- (void) drawDragHandleImm:(float*)xyz withSize:(float)size;

// moved to category
//- (struct LDrawDL *)builderFinish:(struct LDrawDLBuilder *)ctx;

@end
