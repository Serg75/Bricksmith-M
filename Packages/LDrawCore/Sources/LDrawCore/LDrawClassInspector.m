//==============================================================================
//
//  File:       LDrawClassInspector.m
//  Package:    LDrawCore
//
//  Purpose:    Contains methods to inspect class like finding subclasses.
//
//  Created by Sergey Slobodenyuk on 2023-02-06.
//
//==============================================================================

#import "LDrawClassInspector.h"

#import <objc/runtime.h>

@implementation LDrawClassInspector

//---------- classesBesideClass: -------------------------------------[static]--
///
/// @abstract	Returns the classes built into the same binary as the given
///				class. Looking only there is fast; asking for every class
///				loads all classes of all system frameworks first.
///
//------------------------------------------------------------------------------
+ (NSArray<Class> *)classesBesideClass:(Class)aClass
{
	const char		*image		= class_getImageName(aClass);
	unsigned int	count		= 0;
	const char		**names		= image ? objc_copyClassNamesForImage(image, &count) : NULL;
	NSMutableArray	*classes	= [NSMutableArray arrayWithCapacity:count];

	for (unsigned int i = 0; i < count; i++) {
		Class found = objc_getClass(names[i]);
		if (found) {
			[classes addObject:found];
		}
	}
	free(names);
	return classes;

}//end classesBesideClass:


//---------- subclassesFor: ------------------------------------------[static]--
///
/// @abstract	Returns all subclasses of a given class that are built into the
///				same binary as it.
///
//------------------------------------------------------------------------------
+ (NSArray<Class> *)subclassesFor:(Class)parentClass
{
	NSMutableArray<Class> *result = [NSMutableArray new];

	for (Class aClass in [self classesBesideClass:parentClass]) {
		Class superClass = class_getSuperclass(aClass);

		while (superClass && superClass != parentClass) {
			superClass = class_getSuperclass(superClass);
		}
		if (superClass) {
			[result addObject:aClass];
		}
	}
	return result;

}//end subclassesFor:


//---------- firstLevelSubclassesFor: --------------------------------[static]--
///
/// @abstract	Returns only the direct subclasses of a given class that are
///				built into the same binary as it.
///
//------------------------------------------------------------------------------
+ (NSArray<Class> *)firstLevelSubclassesFor:(Class)parentClass
{
	NSMutableArray<Class> *result = [NSMutableArray new];

	for (Class aClass in [self classesBesideClass:parentClass]) {
		if (class_getSuperclass(aClass) == parentClass) {
			[result addObject:aClass];
		}
	}
	return result;

}//end firstLevelSubclassesFor:

@end
