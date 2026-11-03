//==============================================================================
//
//  File:       LDrawPartLimitPresentation.m
//  Package:    LDrawFeatures
//
//  Purpose:    How a host shows a part's status against the parts limit: its
//              badge, the text about it, and the nearest color a part is made
//              in.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartLimitPresentation.h>

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartReplacements.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

/// How many color names a list shows before "and N more".
static const NSUInteger ListedColorCount = 3;


@implementation LDrawPartLimitPresentation


// MARK: - BADGES -


//---------- badgeSymbolNameForStatus: -------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)badgeSymbolNameForStatus:(LDrawPartLimitStatus)status
{
	switch (status)
	{
		case LDrawPartLimitStatusNotAvailable:	return @"nosign";
		case LDrawPartLimitStatusNotInColor:	return @"exclamationmark.circle.fill";
		case LDrawPartLimitStatusTooMany:		return @"plus.circle.fill";
		case LDrawPartLimitStatusNoData:		return @"questionmark.circle";
		case LDrawPartLimitStatusAllowed:		return nil;
	}
	return nil;
}


//---------- badgeTintForStatus: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (LDrawPartLimitBadgeTint)badgeTintForStatus:(LDrawPartLimitStatus)status
{
	switch (status)
	{
		case LDrawPartLimitStatusNotAvailable:
		case LDrawPartLimitStatusNotInColor:	return LDrawPartLimitBadgeTintNotAvailable;
		case LDrawPartLimitStatusTooMany:		return LDrawPartLimitBadgeTintTooMany;
		case LDrawPartLimitStatusNoData:		return LDrawPartLimitBadgeTintGray;
		case LDrawPartLimitStatusAllowed:		return LDrawPartLimitBadgeTintNone;
	}
	return LDrawPartLimitBadgeTintNone;
}


// MARK: - TEXT -


//---------- titleForLimit:store: ------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)titleForLimit:(LDrawPartLimit *)limit store:(LDrawInventoryStore *)store
{
	NSString *title = nil;

	switch (limit.kind)
	{
		case LDrawPartLimitKindNone:			return [LDrawLocalization stringForKey:@"All Parts"];
		case LDrawPartLimitKindAvailableNow:	return [LDrawLocalization stringForKey:@"Available Now"];
		case LDrawPartLimitKindInventory:
			title = [store titleForInventoryIdentifier:limit.inventoryIdentifier ?: @""];
			break;
	}
	return title ?: [LDrawLocalization stringForKey:@"Missing Inventory"];
}


//---------- titleForStatus: -----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)titleForStatus:(LDrawPartLimitStatus)status
{
	switch (status)
	{
		case LDrawPartLimitStatusNotAvailable:	return [LDrawLocalization stringForKey:@"Not available"];
		case LDrawPartLimitStatusNotInColor:	return [LDrawLocalization stringForKey:@"Not in this color"];
		case LDrawPartLimitStatusTooMany:		return [LDrawLocalization stringForKey:@"Too many"];
		case LDrawPartLimitStatusNoData:		return [LDrawLocalization stringForKey:@"No data"];
		case LDrawPartLimitStatusAllowed:		return @"";
	}
	return @"";
}


//---------- summaryForStatus:count: ---------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)summaryForStatus:(LDrawPartLimitStatus)status count:(NSUInteger)count
{
	NSString *key = @"%lu";

	switch (status)
	{
		case LDrawPartLimitStatusNotAvailable:	key = @"%lu not available";					break;
		case LDrawPartLimitStatusNotInColor:	key = @"%lu not made in their color";		break;
		case LDrawPartLimitStatusTooMany:		key = @"%lu more than the inventory holds";	break;
		case LDrawPartLimitStatusNoData:		key = @"%lu with no data";					break;
		case LDrawPartLimitStatusAllowed:											break;
	}
	return [NSString localizedStringWithFormat:[LDrawLocalization stringForKey:key], (unsigned long)count];
}


//---------- explanationForStatus: -----------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)explanationForStatus:(LDrawPartLimitStatus)status
{
	switch (status)
	{
		case LDrawPartLimitStatusNotAvailable:
			return [LDrawLocalization stringForKey:@"The limit does not allow these parts in any color."];
		case LDrawPartLimitStatusNotInColor:
			return [LDrawLocalization stringForKey:@"The limit allows these parts, but not in the color they have."];
		case LDrawPartLimitStatusTooMany:
			return [LDrawLocalization stringForKey:@"Copies past what the inventory holds, counted in build order."];
		case LDrawPartLimitStatusNoData:
			return [LDrawLocalization stringForKey:@"Rebrickable knows nothing of these parts or colors, so they "
												   @"are not checked."];
		case LDrawPartLimitStatusAllowed:
			return @"";
	}
	return @"";
}


//---------- lineForPart:report:store:fully: -------------------------[static]--
///
/// @abstract	The part is described in the color it was checked in: a part in
/// 			color 16 takes the color of what places it.
///
//------------------------------------------------------------------------------
+ (NSString *)lineForPart:(LDrawPart *)part
				   report:(LDrawPartLimitReport *)report
					store:(LDrawInventoryStore *)store
					fully:(BOOL)fully
{
	LDrawPartLimitTable		*table		= report.table;
	LDrawPartLimitStatus	 status		= [report statusForPart:part];
	NSString				*partName	= [part displayName];
	LDrawColor				*color		= [part LDrawColor];
	LDrawColorT				 checked	= [report colorCodeForPart:part];

	if (checked != LDrawColorBogus && checked != [color colorCode])
		color = [[LDrawColorLibrary sharedColorLibrary] colorForCode:checked] ?: color;

	if (status == LDrawPartLimitStatusTooMany)
	{
		LDrawPartLibrary	*library	= [LDrawPartLibrary sharedPartLibraryIfRegistered];
		NSString			*inventory	= [self titleForLimit:table.limit store:store];
		NSUInteger			 used		= [report usedCountForPartNamed:partName colorCode:[color colorCode]];
		NSUInteger			 owned		= [table ownedCountForPartNamed:partName colorCode:[color colorCode]];
		NSString			*what		= [library descriptionForPartName:partName] ?: partName;
		NSString			*format		= nil;

		if (fully == NO)
			return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"Uses %lu of %lu in %@"],
					(unsigned long)used, (unsigned long)owned, inventory];
		format = [LDrawLocalization stringForKey:@"The model uses %lu %@ %@; %@ holds %lu."];
		return [NSString stringWithFormat:format,
				(unsigned long)used, [color localizedName], what, inventory, (unsigned long)owned];
	}
	return [self lineForStatus:status partName:partName color:color table:table store:store fully:fully];
}


//---------- lineForReplacement:table:store: -------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)lineForReplacement:(LDrawPartReplacement *)replacement
						   table:(LDrawPartLimitTable *)table
						   store:(LDrawInventoryStore *)store
{
	LDrawColor *color = nil;

	if (replacement.usedCount != NSNotFound)
		return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"Uses %lu of %lu in %@"],
				(unsigned long)replacement.usedCount, (unsigned long)replacement.ownedCount,
				[self titleForLimit:table.limit store:store]];

	if (replacement.colorCode != LDrawColorBogus)
		color = [[LDrawColorLibrary sharedColorLibrary] colorForCode:replacement.colorCode];
	return [self lineForStatus:replacement.status
					  partName:replacement.partName
						 color:color
						 table:table
						 store:store
						 fully:NO];
}


//---------- lineForStatus:partName:color:table:store:fully: ---------[static]--
///
/// @abstract	Why the limit does not allow the part in the color. Nil when it
/// 			does, and for too many, which needs the counts. The color is nil
/// 			when not known.
///
//------------------------------------------------------------------------------
+ (NSString *)lineForStatus:(LDrawPartLimitStatus)status
				   partName:(NSString *)partName
					  color:(LDrawColor *)color
					  table:(LDrawPartLimitTable *)table
					  store:(LDrawInventoryStore *)store
					  fully:(BOOL)fully
{
	BOOL		 isNow		= (table.limit.kind == LDrawPartLimitKindAvailableNow);
	NSString	*inventory	= [self titleForLimit:table.limit store:store];
	NSString	*colorName	= [color localizedName];
	NSString	*line		= nil;
	NSString	*key		= nil;

	switch (status)
	{
		case LDrawPartLimitStatusAllowed:
		case LDrawPartLimitStatusTooMany:
			return nil;

		case LDrawPartLimitStatusNoData:
			// In a color with no match, every part has no data.
			if (color != nil && [table hasData] && [table matchesColorCode:[color colorCode]] == NO)
			{
				key = fully ? @"Bricksmith cannot match %@ to a LEGO color." : @"No LEGO color matches %@";
				return [NSString stringWithFormat:[LDrawLocalization stringForKey:key], colorName];
			}
			return [LDrawLocalization stringForKey:fully ? @"Bricksmith cannot match this part to a LEGO part."
														 : @"No LEGO part matches it"];

		case LDrawPartLimitStatusNotAvailable:
			line = isNow ? [LDrawLocalization stringForKey:@"Not made now in any color"]
						 : [NSString stringWithFormat:[LDrawLocalization stringForKey:@"Not in %@"], inventory];
			return fully ? [line stringByAppendingString:@"."] : line;

		case LDrawPartLimitStatusNotInColor:
			line = isNow ? [NSString stringWithFormat:[LDrawLocalization stringForKey:@"Not made in %@ now"], colorName]
						 : [NSString stringWithFormat:[LDrawLocalization stringForKey:@"Not in %@ in %@"],
							inventory, colorName];
			if (fully == NO)
				return line;
			key = isNow ? @"%@. Made in %@." : @"%@. It has %@.";
			return [NSString stringWithFormat:[LDrawLocalization stringForKey:key],
					line, [self listOfColorCodes:[table colorCodesForPartNamed:partName]]];
	}
	return nil;
}


//---------- listOfColorCodes: ---------------------------------------[static]--
///
/// @abstract	"Black, Red, Light Bluish Gray and 11 more".
///
//------------------------------------------------------------------------------
+ (NSString *)listOfColorCodes:(NSArray<NSNumber *> *)codes
{
	LDrawColorLibrary	*library	= [LDrawColorLibrary sharedColorLibrary];
	NSMutableArray		*names		= [NSMutableArray array];
	NSUInteger			 shown		= MIN([codes count], ListedColorCount);

	for (NSUInteger index = 0; index < shown; index++)
		[names addObject:[[library colorForCode:(LDrawColorT)[codes[index] intValue]] localizedName] ?: @"?"];

	if ([codes count] > shown)
		return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%@ and %lu more"],
				[names componentsJoinedByString:@", "], (unsigned long)([codes count] - shown)];
	if ([names count] > 1)
		return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%@ and %@"],
				[[names subarrayWithRange:NSMakeRange(0, [names count] - 1)] componentsJoinedByString:@", "],
				[names lastObject]];
	return [names firstObject] ?: @"";
}


// MARK: - COLORS -


//---------- nearestColorTo:amongColors: -----------------------------[static]--
///
/// @abstract	The color whose red, green and blue are the least distance away.
/// 			Alpha does not count, so a solid part may get a clear color.
///
//------------------------------------------------------------------------------
+ (LDrawColor *)nearestColorTo:(LDrawColor *)color amongColors:(NSArray<LDrawColor *> *)colors
{
	LDrawColor	*nearest	= nil;
	float		 best		= INFINITY;
	float		 from[4];

	[color getColorRGBA:from];

	for (LDrawColor *candidate in colors)
	{
		float to[4];
		float distance = 0.0f;

		[candidate getColorRGBA:to];
		for (int index = 0; index < 3; index++)
			distance += (to[index] - from[index]) * (to[index] - from[index]);

		if (distance < best)
		{
			best	= distance;
			nearest	= candidate;
		}
	}
	return nearest;
}

@end
