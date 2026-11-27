//==============================================================================
//
//  File:       LDrawFastSet.m
//  Package:    LDrawCore
//
//  Purpose:    Compact set that stores a single object without allocating a
//              hash table until a second insert.
//
//  Created by Sergey Slobodenyuk on 15.09.21.
//
//==============================================================================

/*
 LDrawFastSet - THEORY OF OPERATION

 Here's the problem: the overhead of NS collections is relatively high, and attaching a
 mutable set to each directive to keep track of who is observing it basically doubles
 the number of NS containers and load time.

 Buuuuut - in nearly every important case, the number of objects in a container is 1.
 So the fast set structure optimizes away the collection for the simple cases where
 we don't need a real set.

 ENCODING

 One object is kept as a plain pointer. Two or more are kept in a hash table that
 compares and holds them by pointer, without retaining them.
 */

#import "LDrawFastSet.h"

@interface LDrawFastSet ()
{
	__unsafe_unretained id	single;		// The only object, while there is one.
	NSHashTable				*many;		// All objects, while there are two or more.
}

@end


@implementation LDrawFastSet

//========== addObject: =======================================================
//
// Purpose:		Insert object. One object stays as a plain pointer; a second
//				one moves both into a hash table.
//
//==============================================================================
- (void)addObject:(id)object
{
	if (many) {
		[many addObject:object];
	} else if (single == nil) {
		single = object;
	} else if (single != object) {
		many = [[NSHashTable alloc] initWithOptions:(NSPointerFunctionsOpaqueMemory |
													 NSPointerFunctionsOpaquePersonality)
										   capacity:2];
		[many addObject:single];
		[many addObject:object];
		single = nil;
	}
}


//========== removeObject: ====================================================
//
// Purpose:		Remove object. If one object is left, it goes back to a plain
//				pointer.
//
//==============================================================================
- (void)removeObject:(id)object
{
	if (many) {
		assert([many containsObject:object]);
		[many removeObject:object];
		if ([many count] == 1) {
			single = [many anyObject];
			many = nil;
		}
	} else if (single == object) {
		single = nil;
	} else {
		assert(!"Removal of an unknown object.");
	}
}


//========== enumerateObjectsUsingBlock: ======================================
//
// Purpose:		Calls the block with each object. The block may add or remove
//				objects. It walks a copy, and skips an object that was removed
//				before its turn.
//
//==============================================================================
- (void)enumerateObjectsUsingBlock:(void (NS_NOESCAPE ^)(id object))block
{
	if (many) {
		for (id object in [many copy]) {
			if ([self containsObject:object]) {
				block(object);
			}
		}
	} else if (single) {
		block(single);
	}
}


//========== containsObject: ==================================================
//
// Purpose:		Whether the object is in the set.
//
//==============================================================================
- (BOOL)containsObject:(id)object
{
	if (many) {
		return [many containsObject:object];
	}
	return single == object;
}

@end
