//==============================================================================
//
//  File:       LDrawPartReplacements.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawPartLimitStatus.h>

@class LDrawPart;
@class LDrawPartIdentity;
@class LDrawPartLimitReport;
@class LDrawPartUsage;

NS_ASSUME_NONNULL_BEGIN

/// How a replacement is related to the part it replaces.
typedef NS_ENUM(NSInteger, LDrawPartReplacementKind)
{
	/// Another mold of the part, or an alternate Rebrickable counts as one.
	LDrawPartReplacementKindMold	= 0,

	/// The part a print or pattern is made on.
	LDrawPartReplacementKindPlain	= 1,

	/// A print or pattern made on the part.
	LDrawPartReplacementKindPrint	= 2
};


//------------------------------------------------------------------------------
///
/// @class      LDrawPartReplacement
///
/// @abstract   A part that can take the place of others, and how it would
///             stand against the limit once it does.
///
//------------------------------------------------------------------------------
@interface LDrawPartReplacement : NSObject

/// The LDraw part, e.g. "12825.dat".
@property (nonatomic, readonly, copy) NSString *partName;

@property (nonatomic, readonly) LDrawPartReplacementKind kind;

/// The color the status is for. LDrawColorBogus when the parts, or the
/// copies they stand for, differ in color.
@property (nonatomic, readonly) LDrawColorT colorCode;

/// Whether the parts take `colorCode`. NO keeps each part's own color.
@property (nonatomic, readonly) BOOL setsColor;

/// Allowed when no limit restricts. Too many when the model would use more
/// than the inventory holds.
@property (nonatomic, readonly) LDrawPartLimitStatus status;

/// How many the inventory holds in the color, or `NSNotFound` when the limit
/// does not count.
@property (nonatomic, readonly) NSUInteger ownedCount;

/// How many the model would use in the color, or `NSNotFound` when the
/// limit does not count.
@property (nonatomic, readonly) NSUInteger usedCount;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartReplacements
///
/// @abstract   The parts that can take the place of a part: its molds and
///             alternates, its plain part, and its prints.
///
/// @discussion Rebrickable's relations say which parts these are. Only parts
///             the library has are offered, so a part the library lacks can
///             be swapped for one it has.
///
//------------------------------------------------------------------------------
@interface LDrawPartReplacements : NSObject

/// The replacements for parts that share one name: molds first, then the
/// plain part, then prints. Within each, those the limit allows come first.
/// Empty when the parts differ in name or Rebrickable does not know them.
///
/// With a limit, each part is offered in the parts' color, and when it is
/// not made in that color, in each color the limit has it in. A color the
/// part is not made in is not offered when the limit does more than warn. The
/// parts keep their color when they differ in color or take the color of what
/// places them. A part in color 16 placed in several colors counts as parts
/// that differ in color. Prints are offered only when the limit allows them,
/// so a part with no limit offers no prints. `report` is the model's check,
/// or nil when no limit is on; `usage` counts how many copies the parts stand
/// for.
+ (NSArray<LDrawPartReplacement *> *) replacementsForParts:(NSArray<LDrawPart *> *)parts
													report:(nullable LDrawPartLimitReport *)report
													 usage:(nullable LDrawPartUsage *)usage
												  identity:(LDrawPartIdentity *)identity
											libraryHasPart:(BOOL (^)(NSString *partName))libraryHasPart
	NS_SWIFT_NAME(replacements(for:report:usage:identity:libraryHasPart:));

@end

NS_ASSUME_NONNULL_END
