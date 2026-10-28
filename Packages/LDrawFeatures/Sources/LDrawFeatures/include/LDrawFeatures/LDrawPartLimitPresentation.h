//==============================================================================
//
//  File:       LDrawPartLimitPresentation.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawPartLimitStatus.h>

NS_ASSUME_NONNULL_BEGIN

/// Which color a badge takes.
typedef NS_ENUM(NSInteger, LDrawPartLimitBadgeTint)
{
	LDrawPartLimitBadgeTintNone			= 0,

	/// The mark color of parts not available or not in their color.
	LDrawPartLimitBadgeTintNotAvailable	= 1,

	/// The mark color of too many.
	LDrawPartLimitBadgeTintTooMany		= 2,

	/// Gray, for no data.
	LDrawPartLimitBadgeTintGray			= 3
};


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitPresentation
///
/// @abstract   How a host shows a part's status against the parts limit, and
///             the nearest color a part is made in.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitPresentation : NSObject

/// The SF Symbol of a status's badge in a list of the model, or nil for none.
+ (nullable NSString *)badgeSymbolNameForStatus:(LDrawPartLimitStatus)status;

+ (LDrawPartLimitBadgeTint)badgeTintForStatus:(LDrawPartLimitStatus)status;

/// The color among `colors` nearest to `color` in RGB, or nil when there are
/// none. A color among them is its own nearest.
+ (nullable LDrawColor *)nearestColorTo:(LDrawColor *)color amongColors:(NSArray<LDrawColor *> *)colors
	NS_SWIFT_NAME(nearestColor(to:among:));

@end

NS_ASSUME_NONNULL_END
