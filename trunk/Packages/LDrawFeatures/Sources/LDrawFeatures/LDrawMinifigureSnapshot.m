//==============================================================================
//
//  File:       LDrawMinifigureSnapshot.m
//  Package:    LDrawFeatures
//
//  Purpose:    NSUserDefaults packing for the minifigure generator.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawMinifigureSnapshot.h>
#import <LDrawFeatures/LDrawMinifigureAssembler.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawFeatures/LDrawHostKeys.h>


@interface LDrawMinifigureSnapshot ()
+ (NSArray<NSString *> *)colorKeys;
+ (NSArray<NSString *> *)partNameKeys;
- (NSInteger)colorCodeAtIndex:(NSUInteger)index;
- (void)setColorCode:(NSInteger)code atIndex:(NSUInteger)index;
- (nullable NSString *)partNameAtIndex:(NSUInteger)index;
- (void)setPartName:(nullable NSString *)name atIndex:(NSUInteger)index;
@end

@implementation LDrawMinifigureSnapshot

//---------- snapshotFromUserDefaults: -------------------------------[static]--
//
// Purpose:		Reads previous values out of preferences.
//
// Notes:		Wow what a horrific method.
//
//------------------------------------------------------------------------------
+ (instancetype)snapshotFromUserDefaults:(NSUserDefaults *)defaults
{
	LDrawMinifigureSnapshot *snap = [[self alloc] init];

	snap.hasHat                 = [defaults boolForKey:MINIFIGURE_HAS_HAT];
	snap.hasNeckAccessory       = [defaults boolForKey:MINIFIGURE_HAS_NECK];
	snap.hasHips                = [defaults boolForKey:MINIFIGURE_HAS_HIPS];
	snap.hasRightArm            = [defaults boolForKey:MINIFIGURE_HAS_ARM_RIGHT];
	snap.hasRightHand           = [defaults boolForKey:MINIFIGURE_HAS_HAND_RIGHT];
	snap.hasRightHandAccessory  = [defaults boolForKey:MINIFIGURE_HAS_HAND_RIGHT_ACCESSORY];
	snap.hasLeftArm             = [defaults boolForKey:MINIFIGURE_HAS_ARM_LEFT];
	snap.hasLeftHand            = [defaults boolForKey:MINIFIGURE_HAS_HAND_LEFT];
	snap.hasLeftHandAccessory   = [defaults boolForKey:MINIFIGURE_HAS_HAND_LEFT_ACCESSORY];
	snap.hasRightLeg            = [defaults boolForKey:MINIFIGURE_HAS_LEG_RIGHT];
	snap.hasRightLegAccessory   = [defaults boolForKey:MINIFIGURE_HAS_LEG_RIGHT_ACCESSORY];
	snap.hasLeftLeg             = [defaults boolForKey:MINIFIGURE_HAS_LEG_LEFT];
	snap.hasLeftLegAccessory    = [defaults boolForKey:MINIFIGURE_HAS_LEG_LEFT_ACCESSORY];

	snap.headElevation          = [defaults floatForKey:MINIFIGURE_HEAD_ELEVATION];

	snap.angleOfHat             = [defaults floatForKey:MINIFIGURE_ANGLE_HAT];
	snap.angleOfHead            = [defaults floatForKey:MINIFIGURE_ANGLE_HEAD];
	snap.angleOfNeck            = [defaults floatForKey:MINIFIGURE_ANGLE_NECK];
	snap.angleOfLeftArm         = [defaults floatForKey:MINIFIGURE_ANGLE_ARM_LEFT];
	snap.angleOfRightArm        = [defaults floatForKey:MINIFIGURE_ANGLE_ARM_RIGHT];
	snap.angleOfLeftHand        = [defaults floatForKey:MINIFIGURE_ANGLE_HAND_LEFT];
	snap.angleOfLeftHandAccessory  = [defaults floatForKey:MINIFIGURE_ANGLE_HAND_LEFT_ACCESSORY];
	snap.angleOfRightHand       = [defaults floatForKey:MINIFIGURE_ANGLE_HAND_RIGHT];
	snap.angleOfRightHandAccessory = [defaults floatForKey:MINIFIGURE_ANGLE_HAND_RIGHT_ACCESSORY];
	snap.angleOfLeftLeg         = [defaults floatForKey:MINIFIGURE_ANGLE_LEG_LEFT];
	snap.angleOfLeftLegAccessory    = [defaults floatForKey:MINIFIGURE_ANGLE_LEG_LEFT_ACCESSORY];
	snap.angleOfRightLeg        = [defaults floatForKey:MINIFIGURE_ANGLE_LEG_RIGHT];
	snap.angleOfRightLegAccessory   = [defaults floatForKey:MINIFIGURE_ANGLE_LEG_RIGHT_ACCESSORY];

	snap.colorHat               = [defaults integerForKey:MINIFIGURE_COLOR_HAT];
	snap.colorHead              = [defaults integerForKey:MINIFIGURE_COLOR_HEAD];
	snap.colorNeck              = [defaults integerForKey:MINIFIGURE_COLOR_NECK];
	snap.colorTorso             = [defaults integerForKey:MINIFIGURE_COLOR_TORSO];
	snap.colorArmRight          = [defaults integerForKey:MINIFIGURE_COLOR_ARM_RIGHT];
	snap.colorHandRight         = [defaults integerForKey:MINIFIGURE_COLOR_HAND_RIGHT];
	snap.colorHandRightAccessory = [defaults integerForKey:MINIFIGURE_COLOR_HAND_RIGHT_ACCESSORY];
	snap.colorArmLeft           = [defaults integerForKey:MINIFIGURE_COLOR_ARM_LEFT];
	snap.colorHandLeft          = [defaults integerForKey:MINIFIGURE_COLOR_HAND_LEFT];
	snap.colorHandLeftAccessory  = [defaults integerForKey:MINIFIGURE_COLOR_HAND_LEFT_ACCESSORY];
	snap.colorHips              = [defaults integerForKey:MINIFIGURE_COLOR_HIPS];
	snap.colorLegRight          = [defaults integerForKey:MINIFIGURE_COLOR_LEG_RIGHT];
	snap.colorLegRightAccessory  = [defaults integerForKey:MINIFIGURE_COLOR_LEG_RIGHT_ACCESSORY];
	snap.colorLegLeft           = [defaults integerForKey:MINIFIGURE_COLOR_LEG_LEFT];
	snap.colorLegLeftAccessory   = [defaults integerForKey:MINIFIGURE_COLOR_LEG_LEFT_ACCESSORY];

	snap.partNameHat            = [defaults stringForKey:MINIFIGURE_PARTNAME_HAT];
	snap.partNameHead           = [defaults stringForKey:MINIFIGURE_PARTNAME_HEAD];
	snap.partNameNeck           = [defaults stringForKey:MINIFIGURE_PARTNAME_NECK];
	snap.partNameTorso          = [defaults stringForKey:MINIFIGURE_PARTNAME_TORSO];
	snap.partNameArmRight       = [defaults stringForKey:MINIFIGURE_PARTNAME_ARM_RIGHT];
	snap.partNameHandRight      = [defaults stringForKey:MINIFIGURE_PARTNAME_HAND_RIGHT];
	snap.partNameHandRightAccessory = [defaults stringForKey:MINIFIGURE_PARTNAME_HAND_RIGHT_ACCESSORY];
	snap.partNameArmLeft        = [defaults stringForKey:MINIFIGURE_PARTNAME_ARM_LEFT];
	snap.partNameHandLeft       = [defaults stringForKey:MINIFIGURE_PARTNAME_HAND_LEFT];
	snap.partNameHandLeftAccessory  = [defaults stringForKey:MINIFIGURE_PARTNAME_HAND_LEFT_ACCESSORY];
	snap.partNameHips           = [defaults stringForKey:MINIFIGURE_PARTNAME_HIPS];
	snap.partNameLegRight       = [defaults stringForKey:MINIFIGURE_PARTNAME_LEG_RIGHT];
	snap.partNameLegRightAccessory  = [defaults stringForKey:MINIFIGURE_PARTNAME_LEG_RIGHT_ACCESSORY];
	snap.partNameLegLeft        = [defaults stringForKey:MINIFIGURE_PARTNAME_LEG_LEFT];
	snap.partNameLegLeftAccessory   = [defaults stringForKey:MINIFIGURE_PARTNAME_LEG_LEFT_ACCESSORY];

	return snap;
}


//---------- writeToUserDefaults: ------------------------------------[instance]
//
// Purpose:		Writes current values out of preferences.
//
// Notes:		Wow what a horrific method.
//
//------------------------------------------------------------------------------
- (void)writeToUserDefaults:(NSUserDefaults *)defaults
{
	[defaults setBool:self.hasHat                        forKey:MINIFIGURE_HAS_HAT];
	[defaults setBool:self.hasNeckAccessory              forKey:MINIFIGURE_HAS_NECK];
	[defaults setBool:self.hasHips                       forKey:MINIFIGURE_HAS_HIPS];
	[defaults setBool:self.hasRightArm                   forKey:MINIFIGURE_HAS_ARM_RIGHT];
	[defaults setBool:self.hasRightHand                  forKey:MINIFIGURE_HAS_HAND_RIGHT];
	[defaults setBool:self.hasRightHandAccessory         forKey:MINIFIGURE_HAS_HAND_RIGHT_ACCESSORY];
	[defaults setBool:self.hasLeftArm                    forKey:MINIFIGURE_HAS_ARM_LEFT];
	[defaults setBool:self.hasLeftHand                   forKey:MINIFIGURE_HAS_HAND_LEFT];
	[defaults setBool:self.hasLeftHandAccessory          forKey:MINIFIGURE_HAS_HAND_LEFT_ACCESSORY];
	[defaults setBool:self.hasRightLeg                   forKey:MINIFIGURE_HAS_LEG_RIGHT];
	[defaults setBool:self.hasRightLegAccessory          forKey:MINIFIGURE_HAS_LEG_RIGHT_ACCESSORY];
	[defaults setBool:self.hasLeftLeg                    forKey:MINIFIGURE_HAS_LEG_LEFT];
	[defaults setBool:self.hasLeftLegAccessory           forKey:MINIFIGURE_HAS_LEG_LEFT_ACCESSORY];

	[defaults setFloat:self.headElevation                forKey:MINIFIGURE_HEAD_ELEVATION];

	[defaults setFloat:self.angleOfHat                   forKey:MINIFIGURE_ANGLE_HAT];
	[defaults setFloat:self.angleOfHead                  forKey:MINIFIGURE_ANGLE_HEAD];
	[defaults setFloat:self.angleOfNeck                  forKey:MINIFIGURE_ANGLE_NECK];
	[defaults setFloat:self.angleOfLeftArm               forKey:MINIFIGURE_ANGLE_ARM_LEFT];
	[defaults setFloat:self.angleOfRightArm              forKey:MINIFIGURE_ANGLE_ARM_RIGHT];
	[defaults setFloat:self.angleOfLeftHand              forKey:MINIFIGURE_ANGLE_HAND_LEFT];
	[defaults setFloat:self.angleOfLeftHandAccessory     forKey:MINIFIGURE_ANGLE_HAND_LEFT_ACCESSORY];
	[defaults setFloat:self.angleOfRightHand             forKey:MINIFIGURE_ANGLE_HAND_RIGHT];
	[defaults setFloat:self.angleOfRightHandAccessory    forKey:MINIFIGURE_ANGLE_HAND_RIGHT_ACCESSORY];
	[defaults setFloat:self.angleOfLeftLeg               forKey:MINIFIGURE_ANGLE_LEG_LEFT];
	[defaults setFloat:self.angleOfLeftLegAccessory      forKey:MINIFIGURE_ANGLE_LEG_LEFT_ACCESSORY];
	[defaults setFloat:self.angleOfRightLeg              forKey:MINIFIGURE_ANGLE_LEG_RIGHT];
	[defaults setFloat:self.angleOfRightLegAccessory     forKey:MINIFIGURE_ANGLE_LEG_RIGHT_ACCESSORY];

	[defaults setInteger:self.colorHat                   forKey:MINIFIGURE_COLOR_HAT];
	[defaults setInteger:self.colorHead                  forKey:MINIFIGURE_COLOR_HEAD];
	[defaults setInteger:self.colorNeck                  forKey:MINIFIGURE_COLOR_NECK];
	[defaults setInteger:self.colorTorso                 forKey:MINIFIGURE_COLOR_TORSO];
	[defaults setInteger:self.colorArmRight              forKey:MINIFIGURE_COLOR_ARM_RIGHT];
	[defaults setInteger:self.colorHandRight             forKey:MINIFIGURE_COLOR_HAND_RIGHT];
	[defaults setInteger:self.colorHandRightAccessory    forKey:MINIFIGURE_COLOR_HAND_RIGHT_ACCESSORY];
	[defaults setInteger:self.colorArmLeft               forKey:MINIFIGURE_COLOR_ARM_LEFT];
	[defaults setInteger:self.colorHandLeft              forKey:MINIFIGURE_COLOR_HAND_LEFT];
	[defaults setInteger:self.colorHandLeftAccessory     forKey:MINIFIGURE_COLOR_HAND_LEFT_ACCESSORY];
	[defaults setInteger:self.colorHips                  forKey:MINIFIGURE_COLOR_HIPS];
	[defaults setInteger:self.colorLegRight              forKey:MINIFIGURE_COLOR_LEG_RIGHT];
	[defaults setInteger:self.colorLegRightAccessory     forKey:MINIFIGURE_COLOR_LEG_RIGHT_ACCESSORY];
	[defaults setInteger:self.colorLegLeft               forKey:MINIFIGURE_COLOR_LEG_LEFT];
	[defaults setInteger:self.colorLegLeftAccessory      forKey:MINIFIGURE_COLOR_LEG_LEFT_ACCESSORY];

	[defaults setObject:self.partNameHat                 forKey:MINIFIGURE_PARTNAME_HAT];
	[defaults setObject:self.partNameHead                forKey:MINIFIGURE_PARTNAME_HEAD];
	[defaults setObject:self.partNameNeck                forKey:MINIFIGURE_PARTNAME_NECK];
	[defaults setObject:self.partNameTorso               forKey:MINIFIGURE_PARTNAME_TORSO];
	[defaults setObject:self.partNameArmRight            forKey:MINIFIGURE_PARTNAME_ARM_RIGHT];
	[defaults setObject:self.partNameHandRight           forKey:MINIFIGURE_PARTNAME_HAND_RIGHT];
	[defaults setObject:self.partNameHandRightAccessory  forKey:MINIFIGURE_PARTNAME_HAND_RIGHT_ACCESSORY];
	[defaults setObject:self.partNameArmLeft             forKey:MINIFIGURE_PARTNAME_ARM_LEFT];
	[defaults setObject:self.partNameHandLeft            forKey:MINIFIGURE_PARTNAME_HAND_LEFT];
	[defaults setObject:self.partNameHandLeftAccessory   forKey:MINIFIGURE_PARTNAME_HAND_LEFT_ACCESSORY];
	[defaults setObject:self.partNameHips                forKey:MINIFIGURE_PARTNAME_HIPS];
	[defaults setObject:self.partNameLegRight            forKey:MINIFIGURE_PARTNAME_LEG_RIGHT];
	[defaults setObject:self.partNameLegRightAccessory   forKey:MINIFIGURE_PARTNAME_LEG_RIGHT_ACCESSORY];
	[defaults setObject:self.partNameLegLeft             forKey:MINIFIGURE_PARTNAME_LEG_LEFT];
	[defaults setObject:self.partNameLegLeftAccessory    forKey:MINIFIGURE_PARTNAME_LEG_LEFT_ACCESSORY];
}


//---------- applyInclusionAndAnglesToTarget: ------------------------[instance]
//
//------------------------------------------------------------------------------
- (void)applyInclusionAndAnglesToTarget:(id)target
{
	for (NSString *key in [LDrawMinifigureSpec inclusionAndAngleKeys])
	{
		[target setValue:[self valueForKey:key] forKey:key];
	}
}


//---------- takeInclusionAndAnglesFromTarget: -----------------------[instance]
//
//------------------------------------------------------------------------------
- (void)takeInclusionAndAnglesFromTarget:(id)target
{
	for (NSString *key in [LDrawMinifigureSpec inclusionAndAngleKeys])
	{
		[self setValue:[target valueForKey:key] forKey:key];
	}
}


//---------- colorKeys ------------------------------------------------[static]--
//
// Purpose:		Color-code property names in prefs slot order. The host still
//				maps those codes onto color wells.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)colorKeys
{
	return @[
		@"colorHat",
		@"colorHead",
		@"colorNeck",
		@"colorTorso",
		@"colorArmRight",
		@"colorHandRight",
		@"colorHandRightAccessory",
		@"colorArmLeft",
		@"colorHandLeft",
		@"colorHandLeftAccessory",
		@"colorHips",
		@"colorLegRight",
		@"colorLegRightAccessory",
		@"colorLegLeft",
		@"colorLegLeftAccessory",
	];
}


//---------- partNameKeys --------------------------------------------[static]--
//
// Purpose:		Part-name property names in the same slot order. The host still
//				selects catalog parts in array controllers.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)partNameKeys
{
	return @[
		@"partNameHat",
		@"partNameHead",
		@"partNameNeck",
		@"partNameTorso",
		@"partNameArmRight",
		@"partNameHandRight",
		@"partNameHandRightAccessory",
		@"partNameArmLeft",
		@"partNameHandLeft",
		@"partNameHandLeftAccessory",
		@"partNameHips",
		@"partNameLegRight",
		@"partNameLegRightAccessory",
		@"partNameLegLeft",
		@"partNameLegLeftAccessory",
	];
}


//---------- colorCodeAtIndex: ---------------------------------------[instance]
//
//------------------------------------------------------------------------------
- (NSInteger)colorCodeAtIndex:(NSUInteger)index
{
	NSArray *keys = [[self class] colorKeys];
	if (index >= [keys count]) return 0;
    
	return [[self valueForKey:[keys objectAtIndex:index]] integerValue];
}


//---------- setColorCode:atIndex: -----------------------------------[instance]
//
//------------------------------------------------------------------------------
- (void)setColorCode:(NSInteger)code atIndex:(NSUInteger)index
{
	NSArray *keys = [[self class] colorKeys];
	if (index < [keys count])
	{
		[self setValue:@(code) forKey:[keys objectAtIndex:index]];
	}
}


//---------- partNameAtIndex: ----------------------------------------[instance]
//
// Purpose:		Parts are identified in user defaults by their reference name,
//				such as "3001.dat".
//
//------------------------------------------------------------------------------
- (NSString *)partNameAtIndex:(NSUInteger)index
{
	NSArray *keys = [[self class] partNameKeys];
	if (index >= [keys count]) return nil;
    
	return [self valueForKey:[keys objectAtIndex:index]];
}


//---------- setPartName:atIndex: ------------------------------------[instance]
//
//------------------------------------------------------------------------------
- (void)setPartName:(NSString *)name atIndex:(NSUInteger)index
{
	NSArray *keys = [[self class] partNameKeys];
	if (index < [keys count])
	{
		[self setValue:name forKey:[keys objectAtIndex:index]];
	}
}


//---------- setColorCodesFromColors: --------------------------------[instance]
//
// Purpose:		Writes current values out of preferences. Color wells stay on
//				the host.
//
//------------------------------------------------------------------------------
- (void)setColorCodesFromColors:(NSArray *)colors
{
	NSUInteger i;
	NSUInteger count = MIN([colors count], [[[self class] colorKeys] count]);
	for (i = 0; i < count; i++)
	{
		[self setColorCode:[[colors objectAtIndex:i] colorCode] atIndex:i];
	}
}


//---------- setPartNamesFromSlotSelections: -------------------------[instance]
//
// Purpose:		Parts are identified in user defaults by their reference name,
//				such as "3001.dat". The host still reads NSArrayControllers.
//
//------------------------------------------------------------------------------
- (void)setPartNamesFromSlotSelections:(NSArray *)selections
{
	NSUInteger i;
	NSUInteger count = MIN([selections count], [[[self class] partNameKeys] count]);
	for (i = 0; i < count; i++)
	{
		NSArray *selection = [selections objectAtIndex:i];
		[self setPartName:[[selection objectAtIndex:0] referenceName] atIndex:i];
	}
}


//---------- colorCodesInSlotOrder -----------------------------------[instance]
//
// Purpose:		Reads previous color codes out of preferences. The host still
//				maps them onto wells.
//
//------------------------------------------------------------------------------
- (NSArray<NSNumber *> *)colorCodesInSlotOrder
{
	NSArray        *keys  = [[self class] colorKeys];
	NSMutableArray *codes = [NSMutableArray array];
	NSUInteger      i;
	for (i = 0; i < [keys count]; i++)
	{
		[codes addObject:@([self colorCodeAtIndex:i])];
	}
	return codes;
}


//---------- partNamesInSlotOrder ------------------------------------[instance]
//
// Purpose:		Parts are identified in user defaults by their reference name,
//				such as "3001.dat". The host still selects them in controllers.
//
//------------------------------------------------------------------------------
- (NSArray *)partNamesInSlotOrder
{
	NSArray        *keys  = [[self class] partNameKeys];
	NSMutableArray *names = [NSMutableArray array];
	NSUInteger      i;
	for (i = 0; i < [keys count]; i++)
	{
		NSString *name = [self partNameAtIndex:i];
		[names addObject:(name != nil) ? name : @""];
	}
	return names;
}


//---------- indexOfPartNamed:inParts: -------------------------------[static]--
//
// Purpose:		Parts are identified in user defaults by their reference name,
//				such as "3001.dat". This method finds the actual part object
//				based on the name. The host still selects it in the controller.
//
//------------------------------------------------------------------------------
+ (NSUInteger)indexOfPartNamed:(NSString *)name inParts:(NSArray *)parts
{
	NSUInteger counter = 0;
	for (LDrawPart *currentPart in parts)
	{
		if ([[currentPart referenceName] isEqualToString:name])
		{
			return counter;
		}
		counter++;
	}
	return NSNotFound;
}

@end
