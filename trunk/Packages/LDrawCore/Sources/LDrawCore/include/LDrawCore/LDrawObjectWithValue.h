//==============================================================================
//
//  File:       LDrawObjectWithValue.h
//  Package:    LDrawCore
//
//  Purpose:    Tuple to store extra string information for any object. Used for
//              handling MLCAD groups.
//
//  Created by Sergey Slobodenyuk on 2022-12-17.
//  Copyright 2006. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawObjectWithValue
///
/// @abstract   Tuple to store extra string information for any object. Used for
///             handling MLCAD groups.
///
//------------------------------------------------------------------------------
@interface LDrawObjectWithValue : NSObject

@property (strong) id object;
@property (strong) NSString *value;

- (instancetype)initWithObject:(id)object value:(NSString *)value;

@end
