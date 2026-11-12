//==============================================================================
//
//  File:       MetalGPU.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    Shared system-default MTLDevice for Metal rendering.
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//
//==============================================================================

@import MetalKit;

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const int MSAASampleCount;

// The depth target of every pass. Its stencil marks where a ghost is in front.
extern const MTLPixelFormat DepthStencilPixelFormat;

//------------------------------------------------------------------------------
///
/// @class      MetalGPU
///
/// @abstract   Shared system-default MTLDevice, created once.
///
//------------------------------------------------------------------------------
@interface MetalGPU : NSObject

/// Return the shared system-default Metal device, created once.
+ (id<MTLDevice>)device;

@end

NS_ASSUME_NONNULL_END
