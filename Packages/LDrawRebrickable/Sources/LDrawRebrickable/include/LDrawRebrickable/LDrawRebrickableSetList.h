//==============================================================================
//
//  File:       LDrawRebrickableSetList.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawRebrickableDownloads;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableSet
///
/// @abstract   One set as Rebrickable's set list has it.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableSet : NSObject

@property (nonatomic, readonly, copy) NSString *setNumber;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSInteger year;
@property (nonatomic, readonly, copy, nullable) NSString *themeName;

/// The parts Rebrickable counts for the set, spares not included.
@property (nonatomic, readonly) NSUInteger partCount;

@property (nonatomic, readonly, copy, nullable) NSString *imageURL;

/// The set is one of Rebrickable's Database Sets, such as a Pick a Brick list,
/// not a set LEGO sold.
@property (nonatomic, readonly) BOOL isDatabaseSet;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableSetList
///
/// @abstract   Every set Rebrickable has, read from the downloads, for finding
///             a set by number or name.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableSetList : NSObject

/// Reads `sets` and `themes`. Nil, with an error, when they cannot be read.
+ (nullable instancetype) setListFromDownloads:(LDrawRebrickableDownloads *)downloads
										 error:(NSError **)error NS_SWIFT_NAME(init(downloads:));

/// How many sets the list holds.
@property (nonatomic, readonly) NSUInteger count;

/// The set with this number. "42115" finds "42115-1".
- (nullable LDrawRebrickableSet *) setForNumber:(NSString *)setNumber NS_SWIFT_NAME(set(forNumber:));

/// Sets whose number starts with the text, then sets whose name holds every
/// word of it, newest first in each group. At most `limit`.
- (NSArray<LDrawRebrickableSet *> *) setsMatching:(NSString *)text limit:(NSUInteger)limit
	NS_SWIFT_NAME(sets(matching:limit:));

/// The numbers of every Database Set.
@property (nonatomic, readonly, copy) NSSet<NSString *> *databaseSetNumbers;

@end

NS_ASSUME_NONNULL_END
