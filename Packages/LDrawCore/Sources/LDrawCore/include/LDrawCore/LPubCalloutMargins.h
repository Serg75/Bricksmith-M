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
/// @abstract   The things in a callout or a parts list that a line can style.
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
	/// How many times the box is built, or a part is used in a parts list.
	LPubCalloutPartInstanceCount	= 4,
	/// The text on a part in a parts list. Only a PLI line has it.
	LPubCalloutPartAnnotation		= 5
};


//------------------------------------------------------------------------------
///
/// @class      LPubCalloutMargins
///
/// @abstract   The room kept around a callout or something in it, around a
///             parts list or its counts, or inside the page:
///             0 !LPUB CALLOUT [ASSEM | PLI | STEP_NUMBER | INSTANCE_COUNT]
///                 MARGINS [GLOBAL|LOCAL] <x> <y>
///             0 !LPUB PLI [INSTANCE_COUNT] MARGINS [GLOBAL|LOCAL] <x> <y>
///             0 !LPUB PAGE MARGINS [GLOBAL|LOCAL] <x> <y>
///
/// @discussion The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutMargins : LPubCommand <LPubStyleLine>

@property (nonatomic, readonly) LPubStyleBranch	branch;
@property (nonatomic, readonly) LPubMetaScope	scope;

/// The box for a line with no part. In a parts list only the count has one.
@property (nonatomic, readonly) LPubCalloutPart	part;

/// In inches. LPub3D's default is 0.05 each way.
@property (nonatomic, readonly) Size2			margins;

/// Reads the keyword of a thing inside a callout or a parts list: ASSEM, PLI,
/// STEP_NUMBER, INSTANCE_COUNT or ANNOTATE. NO for any other word.
+ (BOOL) getPart:(LPubCalloutPart *)outPart fromToken:(NSString *)token;

/// The keyword of a thing inside a callout or a parts list, or nil for the
/// box itself.
+ (nullable NSString *) nameForPart:(LPubCalloutPart)part;

@end

NS_ASSUME_NONNULL_END
