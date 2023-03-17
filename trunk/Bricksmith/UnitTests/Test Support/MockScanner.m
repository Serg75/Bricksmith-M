//
//  MockScanner.m
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-09.
//

#import "MockScanner.h"

@implementation MockScanner

//========== string ============================================================
///
/// @abstract	Implementation for the protocol method.
///
//==============================================================================
- (NSString *)string
{
	[self.stringExpectation fulfill];
	return self.stringReturnedValue;
}

//========== string ============================================================
///
/// @abstract	Implementation for the protocol method.
///
//==============================================================================
- (NSUInteger)scanLocation
{
	[self.scanLocationExpectation fulfill];
	return self.scanLocationReturnedValue;
}

//========== string ============================================================
///
/// @abstract	Implementation for our extension method.
///
//==============================================================================
- (NSArray<NSString *> *)scanSubstringsWithQuotations
{
	[self.scanSubstringsWithQuotationsExpectation fulfill];
	return self.scanSubstringsWithQuotationsReturnedValue;
}

@end
