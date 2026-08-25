//
//  GPU.h
//  Bricksmith
//
//  App-target GPU routing header. GPU-agnostic types live in
//  LDrawRenderCore/GPUTypes.h; this header wires AppKit view types and
//  legacy macro indirection used by the macOS shell.
//

#ifndef GPU_h
#define GPU_h

#ifdef METAL

#import <LDrawRenderMetal/MTL.h>
#import <LDrawRenderCore/GPUTypes.h>

#define RenderEncoder           id<MTLRenderCommandEncoder>
#define Buffer                  id<MTLBuffer>
#define Texture                 id<MTLTexture>

#else

#import <LDrawRenderOpenGL/GL.h>
#import <LDrawRenderCore/GPUTypes.h>

#define RenderEncoder           id
#define Buffer                  id
#define Texture                 id

#endif

#endif /* GPU_h */
