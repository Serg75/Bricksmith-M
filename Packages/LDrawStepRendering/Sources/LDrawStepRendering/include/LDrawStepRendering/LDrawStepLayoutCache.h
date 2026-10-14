//==============================================================================
//
//  File:       LDrawStepLayoutCache.h
//  Package:    LDrawStepRendering
//
//  Created by Sergey Slobodenyuk on 2026-10-14.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepLayoutCache
///
/// @abstract   Keeps what centering a step on LPub3D's page measured: the
///             points around the step's assembly, and where the page went for
///             it in a view. A step centered again in the same view is then
///             not measured again.
///
/// @discussion Steps are told apart by their model's name and their place in
///             it, so a host shares one only between views that show copies
///             of one file. A model with no name is not kept.
///
///             A page's place is kept for one viewing angle, zoom, view size
///             and scroll, and used for no other.
///
//------------------------------------------------------------------------------
@interface LDrawStepLayoutCache : NSObject

/// Forgets everything. Call it when the file, the part library or the parts
/// list's settings change.
- (void) removeAll;

@end

NS_ASSUME_NONNULL_END
