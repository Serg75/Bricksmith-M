//
//  MetalGPU.m
//  Bricksmith-MetalGPU
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

#import "MetalGPU.h"

@implementation MetalGPU

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
