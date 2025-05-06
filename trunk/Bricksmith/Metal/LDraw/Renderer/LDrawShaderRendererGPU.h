//==============================================================================
//
//	LDrawShaderRendererGPU.h
//	Bricksmith
//
//	Purpose:	an implementation of the LDrawCoreRenderer API using shaders.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawShaderRenderer.h"


@interface LDrawShaderRenderer (Metal)

- (id) initWithEncoder:(id<MTLRenderCommandEncoder>)encoder scale:(float)scale modelView:(float *)mv_matrix projection:(float *)proj_matrix;

- (void) finishDraw;

@end
