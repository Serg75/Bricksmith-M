//==============================================================================
//
//  File:       LDrawStepPageNumbers.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-18.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawFile;
@class LDrawStep;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPageNumber
///
/// @abstract   One page of the instruction book that shows a step.
///
//------------------------------------------------------------------------------
@interface LDrawStepPageNumber : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// The page's number, from 1.
@property (nonatomic, readonly) NSUInteger	number;

/// YES when the step is shown in a callout's box on that page.
@property (nonatomic, readonly) BOOL		isInCallout;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPageNumbers
///
/// @abstract   Which pages of the instruction book show each step of a file.
///
/// @discussion The pages are counted as LPub3D prints the file's first model,
///             one step per page. A submodel called out with its steps is
///             shown on the page of the step that places it. The count is
///             made once: make a new one after the file changes.
///
//------------------------------------------------------------------------------
@interface LDrawStepPageNumbers : NSObject

- (instancetype) init NS_UNAVAILABLE;

+ (instancetype) pageNumbersOfFile:(nullable LDrawFile *)file NS_SWIFT_NAME(init(file:));

/// The file the pages were counted in.
@property (nonatomic, readonly, weak, nullable) LDrawFile *file;

/// The pages that show the step, in reading order. Empty for a step on no
/// page.
- (NSArray<LDrawStepPageNumber *> *) pagesShowingStep:(nullable LDrawStep *)step NS_SWIFT_NAME(pages(showing:));

/// The pages as one line, such as "10/15". A page where the step is in a
/// callout has a mark before its number.
+ (NSString *) textForPages:(NSArray<LDrawStepPageNumber *> *)pages NS_SWIFT_NAME(text(for:));

@end

NS_ASSUME_NONNULL_END
