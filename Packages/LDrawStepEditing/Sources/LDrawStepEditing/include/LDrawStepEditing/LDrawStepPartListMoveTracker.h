//==============================================================================
//
//  File:       LDrawStepPartListMoveTracker.h
//  Package:    LDrawStepEditing
//
//  Created by Sergey Slobodenyuk on 2026-10-21.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawStepEditing/LDrawStepAssemblyEdit.h>

@class LDrawModel;
@class LDrawStepPartListPresentation;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListMoveTracker
///
/// @abstract   Follows a drag of the parts list on LPub3D's page, and says what
///             dropping it writes.
///
/// @discussion The list snaps to the page's nine places: on each axis, to the
///             column or row of places within a few points. Dropped on one of
///             them, it is placed there with no offset. Dropped anywhere else,
///             it is placed at the nearest of them, with the offset from it.
///             That keeps the offset small, and the edge a resize moves on the
///             far side from the place.
///
///             The host keeps the frame where `origin` says while the drag
///             goes on, and writes nothing until the drop.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListMoveTracker : NSObject

/// A drag of the list is in progress.
@property (nonatomic, readonly) BOOL isMoving;

/// Where the list's frame is held: its top left corner in the view, snapped.
@property (nonatomic, readonly) Point2 origin;

/// The page's guides the frame snapped to: Box2 lines across the page, with
/// no width or no height. The margin line its edge meets, or the middle line
/// its middle meets. Empty when it snapped to none.
@property (nonatomic, readonly, copy) NSData *guides;

/// Starts a drag when the point is on the list on the page. NO anywhere else.
- (BOOL) beginAtPoint:(Point2)point presentation:(nullable LDrawStepPartListPresentation *)presentation
	NS_SWIFT_NAME(begin(at:presentation:));

/// Moves the frame under the pointer, snapped to the page's places.
- (void) dragToPoint:(Point2)point NS_SWIFT_NAME(drag(to:));

/// The edit that puts the list where it is held, for these steps. Nil when it
/// was not moved, as by a click.
- (nullable LDrawStepAssemblyEdit *) editForDropInModel:(nullable LDrawModel *)model
												  scope:(LDrawStepAssemblyScope)scope
	NS_SWIFT_NAME(editForDrop(inModel:scope:));

/// Ends the drag, dropped or not.
- (void) end;

/// The edit that puts the list's corner at `origin`, a point of the view, as a
/// drop there would with nothing snapped: at the nearest of the page's places,
/// with the offset from it. Nil off the page.
+ (nullable LDrawStepAssemblyEdit *) editPlacingListAtOrigin:(Point2)origin
												presentation:(nullable LDrawStepPartListPresentation *)presentation
													   scope:(LDrawStepAssemblyScope)scope
													 inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(placingListAt:presentation:scope:inModel:));

@end

NS_ASSUME_NONNULL_END
