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


@interface LDrawShaderRenderer (MetalWideLines)

/// Draws the session's edge and conditional lines as quads of the given width.
- (void)setWideLines:(const struct LDrawDLWideLines *)lines;

@end

NS_ASSUME_NONNULL_END
