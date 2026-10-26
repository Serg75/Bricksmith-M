//==============================================================================
//
//  File:       LDrawLPubRangeTracker.h
//  Package:    LDrawFeatures
//
//  Purpose:    Follows LPub3D's IGN and SUB ranges while a step's directives
//              are walked. Shared by the step parts list and the parts limit,
//              so both leave out and stand in for the same parts.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawColor;
@class LDrawDirective;
@class LDrawPart;
@class LPubPliSubstitute;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLPubRange
///
/// @abstract   One open `PLI BEGIN IGN` or `PLI BEGIN SUB` range.
///
//------------------------------------------------------------------------------
@interface LDrawLPubRange : NSObject

/// The substitute this range lists in its place, or nil for an IGN range.
@property (nonatomic, strong, nullable) LPubPliSubstitute *substitute;

/// This range sits inside one that lists nothing, so its substitute is not
/// listed either.
@property (nonatomic) BOOL suppressed;

/// The color of the first part inside, for a substitute that names none.
@property (nonatomic, strong, nullable) LDrawColor *firstColor;

/// The parts inside, which the substitute stands for.
@property (nonatomic, readonly) NSMutableArray<LDrawPart *> *enclosedParts;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawLPubRangeTracker
///
/// @abstract   The ranges open at a point of a step.
///
/// @discussion `PLI BEGIN IGN` and `PLI BEGIN SUB` share one `PLI END`, so an
///             END closes whichever opened last. They nest, so they are a
///             stack, and an END with nothing open does nothing.
///             `PART BEGIN IGN` has its own END and depth.
///
//------------------------------------------------------------------------------
@interface LDrawLPubRangeTracker : NSObject

/// Reads a directive. Returns YES when it opens or closes a range, and then
/// sets `closedRange` to the range a `PLI END` closed, if any.
- (BOOL) readBracket:(LDrawDirective *)directive closedRange:(LDrawLPubRange * _Nullable * _Nonnull)closedRange;

/// Tells every open range about a part inside it, in its color.
- (void) notePart:(LDrawPart *)part color:(nullable LDrawColor *)color;

/// Whether some range is open, so a part here is not listed for itself.
@property (nonatomic, readonly) BOOL isInsideRange;

/// The ranges still open, oldest first. A range that never closes still
/// stands in for the rest of the step.
@property (nonatomic, readonly) NSArray<LDrawLPubRange *> *openRanges;

@end

NS_ASSUME_NONNULL_END
