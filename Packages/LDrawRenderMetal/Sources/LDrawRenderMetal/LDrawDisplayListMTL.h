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
	// Draw the depth of ghosts' faces and thin lines, and wide lines.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	ghost_prepass_pipeline;
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	ghost_prepass_wide_line_pipeline;
	// Blend ghosts' faces and thin lines, and wide lines. Where a transparent
	// part is, they put them into the lists.
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	ghost_pipeline;
	__unsafe_unretained id<MTLRenderPipelineState> _Nullable	ghost_wide_line_pipeline;
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

// Has transparent parts blended without the lists draw their far faces before
// their near ones, through facing, and put face back after. The renderer keeps
// the pipelines, so the session does not retain them.
void LDrawDLSessionSetFacingPipelines(struct LDrawDLSession *session,
									  id<MTLRenderPipelineState> _Nullable facing,
									  id<MTLRenderPipelineState> _Nullable face);

// Has the opaque parts drawn through this pipeline, and the face pipeline put
// back after them. Nil draws them through the pipeline bound already. The
// renderer keeps it, so the session does not retain it.
void LDrawDLSessionSetOpaquePipeline(struct LDrawDLSession *session,
									 id<MTLRenderPipelineState> _Nullable opaque);

// Has the ghosts' depth prepass without the lists drawn through these, which
// draw only depth and stencil. Nil draws it through the face pipeline at an
// alpha of 0. The renderer keeps them, so the session does not retain them.
void LDrawDLSessionSetGhostDepthPipelines(struct LDrawDLSession *session,
										  id<MTLRenderPipelineState> _Nullable face,
										  id<MTLRenderPipelineState> _Nullable wideLine);


// The DLs a session drew under a highlight, and where, kept after its render
// pass so the renderer can draw their band. Their DLs stay alive until the list
// is destroyed.
struct LDrawDLHighlightList;

// Has the session hand over its highlighted DLs as it finishes, into *list,
// which it leaves NULL when there are none. Without it, they are drawn as
// usual and not kept.
void LDrawDLSessionSetHighlightList(struct LDrawDLSession *session,
									struct LDrawDLHighlightList * _Nullable * _Nullable list);

// Whether any DL has this LDrawRenderHighlight.
BOOL LDrawDLHighlightListHas(const struct LDrawDLHighlightList *list, int highlight);

// The pixel rectangle, from the top left, that the DLs cover under
// viewProjection. The whole surface when one reaches behind the eye or has no
// box.
CGRect LDrawDLHighlightListBounds(const struct LDrawDLHighlightList *list,
								  simd_float4x4 viewProjection,
								  CGSize pixelSize);

// Draws the triangles of the DLs with this LDrawRenderHighlight. The caller
// sets the pipeline and the uniforms.
void LDrawDLHighlightListDrawTriangles(id<MTLRenderCommandEncoder>			renderEncoder,
									   const struct LDrawDLHighlightList *	list,
									   int									highlight);

void LDrawDLHighlightListDestroy(struct LDrawDLHighlightList *list);

@interface LDrawShaderRenderer (MetalWideLines)

/// Draws the session's edge and conditional lines as quads of the given width.
- (void)setWideLines:(const struct LDrawDLWideLines *)lines;

@end


@interface LDrawShaderRenderer (MetalHighlights)
/// Keeps the parts drawn under a highlight in *list once the drawing is
/// finished, for their band. The caller destroys it.
- (void)setHighlightList:(struct LDrawDLHighlightList * _Nullable * _Nullable)list;
@end

@interface LDrawShaderRenderer (MetalTransparency)

/// Puts the transparent parts into the lists prepare gets ready, or blends
/// them one at a time without it. The block must stay alive until the drawing
/// is finished.
- (void)setPrepareTransparentLists:(LDrawDLPrepareTransparentLists _Nullable)prepare;

/// Without the lists, draws each transparent part's far faces before its near
/// ones, through facing, and puts face back after.
- (void)setFacingPipeline:(id<MTLRenderPipelineState> _Nullable)facing
			 facePipeline:(id<MTLRenderPipelineState> _Nullable)face;

/// Draws the opaque parts through this pipeline, and puts the face pipeline
/// back after them. Nil draws them through the one bound already.
- (void)setOpaquePipeline:(id<MTLRenderPipelineState> _Nullable)opaque;

/// Draws the ghosts' depth prepass without the lists through these, which
/// draw only depth and stencil.
- (void)setGhostDepthPipeline:(id<MTLRenderPipelineState> _Nullable)face
			 wideLinePipeline:(id<MTLRenderPipelineState> _Nullable)wideLine;

@end

NS_ASSUME_NONNULL_END
