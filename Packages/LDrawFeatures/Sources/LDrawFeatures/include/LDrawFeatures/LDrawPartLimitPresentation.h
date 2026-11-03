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

@class LDrawInventoryStore;
@class LDrawPart;
@class LDrawPartLimit;
@class LDrawPartLimitReport;
@class LDrawPartLimitTable;
@class LDrawPartReplacement;

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
/// @discussion Text is looked up through LDrawLocalization, in the bundle the
///             host names.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitPresentation : NSObject

/// The SF Symbol of a status's badge in a list of the model, or nil for none.
+ (nullable NSString *)badgeSymbolNameForStatus:(LDrawPartLimitStatus)status;

/// The color of a status's badge.
+ (LDrawPartLimitBadgeTint)badgeTintForStatus:(LDrawPartLimitStatus)status;

/// What menus and headings call a limit: All Parts, Available Now, or the
/// inventory's title. An inventory the store lacks is Missing Inventory.
+ (NSString *)titleForLimit:(LDrawPartLimit *)limit store:(nullable LDrawInventoryStore *)store
	NS_SWIFT_NAME(title(forLimit:store:));

/// A status's name in a list, such as "Too many". Empty for allowed.
+ (NSString *)titleForStatus:(LDrawPartLimitStatus)status NS_SWIFT_NAME(statusTitle(for:));

/// How many parts have a status, such as "3 not available".
+ (NSString *)summaryForStatus:(LDrawPartLimitStatus)status count:(NSUInteger)count
	NS_SWIFT_NAME(summary(for:count:));

/// What a status means, for a tooltip. Empty for allowed.
+ (NSString *)explanationForStatus:(LDrawPartLimitStatus)status NS_SWIFT_NAME(explanation(for:));

/// How a part in the report breaks the limit, in a short line, or fully for
/// a tooltip. Nil for a part within it.
+ (nullable NSString *)lineForPart:(LDrawPart *)part
							report:(LDrawPartLimitReport *)report
							 store:(nullable LDrawInventoryStore *)store
							 fully:(BOOL)fully
	NS_SWIFT_NAME(line(for:report:store:fully:));

/// How a replacement would stand against the table, in a short line: how
/// many the model would use of what the inventory holds, or why the limit
/// does not allow it. Nil when there is nothing to say.
+ (nullable NSString *)lineForReplacement:(LDrawPartReplacement *)replacement
									table:(LDrawPartLimitTable *)table
									store:(nullable LDrawInventoryStore *)store
	NS_SWIFT_NAME(line(for:table:store:));

/// The color among `colors` nearest to `color` in RGB, or nil when there are
/// none. A color among them is its own nearest.
+ (nullable LDrawColor *)nearestColorTo:(LDrawColor *)color amongColors:(NSArray<LDrawColor *> *)colors
	NS_SWIFT_NAME(nearestColor(to:among:));

@end

NS_ASSUME_NONNULL_END
