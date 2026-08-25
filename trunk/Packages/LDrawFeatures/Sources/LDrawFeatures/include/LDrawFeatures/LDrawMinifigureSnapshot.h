//==============================================================================
//
//  File:       LDrawMinifigureSnapshot.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only persistence for the minifigure generator.
//
//  Info:       Maps MINIFIGURE_* user-default keys (has-flags, angles,
//              elevation, color codes, part names). Color codes and part names
//              are addressed in prefs slot order. The host still maps wells and
//              array controllers, and synchronizes defaults.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigureSnapshot
///
/// @abstract   Foundation-only persistence for the minifigure generator.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigureSnapshot : NSObject

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

@property (nonatomic) NSInteger colorHat;
@property (nonatomic) NSInteger colorHead;
@property (nonatomic) NSInteger colorNeck;
@property (nonatomic) NSInteger colorTorso;
@property (nonatomic) NSInteger colorArmRight;
@property (nonatomic) NSInteger colorHandRight;
@property (nonatomic) NSInteger colorHandRightAccessory;
@property (nonatomic) NSInteger colorArmLeft;
@property (nonatomic) NSInteger colorHandLeft;
@property (nonatomic) NSInteger colorHandLeftAccessory;
@property (nonatomic) NSInteger colorHips;
@property (nonatomic) NSInteger colorLegRight;
@property (nonatomic) NSInteger colorLegRightAccessory;
@property (nonatomic) NSInteger colorLegLeft;
@property (nonatomic) NSInteger colorLegLeftAccessory;

@property (nonatomic, copy, nullable) NSString *partNameHat;
@property (nonatomic, copy, nullable) NSString *partNameHead;
@property (nonatomic, copy, nullable) NSString *partNameNeck;
@property (nonatomic, copy, nullable) NSString *partNameTorso;
@property (nonatomic, copy, nullable) NSString *partNameArmRight;
@property (nonatomic, copy, nullable) NSString *partNameHandRight;
@property (nonatomic, copy, nullable) NSString *partNameHandRightAccessory;
@property (nonatomic, copy, nullable) NSString *partNameArmLeft;
@property (nonatomic, copy, nullable) NSString *partNameHandLeft;
@property (nonatomic, copy, nullable) NSString *partNameHandLeftAccessory;
@property (nonatomic, copy, nullable) NSString *partNameHips;
@property (nonatomic, copy, nullable) NSString *partNameLegRight;
@property (nonatomic, copy, nullable) NSString *partNameLegRightAccessory;
@property (nonatomic, copy, nullable) NSString *partNameLegLeft;
@property (nonatomic, copy, nullable) NSString *partNameLegLeftAccessory;


/// Reads previous values out of preferences.
+ (instancetype)snapshotFromUserDefaults:(NSUserDefaults *)defaults;

/// Writes current values out of preferences. The host still synchronizes.
- (void)writeToUserDefaults:(NSUserDefaults *)defaults;

/// Copies has-flags, elevation, and joint angles onto the generator (KVC).
- (void)applyInclusionAndAnglesToTarget:(id)target;

/// Copies has-flags, elevation, and joint angles from the generator (KVC).
- (void)takeInclusionAndAnglesFromTarget:(id)target;

/// Slot-order color codes from LDrawColor objects. Extra entries ignored.
- (void)setColorCodesFromColors:(NSArray *)colors;

/// First selected object's referenceName in each slot array, e.g. "3001.dat".
/// The host still reads NSArrayControllers.
- (void)setPartNamesFromSlotSelections:(NSArray *)selections;

/// Color codes in prefs slot order. The host still maps them onto wells.
- (NSArray<NSNumber *> *)colorCodesInSlotOrder;

/// Part names in the same slot order. The host still selects in controllers.
- (NSArray *)partNamesInSlotOrder;

/// Parts are identified in user defaults by their reference name, such as
/// "3001.dat". NSNotFound if name is missing or not in the list.
+ (NSUInteger)indexOfPartNamed:(nullable NSString *)name inParts:(NSArray *)parts;

@end

NS_ASSUME_NONNULL_END
