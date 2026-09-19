//==============================================================================
//
//  File:       PartCatalogBuilder.h
//  Package:    LDrawCore
//
//  Purpose:    Scans the LDraw folder for a list of all available parts and
//              categories.
//
//  Info:       Private to LDrawPartLibrary. The host stamps a catalog version
//              via LDrawPartLibrary; this builder does not look up the app
//              main bundle.
//
//  Created by Allen Smith on 1/6/22.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      PartCatalogBuilder
///
/// @abstract   Scans the LDraw folder for a list of all available parts and
///             categories.
///
//------------------------------------------------------------------------------
@interface PartCatalogBuilder : NSObject

/// Host app version stamped into the catalog file. Nil falls back to @"1.0".
- (void)setCatalogVersion:(nullable NSString *)version;

- (void) makePartCatalogWithMaxLoadCountHandler:(void (^)(NSUInteger maxPartCount))maxLoadCountHandler
					   progressIncrementHandler:(void (^)(void))progressIncrementHandler
							  completionHandler:(void (^)(NSDictionary<NSString*, id> *newCatalog))completionHandler;

@end

NS_ASSUME_NONNULL_END
