//
//  LPubRemoveGroup_Tests.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-09.
//

#import "LPubRemoveGroup.h"

#import <XCTest/XCTest.h>
#import "MockArchiver.h"
#import "MockScanner.h"


// MARK: Mocks -

@interface LPubRemoveGroup ()

+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters;

@end


// MARK: - Tests -

@interface LPubRemoveGroup_Tests : XCTestCase

@end

@implementation LPubRemoveGroup_Tests

- (void)test_LPubRemoveGroup_EncodedProperly
{
	MockArchiver *encoder = [MockArchiver new];
	LPubRemoveGroup *command = [[LPubRemoveGroup alloc] init];
	command.groupName = @"Some string";

	[command encodeWithCoder:encoder];

	XCTAssertEqual(encoder.data.count, 3);
	XCTAssertEqualObjects(encoder.data[@"groupName"], @"Some string");
	XCTAssertEqualObjects(encoder.data[@"lpubCommandString"], @"REMOVE GROUP \"Some string\"");
	XCTAssertEqualObjects(encoder.data[@"commandString"], @"!LPUB REMOVE GROUP \"Some string\"");
}


- (void)test_LPubRemoveGroup_DecodedProperly
{
	MockArchiver *decoder = [MockArchiver new];
	decoder.data = [@{
				@"groupName" : @"Some string",
		@"lpubCommandString" : @"REMOVE GROUP \"Some string\"",
			@"commandString" : @"!LPUB REMOVE GROUP \"Some string\""
	} mutableCopy];
	
	LPubRemoveGroup *command = [[LPubRemoveGroup alloc] initWithCoder:decoder];
	command.groupName = @"Some string";

	XCTAssertEqualObjects(command.groupName, @"Some string");
	XCTAssertEqualObjects(command.lPubCommandString, @"REMOVE GROUP \"Some string\"");
	XCTAssertEqualObjects(command.commandString, @"!LPUB REMOVE GROUP \"Some string\"");
}


- (void)test_LPubRemoveGroup_CopiedProperly
{
	LPubRemoveGroup *command = [[LPubRemoveGroup alloc] init];
	command.groupName = @"Some string";

	LPubRemoveGroup *duplicate = [command copyWithZone:nil];
	
	XCTAssertEqualObjects(command.groupName, duplicate.groupName);
	XCTAssertEqualObjects(command.lPubCommandString, duplicate.lPubCommandString);
	XCTAssertEqualObjects(command.commandString, duplicate.commandString);
	XCTAssertNotIdentical(command, duplicate);
}


- (void)test_LPubRemoveGroup_CopiedObjectHasNonIdenticalValues
{
	LPubRemoveGroup *command = [[LPubRemoveGroup alloc] init];
	command.groupName = @"Some string";

	LPubRemoveGroup *duplicate = [command copyWithZone:nil];
	command.groupName = @"Another string";
	
	XCTAssertNotEqualObjects(command.groupName, duplicate.groupName);
	XCTAssertNotEqualObjects(command.lPubCommandString, duplicate.lPubCommandString);
	XCTAssertNotEqualObjects(command.commandString, duplicate.commandString);
}


- (void)test_LPubRemoveGroup_IfParametersIsLessThan3_NoLPubCommandCreated
{
	NSArray<NSString *> *parameters = @[@"REMOVE", @"GROUP"];
	
	LPubCommand *command = [LPubRemoveGroup lpubCommandInstance:parameters];
	
	XCTAssertNil(command);
}


- (void)test_LPubRemoveGroup_IfParametersIsMoreThan3_NoLPubCommandCreated
{
	NSArray<NSString *> *parameters = @[@"REMOVE", @"GROUP", @"\"name\"", @"extra"];
	
	LPubCommand *command = [LPubRemoveGroup lpubCommandInstance:parameters];
	
	XCTAssertNil(command);
}


- (void)test_LPubRemoveGroup_IfWrongParameters_NoLPubCommandCreated
{
	NSArray<NSString *> *parameters = @[@"REMOVE", @"GROUPS", @"\"name\""];
	
	LPubCommand *command = [LPubRemoveGroup lpubCommandInstance:parameters];
	
	XCTAssertNil(command);
}


- (void)test_LPubRemoveGroup_IfExpectedParameters_ProperCommandCreated
{
	NSArray<NSString *> *parameters = @[@"REMOVE", @"GROUP", @"\"name\""];
	
	LPubCommand *command = [LPubRemoveGroup lpubCommandInstance:parameters];
	
	XCTAssertIdentical(command.class, LPubRemoveGroup.class);
	XCTAssertEqualObjects(((LPubRemoveGroup *)command).groupName, @"name");
	XCTAssertEqualObjects(command.lPubCommandString, @"REMOVE GROUP \"name\"");
	XCTAssertEqualObjects(command.commandString, @"!LPUB REMOVE GROUP \"name\"");
}


- (void)test_LPubRemoveGroup_finishParsing_DoesNothing
{
	NSArray<NSString *> *parameters = @[@"REMOVE", @"GROUP", @"\"name\""];
	LPubRemoveGroup *command = (LPubRemoveGroup *)[LPubRemoveGroup lpubCommandInstance:parameters];
	LPubRemoveGroup *duplicate = [command copy];

	MockScanner *scanner = [MockScanner new];
	[command finishParsing:(id)scanner];
	
	XCTAssertEqualObjects(command.groupName, duplicate.groupName);
}


- (void)test_LPubRemoveGroup_groupName_AssignedAsCopy
{
	NSArray<NSString *> *parameters = @[@"REMOVE", @"GROUP", @"\"name\""];
	LPubRemoveGroup *command = (LPubRemoveGroup *)[LPubRemoveGroup lpubCommandInstance:parameters];

	NSMutableString *originalString = [@"group" mutableCopy];
	command.groupName = originalString;
	[originalString appendString:@"2"];
	
	XCTAssertEqualObjects(originalString, @"group2");
	XCTAssertEqualObjects(command.groupName, @"group");
}

@end
