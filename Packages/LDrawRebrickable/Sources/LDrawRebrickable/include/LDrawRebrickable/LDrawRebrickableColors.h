//==============================================================================
//
//  File:       LDrawRebrickableColors.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableColors
///
/// @abstract   Which LDraw colors Rebrickable's colors are, from a table the
///             package ships.
///
/// @discussion The table maps a Rebrickable color id to one or more LDraw
///             color codes.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableColors : NSObject

/// The links in the shipped table.
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) builtInColorLinks;

/// How the shipped table was made: "api" or "names".
+ (nullable NSString *) builtInTableSource;

@end

NS_ASSUME_NONNULL_END
