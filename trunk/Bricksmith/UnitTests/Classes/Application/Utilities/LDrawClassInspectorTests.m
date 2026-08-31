//
//  LDrawClassInspectorTests.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-17.
//

#import "LDrawClassInspector.h"

#import <XCTest/XCTest.h>

// MARK: Mocks -

// first level

// has 2 levels of subclasses
@interface Class1 : NSObject
@end

@implementation Class1
@end


// second level

// has no subclasses
@interface Class1a : Class1
@end

@implementation Class1a
@end


// has 1 level of subclasses
@interface Class1b : Class1
@end

@implementation Class1b
@end


// third level

// has no subclasses
@interface Class1bSub1 : Class1b
@end

@implementation Class1bSub1
@end


// MARK: - Tests -

@interface LDrawClassInspectorTests : XCTestCase

@end

@implementation LDrawClassInspectorTests

- (void)test_ClassInspector_FindsAllSubclasses
{
	NSArray *subclasses = [LDrawClassInspector subclassesFor:[Class1 class]];
	
	XCTAssertEqual(subclasses.count, 3);
	XCTAssertTrue([subclasses containsObject:[Class1a class]]);
	XCTAssertTrue([subclasses containsObject:[Class1b class]]);
	XCTAssertTrue([subclasses containsObject:[Class1bSub1 class]]);
}


- (void)test_ClassInspector_ForClassWithoutSublassesReturnsEmptyArray
{
	NSArray *subclasses = [LDrawClassInspector subclassesFor:[Class1a class]];
	
	XCTAssertEqual(subclasses.count, 0);
}


- (void)test_ClassInspector_FindsAllDirectSubclasses
{
	NSArray *subclasses = [LDrawClassInspector firstLevelSubclassesFor:[Class1 class]];
	
	XCTAssertEqual(subclasses.count, 2);
	XCTAssertTrue([subclasses containsObject:[Class1a class]]);
	XCTAssertTrue([subclasses containsObject:[Class1b class]]);
}

@end
