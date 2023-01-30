//==============================================================================
//
// File:		LDrawObjectWithValue.h
//
// Purpose:		Tuple to store extra sting information for any onject.
//				Used for handling MLCAD groups.
//
//  Created by Sergey Slobodenyuk on 2022-12-17.
//  Copyright 2006. All rights reserved.
//==============================================================================

#import <Foundation/Foundation.h>

@interface LDrawObjectWithValue : NSObject

@property (strong) id object;
@property (strong) NSString *value;

- (instancetype)initWithObject:(id)object value:(NSString *)value;

@end
