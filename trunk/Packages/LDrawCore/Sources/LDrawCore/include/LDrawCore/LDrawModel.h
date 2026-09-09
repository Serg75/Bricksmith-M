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

	BOOL					 anyGroupSuppressed;	// YES if any subdirective is currently dropped or ghosted
													// by an !LPUB REMOVE GROUP, so a clearing pass is owed
	BOOL					 derivedWithGroupHiding;// values of +hidesRemovedGroupsInStepDisplay and
	BOOL					 derivedWithGhosting;	// +showsRemovedGroupsAsGhosts the last derivation ran
													// under, so a preference change re-derives

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

// Host-injected: whether step display honors `0 !LPUB REMOVE GROUP`. All mode
// always does. Defaults to YES; the host pushes the user's preference at
// launch and whenever it changes. This class does not read
// standardUserDefaults.
+ (BOOL) hidesRemovedGroupsInStepDisplay;
+ (void) setHidesRemovedGroupsInStepDisplay:(BOOL)flag;

// Host-injected: whether All mode draws a removed group translucent instead of
// dropping it. Step display is unaffected. Defaults to NO.
+ (BOOL) showsRemovedGroupsAsGhosts;
+ (void) setShowsRemovedGroupsAsGhosts:(BOOL)flag;

// Host-injected: whether step display draws everything built before the step on
// display as translucent ghosts, leaving only that step solid. All mode is
// unaffected. Defaults to NO.
+ (BOOL) ghostsPreviousSteps;
+ (void) setGhostsPreviousSteps:(BOOL)flag;

// Host-injected: how solid a ghost draws, for both kinds -- removed groups and
// previous steps. Clamped to LDRAW_MIN_GHOST_ALPHA...LDRAW_MAX_GHOST_ALPHA.
// Defaults to LDRAW_DEFAULT_GHOST_ALPHA.
+ (float) ghostAlpha;
+ (void) setGhostAlpha:(float)alpha;

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
/// Brings the derived MLCAD group visibility up to date if it has gone stale.
/// Every drawing, bounds and picking entry point calls this first; it is
/// exposed so that a test can drive the derivation without a part library.
- (void) updateGroupSuppressionIfNeeded;
/// Whether the steps built before the one on display draw as translucent
/// ghosts. Exposed so a test can check the rule without a renderer.
- (BOOL) drawsPreviousStepsAsGhosts;
- (NSUInteger) numberElements;
- (void) optimizeStructure;
- (NSUInteger) parseHeaderFromLines:(NSArray *)lines beginningAtIndex:(NSUInteger)index;
- (BOOL) line:(NSString *)line isValidForHeader:(NSString *)headerKey info:(NSString * _Nullable * _Nullable)infoPtr;

@end

NS_ASSUME_NONNULL_END
