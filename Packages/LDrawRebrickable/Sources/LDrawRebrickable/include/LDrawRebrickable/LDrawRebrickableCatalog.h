//==============================================================================
//
//  File:       LDrawRebrickableCatalog.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawInventoryStore;
@class LDrawPartAvailability;
@class LDrawRebrickableDownloads;
@class LDrawRebrickableSetList;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableCatalog
///
/// @abstract   What Rebrickable's downloads tell about every part: when it
///             came in which colors, how parts relate, and which parts exist.
///
/// @discussion Building one reads every part of every set, over a million
///             rows, so it takes seconds: build it off the main thread, then
///             save it on the thread the store is used on.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableCatalog : NSObject

/// Reads the downloads. Nil, with an error, when a file is missing or cannot
/// be read.
+ (nullable instancetype) catalogFromDownloads:(LDrawRebrickableDownloads *)downloads
										 error:(NSError **)error NS_SWIFT_NAME(init(downloads:));

@property (nonatomic, readonly) LDrawPartAvailability *availability;

/// Rows of relation code, child and parent, from `part_relationships`.
@property (nonatomic, readonly, copy) NSArray<NSArray<NSString *> *> *relations;

/// Every part Rebrickable has.
@property (nonatomic, readonly, copy) NSSet<NSString *> *knownPartNumbers;

@property (nonatomic, readonly) LDrawRebrickableSetList *setList;

/// Saves the availability catalog, and the relations, the known parts and the
/// color links in the identity data, keeping the part links the store has.
- (BOOL) saveIntoStore:(LDrawInventoryStore *)store
			colorLinks:(NSDictionary<NSNumber *, id> *)colorLinks
				 error:(NSError **)error NS_SWIFT_NAME(save(into:colorLinks:));

@end

NS_ASSUME_NONNULL_END
