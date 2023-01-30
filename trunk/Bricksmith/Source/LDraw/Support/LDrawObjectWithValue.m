//==============================================================================
//
// File:		LDrawObjectWithValue.m
//
// Purpose:		Tuple to store extra sting information for any onject.
//				Used for handling MLCAD groups.
//
//  Created by Sergey Slobodenyuk on 2022-12-17.
//  Copyright 2006. All rights reserved.
//==============================================================================

#import "LDrawObjectWithValue.h"

@implementation LDrawObjectWithValue

- (instancetype)initWithObject:(id)object value:(NSString *)value
{
	self = [super init];
	if (self) {
		self.object = object;
		self.value = value;
	}
	return self;
}

@end
