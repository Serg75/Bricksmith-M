//==============================================================================
//
//  File:       LDrawPartSpecific.m
//  Package:    LDrawCore
//
//  Purpose:    Some data connected to particular parts.
//
//              This class keeps additional parameters for particular parts.
//              When parts change their names don't forget to update them here.
//
//  Created by Sergey Slobodenyuk on 2022-11-19.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawPartSpecific.h>
#import <LDrawCore/LDrawPaths.h>

static NSDictionary *parts;


@implementation LDrawPartSpecific


//---------- LoadIfNeeded ------------------------------------------------------
//
// Purpose:		Load part-specific rotation data from the bundled JSON file
//				the first time this class is used after the host has set
//				internalLDrawPath.
//
//------------------------------------------------------------------------------
static void LDrawPartSpecificLoadIfNeeded(void)
{
	if (parts != nil)
		return;

	NSString *root = [[LDrawPaths sharedPaths] internalLDrawPath];
	if (root == nil)
		return;

	NSString *filePath = [root stringByAppendingPathComponent:@"parts rotation.json"];
	NSData   *data     = [NSData dataWithContentsOfFile:filePath];
	if (data == nil)
	{
		parts = @{};
		return;
	}

	parts = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:NULL] ?: @{};
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
	LDrawPartSpecificLoadIfNeeded();
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
	LDrawPartSpecificLoadIfNeeded();
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
	LDrawPartSpecificLoadIfNeeded();
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
