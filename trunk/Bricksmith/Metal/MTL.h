//
//  MTL.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-06-06.
//

#ifndef MTL_h
#define MTL_h

@import MetalKit;
#define GPUView MTKView

#define TexType					__strong id<MTLTexture>

#define LDrawTextureGPU_h		"LDrawTextureMTL.h"
#define LDrawTextureGPU 		LDrawTextureMTL

#define PartLibraryGPU_h		"PartLibraryMTL.h"
#define PartLibraryGPU			PartLibraryMTL

#endif /* MTL_h */
