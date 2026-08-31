//==============================================================================
//
//  File:       LDrawRenderCore.h
//  Package:    LDrawRenderCore
//
//  Purpose:    Host-facing umbrella for the LDrawRenderCore Swift Package.
//
//  Info:       GPU-agnostic renderer protocols, shader renderer, camera, and
//              display-list API shared by the Metal and OpenGL renderers.
//              MeshSmooth, the pool allocator, and the display-list builder
//              remain on the umbrella because Clang modules only surface
//              headers listed here (Metal/OpenGL import them as LDrawRenderCore).
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawRenderCore/LDrawRenderTypes.h>
#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawRenderCore/LDrawDisplayList.h>
#import <LDrawRenderCore/LDrawDisplayListBuilder.h>
#import <LDrawRenderCore/LDrawPoolAllocator.h>
#import <LDrawRenderCore/LDrawShaderRenderer.h>
#import <LDrawRenderCore/LDrawShaderRendererDraw.h>
#import <LDrawRenderCore/MeshSmooth.h>
#import <LDrawRenderCore/LDrawCamera.h>
#import <LDrawRenderCore/LDrawRenderer.h>
