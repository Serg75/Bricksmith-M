//==============================================================================
//
//  File:       LDrawRenderCore.h
//  Package:    LDrawRenderCore
//
//  Purpose:    Host-facing umbrella for the LDrawRenderCore Swift Package.
//
//  Info:       GPU-agnostic renderer protocols, shader renderer, camera, and
//              display-list API shared by the Metal and OpenGL renderers.
//              MeshSmooth, the BDP allocator, and backend GPU categories remain
//              public because other packages import them as modular headers.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawRenderCore/GPUTypes.h>
#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawRenderCore/LDrawDisplayList.h>
#import <LDrawRenderCore/LDrawBDPAllocator.h>
#import <LDrawRenderCore/LDrawShaderRenderer.h>
#import <LDrawRenderCore/LDrawShaderRendererGPU.h>
#import <LDrawRenderCore/MeshSmooth.h>
#import <LDrawRenderCore/LDrawCamera.h>
#import <LDrawRenderCore/LDrawRenderer.h>
