//==============================================================================
//
//  File:       LDrawLine.h
//  Package:    LDrawCore
//
//  Purpose:    Line primitive command.
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
/// @class      LDrawLine
///
/// @abstract   Line primitive command.
///
//------------------------------------------------------------------------------
@interface LDrawLine : LDrawDrawableElement
{
	Point3		vertex1;
	Point3		vertex2;

	NSArray		*dragHandles;
}

//Directives
- (NSString *) write;

//Accessors
- (Point3) vertex1;
- (Point3) vertex2;
- (void) setVertex1:(Point3)newVertex;
- (void) setVertex2:(Point3)newVertex;

@end

NS_ASSUME_NONNULL_END
