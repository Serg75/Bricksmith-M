//==============================================================================
//
//  File:       LDrawFastSet.h
//  Package:    LDrawCore
//
//  Purpose:    Compact set that stores a single object without allocating an
//              NSMutableSet until a second insert.
//
//  Created by Sergey Slobodenyuk on 15.09.21.
//
//==============================================================================

#import <Foundation/Foundation.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawFastSet
///
/// @abstract   Compact set that stores a single object without allocating an
///             NSMutableSet until a second insert.
///
//------------------------------------------------------------------------------
@interface LDrawFastSet : NSObject

/// First insert stores a single pointer; later inserts promote to NSMutableSet.
- (void)addObject:(id)object;

/// If the set shrinks to one element, storage collapses back to a pointer.
- (void)removeObject:(id)object;

/// Calls the block with each stored object, as an NSValue of its pointer. The
/// block may add or remove objects; one removed before its turn is skipped.
- (void)enumerateValuesUsingBlock:(void (NS_NOESCAPE ^)(NSValue *value))block;

@end
