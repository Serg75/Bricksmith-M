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

/// Enumerate the stored objects.
- (NSEnumerator *)objectEnumerator;

@end
