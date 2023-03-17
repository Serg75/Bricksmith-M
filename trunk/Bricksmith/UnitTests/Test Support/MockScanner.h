//
//  MockScanner.h
//  UnitTests
//
//  Created by Sergey Slobodenyuk on 2023-03-09.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class		MockScanner
///
/// @abstract	Mock for the NSScanner class.
///
//------------------------------------------------------------------------------
@interface MockScanner : NSObject

@property NSString *stringReturnedValue;
@property NSUInteger scanLocationReturnedValue;
@property NSArray<NSString *> *scanSubstringsWithQuotationsReturnedValue;

@property XCTestExpectation *stringExpectation;
@property XCTestExpectation *scanLocationExpectation;
@property XCTestExpectation *scanSubstringsWithQuotationsExpectation;

@end

NS_ASSUME_NONNULL_END
