//
//  LPubCommand_Tests.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-04.
//

#import "LPubCommand.h"

#import <XCTest/XCTest.h>
#import "LPubRemoveGroup.h"
#import "MockArchiver.h"
#import "MockScanner.h"


// MARK: Mocks -

@interface LPubCommand ()

+ (LDrawMetaCommand *) metaCommandInstanceByMarker:(NSString *)ldrawMarker scanner:(NSScanner *)scanner;

+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters;

@end


// MARK: - Tests -

@interface LPubCommand_Tests : XCTestCase

@end

@implementation LPubCommand_Tests

- (void)test_LPubCommand_ClassContainsSubclasses
{
	SEL sel = NSSelectorFromString(@"subclassNames");
	NSArray *subclasses = [LPubCommand performSelector:sel];
	XCTAssertEqual(subclasses.count, 1);
	XCTAssertEqualObjects(subclasses[0], @"LPubRemoveGroup");
}


- (void)test_LPubCommand_EncodedProperly
{
	MockArchiver *encoder = [MockArchiver new];
	LPubCommand *command = [[LPubCommand alloc] init];
	command.lPubCommandString = @"Some string";

	[command encodeWithCoder:encoder];

	XCTAssertEqual(encoder.data.count, 2);
	XCTAssertEqualObjects(encoder.data[@"lpubCommandString"], @"Some string");
	XCTAssertEqualObjects(encoder.data[@"commandString"], @"!LPUB Some string");
}


- (void)test_LPubCommand_DecodedProperly
{
	MockArchiver *decoder = [MockArchiver new];
	decoder.data = [@{
		@"lpubCommandString" : @"Some string",
		    @"commandString" : @"!LPUB Some string"
	} mutableCopy];
	
	LPubCommand *command = [[LPubCommand alloc] initWithCoder:decoder];
	command.lPubCommandString = @"Some string";

	XCTAssertEqualObjects(command.lPubCommandString, @"Some string");
	XCTAssertEqualObjects(command.commandString, @"!LPUB Some string");
}


- (void)test_LPubCommand_CopiedProperly
{
	LPubCommand *command = [[LPubCommand alloc] init];
	command.lPubCommandString = @"Some string";

	LPubCommand *duplicate = [command copyWithZone:nil];
	
	XCTAssertEqualObjects(command.lPubCommandString, duplicate.lPubCommandString);
	XCTAssertEqualObjects(command.commandString, duplicate.commandString);
	XCTAssertNotIdentical(command, duplicate);
}


- (void)test_LPubCommand_CopiedObjectHasNonIdenticalValues
{
	LPubCommand *command = [[LPubCommand alloc] init];
	command.lPubCommandString = @"Some string";

	LPubCommand *duplicate = [command copyWithZone:nil];
	command.lPubCommandString = @"Another string";
	
	XCTAssertNotEqualObjects(command.lPubCommandString, duplicate.lPubCommandString);
	XCTAssertNotEqualObjects(command.commandString, duplicate.commandString);
}


- (void)test_LPubCommand_IfMarkerIsNotLPubCommand_NoMetaCommandCreated
{
	NSString *ldrawMarker = @"abc";
	id scanner = [MockScanner new];
	
	LDrawMetaCommand *metaCommand = [LPubCommand metaCommandInstanceByMarker:ldrawMarker scanner: scanner];
	
	XCTAssertNil(metaCommand);
}


- (void)test_LPubCommand_IfMarkerIsLPubCommand_ProperCommandCreated
{
	XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"'scanSubstringsWithQuotations' method called"];
	NSString *ldrawMarker = @"!LPUB";
	MockScanner *scanner = [MockScanner new];
	scanner.scanSubstringsWithQuotationsReturnedValue = @[@"string1", @"string2"];
	scanner.scanSubstringsWithQuotationsExpectation = expectation;
	
	LDrawMetaCommand *metaCommand = [LPubCommand metaCommandInstanceByMarker:ldrawMarker scanner: (id)scanner];
	[self waitForExpectations:@[expectation] timeout:1];

	XCTAssertIdentical(metaCommand.class, LPubCommand.class);
}


- (void)test_LPubCommand_IfMarkerIsLPubCommandAndRestIsRemoveGroup_ProperCommandCreated
{
	XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"'scanSubstringsWithQuotations' method called"];
	NSString *ldrawMarker = @"!LPUB";
	MockScanner *scanner = [MockScanner new];
	scanner.scanSubstringsWithQuotationsReturnedValue = @[@"REMOVE", @"GROUP", @"\"name\""];
	scanner.scanSubstringsWithQuotationsExpectation = expectation;

	LDrawMetaCommand *metaCommand = [LPubCommand metaCommandInstanceByMarker:ldrawMarker scanner: (id)scanner];
	[self waitForExpectations:@[expectation] timeout:1];

	XCTAssertIdentical(metaCommand.class, LPubRemoveGroup.class);
}


- (void)test_LPubCommand_lpubCommandInstance_ReturnsNil
{
	NSArray<NSString *> *parameters = @[@"param1", @"param2"];
	LPubCommand *command = [LPubCommand lpubCommandInstance:parameters];
	
	XCTAssertNil(command);
}


- (void)test_LPubCommand_finishParsing_lPubCommandStringFilledInProperly
{
	XCTestExpectation *expectation1 = [[XCTestExpectation alloc] initWithDescription:@"'string' method called"];
	XCTestExpectation *expectation2 = [[XCTestExpectation alloc] initWithDescription:@"'scanLocation' method called"];
	MockScanner *scanner = [MockScanner new];
	scanner.stringReturnedValue = @"str1 str2 str3";
	scanner.stringExpectation = expectation1;
	scanner.scanLocationReturnedValue = 5;	// str2 first character
	scanner.scanLocationExpectation = expectation2;
	
	LPubCommand *command = [[LPubCommand alloc] init];
	[command finishParsing:(id)scanner];
	[self waitForExpectations:@[expectation1, expectation2] timeout:1];
	
	XCTAssertEqualObjects(command.lPubCommandString, @"str2 str3");
}


- (void)test_LPubCommand_lPubCommandString_AssignedAsCopy
{
	NSMutableString *originalString = [@"Some string" mutableCopy];
	LPubCommand *command = [[LPubCommand alloc] init];
	command.lPubCommandString = originalString;

	[originalString appendString:@"2"];
	
	XCTAssertEqualObjects(originalString, @"Some string2");
	XCTAssertEqualObjects(command.lPubCommandString, @"Some string");
}

@end
