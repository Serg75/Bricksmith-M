//==============================================================================
//
//  File:       LPubModelScale.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubModelScaleBranch
///
/// @abstract   Which picture a MODEL_SCALE sizes.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubModelScaleBranch) {
	/// The parts list's icons.
	LPubModelScaleBranchPli			= 0,
	/// The step's assembly picture.
	LPubModelScaleBranchAssembly	= 1,
	/// The bill of materials' icons. Parsed and written back only.
	LPubModelScaleBranchBom			= 2
};


//------------------------------------------------------------------------------
///
/// @class      LPubModelScale
///
/// @abstract   LPub MODEL_SCALE command: how big a picture is drawn.
///
/// @discussion The value multiplies life size, where one LDU covers 1/64 inch.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubModelScale : LPubCommand

@property (nonatomic, readonly) LPubModelScaleBranch	branch;
@property (nonatomic, readonly) LPubMetaScope			scope;
/// A multiplier on life size. LPub3D's default is 1.0.
@property (nonatomic, readonly) double					scale;

/// Inches one LDU covers at a scale of 1.0.
+ (double) inchesPerLDU;

@end

NS_ASSUME_NONNULL_END
