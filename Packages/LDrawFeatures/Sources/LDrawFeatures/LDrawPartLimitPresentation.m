//==============================================================================
//
//  File:       LDrawPartLimitPresentation.m
//  Package:    LDrawFeatures
//
//  Purpose:    How a host shows a part's status against the parts limit, and
//              the nearest color a part is made in.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartLimitPresentation.h>


@implementation LDrawPartLimitPresentation


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
