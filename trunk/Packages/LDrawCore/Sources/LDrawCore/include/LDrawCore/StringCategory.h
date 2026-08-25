//==============================================================================
//
//  File:       StringCategory.h
//  Package:    LDrawCore
//
//  Purpose:    Handy string utilities.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>


//------------------------------------------------------------------------------
///
/// @class      NSString
///
/// @abstract   Handy string utilities.
///
//------------------------------------------------------------------------------
@interface NSString (StringCategory)

- (BOOL) ams_containsString:(NSString *)substring options:(NSUInteger)mask;
+ (NSString *) CRLF;
- (NSComparisonResult)numericCompare:(NSString *)string;
- (NSArray *) separateByLine;
- (NSString *) ams_stringByRemovingWhitespace;

@end
