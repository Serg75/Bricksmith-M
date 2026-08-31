//==============================================================================
//
//  File:       LDrawRendererInternal.h
//  Package:    LDrawRenderCore
//
//  Purpose:    Private ivars and cross-file helpers for LDrawRenderer.
//
//  Info:       Not part of the public module API. Imported only by
//              LDrawRenderer.m and its category implementation files.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#ifndef LDrawRendererInternal_h
#define LDrawRendererInternal_h

#import <LDrawRenderCore/LDrawRenderer.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawRenderer ()
{
	id<LDrawCameraScroller>	_Nullable scroller;
	id						_Nullable target;
	BOOL					allowsEditing;

	// Drawing Environment
	LDrawColor				*color;					// default color to draw parts if none is specified

	// Event Tracking
	float					gridSpacing;

	BOOL					isStartingDrag;			// this is the first event in a drag
	Point3                  initialDragLocation;	// pan-drag anchor in model space
}

- (Matrix4)getInverseMatrix;
- (float)getDepthUnderPoint:(Point2)point_view;
- (Point2)convertPointToViewport:(Point2)point_view;
- (Point2)convertPointFromViewport:(Point2)viewportPoint;
- (Point3)modelPointForPoint:(Point2)viewPoint;
- (Point3)modelPointForPoint:(Point2)viewPoint depthReferencePoint:(Point3)depthPoint;
- (void)getModelAxesForViewX:(Vector3 * _Nullable)outModelX Y:(Vector3 * _Nullable)outModelY Z:(Vector3 * _Nullable)outModelZ;

@end

NS_ASSUME_NONNULL_END

#endif /* LDrawRendererInternal_h */
