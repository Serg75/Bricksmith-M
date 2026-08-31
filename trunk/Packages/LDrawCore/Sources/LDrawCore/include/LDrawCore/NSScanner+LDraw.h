//==============================================================================
//
//  File:       NSScanner+LDraw.h
//  Package:    LDrawCore
//
//  Purpose:    Extends functionality for NSScanner.
//
//  Created by Sergey Slobodenyuk on 2023-02-28.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      NSScanner
///
/// @abstract   Extends functionality for NSScanner.
///
//------------------------------------------------------------------------------
@interface NSScanner (LDraw)

- (NSArray<NSString *> *)scanSubstringsWithQuotations;

@end

NS_ASSUME_NONNULL_END
