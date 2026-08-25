//==============================================================================
//
//  File:       LDrawRegex.h
//  Package:    LDrawCore
//
//  Purpose:    Foundation-only NSString regex helpers used by the LDraw parser
//              and LSynth code. Replaces RegexKitLite for SPM and ARC builds.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

//------------------------------------------------------------------------------
///
/// @class      NSString
///
/// @abstract   Foundation-only NSString regex helpers used by the LDraw parser
///             and LSynth code. Replaces RegexKitLite for SPM and ARC builds.
///
//------------------------------------------------------------------------------
@interface NSString (LDrawRegex)

/// YES if the receiver contains a match for pattern. An empty pattern or a
/// compile error returns NO.
- (BOOL)isMatchedByRegex:(NSString *)pattern;

/// Capture groups for the first match of pattern, including group 0 (the full
/// match). Missing groups become empty strings.
///
/// An empty pattern or a compile error returns an empty array.
- (NSArray<NSString *> *)captureComponentsMatchedByRegex:(NSString *)pattern;

/// Capture groups for every match of pattern in the receiver. Each inner array
/// is one match, formatted like `-captureComponentsMatchedByRegex:`.
- (NSArray<NSArray<NSString *> *> *)arrayOfCaptureComponentsMatchedByRegex:(NSString *)pattern;

@end
