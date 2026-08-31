//==============================================================================
//
//  File:       LDrawMovableDirective.h
//  Package:    LDrawCore
//
//  Purpose:    Protocol adopted by classes that can be moved. This allows both
//              simple parts and containers such as LDrawLSynth to be targeted
//              by move operations.
//
//==============================================================================

#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @protocol   LDrawMovableDirective
///
/// @abstract   This protocol is adopted by classes that are movable. This
///             allows both simple parts and containers such as LDrawLSynth to
///             be targeted by move operations.
///
//------------------------------------------------------------------------------
@protocol LDrawMovableDirective
- (Vector3) displacementForNudge:(Vector3)nudgeVector;
- (void) moveBy:(Vector3)moveVector;
@end

NS_ASSUME_NONNULL_END
