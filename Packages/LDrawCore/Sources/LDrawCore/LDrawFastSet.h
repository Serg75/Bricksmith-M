//==============================================================================
//
//  File:       LDrawFastSet.h
//  Package:    LDrawCore
//
//  Purpose:    Compact set that stores a single object without allocating a
//              hash table until a second insert.
//
//  Created by Sergey Slobodenyuk on 15.09.21.
//
//==============================================================================

#import <Foundation/Foundation.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawFastSet
///
/// @abstract   Compact set that stores a single object without allocating a
///             hash table until a second insert. It does not retain objects.
///
//------------------------------------------------------------------------------
@interface LDrawFastSet : NSObject

/// First insert stores a single pointer; a second one moves to a hash table.
- (void)addObject:(id)object;

/// If one object is left, it goes back to a single pointer.
- (void)removeObject:(id)object;

/// Calls the block with each stored object. The block may add or remove
/// objects; one removed before its turn is skipped.
- (void)enumerateObjectsUsingBlock:(void (NS_NOESCAPE ^)(id object))block;

@end
