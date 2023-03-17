//
//  ClassInspector.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-02-06.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class		ClassInspector
///
/// @abstract	Contains methods to inspect class like finding subclasses.
///
//------------------------------------------------------------------------------
@interface ClassInspector : NSObject

+ (NSArray<Class> *)subclassesFor:(Class)parentClass;
+ (NSArray<Class> *)firstLevelSubclassesFor:(Class)parentClass;

@end

NS_ASSUME_NONNULL_END
