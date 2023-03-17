//
//  MockArchiver.h
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-06.
//

#import <Foundation/Foundation.h>

//------------------------------------------------------------------------------
///
/// @class		MockArchiver
///
/// @abstract	Mock for the NSArchiver class.
///
//------------------------------------------------------------------------------
@interface MockArchiver : NSCoder

@property NSMutableDictionary * _Nonnull data;

- (void)encodeObject:(nullable id)object forKey:(nonnull NSString *)key;
- (void)encodeConditionalObject:(nullable id)object forKey:(nonnull NSString *)key;

- (nullable id)decodeObjectForKey:(nonnull NSString *)key;

@end
