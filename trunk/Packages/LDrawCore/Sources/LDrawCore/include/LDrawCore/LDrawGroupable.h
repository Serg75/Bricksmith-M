//==============================================================================
//
//  File:       LDrawGroupable.h
//  Package:    LDrawCore
//
//  Purpose:    Directives that can belong to an MLCAD group.
//
//  Created by Sergey Slobodenyuk on 2026-09-02.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// Types & Constants
//
////////////////////////////////////////////////////////////////////////////////

/// What the visualization engine does with a directive, given the
/// `0 !LPUB REMOVE GROUP` commands in scope. Derived by LDrawModel.
typedef NS_ENUM(NSInteger, LDrawGroupVisibilityT)
{
	/// No removal in scope: draw normally.
	LDrawGroupVisibilityVisible	= 0,

	/// Removed: draw nothing, and stay out of the bounds and picking.
	LDrawGroupVisibilityHidden	= 1,

	/// Drawn translucent: still visible, and still counted for bounds and
	/// picking so it can be clicked and edited, but no longer obscuring the
	/// rest of the model. The renderers blend a ghost as one whole part rather
	/// than surface by surface, so its interior does not show through the way
	/// a transparent brick's does.
	LDrawGroupVisibilityGhosted	= 2
};


/// Alpha a ghost draws at.
///
/// Has to stay strictly between 0 and 1: the renderers scale a ghost's alpha by
/// this, so 0 would draw nothing at all and 1 would defeat the point.
static const float LDRAW_GHOST_ALPHA = 0.3f;


//------------------------------------------------------------------------------
///
/// @protocol   LDrawGroupable
///
/// @abstract   A directive that can carry an MLCAD group name, and that the
///             visualization engine can therefore drop or ghost when an
///             `0 !LPUB REMOVE GROUP` command names that group.
///
//------------------------------------------------------------------------------
@protocol LDrawGroupable <NSObject>

/// MLCAD group name (`0 MLCAD BTG <name>`), or nil when ungrouped.
@property (nonatomic, strong, nullable) NSString *group;

/// What an in-scope `0 !LPUB REMOVE GROUP` does to this directive.
///
/// LDrawModel derives this from its steps; it is never parsed or written, and
/// it is separate from the user's own Hide/Show flag so that hiding a part by
/// hand and removing its group don't overwrite each other.
@property (nonatomic) LDrawGroupVisibilityT groupVisibility;

/// YES when the directive takes no part in the rendered model at all -- either
/// hidden by hand or dropped by an in-scope `0 !LPUB REMOVE GROUP`.
///
/// Drawing, bounds and picking all gate on this one answer, so they cannot
/// drift apart and leave something invisible but still clickable, or gone from
/// the screen but still inflating the model's bounding box. A ghost is *not*
/// omitted: it draws, and it stays selectable so it can be edited.
@property (readonly, getter=isOmitted) BOOL omitted;

@end

NS_ASSUME_NONNULL_END
