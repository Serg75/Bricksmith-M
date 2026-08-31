//==============================================================================
//
//  File:       LDrawTriangle.h
//  Package:    LDrawCore
//
//  Purpose:    Triangle primitive command.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawDirective.h>

#import <LDrawCore/LDrawDrawableElement.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawTriangle
///
/// @abstract   Triangle primitive command.
///
//------------------------------------------------------------------------------
@interface LDrawTriangle : LDrawDrawableElement <NSCoding>
{
	Point3		vertex1;
	Point3		vertex2;
	Point3		vertex3;

	Vector3		normal;

	NSArray		*dragHandles;
}

//Accessors
- (Point3) vertex1;
- (Point3) vertex2;
- (Point3) vertex3;
-(void) setVertex1:(Point3)newVertex;
-(void) setVertex2:(Point3)newVertex;
-(void) setVertex3:(Point3)newVertex;

//Utilities
- (void) recomputeNormal;

@end

NS_ASSUME_NONNULL_END
