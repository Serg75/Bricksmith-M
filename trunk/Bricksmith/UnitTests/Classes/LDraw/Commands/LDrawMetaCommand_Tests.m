//
//  LDrawMetaCommand_Tests.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-12.
//

#import "LDrawMetaCommand.h"

#import <XCTest/XCTest.h>
#import "LDrawColor.h"
#import "LDrawComment.h"
#import "LDrawLSynthDirective.h"
#import "LPubCommand.h"
#import "LPubRemoveGroup.h"
#import "MockArchiver.h"
#import "MockScanner.h"


// MARK: Mocks -

@interface LDrawMetaCommand ()

+ (LDrawMetaCommand *) metaCommandInstanceByMarker:(NSString *)ldrawMarker scanner:(NSScanner *)scanner;

@end


// MARK: - Tests -

@interface LDrawMetaCommand_Tests : XCTestCase

@end

@implementation LDrawMetaCommand_Tests

- (void)test_LDrawMetaCommand_ClassContainsSubclasses
{
	SEL sel = NSSelectorFromString(@"subclassNames");
	NSArray *subclasses = [LDrawMetaCommand performSelector:sel];
	XCTAssertEqual(subclasses.count, 4);
	XCTAssertTrue([subclasses containsObject:@"LDrawColor"]);
	XCTAssertTrue([subclasses containsObject:@"LDrawComment"]);
	XCTAssertTrue([subclasses containsObject:@"LDrawLSynthDirective"]);
	XCTAssertTrue([subclasses containsObject:@"LPubCommand"]);
}


- (void)test_LDrawMetaCommand_initWithLines_Success
{
	// This version uses XCTActivity to split multiple test executions with different parameters (visible only in Report Navigator).
	// To have separate lines in Test Navigator the technic with overriding testInvocations method should be used.
	// See example: https://github.com/manicmaniac/xcnew/blob/7417eb2efa2c60ccd71f3d13be8582a54d1fedd2/Tests/xcnew-tests/XCNOptionParserParameterizedTests.m
	
	NSArray *testCases = @[
		@{@"line":
			  @"  ",
		  @"result":
			  [LDrawMetaCommand class]},

		@{@"line":
			  @"",
		  @"result":
			  [LDrawMetaCommand class]},

		@{@"line":
			  @"0 some text",
		  @"result":
			  [LDrawMetaCommand class]},

		@{@"line":
			  @"0 !COLOUR name CODE 100 VALUE #F0F0F0 EDGE 400 ALPHA 0",
		  @"result":
			  [LDrawColor class]},

		@{@"line":
			  @"0 // comment",
		  @"result":
			  [LDrawComment class]},

		@{@"line":
			  @"0 !LPUB command",
		  @"result":
			  [LPubCommand class]},

		@{@"line":
			  @"0 !LPUB REMOVE GROUP \"a\"",
		  @"result":
			  [LPubRemoveGroup class]}
	];
	
	for (NSDictionary *testCase in testCases) {
		NSString *line = testCase[@"line"];
		id result = testCase[@"result"];
		NSString *activityName = [NSString stringWithFormat:@"Line: \"%@\"", line];
		
		[XCTContext runActivityNamed:activityName block:^(id<XCTActivity>  _Nonnull activity) {
			LDrawMetaCommand *command =
				[[LDrawMetaCommand alloc] initWithLines:@[line]
												inRange:NSMakeRange(0, 1)
											parentGroup:NULL];
			XCTAssertIdentical(command.class, result);
		}];
	}
}


- (void)test_LDrawMetaCommand_EncodedProperly
{
	MockArchiver *encoder = [MockArchiver new];
	LDrawMetaCommand *command = [[LDrawMetaCommand alloc] init];
	command.commandString = @"Some string";

	[command encodeWithCoder:encoder];

	XCTAssertEqual(encoder.data.count, 1);
	XCTAssertEqualObjects(encoder.data[@"commandString"], @"Some string");
}


- (void)test_LDrawMetaCommand_DecodedProperly
{
	MockArchiver *decoder = [MockArchiver new];
	decoder.data = [@{
		@"commandString" : @"Some string"
	} mutableCopy];

	LDrawMetaCommand *command = [[LDrawMetaCommand alloc] initWithCoder:decoder];
	command.commandString = @"Some string";

	XCTAssertEqualObjects(command.commandString, @"Some string");
}


- (void)test_LDrawMetaCommand_CopiedProperly
{
	LDrawMetaCommand *command = [[LDrawMetaCommand alloc] init];
	command.commandString = @"Some string";

	LDrawMetaCommand *duplicate = [command copyWithZone:nil];

	XCTAssertEqualObjects(command.commandString, duplicate.commandString);
	XCTAssertNotIdentical(command, duplicate);
}


- (void)test_LDrawMetaCommand_CopiedObjectHasNonIdenticalValues
{
	LDrawMetaCommand *command = [[LDrawMetaCommand alloc] init];
	command.commandString = @"Some string";

	LDrawMetaCommand *duplicate = [command copyWithZone:nil];
	command.commandString = @"Another string";

	XCTAssertNotEqualObjects(command.commandString, duplicate.commandString);
}


- (void)test_LDrawMetaCommand_metaCommandInstanceByMarker_ReturnsNil
{
	NSString *marker = @"string";
	id scanner = [MockScanner new];
	LDrawMetaCommand *command = [LDrawMetaCommand metaCommandInstanceByMarker:marker scanner:scanner];
	
	XCTAssertNil(command);
}

@end
