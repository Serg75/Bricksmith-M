//
//  MetalGPU.h
//  Bricksmith-MetalGPU
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

#import <Foundation/Foundation.h>
@import MetalKit;
extern const int MSAASampleCount;
#include "MetalCommonDefinitions.h"

@interface MetalGPU : NSObject

+ (id<MTLDevice>)device;

@end
