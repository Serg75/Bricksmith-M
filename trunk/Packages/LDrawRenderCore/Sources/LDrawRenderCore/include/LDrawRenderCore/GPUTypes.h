//==============================================================================
//
//  File:       GPUTypes.h
//  Package:    LDrawRenderCore
//
//  Purpose:    GPU-agnostic resource typedefs used by LDrawRenderCore.
//
//  Info:       Concrete Metal and OpenGL packages cast these to their native
//              types at runtime.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#ifndef GPUTypes_h
#define GPUTypes_h

#import <Foundation/Foundation.h>

typedef id LDrawGPUBuffer;
typedef id LDrawGPUTexture;
typedef id LDrawRenderEncoder;

#define NEED_CORRECT_PROJECTION 0

#endif /* GPUTypes_h */
