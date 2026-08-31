//==============================================================================
//
//  File:       LDrawClassInspector.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2023-02-06.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawClassInspector
///
/// @abstract   Contains methods to inspect class like finding subclasses.
///
//------------------------------------------------------------------------------
@interface LDrawClassInspector : NSObject

+ (NSArray<Class> *)subclassesFor:(Class)parentClass;
+ (NSArray<Class> *)firstLevelSubclassesFor:(Class)parentClass;

@end

NS_ASSUME_NONNULL_END
