//==============================================================================
//
//  File:       MetalGPU.m
//  Package:    LDrawRenderMetal
//
//  Purpose:    Shared system-default MTLDevice for Metal rendering.
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//
//==============================================================================

#import <LDrawRenderMetal/MetalGPU.h>

@implementation MetalGPU

//---------- device -------------------------------------------------[static]--
//
// Purpose:		Return the shared system-default Metal device, created once.
//
//------------------------------------------------------------------------------
+ (id<MTLDevice>)device
{
	static id<MTLDevice> _sharedDevice = nil;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		_sharedDevice = MTLCreateSystemDefaultDevice();
	});
	return _sharedDevice;

}//end device

@end
