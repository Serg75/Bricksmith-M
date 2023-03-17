//
//  ScannerCategory_Tests.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-03.
//

#import "ScannerCategory.h"

#import <XCTest/XCTest.h>

@interface ScannerCategory_Tests : XCTestCase

@end


@implementation ScannerCategory_Tests

- (void)test_Quotations_EmptyString_ReturnsEmptyArray
{
	NSString *inputString = @"";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 0);
}


- (void)test_Quotations_OnlyWhitespaces_ReturnsEmptyArray
{
	NSString *inputString = @"  	";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 0);
}


- (void)test_Quotations_OneWord_ReturnsArrayWithOneItem
{
	NSString *inputString = @"word";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 1);
	XCTAssertEqualObjects(result[0], @"word");
}


- (void)test_Quotations_OneWordWithSpaces_ReturnsArrayWithOneItem
{
	NSString *inputString = @"   word	";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 1);
	XCTAssertEqualObjects(result[0], @"word");
}


- (void)test_Quotations_SeveralWords_ReturnsSplittedWords
{
	NSString *inputString = @"word1 word2 word3";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 3);
	XCTAssertEqualObjects(result[0], @"word1");
	XCTAssertEqualObjects(result[1], @"word2");
	XCTAssertEqualObjects(result[2], @"word3");
}


- (void)test_Quotations_SeveralWordsWithSpaces_ReturnsSplittedWords
{
	NSString *inputString = @"word1   word2			word3	";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 3);
	XCTAssertEqualObjects(result[0], @"word1");
	XCTAssertEqualObjects(result[1], @"word2");
	XCTAssertEqualObjects(result[2], @"word3");
}


- (void)test_Quotations_PhraseInsideQuotes_ReturnsThatPhrase
{
	NSString *inputString = @"\"word1   word2\"	";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 1);
	XCTAssertEqualObjects(result[0], @"\"word1   word2\"");
}


- (void)test_Quotations_PlainWordsAndQuotation_ReturnsPropperResult
{
	NSString *inputString = @"word1   word2   \"word3   word4\"	";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 3);
	XCTAssertEqualObjects(result[0], @"word1");
	XCTAssertEqualObjects(result[1], @"word2");
	XCTAssertEqualObjects(result[2], @"\"word3   word4\"");
}


- (void)test_Quotations_SeveralQuotations_ReturnsPropperResult
{
	NSString *inputString = @"\"word1   word2\"   \"word3   word4\"	";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 2);
	XCTAssertEqualObjects(result[0], @"\"word1   word2\"");
	XCTAssertEqualObjects(result[1], @"\"word3   word4\"");
}


- (void)test_Quotations_QuoteWithoutLeadingSpase_DoesNotFormQuotation
{
	NSString *inputString = @" word1\"word2\" ";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 1);
	XCTAssertEqualObjects(result[0], @"word1\"word2\"");
}


// TODO: - Fix corner cases -


- (void)TODO_test_Quotations_LeadingOrTrailingSpaceInsideQuotation_ReturnsPropperResult
{
	NSString *inputString = @"\" word1   word2 \" ";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 1);
	XCTAssertEqualObjects(result[0], @"\" word1   word2 \" ");
}


- (void)TODO_test_Quotations_SingleOpenQuote_DoesNotFormQuotation
{
	NSString *inputString = @" word1   \"word2 ";
	NSScanner *scanner = [NSScanner scannerWithString:inputString];
	
	NSArray *result = [scanner scanSubstringsWithQuotations];
	
	XCTAssertEqual(result.count, 2);
	XCTAssertEqualObjects(result[0], @"word1");
	XCTAssertEqualObjects(result[1], @"\"word2");
}


@end
