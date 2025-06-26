//
//  MTL.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-06-06.
//

#ifndef MTL_h
#define MTL_h

@import MetalKit;

#define LDrawApplicationGPU_h		"LDrawApplicationMTL.h"
#define LDrawDirectiveGPU_h			"LDrawDirectiveMTL.h"
#define LDrawDisplayList_h			"LDrawDisplayListMTL.h"
#define LDrawDocumentGPU_h			"LDrawDocumentMTL.h"
#define LDrawRendererGPU_h			"LDrawRendererMTL.h"
#define LDrawShaderRendererGPU_h	"LDrawShaderRendererMTL.h"
#define LDrawTextureGPU_h			"LDrawTextureMTL.h"
#define LDrawViewGPU_h				"LDrawViewMTL.h"
#define PartLibraryGPU_h			"PartLibraryMTL.h"

#define GPUView						MTKView
#define TexType						__strong id<MTLTexture>
#define LDrawTextureGPU 			LDrawTextureMTL
#define PartLibraryGPU				PartLibraryMTL

#endif /* MTL_h */
