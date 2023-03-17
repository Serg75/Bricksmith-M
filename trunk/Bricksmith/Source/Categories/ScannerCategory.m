//==============================================================================
//
//	Category:	ScannerCategory.m
//
//	Purpose:	Extends functionality for NSScanner.
//
//	Created by Sergey Slobodenyuk on 2023-02-28.
//
//==============================================================================

#import "ScannerCategory.h"

static NSString * const quoteMark = @"\"";


@implementation NSScanner (ScannerCategory)

//========== scanSubstringsWithQuotations ======================================
///
/// @abstract	Splits a string into substrings using space characters as
/// 			delimiters.
/// 			Anything enclosed in double quotes is considered an entire
/// 			substring.
/// 			Multiple consecutive space characters act as a single delimiter.
///
//==============================================================================
- (NSArray<NSString *> *)scanSubstringsWithQuotations
{
	NSCharacterSet *spaceSet = NSCharacterSet.whitespaceCharacterSet;
	
	NSCharacterSet *initialSkippedChars = self.charactersToBeSkipped;
	self.charactersToBeSkipped = NSCharacterSet.whitespaceCharacterSet;
	
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	NSString *buffer = @"";
	while ([self scanUpToCharactersFromSet:spaceSet intoString:&buffer]) {
		NSString *remainder = @"";
		if ([buffer hasPrefix:quoteMark]) {
			if ([buffer hasSuffix:quoteMark] == NO ) {
				NSCharacterSet *oldSkippedChars = self.charactersToBeSkipped;
				self.charactersToBeSkipped = nil;
				if ([self scanUpToString:quoteMark intoString:&remainder]) {
					// skip closing quote
					[self scanString:quoteMark intoString:nil];
					remainder = [remainder stringByAppendingString:quoteMark];
				}
				self.charactersToBeSkipped = oldSkippedChars;
			}
		}
		[result addObject:[buffer stringByAppendingString:remainder]];
	}
	self.charactersToBeSkipped = initialSkippedChars;
	
	return result;
	
}//end scanSubstringsWithQuotations

@end
