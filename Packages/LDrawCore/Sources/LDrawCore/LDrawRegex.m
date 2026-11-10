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


//---------- LDrawCompiledRegex ------------------------------------------------
//
// Purpose:		The compiled pattern, or nil for an empty or bad pattern.
//				Patterns are compiled once and kept, since the parser asks for
//				the same few on every line. Safe from any thread.
//
//------------------------------------------------------------------------------
static NSRegularExpression *LDrawCompiledRegex(NSString *pattern)
{
	static NSCache		*cache	= nil;
	static dispatch_once_t once;
	id					 regex	= nil;

	if (pattern.length == 0)
		return nil;

	dispatch_once(&once, ^{
		cache = [[NSCache alloc] init];
		[cache setCountLimit:256];
	});

	regex = [cache objectForKey:pattern];
	if (regex == nil)
	{
		regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
		// A bad pattern is kept as NSNull so it is not compiled again.
		// The key is copied because the cache does not copy it.
		[cache setObject:(regex ?: [NSNull null]) forKey:[pattern copy]];
	}

	return (regex == [NSNull null]) ? nil : regex;
}


@implementation NSString (LDrawRegex)

//========== isMatchedByRegex: ================================================
//
// Purpose:		Return YES if the receiver contains a match for pattern.
//				An empty pattern or a compile error returns NO.
//
//==============================================================================
- (BOOL)isMatchedByRegex:(NSString *)pattern
{
	NSRegularExpression *regex = LDrawCompiledRegex(pattern);
	if (regex == nil) {
		return NO;
	}
	NSRange range = NSMakeRange(0, self.length);
	return [regex rangeOfFirstMatchInString:self options:0 range:range].location != NSNotFound;
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
	NSRegularExpression *regex = LDrawCompiledRegex(pattern);
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
	NSRegularExpression *regex = LDrawCompiledRegex(pattern);
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
