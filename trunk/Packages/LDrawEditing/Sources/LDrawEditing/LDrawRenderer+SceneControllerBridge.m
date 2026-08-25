//==============================================================================
//
//  File:       LDrawRenderer+SceneControllerBridge.m
//  Package:    LDrawEditing
//
//  Purpose:    Publishes LDrawRenderer methods as LDrawSceneControllerRendererBridge.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawEditing/LDrawRenderer+SceneControllerBridge.h>

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDragHandle.h>
#import <LDrawCore/MacLDraw.h>

@implementation LDrawRenderer (SceneControllerBridge)

//========== camera ===========================================================
//
// Purpose:		Expose the renderer's camera to LDrawSceneController without
//				creating a package dependency cycle.
//
//==============================================================================
- (LDrawCamera *)camera
{
	return camera;
}

//========== preferredPartTransform ===========================================
//
// Purpose:		Ask the renderer delegate for the transform to apply to newly
//				dropped parts. Returns identity if the delegate does not
//				implement the optional method.
//
//==============================================================================
- (TransformComponents)preferredPartTransform
{
	if ([delegate respondsToSelector:@selector(LDrawRendererPreferredPartTransform:)])
	{
		return [delegate LDrawRendererPreferredPartTransform:self];
	}
	return IdentityComponents;
}

//========== wantsToSelectDirective:byExtendingSelection: =====================
//
// Purpose:		Forward a single-directive selection request to the renderer
//				delegate when it implements the optional method.
//
//==============================================================================
- (void)wantsToSelectDirective:(LDrawDirective *)directive byExtendingSelection:(BOOL)shouldExtend
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:wantsToSelectDirective:byExtendingSelection:)])
	{
		[delegate LDrawRenderer:self wantsToSelectDirective:directive byExtendingSelection:shouldExtend];
	}
}

//========== wantsToSelectDirectives:selectionMode: ===========================
//
// Purpose:		Forward a multi-directive selection request to the renderer
//				delegate when it implements the optional method.
//
//==============================================================================
- (void)wantsToSelectDirectives:(NSArray *)directives selectionMode:(SelectionModeT)selectionMode
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:wantsToSelectDirectives:selectionMode:)])
	{
		[delegate LDrawRenderer:self wantsToSelectDirectives:directives selectionMode:selectionMode];
	}
}

//========== willBeginDraggingHandle: =========================================
//
// Purpose:		Tell the renderer delegate a drag-handle drag is starting.
//
//==============================================================================
- (void)willBeginDraggingHandle:(LDrawDragHandle *)handle
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:willBeginDraggingHandle:)])
	{
		[delegate LDrawRenderer:self willBeginDraggingHandle:handle];
	}
}

//========== dragHandleDidMove: ===============================================
//
// Purpose:		Tell the renderer delegate the drag handle moved.
//
//==============================================================================
- (void)dragHandleDidMove:(LDrawDragHandle *)handle
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:dragHandleDidMove:)])
	{
		[delegate LDrawRenderer:self dragHandleDidMove:handle];
	}
}

//========== noteNeedsDisplay =================================================
//
// Purpose:		Ask the file being drawn to mark itself dirty so the view
//				redisplays.
//
//==============================================================================
- (void)noteNeedsDisplay
{
	[[self LDrawDirective] noteNeedsDisplay];
}

@end
