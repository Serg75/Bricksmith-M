//==============================================================================
//
//  File:       LPubResolution.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubResolutionUnit
///
/// @abstract   What a RESOLUTION value counts dots per.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubResolutionUnit) {
	LPubResolutionUnitDotsPerInch		= 0,
	LPubResolutionUnitDotsPerCentimeter	= 1
};


//------------------------------------------------------------------------------
///
/// @class      LPubResolution
///
/// @abstract   LPub RESOLUTION command: how many dots the printed page has per
///             inch or per centimeter.
///
/// @discussion A page size in the file is in the unit named here.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubResolution : LPubCommand

@property (nonatomic, readonly) LPubMetaScope		scope;
/// Dots per `unit`. LPub3D's default is 150 DPI.
@property (nonatomic, readonly) double				dotsPerUnit;
@property (nonatomic, readonly) LPubResolutionUnit	unit;

/// Inches in one `unit`: 1 for DPI, 1/2.54 for DPCM.
@property (nonatomic, readonly) double		inchesPerUnit;

@end

NS_ASSUME_NONNULL_END
