//==============================================================================
//
//  File:       LDrawObjectWithValue.m
//  Package:    LDrawCore
//
//  Purpose:    Tuple to store extra string information for any object.
//              Used for handling MLCAD groups.
//
//  Created by Sergey Slobodenyuk on 2022-12-17.
//  Copyright 2006. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawObjectWithValue.h>

@implementation LDrawObjectWithValue

//========== initWithObject:value: ============================================
//
// Purpose:		Create a tuple pairing an LDraw object with extra string data,
//				used when tracking MLCAD groups.
//
//==============================================================================
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
