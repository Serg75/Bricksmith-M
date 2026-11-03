//==============================================================================
//
//  File:       LDrawRebrickableSetImporter.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawRebrickableDownloads;
@class LDrawRebrickableSetList;
@class LDrawSetInventory;

NS_ASSUME_NONNULL_BEGIN

/// The `source` of a set imported from the downloads.
extern NSString * const LDrawRebrickableSourceDownloads;

/// The `source` of a set imported through Rebrickable's API.
extern NSString * const LDrawRebrickableSourceAPI;

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableSetImporter
///
/// @abstract   Gets the parts of one set from the downloads.
///
/// @discussion The set's parts include its minifigures' parts and its spares,
///             each part and color once.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableSetImporter : NSObject

/// The set's parts: its newest inventory, and the sets and minifigures inside
/// it, each counted as often as it comes. Reads every part row, so it takes a
/// second or two; call it off the main thread. Nil, with an error, when the
/// set is unknown or a file cannot be read.
+ (nullable LDrawSetInventory *) setInventoryForNumber:(NSString *)setNumber
										 fromDownloads:(LDrawRebrickableDownloads *)downloads
											   setList:(LDrawRebrickableSetList *)setList
												 error:(NSError **)error
	NS_SWIFT_NAME(setInventory(number:downloads:setList:));

@end

NS_ASSUME_NONNULL_END
