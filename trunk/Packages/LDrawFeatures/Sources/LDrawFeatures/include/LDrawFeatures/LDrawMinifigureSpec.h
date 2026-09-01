//==============================================================================
//
//  File:       LDrawMinifigureSpec.h
//  Package:    LDrawFeatures
//
//  Purpose:    Catalog parts for one minifigure layout, plus the shared pose.
//              The assembler positions these parts; persistence lives on
//              LDrawMinifigureDefaults.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawFeatures/LDrawMinifigurePose.h>

@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigureSpec
///
/// @abstract   Catalog parts for one minifigure, plus inclusion flags and
///             joint angles from LDrawMinifigurePose. The host still owns the
///             generator dialog and color wells.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigureSpec : LDrawMinifigurePose

@property (nonatomic, copy)           NSString  *modelName;

@property (nonatomic, strong, nullable) LDrawPart *hat;
@property (nonatomic, strong, nullable) LDrawPart *head;
@property (nonatomic, strong, nullable) LDrawPart *neck;
@property (nonatomic, strong, nullable) LDrawPart *torso;
@property (nonatomic, strong, nullable) LDrawPart *leftArm;
@property (nonatomic, strong, nullable) LDrawPart *leftHand;
@property (nonatomic, strong, nullable) LDrawPart *leftHandAccessory;
@property (nonatomic, strong, nullable) LDrawPart *rightArm;
@property (nonatomic, strong, nullable) LDrawPart *rightHand;
@property (nonatomic, strong, nullable) LDrawPart *rightHandAccessory;
@property (nonatomic, strong, nullable) LDrawPart *hips;
@property (nonatomic, strong, nullable) LDrawPart *leftLeg;
@property (nonatomic, strong, nullable) LDrawPart *leftLegAccessory;
@property (nonatomic, strong, nullable) LDrawPart *rightLeg;
@property (nonatomic, strong, nullable) LDrawPart *rightLegAccessory;

/// Copies the first object of each slot's selected-objects array. The host
/// still reads NSArrayControllers.
+ (NSArray *)copiedPartsFromSlotSelections:(NSArray *)selections;

/// Assigns copied catalog parts in partSlotKeys order. Extra entries ignored.
- (void)setPartsInSlotOrder:(NSArray *)parts;

/// Applies colors onto those parts in the same order. The host still owns
/// color wells.
- (void)applyColorsInSlotOrder:(NSArray *)colors;

@end

NS_ASSUME_NONNULL_END
