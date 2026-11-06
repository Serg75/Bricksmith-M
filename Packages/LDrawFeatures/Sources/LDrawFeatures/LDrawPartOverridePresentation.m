//==============================================================================
//
//  File:       LDrawPartOverridePresentation.m
//  Package:    LDrawFeatures
//
//  Purpose:    How a host shows the parts in the overrides folder, and which
//              of them it has reported as outdated.
//
//  Created by Sergey Slobodenyuk on 2026-11-06.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartOverridePresentation.h>

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawPartOverride.h>

/// How many outdated parts the summary names before "N more".
static const NSUInteger SummaryNameCount = 5;


//========== ReportedKey =======================================================
///
/// @abstract	How an outdated override is saved as reported. A later library
/// 			release of the part makes a new key.
///
//==============================================================================
static NSString *ReportedKey(LDrawPartOverride *override)
{
	return [NSString stringWithFormat:@"%@ %@", [override partName], [override libraryUpdate]];
}


//========== PartNameOfReportedKey =============================================
///
/// @abstract	The part a saved key is about: the key up to its last space.
///
//==============================================================================
static NSString *PartNameOfReportedKey(NSString *key)
{
	NSRange space = [key rangeOfString:@" " options:NSBackwardsSearch];

	return (space.location != NSNotFound) ? [key substringToIndex:space.location] : key;
}


@implementation LDrawPartOverridePresentation


// MARK: - TEXT -


//---------- outdatedOverrides: --------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartOverride *> *)outdatedOverrides:(NSArray<LDrawPartOverride *> *)overrides
{
	NSPredicate *newer = [NSPredicate predicateWithBlock:^BOOL(LDrawPartOverride *override, NSDictionary *bindings) {
		return [override libraryIsNewer];
	}];

	return [overrides filteredArrayUsingPredicate:newer];
}


//---------- releasesOfOverride: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)releasesOfOverride:(LDrawPartOverride *)override
{
	return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%@: yours %@, library %@"],
			[override partName], [override update], [override libraryUpdate]];
}


//---------- summaryOfOverrides: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)summaryOfOverrides:(NSArray<LDrawPartOverride *> *)overrides
{
	NSArray						*outdated	= [self outdatedOverrides:overrides];
	NSMutableArray<NSString *>	*names		= [NSMutableArray array];
	NSString					*count		= nil;

	if ([overrides count] == 0)
		return [LDrawLocalization stringForKey:@"None in its parts or p folders."];

	if ([overrides count] == 1)
		count = [LDrawLocalization stringForKey:@"1 part."];
	else
		count = [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%lu parts."],
				 (unsigned long)[overrides count]];

	if ([outdated count] == 0)
		return count;

	for (LDrawPartOverride *override in outdated)
	{
		if ([names count] == SummaryNameCount)
		{
			[names addObject:[NSString stringWithFormat:[LDrawLocalization stringForKey:@"%lu more"],
							  (unsigned long)([outdated count] - SummaryNameCount)]];
			break;
		}
		[names addObject:[override partName]];
	}

	return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%@ The library has a newer version of %@."],
			count, [NSListFormatter localizedStringByJoiningStrings:names]];
}


//---------- detailsOfOverrides: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)detailsOfOverrides:(NSArray<LDrawPartOverride *> *)overrides
{
	NSArray *outdated = [self outdatedOverrides:overrides];

	if ([outdated count] == 0)
		return nil;

	return [self listOfOutdatedOverrides:outdated limit:[outdated count]];
}


//---------- listOfOutdatedOverrides:limit: --------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)listOfOutdatedOverrides:(NSArray<LDrawPartOverride *> *)outdated limit:(NSUInteger)limit
{
	NSUInteger					 listed	= MIN([outdated count], limit);
	NSMutableArray<NSString *>	*lines	= [NSMutableArray arrayWithCapacity:listed + 1];

	for (LDrawPartOverride *override in [outdated subarrayWithRange:NSMakeRange(0, listed)])
		[lines addObject:[self releasesOfOverride:override]];

	if ([outdated count] > listed)
	{
		[lines addObject:[NSString stringWithFormat:[LDrawLocalization stringForKey:@"and %lu more"],
						  (unsigned long)([outdated count] - listed)]];
	}

	return [lines componentsJoinedByString:@"\n"];
}


//---------- noteForFileAtPath: --------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)noteForFileAtPath:(NSString *)path
{
	NSString *update = [LDrawPartOverride updateOfFileAtPath:path];

	if (path == nil)
		return [LDrawLocalization stringForKey:@"Not in the library"];

	if (update == nil)
		return [path stringByAbbreviatingWithTildeInPath];

	return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%@ — release %@"],
			[path stringByAbbreviatingWithTildeInPath], update];
}


//---------- lineForChangedPartNames: --------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)lineForChangedPartNames:(NSArray<NSString *> *)partNames
{
	return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"Parts that differ: %@"],
			[partNames componentsJoinedByString:@", "]];
}


// MARK: - REPORTING -


//---------- recordOutdatedOverrides:inDefaults: ---------------------[static]--
///
/// @abstract	Saves the outdated overrides as reported. A saved part that is
/// 			not in the list keeps its entry, so a folder that could not be
/// 			read does not clear the record.
///
//------------------------------------------------------------------------------
+ (BOOL)recordOutdatedOverrides:(NSArray<LDrawPartOverride *> *)overrides
					 inDefaults:(NSUserDefaults *)userDefaults
{
	NSArray			*saved		= [userDefaults arrayForKey:PART_OVERRIDES_REPORTED_KEY] ?: @[];
	NSSet			*listed		= [NSSet setWithArray:[overrides valueForKey:@"partName"]];
	NSMutableArray	*record		= [NSMutableArray array];
	BOOL			 anyNew		= NO;

	for (NSString *key in saved)
	{
		if ([key isKindOfClass:[NSString class]] && [listed containsObject:PartNameOfReportedKey(key)] == NO)
			[record addObject:key];
	}

	for (LDrawPartOverride *override in [self outdatedOverrides:overrides])
	{
		NSString *key = ReportedKey(override);

		[record addObject:key];
		if ([saved containsObject:key] == NO)
			anyNew = YES;
	}

	if ([record isEqualToArray:saved] == NO)
		[userDefaults setObject:record forKey:PART_OVERRIDES_REPORTED_KEY];

	return anyNew;
}

@end
