//
//  MetalGPU.h
//  Bricksmith-MetalGPU
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

#import <Foundation/Foundation.h>
@import MetalKit;

extern const int InstanceInputLength;
extern const int InstanceInputStructSize;
extern const int MSAASampleCount;

@interface MetalGPU : NSObject

+ (id<MTLDevice>)device;

@end
