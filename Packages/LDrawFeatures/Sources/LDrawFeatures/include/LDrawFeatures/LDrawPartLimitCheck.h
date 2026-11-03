//==============================================================================
//
//  File:       LDrawPartLimitCheck.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawPartLimitStatus.h>

@class LDrawContainer;
@class LDrawFile;
@class LDrawPart;
@class LDrawPartLimitTable;
@class LDrawPartUsage;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitRow
///
/// @abstract   One part and color the model uses, against the limit.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitRow : NSObject

/// The part and color of the first copy. Copies that count as one, such as a
/// part's molds, share the row.
@property (nonatomic, readonly, copy) NSString *partName;
@property (nonatomic, readonly) LDrawColorT colorCode;

/// How many copies the model uses. Copies in submodels nothing places are
/// left out.
@property (nonatomic, readonly) NSUInteger usedCount;

/// How many the inventory holds, or `NSNotFound` when the limit does not count.
@property (nonatomic, readonly) NSUInteger ownedCount;

/// The worst status of the row's copies.
@property (nonatomic, readonly) LDrawPartLimitStatus status;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitReport
///
/// @abstract   How every part of a model stands against a limit.
///
/// @discussion A part is too many when it is a copy past what the inventory
///             holds, counted in build order: if the sets hold 10, the 11th
///             copy built and those after it are too many. A part inside a
///             submodel stands for every copy of the submodel, and takes the
///             worst status of them. An assembly an inventory counts by its
///             pieces takes the worst status of its pieces.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitReport : NSObject

@property (nonatomic, readonly) LDrawPartLimitTable *table;

/// In the order each part and color is first used.
@property (nonatomic, readonly, copy) NSArray<LDrawPartLimitRow *> *rows;

/// A part's status. Allowed for a part the walk does not count, such as one
/// inside an IGN range.
- (LDrawPartLimitStatus) statusForPart:(LDrawPart *)part;

/// The color the part was checked in: for a part in color 16, the color of
/// what places it, from the copy that gave its status. LDrawColorBogus for a
/// part the walk does not count.
- (LDrawColorT) colorCodeForPart:(LDrawPart *)part;

/// How many copies of the part in this color the model uses, counted the way
/// the limit counts them.
- (NSUInteger) usedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;

/// How the copies of the part in this color stand: the worst of the copies
/// counted with them, or of their pieces for an assembly counted by its
/// pieces. The table's status for a part the model does not use.
- (LDrawPartLimitStatus) statusForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
	NS_SWIFT_NAME(status(forPartNamed:colorCode:));

/// The parts with this status, in no set order.
- (NSArray<LDrawPart *> *) partsWithStatus:(LDrawPartLimitStatus)status;

/// The parts that break the limit, in no set order.
- (NSArray<LDrawPart *> *) problemParts;

/// The parts the library does not have, in no set order. Each is still checked
/// by its name, so it has no data only when no LEGO part matches it.
- (NSArray<LDrawPart *> *) missingParts;

/// How many parts inside the container are too many, not in their color, or
/// not available. Parts with no data are not problems.
- (NSUInteger) problemCountInContainer:(LDrawContainer *)container;

/// The worst status of the parts inside the container.
- (LDrawPartLimitStatus) worstStatusInContainer:(LDrawContainer *)container;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitCheck
///
/// @abstract   Puts what a model uses against what a limit allows.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitCheck : NSObject

/// The report for a file: its usage, checked against the table.
+ (LDrawPartLimitReport *) reportForFile:(LDrawFile *)file table:(LDrawPartLimitTable *)table;

/// The same for a usage already walked.
+ (LDrawPartLimitReport *) reportForUsage:(LDrawPartUsage *)usage table:(LDrawPartLimitTable *)table;

/// Sets every part's `limitStatus` in the file from the report, and its
/// `isLimitChecked` to whether the limit restricts. Returns the parts where
/// either changed, which the host redraws.
+ (NSArray<LDrawPart *> *) applyReport:(LDrawPartLimitReport *)report toFile:(LDrawFile *)file;

@end

NS_ASSUME_NONNULL_END
