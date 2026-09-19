//==============================================================================
//
//  File:       LDrawMinifigureDefaults.h
//  Package:    LDrawFeatures
//
//  Purpose:    Saved minifigure generator settings (NSUserDefaults packing).
//
//  Info:       Maps MINIFIGURE_* user-default keys (has-flags, angles,
//              elevation, color codes, part names). Pose fields come from
//              LDrawMinifigurePose. Color codes and part names are addressed
//              in prefs slot order. The host still maps wells and array
//              controllers, and synchronizes defaults.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawFeatures/LDrawMinifigurePose.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigureDefaults
///
/// @abstract   Saved generator settings: pose plus color codes and part names.
///             Preference keys are unchanged.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigureDefaults : LDrawMinifigurePose

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
+ (instancetype)fromUserDefaults:(NSUserDefaults *)defaults;

/// Writes current values out of preferences. The host still synchronizes.
- (void)writeToUserDefaults:(NSUserDefaults *)defaults;

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
