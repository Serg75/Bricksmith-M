//==============================================================================
//
//  File:       FastSet.m
//  Package:    LDrawCore
//
//  Purpose:    Compact set that stores a single object without allocating an
//              NSMutableSet until a second insert.
//
//  Created by Sergey Slobodenyuk on 15.09.21.
//
//==============================================================================

/*
 FastSet - THEORY OF OPERATION
 
 Here's the problem: the overhead of NS collections is relatively high, and attaching a
 mutable set to each directive to keep track of who is observing it basically doubles
 the number of NS containers and load time.
 
 Buuuuut - in nearly every important case, the number of objects in a container is 1.
 So the fast set structure optimizes away the NS mutable set for the simple cases where
 we don't need a real set.
 
 ENCODING
 
 The fast set is an inner pointer which can contain either one object or an NSMutableSet
 with more than one objects.
 */

#import <LDrawCore/FastSet.h>

@interface FastSet () {
    id  data;
}

@end


@implementation FastSet

//========== init =============================================================
//
// Purpose:		Create an empty set. The first insert stores a single pointer
//				rather than allocating an NSMutableSet.
//
//==============================================================================
- (instancetype)init {
    self = [super init];
    if (self)
    {
        data = nil;
    }
    return self;
}


//========== addObject: =======================================================
//
// Purpose:		Insert object. One element stays as a raw pointer; a second
//				element promotes storage to an NSMutableSet.
//
//==============================================================================
- (void)addObject:(id)object {
	NSValue *value = [NSValue valueWithPointer:(__bridge void *)(object)];
    if (data == nil) {
        data = value;
    } else if (![data isKindOfClass:[NSMutableSet class]]) {
        NSMutableSet * newSet = [[NSMutableSet alloc] initWithCapacity:2];
        [newSet addObject:data];
        [newSet addObject:value];
        data = newSet;
    } else {
        [data addObject:value];
    }
}

//========== removeObject: ====================================================
//
// Purpose:		Remove object. If the set shrinks to one element, storage
//				collapses back to a single pointer.
//
//==============================================================================
- (void)removeObject:(id)object {
	NSValue *value = [NSValue valueWithPointer:(__bridge void *)(object)];
    if ([data isKindOfClass:[NSMutableSet class]]) {
        assert([data containsObject:value]);
        [data removeObject:value];
        if ([data count] == 1) {
            data = [data anyObject];
        }
	} else if ([data isEqualToValue:value]) {
		data = nil;
    } else {
        assert(!"Removal of an unknown object.");
    }
}

//========== objectEnumerator =================================================
//
// Purpose:		Enumerate the set contents. A one-element set is wrapped in a
//				temporary array so callers always get an NSEnumerator.
//
//==============================================================================
- (NSEnumerator *)objectEnumerator {
    if ([data isKindOfClass:[NSMutableSet class]]) {
        return [data objectEnumerator];
    } else if (data != nil) {
        return @[data].objectEnumerator;
    } else {
        return @[].objectEnumerator;
    }
}

@end
