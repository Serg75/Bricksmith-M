//==============================================================================
//
//  File:       LDrawRegex.m
//  Package:    LDrawCore
//
//  Purpose:    Implementation of the LDrawRegex NSString category. Provides a
//              small subset of the old RegexKitLite API on top of
//              NSRegularExpression.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawCore/LDrawRegex.h>

@implementation NSString (LDrawRegex)

//========== isMatchedByRegex: ================================================
//
// Purpose:		Return YES if the receiver contains a match for pattern.
//				An empty pattern or a compile error returns NO.
//
//==============================================================================
- (BOOL)isMatchedByRegex:(NSString *)pattern
{
	if (pattern.length == 0) {
		return NO;
	}
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
																		   options:0
																			 error:&error];
	if (regex == nil) {
		return NO;
	}
	NSRange range = NSMakeRange(0, self.length);
	return [regex firstMatchInString:self options:0 range:range] != nil;
}

//========== captureComponentsMatchedByRegex: =================================
//
// Purpose:		Return capture groups for the first match of pattern, including
//				group 0 (the full match). Missing groups become empty strings.
//
//				An empty pattern or a compile error returns an empty array.
//
//==============================================================================
- (NSArray<NSString *> *)captureComponentsMatchedByRegex:(NSString *)pattern
{
	if (pattern.length == 0) {
		return @[];
	}
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
																		   options:0
																			 error:&error];
	if (regex == nil) {
		return @[];
	}
	NSRange searchRange = NSMakeRange(0, self.length);
	NSTextCheckingResult *match = [regex firstMatchInString:self options:0 range:searchRange];
	if (match == nil) {
		return @[];
	}
	NSMutableArray *components = [NSMutableArray arrayWithCapacity:match.numberOfRanges];
	for (NSUInteger i = 0; i < match.numberOfRanges; i++) {
		NSRange r = [match rangeAtIndex:i];
		if (r.location == NSNotFound) {
			[components addObject:@""];
		} else {
			[components addObject:[self substringWithRange:r]];
		}
	}
	return components;
}

//========== arrayOfCaptureComponentsMatchedByRegex: ==========================
//
// Purpose:		Return capture groups for every match of pattern in the
//				receiver. Each inner array is one match, formatted like
//				-captureComponentsMatchedByRegex:.
//
//==============================================================================
- (NSArray<NSArray<NSString *> *> *)arrayOfCaptureComponentsMatchedByRegex:(NSString *)pattern
{
	if (pattern.length == 0) {
		return @[];
	}
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
																		   options:0
																			 error:&error];
	if (regex == nil) {
		return @[];
	}
	NSRange searchRange = NSMakeRange(0, self.length);
	NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:self options:0 range:searchRange];
	NSMutableArray *allMatches = [NSMutableArray arrayWithCapacity:matches.count];
	for (NSTextCheckingResult *match in matches) {
		NSMutableArray *components = [NSMutableArray arrayWithCapacity:match.numberOfRanges];
		for (NSUInteger i = 0; i < match.numberOfRanges; i++) {
			NSRange r = [match rangeAtIndex:i];
			if (r.location == NSNotFound) {
				[components addObject:@""];
			} else {
				[components addObject:[self substringWithRange:r]];
			}
		}
		[allMatches addObject:components];
	}
	return allMatches;
}

@end
