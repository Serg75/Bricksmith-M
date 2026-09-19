//==============================================================================
//
//  File:       LDrawShaderRendererDraw.h
//  Package:    LDrawRenderCore
//
//  Purpose:    Renderer hooks implemented by LDrawRenderMetal and
//              LDrawRenderOpenGL categories on LDrawShaderRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#ifndef LDrawRenderCore_LDrawShaderRendererDraw_h
#define LDrawRenderCore_LDrawShaderRendererDraw_h

#import <LDrawRenderCore/LDrawShaderRenderer.h>
#import <LDrawRenderCore/LDrawDisplayList.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawShaderRenderer
///
/// @abstract   Renderer hooks implemented by LDrawRenderMetal and
///             LDrawRenderOpenGL categories on LDrawShaderRenderer.
///
//------------------------------------------------------------------------------
@interface LDrawShaderRenderer (Draw)

- (nullable struct LDrawDL *)builderFinish:(struct LDrawDLBuilder *)ctx;
- (void)finishDraw;

@end

NS_ASSUME_NONNULL_END

#endif /* LDrawRenderCore_LDrawShaderRendererDraw_h */
