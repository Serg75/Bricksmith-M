//==============================================================================
//
//  File:       MTL.h
//  Package:    LDrawRenderMetal
//
//  Created by Sergey Slobodenyuk on 2023-06-06.
//
//==============================================================================

#ifndef MTL_h
#define MTL_h

@import MetalKit;

#define LDrawApplicationGPU_h		"LDrawApplicationMTL.h"
#define LDrawDocumentGPU_h			"LDrawDocumentMTL.h"
#define LDrawRendererGPU_h			<LDrawRenderMetal/LDrawRendererMTL.h>
#define LDrawTextureGPU_h			<LDrawRenderMetal/LDrawTextureMTL.h>
#define LDrawViewGPU_h				"LDrawViewMTL.h"
#define PartLibraryGPU_h			<LDrawRenderMetal/PartLibraryMTL.h>

#define GPUView						MTKView
#define TexType						__strong id<MTLTexture>
#define LDrawTextureGPU 			LDrawTextureMTL
#define PartLibraryGPU				PartLibraryMTL

#endif /* MTL_h */
