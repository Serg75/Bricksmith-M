//==============================================================================
//
//  File:       LDrawRebrickableSetImporter.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawRebrickableClient;
@class LDrawRebrickableDownloads;
@class LDrawRebrickableSetList;
@class LDrawSetInventory;

NS_ASSUME_NONNULL_BEGIN

/// The `source` of a set imported from the downloads, or through the API.
extern NSString * const LDrawRebrickableSourceDownloads;
extern NSString * const LDrawRebrickableSourceAPI;

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableSetImporter
///
/// @abstract   Gets the parts of one set, from the downloads or from the API.
///
/// @discussion Either way the set's parts include its minifigures' parts and
///             its spares, each part and color once.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableSetImporter : NSObject

/// The set's parts from the downloads, offline and with no key: its newest
/// inventory, the sets and minifigures inside it, each counted as often as it
/// comes. Reads every part row, so it takes a second or two; call it off the
/// main thread. Nil, with an error, when the set is unknown or a file cannot
/// be read.
+ (nullable LDrawSetInventory *) setInventoryForNumber:(NSString *)setNumber
										 fromDownloads:(LDrawRebrickableDownloads *)downloads
											   setList:(LDrawRebrickableSetList *)setList
												 error:(NSError **)error
	NS_SWIFT_NAME(setInventory(number:downloads:setList:));

/// The set's parts from the API, with Rebrickable's own LDraw ids. The
/// completion also gets those ids as LDraw part name → Rebrickable number,
/// for the identity data. Sets inside the set are not fetched.
/// `setList`, when given, names the set's theme.
+ (void) fetchSetInventoryForNumber:(NSString *)setNumber
							 client:(LDrawRebrickableClient *)client
							setList:(nullable LDrawRebrickableSetList *)setList
						 completion:(void (^)(LDrawSetInventory * _Nullable setInventory,
											  NSDictionary<NSString *, NSString *> *partLinks,
											  NSError * _Nullable error))completion
	NS_SWIFT_NAME(fetchSetInventory(number:client:setList:completion:));

@end

NS_ASSUME_NONNULL_END
