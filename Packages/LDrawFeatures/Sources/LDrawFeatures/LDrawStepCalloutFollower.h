//==============================================================================
//
//  File:       LDrawStepCalloutFollower.h
//  Package:    LDrawFeatures
//
//  Purpose:    Moves the callouts' boxes on a page with their submodels.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepCalloutBox.h>

@class LDrawStepCalloutArrangement;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutFollower
///
/// @abstract   Moves the boxes of a page as far as their submodels have moved
///             in the view, where there is room for it.
///
/// @discussion A box stays on the page, and clear of the parts list and of
///             the other boxes. The room it keeps is LPub3D's: the larger of
///             the two things' margins. It keeps to one side of each, so it
///             slides along them and never jumps over one. Two boxes that
///             meet stop each other half way.
///
///             A box also keeps off the arrows where it can: to its side of
///             where another box's arrow goes, and far enough from where its
///             own goes for the arrow to show. The page, the list and the
///             other boxes count for more than that.
///
///             The sides are the ones the file's layout puts the boxes on.
///             With an arrangement the boxes may take others: each may go to
///             another side of its submodel, and they may change places. They
///             do when that is better by enough, and move there over a short
///             time.
///
///             A box the file puts off the page stays where it is: one that
///             reaches more than a tenth of an inch over an edge. Two things
///             the file puts over each other do not keep clear of each other
///             while the boxes are on the file's sides.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutFollower : NSObject

/// Moves each box as far as the middle of what it places has moved, where
/// there is room.
///
/// `places` has, for each box, where the camera draws what it places now, as
/// Box2 values: a box with no size at the middle of its placements, then the
/// box around each placement one of its arrows goes to. A placement that
/// cannot be measured is a box with no size at its middle. `laidOutPlaces`
/// has the same as it was drawn when the step was laid out. A box with no
/// places in either does not move.
///
/// `listFrame` is the parts list's frame, or an empty box when the step shows
/// none. With no arrangement the boxes keep to the file's sides, and go to
/// their places at once.
+ (void) moveBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
			  from:(NSArray<NSData *> *)laidOutPlaces
				to:(NSArray<NSData *> *)places
			onPage:(Box2)pageRect
		 listFrame:(Box2)listFrame
 pointsPerPageInch:(double)pointsPerPageInch
	   arrangement:(nullable LDrawStepCalloutArrangement *)arrangement;

/// Puts each box by itself, where the file is not asked: beside the step's
/// assembly, past the side nearest what the box calls out and level with
/// that, where there is room. `assemblyRect` is the box around the assembly as
/// the camera draws it now, and `places` is as for moving the boxes.
///
/// With an arrangement the boxes keep their sides from one layout to the next,
/// and move over a short time when they change them. With none they take the
/// best sides there are, at once.
+ (void) placeBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
	 aroundAssembly:(Box2)assemblyRect
			 places:(NSArray<NSData *> *)places
			 onPage:(Box2)pageRect
		  listFrame:(Box2)listFrame
  pointsPerPageInch:(double)pointsPerPageInch
		arrangement:(nullable LDrawStepCalloutArrangement *)arrangement;

/// Puts each box where the file puts it, for a camera at the angle the step
/// was laid out at. A box that had taken another side moves there over a
/// short time.
+ (void) restBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes
			onPage:(Box2)pageRect
 pointsPerPageInch:(double)pointsPerPageInch
	   arrangement:(LDrawStepCalloutArrangement *)arrangement;

@end

NS_ASSUME_NONNULL_END
