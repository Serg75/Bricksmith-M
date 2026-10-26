//==============================================================================
//
//  File:       LDrawRebrickableUpdater.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawInventoryStore;
@class LDrawRebrickableClient;
@class LDrawRebrickableDownloads;
@class LDrawRebrickableSetList;
@class LDrawSetInventory;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableUpdater
///
/// @abstract   Keeps a store's Rebrickable data up to date: the downloads, the
///             catalog built from them, and imported sets.
///
/// @discussion The slow work runs on a background queue. Every completion
///             runs on the main queue, where the store is used.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableUpdater : NSObject

- (instancetype) initWithDownloads:(LDrawRebrickableDownloads *)downloads
							 store:(LDrawInventoryStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly) LDrawRebrickableDownloads *downloads;
@property (nonatomic, readonly) LDrawInventoryStore *store;

/// Whether the store has a catalog.
@property (nonatomic, readonly) BOOL hasCatalog;

/// Whether an update is under way.
@property (nonatomic, readonly) BOOL isUpdating;

/// Fetches the downloads that are due, or all when forced, then builds and
/// saves the catalog when a file changed or the store has none. The progress
/// covers the downloads; building takes a few seconds more. `changed` says
/// whether the catalog was saved.
- (NSProgress *) updateCatalogForcing:(BOOL)force
						   completion:(void (^)(BOOL changed, NSError * _Nullable error))completion
	NS_SWIFT_NAME(updateCatalog(forcing:completion:));

/// The set list from the downloads, read once.
- (void) loadSetListWithCompletion:(void (^)(LDrawRebrickableSetList * _Nullable setList,
											 NSError * _Nullable error))completion
	NS_SWIFT_NAME(loadSetList(completion:));

/// Imports a set and saves it in the store: through the API when a client is
/// given, which also saves Rebrickable's LDraw links, else from the downloads.
- (void) importSetNumber:(NSString *)setNumber
				  client:(nullable LDrawRebrickableClient *)client
			  completion:(void (^)(LDrawSetInventory * _Nullable setInventory, NSError * _Nullable error))completion
	NS_SWIFT_NAME(importSet(number:client:completion:));

@end

NS_ASSUME_NONNULL_END
