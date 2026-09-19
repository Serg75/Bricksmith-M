//==============================================================================
//
//  File:       LDrawMinifigureSpec.m
//  Package:    LDrawFeatures
//
//  Purpose:    Catalog-part packing for one minifigure layout. Pose KVC lives
//              on LDrawMinifigurePose.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawMinifigureSpec.h>

#import <LDrawCore/LDrawPart.h>


@interface LDrawMinifigureSpec ()
+ (NSArray<NSString *> *)partSlotKeys;
@end

@implementation LDrawMinifigureSpec

//---------- partSlotKeys --------------------------------------------[static]--
//
// Purpose:		Part property names in generator-dialog slot order.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)partSlotKeys
{
	return @[
		@"hat",
		@"head",
		@"neck",
		@"torso",
		@"leftArm",
		@"leftHand",
		@"leftHandAccessory",
		@"rightArm",
		@"rightHand",
		@"rightHandAccessory",
		@"hips",
		@"leftLeg",
		@"leftLegAccessory",
		@"rightLeg",
		@"rightLegAccessory",
	];
}


//---------- copiedPartsFromSlotSelections: --------------------------[static]--
//
// Purpose:		This is it! Copy the selected catalog part from each generator
//				slot. The host still reads NSArrayControllers.
//
//------------------------------------------------------------------------------
+ (NSArray *)copiedPartsFromSlotSelections:(NSArray *)selections
{
	NSMutableArray *parts = [NSMutableArray array];
	for (NSArray *selection in selections)
	{
		[parts addObject:[[selection objectAtIndex:0] copy]];
	}
	return parts;
}


//---------- setPartsInSlotOrder: ------------------------------------[instance]
//
// Purpose:		Assigns copied catalog parts in partSlotKeys order.
//
//------------------------------------------------------------------------------
- (void)setPartsInSlotOrder:(NSArray *)parts
{
	NSArray    *keys = [[self class] partSlotKeys];
	NSUInteger  count = MIN([parts count], [keys count]);
	NSUInteger  i;

	for (i = 0; i < count; i++)
	{
		[self setValue:[parts objectAtIndex:i] forKey:[keys objectAtIndex:i]];
	}
}


//---------- applyColorsInSlotOrder: ---------------------------------[instance]
//
// Purpose:		Applies colors onto those parts in the same order. The host
//				still owns color wells.
//
//------------------------------------------------------------------------------
- (void)applyColorsInSlotOrder:(NSArray *)colors
{
	NSArray    *keys = [[self class] partSlotKeys];
	NSUInteger  count = MIN([colors count], [keys count]);
	NSUInteger  i;

	for (i = 0; i < count; i++)
	{
		LDrawPart *part = [self valueForKey:[keys objectAtIndex:i]];
		[part setLDrawColor:[colors objectAtIndex:i]];
	}
}

@end
