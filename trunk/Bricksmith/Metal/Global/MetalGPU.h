//
//  MetalGPU.h
//  Bricksmith-MetalGPU
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

#import <Foundation/Foundation.h>

extern const int InstanceInputLength;
extern const int InstanceInputStructSize;

@interface MetalGPU : NSObject

+ (id<MTLDevice>)device;

@end
