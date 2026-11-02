//==============================================================================
//
//  File:       LDrawRebrickableColors.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawRebrickableClient;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableColors
///
/// @abstract   Which LDraw colors Rebrickable's colors are.
///
/// @discussion The package ships a table. A user with an API key can fetch
///             Rebrickable's own links instead; they are kept in the
///             downloads folder and win over the shipped table. Links map a
///             Rebrickable color id to one or more LDraw codes.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableColors : NSObject

/// The table shipped with the package.
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) builtInColorLinks;

/// How the shipped table was made: "api" or "names".
+ (nullable NSString *) builtInTableSource;

/// Fetches `lego/colors/` through the client.
+ (void) fetchColorLinksWithClient:(LDrawRebrickableClient *)client
						completion:(void (^)(NSDictionary<NSNumber *, NSArray<NSNumber *> *> * _Nullable links,
											 NSError * _Nullable error))completion;

/// Links fetched from the API and kept in the folder, or nil.
+ (nullable NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) fetchedColorLinksInFolder:(NSURL *)folderURL;
+ (BOOL) saveFetchedColorLinks:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)links
					  inFolder:(NSURL *)folderURL
						 error:(NSError **)error;

/// The links to use: those fetched into the folder, else the shipped table.
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksForFolder:(NSURL *)folderURL;

@end

NS_ASSUME_NONNULL_END
