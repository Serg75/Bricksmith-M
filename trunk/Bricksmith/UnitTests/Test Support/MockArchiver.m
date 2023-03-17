//
//  MockArchiver.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-06.
//

#import "MockArchiver.h"


@implementation MockArchiver

//========== init ==============================================================
///
/// @abstract	Initialize an empty archiver.
///
//==============================================================================
- (instancetype)init
{
	self = [super init];
	if (self) {
		_data = [NSMutableDictionary dictionary];
	}
	return self;
}


//========== encodeObject:forKey: ==============================================
///
/// @abstract	Implementation for the protocol method.
///				Just save object in the collection.
///
//==============================================================================
- (void)encodeObject:(nullable id)object forKey:(NSString *)key
{
	_data[key] = object;
}


//========== encodeConditionalObject:forKey: ====================================
///
/// @abstract	Implementation for the protocol method.
///				Nothing to do with conditional objects.
///
//==============================================================================
- (void)encodeConditionalObject:(nullable id)object forKey:(NSString *)key
{
	// nothing
}


//========== decodeObjectForKey: ===============================================
///
/// @abstract	Implementation for the protocol method.
///				Return saved object from the collection.
///
//==============================================================================
- (nullable id)decodeObjectForKey:(NSString *)key
{
	return _data[key];
}

@end
