//==============================================================================
//
//  File:       LDrawMinifigurePose.h
//  Package:    LDrawFeatures
//
//  Purpose:    Has-flags, head elevation, and joint angles shared by the
//              generator layout spec and the preferences snapshot. The host
//              still owns the dialog ivars and copies via KVC.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigurePose
///
/// @abstract   Inclusion flags and joint angles for one minifigure. Layout
///             parts live on LDrawMinifigureSpec; persistence lives on
///             LDrawMinifigureDefaults.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigurePose : NSObject

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

/// Copies has-flags, elevation, and joint angles onto the generator (KVC).
- (void)applyInclusionAndAnglesToTarget:(id)target;

@end

NS_ASSUME_NONNULL_END
