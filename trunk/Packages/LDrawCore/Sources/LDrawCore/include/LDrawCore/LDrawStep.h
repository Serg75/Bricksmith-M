//==============================================================================
//
//  File:       LDrawStep.h
//  Package:    LDrawCore
//
//  Purpose:    Represents a collection of Lego bricks which compose a single
//              step when constructing a model.
//
//  Created by Allen Smith on 2/20/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>

// This notification is sent by steps when step-specific meta-data (e.g. the viewing
// angle changes.  It is only sent when notification is legal to avoid GCD threading
// problems.  If the step changes by a directive being inserted the more generic
// LDrawDirectiveDidChangeNotification is sent out by the base container class.
#define LDrawStepDidChangeNotification				@"LDrawStepDidChangeNotification"

@class LDrawModel;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// Types & Constants
//
////////////////////////////////////////////////////////////////////////////////

typedef NS_ENUM(NSInteger, LDrawStepRotationT)
{
	LDrawStepRotationNone		= 0,	// inherit previous step rotation (or default view)
	LDrawStepRotationRelative	= 1,	// rotate relative to default 3D viewing angle
	LDrawStepRotationAbsolute	= 2,	// rotate relative to (0, 0, 0)
	LDrawStepRotationAdditive	= 3,	// rotate relative to the previous step's rotation
	LDrawStepRotationEnd		= 4		// cancel the effect of the previous rotation

};


//Describes the contents of this step.
typedef NS_ENUM(NSInteger, LDrawStepFlavorT)
{
	LDrawStepAnyDirectives,		//step can hold any type of subdirectives.
	LDrawStepLines,				//step can hold *only* LDrawLines.
	LDrawStepTriangles,			// etc.
	LDrawStepQuadrilaterals,	// etc.
	LDrawStepConditionalLines	// etc.

};


//------------------------------------------------------------------------------
///
/// @class      LDrawStep
///
/// @abstract   Represents a collection of Lego bricks which compose a single
///             step when constructing a model.
///
//------------------------------------------------------------------------------
@interface LDrawStep : LDrawContainer
{
	LDrawStepRotationT	stepRotationType;
	Tuple3				rotationAngle;		// in degrees
	Box3				cachedBounds;		// cached bounds of the step
	//Optimization variables
	LDrawStepFlavorT	stepFlavor; //defaults to LDrawStepAnyDirectives
	LDrawColorT			colorOfAllDirectives;

	//Inherited from the superclasses:
	//NSMutableArray	*containedObjects; //the commands that make up the step.
	//LDrawContainer	*enclosingDirective; //weak link to enclosing model.
}

//Initialization
+ (id) emptyStep;
+ (id) emptyStepWithFlavor:(LDrawStepFlavorT) flavorType;

//Directives
- (NSString *) writeWithStepCommand:(BOOL) flag;

//Accessors
- (nullable LDrawModel *) enclosingModel;
- (Tuple3) rotationAngle;
- (Tuple3) rotationAngleZYX;
- (LDrawStepFlavorT) stepFlavor;
- (LDrawStepRotationT) stepRotationType;

- (void) setModel:(nullable LDrawModel *)enclosingModel;
- (void) setRotationAngle:(Tuple3)newAngle;
- (void) setRotationAngleZYX:(Tuple3)newAngleZYX;
- (void) setStepFlavor:(LDrawStepFlavorT)newFlavor;
- (void) setStepRotationType:(LDrawStepRotationT)newValue;

//Utilities
+ (BOOL) lineIsStepTerminator:(NSString*)line;
+ (BOOL) lineIsRotationStepTerminator:(NSString*)line;
- (BOOL) parseRotationStepFromLine:(NSString *)rotstep;

@end

NS_ASSUME_NONNULL_END
