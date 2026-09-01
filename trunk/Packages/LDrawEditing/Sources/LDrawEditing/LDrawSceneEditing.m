//==============================================================================
//
//  File:       LDrawSceneEditing.m
//  Package:    LDrawEditing
//
//  Purpose:    Forwards LDrawSceneControllerRendererBridge onto LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawEditing/LDrawSceneEditing.h>

#import <LDrawRenderCore/LDrawRenderer.h>

@implementation LDrawSceneEditing

//========== initWithRenderer: ================================================
//
// Purpose:		Wrap the renderer the host view already owns. The adapter does
//				not retain it; the view does.
//
//==============================================================================
- (instancetype)initWithRenderer:(LDrawRenderer *)renderer
{
	self = [super init];
	if (self)
	{
		_renderer = renderer;
	}
	return self;
}


//========== viewport =========================================================
//==============================================================================
- (Box2)viewport
{
	return [self.renderer viewport];
}


//========== convertPointToViewport: ==========================================
//==============================================================================
- (Point2)convertPointToViewport:(Point2)point_view
{
	return [self.renderer convertPointToViewport:point_view];
}


//========== modelPointForPoint: ==============================================
//==============================================================================
- (Point3)modelPointForPoint:(Point2)viewPoint
{
	return [self.renderer modelPointForPoint:viewPoint];
}


//========== modelPointForPoint:depthReferencePoint: ==========================
//==============================================================================
- (Point3)modelPointForPoint:(Point2)viewPoint depthReferencePoint:(Point3)depthPoint
{
	return [self.renderer modelPointForPoint:viewPoint depthReferencePoint:depthPoint];
}


//========== getDirectivesUnderRect:amongDirectives:fastDraw: =================
//==============================================================================
- (NSArray *)getDirectivesUnderRect:(Box2)rect_view amongDirectives:(NSArray *)directives fastDraw:(BOOL)fastDraw
{
	return [self.renderer getDirectivesUnderRect:rect_view amongDirectives:directives fastDraw:fastDraw];
}


//========== allowsEditing ====================================================
//==============================================================================
- (BOOL)allowsEditing
{
	return [self.renderer allowsEditing];
}


//========== LDrawDirective ===================================================
//==============================================================================
- (LDrawDirective *)LDrawDirective
{
	return [self.renderer LDrawDirective];
}


//========== camera ===========================================================
//==============================================================================
- (LDrawCamera *)camera
{
	return [self.renderer camera];
}


//========== gridSpacing ======================================================
//==============================================================================
- (float)gridSpacing
{
	return [self.renderer gridSpacing];
}


//========== setSelectionMarquee: =============================================
//==============================================================================
- (void)setSelectionMarquee:(Box2)box
{
	[self.renderer setSelectionMarquee:box];
}


//========== publishMouseOverPoint: ===========================================
//==============================================================================
- (void)publishMouseOverPoint:(Point2)viewPoint
{
	[self.renderer publishMouseOverPoint:viewPoint];
}


//========== preferredPartTransform ===========================================
//==============================================================================
- (TransformComponents)preferredPartTransform
{
	return [self.renderer preferredPartTransform];
}


//========== wantsToSelectDirective:byExtendingSelection: =====================
//==============================================================================
- (void)wantsToSelectDirective:(LDrawDirective *)directive byExtendingSelection:(BOOL)shouldExtend
{
	[self.renderer wantsToSelectDirective:directive byExtendingSelection:shouldExtend];
}


//========== wantsToSelectDirectives:selectionMode: ===========================
//==============================================================================
- (void)wantsToSelectDirectives:(NSArray *)directives selectionMode:(LDrawSelectionMode)selectionMode
{
	[self.renderer wantsToSelectDirectives:directives selectionMode:selectionMode];
}


//========== willBeginDraggingHandle: =========================================
//==============================================================================
- (void)willBeginDraggingHandle:(LDrawDragHandle *)handle
{
	[self.renderer willBeginDraggingHandle:handle];
}


//========== dragHandleDidMove: ===============================================
//==============================================================================
- (void)dragHandleDidMove:(LDrawDragHandle *)handle
{
	[self.renderer dragHandleDidMove:handle];
}


//========== noteNeedsDisplay =================================================
//==============================================================================
- (void)noteNeedsDisplay
{
	[self.renderer noteNeedsDisplay];
}

@end
