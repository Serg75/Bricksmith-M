//==============================================================================
//
//  File:       LDrawModel.h
//  Package:    LDrawCore
//
//  Purpose:    Represents a collection of Lego bricks that form a single model.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawCoreRenderer.h>
@class LDrawColorLibrary;
@class LDrawFile;
@class LDrawStep;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawModel
///
/// @abstract   Represents a collection of Lego bricks that form a single model.
///
//------------------------------------------------------------------------------
@interface LDrawModel : LDrawContainer <NSCoding>
{	
	NSString				*modelDescription;
	NSString				*fileName;
	NSString				*author;
	Point3					rotationCenter;

	LDrawColorLibrary		*colorLibrary;			// in-scope !COLOURS local to the model
	BOOL					 stepDisplayActive;		// YES if we are only display steps 1-currentStepDisplayed
	NSUInteger				 currentStepDisplayed;	// display up to and including this step index

	Box3					cachedBounds;			// bounds of the model - only covers steps that are showing

	//steps are stored in the superclass.

	// Drag and Drop
	LDrawStep				*draggingDirectives;

	BOOL					isOptimized;			// Were we ever structure-optimized - used to optimize out 
													// some drawing on library parts.
	LDrawMeshHandle			dl;						// Cached DL if we have one.
	LDrawMeshCleanup_f		dl_dtor;
}

//Initialization
+ (id) model;

//Accessors
- (NSString *) category;
- (LDrawColorLibrary *) colorLibrary;
- (nullable NSArray *) draggingDirectives;
- (nullable LDrawFile *)enclosingFile;
- (NSString *)modelDescription;
- (NSString *)fileName;
- (NSString *)author;
- (NSUInteger) maximumStepIndexForStepDisplay;
- (Tuple3) rotationAngleForStepAtIndex:(NSUInteger)stepNumber;
- (Point3) rotationCenter;
- (BOOL) stepDisplay;
- (NSArray *) steps;
- (nullable LDrawStep *) visibleStep;

- (void) setDraggingDirectives:(nullable NSArray *)directives;
- (void) setModelDescription:(NSString *)newDescription;
- (void) setFileName:(NSString *)newName;
- (void) setAuthor:(NSString *)newAuthor;
- (void) setRotationCenter:(Point3)newPoint;
- (void) setStepDisplay:(BOOL)flag;
- (void) setMaximumStepIndexForStepDisplay:(NSUInteger)stepIndex;

//Actions
- (LDrawStep *) addStep;
- (void) addStep:(LDrawStep *)newStep;
- (void) makeStepVisible:(LDrawStep *)step;

//Utilities
- (NSUInteger) maxStepIndexToOutput;
- (NSUInteger) numberElements;
- (void) optimizeStructure;
- (NSUInteger) parseHeaderFromLines:(NSArray *)lines beginningAtIndex:(NSUInteger)index;
- (BOOL) line:(NSString *)line isValidForHeader:(NSString *)headerKey info:(NSString * _Nullable * _Nullable)infoPtr;

@end

NS_ASSUME_NONNULL_END
