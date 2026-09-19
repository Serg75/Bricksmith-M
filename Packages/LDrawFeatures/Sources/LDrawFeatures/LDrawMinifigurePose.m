//==============================================================================
//
//  File:       LDrawMinifigurePose.m
//  Package:    LDrawFeatures
//
//  Purpose:    KVC copy of minifigure inclusion flags and joint angles.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <LDrawFeatures/LDrawMinifigurePose.h>


@implementation LDrawMinifigurePose

//---------- inclusionAndAngleKeys -----------------------------------[static]--
//
// Purpose:		Has-flags, elevation, and joint-angle property names copied
//				between the generator, layout spec, and preferences snapshot.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)inclusionAndAngleKeys
{
	return @[
		@"hasHat",
		@"hasNeckAccessory",
		@"hasHips",
		@"hasRightArm",
		@"hasRightHand",
		@"hasRightHandAccessory",
		@"hasRightLeg",
		@"hasRightLegAccessory",
		@"hasLeftArm",
		@"hasLeftHand",
		@"hasLeftHandAccessory",
		@"hasLeftLeg",
		@"hasLeftLegAccessory",
		@"headElevation",
		@"angleOfHat",
		@"angleOfHead",
		@"angleOfNeck",
		@"angleOfRightArm",
		@"angleOfRightHand",
		@"angleOfRightHandAccessory",
		@"angleOfRightLeg",
		@"angleOfRightLegAccessory",
		@"angleOfLeftArm",
		@"angleOfLeftHand",
		@"angleOfLeftHandAccessory",
		@"angleOfLeftLeg",
		@"angleOfLeftLegAccessory",
	];
}


//---------- takeInclusionAndAnglesFromTarget: -----------------------[instance]
//
// Purpose:		Copies has-flags, elevation, and joint angles from the
//				generator (KVC).
//
//------------------------------------------------------------------------------
- (void)takeInclusionAndAnglesFromTarget:(id)target
{
	for (NSString *key in [[self class] inclusionAndAngleKeys])
	{
		[self setValue:[target valueForKey:key] forKey:key];
	}
}


//---------- applyInclusionAndAnglesToTarget: ------------------------[instance]
//
// Purpose:		Copies has-flags, elevation, and joint angles onto the
//				generator (KVC).
//
//------------------------------------------------------------------------------
- (void)applyInclusionAndAnglesToTarget:(id)target
{
	for (NSString *key in [[self class] inclusionAndAngleKeys])
	{
		[target setValue:[self valueForKey:key] forKey:key];
	}
}

@end
