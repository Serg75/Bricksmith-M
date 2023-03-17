//==============================================================================
//
//  ClassInspector.m
//  Bricksmith
//
//  Purpose:	Contains methods to inspect class like finding subclasses.
//
//  Created by Sergey Slobodenyuk on 2023-02-06.
//
//==============================================================================

#import "ClassInspector.h"

#import <objc/runtime.h>

@implementation ClassInspector

//---------- subclassesFor: ------------------------------------------[static]--
///
/// @abstract	Returns all subclsses for a given class.
///
//------------------------------------------------------------------------------
+ (NSArray<Class> *)subclassesFor:(Class)parentClass
{
	int numClasses = objc_getClassList(NULL, 0);

	// According to the docs of objc_getClassList we should check
	// if numClasses is bigger than 0.
	if (numClasses <= 0) {
		return [NSMutableArray array];
	}

	int memSize = sizeof(Class) * numClasses;
	Class *classes = (__unsafe_unretained Class *)malloc(memSize);

	if (classes == NULL && memSize) {
		return [NSMutableArray array];
	}

	numClasses = objc_getClassList(classes, numClasses);

	NSMutableArray<Class> *result = [NSMutableArray new];

	for (NSInteger i = 0; i < numClasses; i++) {
		Class superClass = classes[i];

		// Don't add the parent class to list of sublcasses
		if (superClass == parentClass) {
			continue;
		}

		// Using a do while loop, like pointed out in Cocoa with Love,
		// can lead to EXC_I386_GPFLT, which stands for General
		// Protection Fault and means we are doing something we
		// shouldn't do. It's safer to use a regular while loop to
		// check if superClass is valid.
		while (superClass && superClass != parentClass) {
			superClass = class_getSuperclass(superClass);
		}

		if (superClass) {
			[result addObject:classes[i]];
		}
	}

	free(classes);

	return result;
	
}//end subclassesFor:


//---------- firstLevelSubclassesFor: --------------------------------[static]--
///
/// @abstract	Returns only direct subclsses for a given class.
///
//------------------------------------------------------------------------------
+ (NSArray<Class> *)firstLevelSubclassesFor:(Class)parentClass
{
	int numClasses = objc_getClassList(NULL, 0);

	// According to the docs of objc_getClassList we should check
	// if numClasses is bigger than 0.
	if (numClasses <= 0) {
		return [NSMutableArray array];
	}

	int memSize = sizeof(Class) * numClasses;
	Class *classes = (__unsafe_unretained Class *)malloc(memSize);

	if (classes == NULL && memSize) {
		return [NSMutableArray array];
	}

	numClasses = objc_getClassList(classes, numClasses);

	NSMutableArray<Class> *result = [NSMutableArray new];

	for (NSInteger i = 0; i < numClasses; i++) {
		Class superClass = classes[i];

		// Don't add the parent class to list of sublcasses
		if (superClass == parentClass) {
			continue;
		}

		superClass = class_getSuperclass(superClass);

		if (superClass && superClass == parentClass) {
			[result addObject:classes[i]];
		}
	}

	free(classes);

	return result;
	
}//end firstLevelSubclassesFor:

@end
