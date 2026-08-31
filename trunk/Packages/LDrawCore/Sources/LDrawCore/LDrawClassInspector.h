//==============================================================================
//
//  File:       LDrawClassInspector.h
//  Package:    LDrawCore
//
//  Info:       Private header next to LDrawClassInspector.m. Not under
//              include/; used by LDrawMetaCommand and LPubCommand to discover
//              subclasses. Host code should not import this.
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
