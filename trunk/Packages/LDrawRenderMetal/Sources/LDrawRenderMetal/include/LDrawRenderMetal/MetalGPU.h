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
#include "MetalCommonDefinitions.h"

extern const int MSAASampleCount;

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
