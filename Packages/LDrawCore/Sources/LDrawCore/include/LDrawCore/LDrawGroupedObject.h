//==============================================================================
//
//  File:       LDrawGroupedObject.h
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

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawGroupedObject
///
/// @abstract   Tuple to store extra string information for any object. Used for
///             handling MLCAD groups.
///
//------------------------------------------------------------------------------
@interface LDrawGroupedObject : NSObject

@property (strong) id object;
@property (strong) NSString *value;

- (instancetype)initWithObject:(id)object value:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
