//==============================================================================
//
//  File:       LDrawPartLimit.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The extended attribute a model file keeps its limit in.
extern NSString * const LDrawPartLimitFileAttributeName;

typedef NS_ENUM(NSInteger, LDrawPartLimitKind)
{
	/// Every part in every color.
	LDrawPartLimitKindNone			= 0,

	/// The parts and colors that came in sets of the last few years.
	LDrawPartLimitKindAvailableNow	= 1,

	/// The parts of a set or a combined inventory, with their counts.
	LDrawPartLimitKindInventory		= 2
};


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimit
///
/// @abstract   Which parts the editor lets a model use, and how strictly.
///
/// @discussion Immutable; `LDrawMutablePartLimit` changes one. The limit is an
///             editor setting, kept in the host's defaults through
///             `-dictionaryRepresentation`, never in a model.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimit : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>

@property (nonatomic, readonly) LDrawPartLimitKind kind;

/// Available now: how many years back a set may be, this one included. 2 is
/// this year and last. 0 is any year, which then only rules out colors a
/// part never came in. Default 5.
@property (nonatomic, readonly) NSInteger yearsBack;

/// Available now: whether parts found only in Rebrickable's Database Sets,
/// such as Pick a Brick lists, count. Default NO.
@property (nonatomic, readonly) BOOL countsPickABrickParts;

/// Inventory: a set number, or a combined inventory's identifier.
@property (nonatomic, readonly, copy, nullable) NSString *inventoryIdentifier;

/// Inventory: whether spare parts count toward what is owned. Default YES.
@property (nonatomic, readonly) BOOL includesSpares;

/// Whether a part's molds and alternates count as the part. Default YES.
@property (nonatomic, readonly) BOOL matchesMoldVariants;

/// Whether a print or pattern counts as its plain part. Default NO.
@property (nonatomic, readonly) BOOL matchesAnyPrint;

/// Whether colors are not checked at all. Default NO.
@property (nonatomic, readonly) BOOL matchesAnyColor;

/// Whether a color the part does not come in may still be picked, and is only
/// marked. Default NO.
@property (nonatomic, readonly) BOOL warnsOnly;

/// No limit, with the default options.
+ (LDrawPartLimit *) noLimit NS_SWIFT_NAME(none());

/// Available now, with the default options.
+ (LDrawPartLimit *) availableNowLimit NS_SWIFT_NAME(availableNow());

/// The parts of a set or combined inventory, with the default options.
+ (LDrawPartLimit *) limitWithInventoryIdentifier:(NSString *)identifier NS_SWIFT_NAME(inventory(_:));

/// The same options, with another kind. An inventory needs an identifier, or
/// the result is no limit.
- (LDrawPartLimit *) limitWithKind:(LDrawPartLimitKind)kind
			   inventoryIdentifier:(nullable NSString *)identifier
	NS_SWIFT_NAME(withKind(_:inventoryIdentifier:));

/// Whether the limit restricts anything.
@property (nonatomic, readonly) BOOL isRestricting;

/// Available now: the first year a set may be from when this is currentYear.
/// NSIntegerMin, for any year, when yearsBack is 0.
- (NSInteger) firstYearForCurrentYear:(NSInteger)currentYear;

/// What the host keeps in its defaults.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;

/// The limit read back. Nil, junk, an unknown kind, or an inventory with no
/// identifier read as no limit; a missing option takes its default.
+ (LDrawPartLimit *) limitWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
	NS_SWIFT_NAME(fromDictionary(_:));

/// The limit kept with a model file, or nil when it has none. It is kept in an
/// extended attribute, so the file's text never changes.
+ (nullable LDrawPartLimit *) limitOfFileAtURL:(NSURL *)fileURL NS_SWIFT_NAME(limit(ofFileAt:));

/// Keeps the limit with a model file, replacing the one it had.
- (BOOL) writeToFileAtURL:(NSURL *)fileURL error:(NSError **)error NS_SWIFT_NAME(write(toFileAt:));

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawMutablePartLimit
///
/// @abstract   A limit whose kind and options can be changed, for a settings
///             sheet. Copy it to get an immutable limit.
///
//------------------------------------------------------------------------------
@interface LDrawMutablePartLimit : LDrawPartLimit

@property (nonatomic, readwrite) LDrawPartLimitKind kind;
@property (nonatomic, readwrite) NSInteger yearsBack;
@property (nonatomic, readwrite) BOOL countsPickABrickParts;
@property (nonatomic, readwrite, copy, nullable) NSString *inventoryIdentifier;
@property (nonatomic, readwrite) BOOL includesSpares;
@property (nonatomic, readwrite) BOOL matchesMoldVariants;
@property (nonatomic, readwrite) BOOL matchesAnyPrint;
@property (nonatomic, readwrite) BOOL matchesAnyColor;
@property (nonatomic, readwrite) BOOL warnsOnly;

@end

NS_ASSUME_NONNULL_END
