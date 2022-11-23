//==============================================================================
//
// File:		PartSpecific.m
//
// Purpose:		Some data connected to particular parts.
//
//				This class keeps additional parameters for particular parts.
//				When parts change their names don't forget to update them here.
//
//  Created by Sergey Slobodenyuk on 2022-11-19.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================

#import "PartSpecific.h"
#import "LDrawPaths.h"

static NSDictionary *parts;


@implementation PartSpecific


+ (void) initialize
{
	if (self == [PartSpecific class]) {

		NSString *filePath = [[[LDrawPaths sharedPaths] internalLDrawPath] stringByAppendingPathComponent:@"parts rotation.json"];
		NSData *data = [NSData dataWithContentsOfFile:filePath];
		NSError *error;
		parts = [NSJSONSerialization JSONObjectWithData:data
												options:kNilOptions
												  error:&error];
	}
}


//========== hasRotationCenter: ================================================
//
// Purpose:		Returns whether the part has single rotation center.
//
//				It is applicable for parts with holes, handles, bars, pins etc.
//
//==============================================================================
+ (BOOL) hasRotationCenter:(NSString *)partName
{
	return parts[partName] != nil;
}


//========== rotationCenterForPart: ============================================
//
// Purpose:		Returns rotation center for the part. If part doesn't have
//				rotation center, or has multiple centers, returns origin.
//
//				It is applicable for parts with holes, handles, bars, pins etc.
//
//==============================================================================
+ (Point3) rotationCenterForPart:(NSString *)partName
{
	NSString *center = parts[partName];
	if (center != nil) {
		NSArray *componets = [center componentsSeparatedByString:@","];
		if (componets.count >= 3) {
			return V3Make(((NSString *)componets[0]).floatValue,
						  ((NSString *)componets[1]).floatValue,
						  ((NSString *)componets[2]).floatValue);
		}
	}
	return V3Make(0, 0, 0);
}


//========== rotationPlaneForPart: =============================================
//
// Purpose:		Returns rotation plane for the part. If part doesn't have
//				rotation center, or has multiple centers, returns (1,1,1).
//
//				It is applicable for parts with holes, handles, bars, pins etc.
//
//==============================================================================
+ (Point3) rotationPlaneForPart:(NSString *)partName
{
	NSString *center = parts[partName];
	if (center != nil) {
		NSArray *componets = [center componentsSeparatedByString:@","];
		if (componets.count == 4) {
			if ([componets[3] isEqualToString:@"x"]) {
				return V3Make(0, 1, 1);
			} else if ([componets[3] isEqualToString:@"y"]) {
				return V3Make(1, 0, 1);
			} else if ([componets[3] isEqualToString:@"z"]) {
				return V3Make(1, 1, 0);
			}
		}
	}
	return V3Make(1, 1, 1);
}


@end
