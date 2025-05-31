//
//  GPU.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-06-20.
//

#ifndef GPU_h
#define GPU_h

#ifdef METAL

#import "MTL.h"
#define RenderEncoder			id<MTLRenderCommandEncoder>
#define Buffer					id<MTLBuffer>
#define Texture					id<MTLTexture>
#define NEED_CORRECT_PROJECTION	1

#else

#import "GL.h"
#define RenderEncoder			id
#define Buffer					id
#define Texture					id
#define NEED_CORRECT_PROJECTION	0

#endif

#endif /* GPU_h */
