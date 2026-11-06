//==============================================================================
//
//  File:       NSString+LDraw.h
//  Package:    LDrawCore
//
//  Purpose:    Handy string utilities.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


//------------------------------------------------------------------------------
///
/// @class      NSString
///
/// @abstract   Handy string utilities.
///
//------------------------------------------------------------------------------
@interface NSString (LDraw)

- (BOOL) ldraw_containsString:(NSString *)substring options:(NSUInteger)mask;
+ (NSString *) CRLF;
- (NSComparisonResult)numericCompare:(NSString *)string;
- (NSArray *) separateByLine;
- (NSString *) ldraw_stringByRemovingWhitespace;
/// The spaces between the words of an LDraw line: whitespace and a byte order
/// mark, which a file can start with.
+ (NSCharacterSet *) ldraw_lineSpaceCharacterSet;

@end

NS_ASSUME_NONNULL_END
