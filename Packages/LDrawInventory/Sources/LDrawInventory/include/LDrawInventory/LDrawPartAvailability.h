//==============================================================================
//
//  File:       LDrawPartAvailability.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// When one part came in one color, by Rebrickable's ids.
typedef struct LDrawPartAvailabilityRecord
{
	NSInteger	colorID;

	/// The first and last year of a set the part came in, in this color.
	NSInteger	firstYear;
	NSInteger	lastYear;

	/// How many sets the part came in, in this color.
	NSUInteger	setCount;

	/// The part came in this color only in Rebrickable's Database Sets, such
	/// as Pick a Brick lists, never in a real set. The years are theirs then.
	/// A C bool, so Swift reads it as Bool.
	bool		onlyInDatabaseSets;

} LDrawPartAvailabilityRecord;


//------------------------------------------------------------------------------
///
/// @class      LDrawPartAvailability
///
/// @abstract   For each part and color, when and how often it came in sets.
///
/// @discussion Immutable, and keyed by Rebrickable's part numbers and color
///             ids. The limit table matches LDraw parts to them. Records are
///             packed per part, since a catalog holds a few hundred thousand.
///
//------------------------------------------------------------------------------
@interface LDrawPartAvailability : NSObject

/// When the data this was built from was made, or nil when it is not known.
@property (nonatomic, readonly, copy, nullable) NSDate *date;

/// How many parts have records.
@property (nonatomic, readonly) NSUInteger partCount;

- (NSArray<NSString *> *) partNumbers;

/// Fills `record` and returns YES when the part came in the color.
- (BOOL) getRecord:(LDrawPartAvailabilityRecord *)record
	 forPartNumber:(NSString *)partNumber
		   colorID:(NSInteger)colorID;

/// Calls the block once for each color the part came in.
- (void) enumerateRecordsForPartNumber:(NSString *)partNumber
							usingBlock:(void (NS_NOESCAPE ^)(LDrawPartAvailabilityRecord record))block;

/// What the store writes.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;

/// Nil when the dictionary holds no parts table. Rows that do not read are
/// skipped.
+ (nullable instancetype) availabilityWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartAvailabilityBuilder
///
/// @abstract   Puts a catalog together from every part of every set.
///
//------------------------------------------------------------------------------
@interface LDrawPartAvailabilityBuilder : NSObject

/// Notes that a set from this year holds the part in this color. Call it once
/// per set for each part and color, since each call counts one more set.
- (void) notePartNumber:(NSString *)partNumber
				colorID:(NSInteger)colorID
				   year:(NSInteger)year
		  inDatabaseSet:(BOOL)isDatabaseSet;

/// The catalog of everything noted so far. A part and color found in both
/// kinds of set keeps the years of the real sets.
- (LDrawPartAvailability *) availabilityWithDate:(nullable NSDate *)date;

@end

NS_ASSUME_NONNULL_END
