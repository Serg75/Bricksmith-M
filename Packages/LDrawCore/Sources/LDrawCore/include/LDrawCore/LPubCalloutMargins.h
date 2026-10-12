//==============================================================================
//
//  File:       LPubCalloutMargins.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubCalloutPart
///
/// @abstract   The things in a callout that a line can style.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubCalloutPart) {
	/// The box as a whole.
	LPubCalloutPartBox				= 0,
	/// A step's picture in the box.
	LPubCalloutPartAssembly			= 1,
	/// A step's parts list in the box.
	LPubCalloutPartPartsList		= 2,
	/// A step's number in the box.
	LPubCalloutPartStepNumber		= 3,
	/// How many times the box is built.
	LPubCalloutPartInstanceCount	= 4
};


//------------------------------------------------------------------------------
///
/// @class      LPubCalloutMargins
///
/// @abstract   The room kept around a callout or something in it:
///             0 !LPUB CALLOUT [ASSEM | PLI | STEP_NUMBER | INSTANCE_COUNT]
///                 MARGINS [GLOBAL|LOCAL] <x> <y>
///
/// @discussion The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutMargins : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;
@property (nonatomic, readonly) LPubCalloutPart	part;

/// In inches. LPub3D's default is 0.05 each way.
@property (nonatomic, readonly) Size2			margins;

/// Reads the keyword of a thing inside a callout: ASSEM, PLI, STEP_NUMBER or
/// INSTANCE_COUNT. NO for any other word.
+ (BOOL) getPart:(LPubCalloutPart *)outPart fromToken:(NSString *)token;

/// The keyword of a thing inside a callout, or nil for the box itself.
+ (nullable NSString *) nameForPart:(LPubCalloutPart)part;

@end

NS_ASSUME_NONNULL_END
