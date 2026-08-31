//==============================================================================
//
//  File:       LDrawShaderRendererMTL.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    an implementation of the LDrawCoreRenderer API using shaders.
//
//  Info:       This category contains Metal-related code.
//
//  Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import <Metal/Metal.h>
#import <LDrawRenderCore/LDrawShaderRenderer.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawShaderRenderer
///
/// @abstract   an implementation of the LDrawCoreRenderer API using shaders.
///
//------------------------------------------------------------------------------
@interface LDrawShaderRenderer (Metal)

- (id)initWithEncoder:(id<MTLRenderCommandEncoder>)encoder scale:(float)scale modelView:(float *)mv_matrix projection:(float *)proj_matrix;

- (nullable struct LDrawDL *)builderFinish:(struct LDrawDLBuilder *)ctx;

- (void)finishDraw;

@end

NS_ASSUME_NONNULL_END
