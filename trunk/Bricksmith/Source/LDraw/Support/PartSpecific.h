//==============================================================================
//
// File:		PartSpecific.h
//
// Purpose:		Some data connected to particular parts.
//
//				This class keeps additional parameters for particular parts.
//				When parts change their names don't forget to update them here.
//
//  Created by Sergey Slobodenyuk on 2022-11-19.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================

#import <Foundation/Foundation.h>
#import "MatrixMath.h"

@interface PartSpecific : NSObject

+ (BOOL) hasRotationCenter:(NSString *)partName;
+ (Point3) rotationCenterForPart:(NSString *)partName;
+ (Point3) rotationPlaneForPart:(NSString *)partName;

@end
