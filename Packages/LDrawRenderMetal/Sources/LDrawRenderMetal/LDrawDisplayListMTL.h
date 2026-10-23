//==============================================================================
//
//  File:       LDrawDisplayListMTL.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    The parts of the display list API only the Metal renderer has.
//
//  Created by Sergey Slobodenyuk on 2026-10-22.
//
//==============================================================================
#import <Metal/Metal.h>
#import <simd/simd.h>

#import <LDrawRenderCore/LDrawDisplayList.h>
#import <LDrawRenderCore/LDrawShaderRenderer.h>
#include <LDrawRenderMetal/MetalCommonDefinitions.h>

NS_ASSUME_NONNULL_BEGIN

// Edge and conditional lines drawn as quads, so they can be wider than a
// pixel. The renderer keeps the pipelines, so the session does not retain
// them.
struct LDrawDLWideLines {
	// Nil for edge lines a pixel wide and no conditional lines.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	line_pipeline;
	// Put back after the lines.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	face_pipeline;
	float														width;			// in pixels
	vector_float2												viewport_size;	// in pixels
	// The most a face is pushed back to keep a line on its edge whole, as a
	// depth. 0 for no limit.
	float														face_bias_clamp;
};

void LDrawDLSessionSetWideLines(id<MTLRenderCommandEncoder> renderEncoder,
								struct LDrawDLSession *session,
								const struct LDrawDLWideLines *lines);

// Per-pixel lists that transparent parts go into, so each pixel blends them in
// depth order. The renderer keeps the pipelines and buffers, so the session
// does not retain them.
struct LDrawDLTransparentLists {
	// A tile shader that empties the lists.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	clear_pipeline;
	// Put faces and thin lines, and wide lines, into the lists.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	list_pipeline;
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	list_wide_line_pipeline;
	// Blends each pixel's list over what is drawn.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	resolve_pipeline;
	// The usual faces, put back afterwards.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	face_pipeline;
	__unsafe_unretained id<MTLBuffer> _Nullable					heads;
	__unsafe_unretained id<MTLBuffer> _Nullable					fragments;
	__unsafe_unretained id<MTLBuffer> _Nullable					counters;
	struct TransparencyUniform									uniform;
};

// Gets the lists ready for a session's transparent parts and fills in where
// they are. Called once, and only when there are transparent parts. Returns NO
// to have them blended one at a time instead.
typedef BOOL (^LDrawDLPrepareTransparentLists)(struct LDrawDLTransparentLists *lists);

void LDrawDLSessionSetPrepareTransparentLists(struct LDrawDLSession *session,
											  LDrawDLPrepareTransparentLists _Nullable prepare);


@interface LDrawShaderRenderer (MetalWideLines)

/// Draws the session's edge and conditional lines as quads of the given width.
- (void)setWideLines:(const struct LDrawDLWideLines *)lines;

@end


@interface LDrawShaderRenderer (MetalTransparency)

/// Puts the transparent parts into the lists prepare gets ready, or blends
/// them one at a time without it. The block must stay alive until the drawing
/// is finished.
- (void)setPrepareTransparentLists:(LDrawDLPrepareTransparentLists _Nullable)prepare;

@end

NS_ASSUME_NONNULL_END
