//==============================================================================
//
//  File:       LDrawMinifigureAssembler.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only minifigure layout extracted from
//              MinifigureDialogController.
//
//  Info:       The host supplies copied catalog parts and colors in slot order.
//              Spec takes inclusion flags and joint angles from the generator
//              via KVC. This assembler positions those parts and returns an
//              LDrawMPDModel. Torso arm-socket angle comes from MLCadIni.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawMPDModel;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigureSpec
///
/// @abstract   Foundation-only minifigure layout extracted from
///             MinifigureDialogController.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigureSpec : NSObject

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

@property (nonatomic) BOOL hasHat;
@property (nonatomic) BOOL hasNeckAccessory;
@property (nonatomic) BOOL hasHips;
@property (nonatomic) BOOL hasRightArm;
@property (nonatomic) BOOL hasRightHand;
@property (nonatomic) BOOL hasRightHandAccessory;
@property (nonatomic) BOOL hasRightLeg;
@property (nonatomic) BOOL hasRightLegAccessory;
@property (nonatomic) BOOL hasLeftArm;
@property (nonatomic) BOOL hasLeftHand;
@property (nonatomic) BOOL hasLeftHandAccessory;
@property (nonatomic) BOOL hasLeftLeg;
@property (nonatomic) BOOL hasLeftLegAccessory;

@property (nonatomic) float headElevation;
@property (nonatomic) float angleOfHat;
@property (nonatomic) float angleOfHead;
@property (nonatomic) float angleOfNeck;
@property (nonatomic) float angleOfRightArm;
@property (nonatomic) float angleOfRightHand;
@property (nonatomic) float angleOfRightHandAccessory;
@property (nonatomic) float angleOfRightLeg;
@property (nonatomic) float angleOfRightLegAccessory;
@property (nonatomic) float angleOfLeftArm;
@property (nonatomic) float angleOfLeftHand;
@property (nonatomic) float angleOfLeftHandAccessory;
@property (nonatomic) float angleOfLeftLeg;
@property (nonatomic) float angleOfLeftLegAccessory;

/// Has-flags, elevation, and joint-angle property names (KVC).
+ (NSArray<NSString *> *)inclusionAndAngleKeys;

/// Copies has-flags, elevation, and joint angles from the generator (KVC).
- (void)takeInclusionAndAnglesFromTarget:(id)target;

/// Copies the first object of each slot's selected-objects array. The host
/// still reads NSArrayControllers.
+ (NSArray *)copiedPartsFromSlotSelections:(NSArray *)selections;

/// Assigns copied catalog parts in partSlotKeys order. Extra entries ignored.
- (void)setPartsInSlotOrder:(NSArray *)parts;

/// Applies colors onto those parts in the same order. The host still owns
/// color wells.
- (void)applyColorsInSlotOrder:(NSArray *)colors;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigureAssembler
///
/// @abstract   Foundation-only minifigure layout extracted from
///             MinifigureDialogController.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigureAssembler : NSObject

/// Mutates spec.part transforms in place and returns a new MPD model that
/// owns those parts. Head and torso are always included (historical).
+ (LDrawMPDModel *)assembleSpec:(LDrawMinifigureSpec *)spec;

/// Default generator model name. The host still localizes.
+ (NSString *)untitledMinifigureLocalizationKey;

/// Generator GL preview starts at this zoom percentage.
+ (CGFloat)generatorPreviewDefaultZoomPercentage;

/// Autosave name for the generator preview viewport.
+ (NSString *)generatorPreviewAutosaveName;

@end

NS_ASSUME_NONNULL_END
