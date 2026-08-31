//==============================================================================
//
//  File:       LDrawSelection+Transform.m
//  Package:    LDrawEditing
//
//  Purpose:    Snap-to-grid and mirror transform helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawSelection.h>

#import <LDrawCore/LDrawPart.h>

@implementation LDrawSelection (Transform)

//---------- snappedTransformUpdatesForSelection:gridSpacing:minimumAngle:
//
// Purpose:		Aligns all selected parts to the current grid setting. Kind of a
//				weird legacy API. The host still applies the components (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartTransformUpdate *> *)snappedTransformUpdatesForSelection:(NSArray *)selection
																 gridSpacing:(float)gridSpacing
																minimumAngle:(float)degrees
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsInSelection:selection])
	{
		LDrawPartTransformUpdate *update = [LDrawPartTransformUpdate new];
		update.part = part;
		update.components = [part componentsSnappedToGrid:gridSpacing minimumAngle:degrees];
		[updates addObject:update];
	}
	return updates;
}


//---------- snappedTransformUpdatesForSelection:gridSpacing:axis: ---[static]--
//
// Purpose:		Aligns by axis all selected parts to the current grid setting.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartTransformUpdate *> *)snappedTransformUpdatesForSelection:(NSArray *)selection
																 gridSpacing:(float)gridSpacing
																		axis:(Vector3)axis
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsInSelection:selection])
	{
		LDrawPartTransformUpdate *update = [LDrawPartTransformUpdate new];
		update.part = part;
		update.components = [part componentsSnappedToGrid:gridSpacing byAxis:axis];
		[updates addObject:update];
	}
	return updates;
}


//---------- mirroredTransformUpdatesForSelection:axis: --------------[static]--
//
// Purpose:		Move all selected parts symmetrically by axis. Pass −1 to
//				component(s) which should be mirrored, and 1 to others.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartTransformUpdate *> *)mirroredTransformUpdatesForSelection:(NSArray *)selection
																		 axis:(Vector3)axis
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsInSelection:selection])
	{
		LDrawPartTransformUpdate *update = [LDrawPartTransformUpdate new];
		update.part = part;
		update.components = [part componentsMirroredByAxis:axis];
		[updates addObject:update];
	}
	return updates;
}


@end
