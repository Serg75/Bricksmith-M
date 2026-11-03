//==============================================================================
//
//  File:       LDrawPartLimitChecker.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawPartLimitStatus.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>

@class LDrawColor;
@class LDrawFile;
@class LDrawInventoryStore;
@class LDrawPart;
@class LDrawPartLimitReport;
@class LDrawPartLimitTable;
@class LDrawPartUsage;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitBadge
///
/// @abstract   What a host shows for a part, a step or a model: a symbol, its
///             tint and a count. Immutable.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitBadge : NSObject

/// The SF Symbol, or nil for no badge.
@property (nonatomic, readonly, copy, nullable) NSString *symbolName;

@property (nonatomic, readonly) LDrawPartLimitBadgeTint tint;

/// The number shown next to the symbol, or 0 for none.
@property (nonatomic, readonly) NSUInteger count;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitChecker
///
/// @abstract   One file's check against the parts limit, and what a host shows
///             for it.
///
/// @discussion The walk of the model and the counts of parts missing from the
///             part library are kept until the host says the model changed.
///             The host decides when to check, and redraws when a mark
///             changed.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitChecker : NSObject

- (instancetype)initWithFile:(LDrawFile *)file NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// The file checked. A host makes a new checker when its file is replaced.
@property (nonatomic, readonly, weak, nullable) LDrawFile *file;

/// What the model uses, walked when first asked for after an edit.
@property (nonatomic, readonly, nullable) LDrawPartUsage *usage;

/// The last check, or nil when no limit was on.
@property (nonatomic, readonly, nullable) LDrawPartLimitReport *report;

/// Whether problems are shown: the last check was under a limit, and parts
/// are marked.
@property (nonatomic, readonly) BOOL showsMarks;

/// Drops what was kept of the model. Call it after every edit.
- (void)modelDidChange;

/// Checks the file against the table and marks each part with its status.
/// YES when a mark changed. With no limit the walk is skipped, once the
/// marks of an earlier limit are cleared.
- (BOOL)checkAgainstTable:(LDrawPartLimitTable *)table NS_SWIFT_NAME(check(against:));

// MARK: - A list of the model

/// A part's badge says how it breaks the limit; a step or model's says how
/// many of its parts do, in the tint of the worst. Parts the part library
/// lacks get a gray badge of their own, with or without a limit, unless they
/// break it.
- (LDrawPartLimitBadge *)badgeForItem:(id)item NS_SWIFT_NAME(badge(for:));

/// Why a part's badge is there, or how many of a step's or model's parts
/// break the limit or are missing. Nil when there is nothing to say.
- (nullable NSString *)toolTipForItem:(id)item store:(nullable LDrawInventoryStore *)store
	NS_SWIFT_NAME(toolTip(for:store:));

/// A short line on how a part breaks the limit, or nil when it is within it
/// or problems are not shown.
- (nullable NSString *)lineForPart:(LDrawPart *)part store:(nullable LDrawInventoryStore *)store
	NS_SWIFT_NAME(line(for:store:));

// MARK: - The summary

/// The file's problem count, in the tint of the worst problem. With none,
/// once the limit has data, it counts in gray the parts with no data or not
/// in the part library. A count of 0 means nothing to show.
- (LDrawPartLimitBadge *)summaryBadge;

/// What the summary badge counts.
- (NSString *)summaryToolTip;

/// The statuses the file's parts have, as NSNumbers: worst first, then no
/// data.
- (NSArray<NSNumber *> *)summaryStatuses;

/// Each part not made in its color, with the nearest color it is made in.
/// Parts in color 16, which take the color of what places them, and parts
/// already in their nearest color are left out.
- (NSMapTable<LDrawPart *, LDrawColor *> *)nearestAllowedColors;

@end

NS_ASSUME_NONNULL_END
