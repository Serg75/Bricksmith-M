//==============================================================================
//
//  File:       LDrawStepCalloutArrangement.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutArrangement
///
/// @abstract   What the callouts' boxes of one step keep from one layout to
///             the next: the sides they have taken, and how far each still
///             has to move.
///
/// @discussion A box keeps to one side of its submodel, of the other boxes
///             and of the arrows. The file's layout says which. In a turn the
///             boxes may take other sides, where that keeps them off the
///             arrows or nearer their submodels. A box that changes sides
///             moves to its new place over a short time.
///
///             A host keeps one for the step on display, sets `time` before
///             each layout, and lays the step out again soon while
///             `isMoving`.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutArrangement : NSObject

/// The time of the layout that is about to be made, in seconds from any fixed
/// moment. Moves are measured by it.
@property (nonatomic) NSTimeInterval time;

/// Whether a box is still on its way to its place at `time`.
@property (nonatomic, readonly) BOOL isMoving;

/// Forgets the sides taken and the moves under way. The next layout starts
/// from the file's.
- (void) reset;

@end

NS_ASSUME_NONNULL_END
