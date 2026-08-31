//==============================================================================
//
//  File:       LDrawDrawableElement.h
//  Package:    LDrawCore
//
//  Purpose:    Abstract superclass for all LDraw elements that can actually be
//              drawn (polygons and parts).
//
//  Created by Allen Smith on 4/20/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/LDrawMovableDirective.h>

typedef struct
{
	float position[3];
	float normal[3];
	float color[4];

} VBOVertexData;

//------------------------------------------------------------------------------
///
/// @class      LDrawDrawableElement
///
/// @abstract   Abstract superclass for all LDraw elements that can actually be
///             drawn (polygons and parts).
///
//------------------------------------------------------------------------------
@interface LDrawDrawableElement : LDrawDirective <LDrawColorable, NSCoding, LDrawMovableDirective>
{
	LDrawColor  *color;
	BOOL        hidden;		//YES if we don't draw this.
}

// Accessors
- (Box3) projectedBoundingBoxWithModelView:(Matrix4)modelView
								projection:(Matrix4)projection
									  view:(Box2)viewport;
- (BOOL) isHidden;
- (Point3) position;

- (void) setHidden:(BOOL)flag;

// Actions
//- (Vector3) displacementForNudge:(Vector3)nudgeVector;
//- (void) moveBy:(Vector3)moveVector;
- (Point3) position:(Point3)position snappedToGrid:(float)gridSpacing;

@end
