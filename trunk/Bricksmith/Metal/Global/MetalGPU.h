//
//  MetalGPU.h
//  Bricksmith-MetalGPU
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

@import MetalKit;

#import <Foundation/Foundation.h>
#include "MetalCommonDefinitions.h"

extern const int MSAASampleCount;

@interface MetalGPU : NSObject

+ (id<MTLDevice>)device;

@end
