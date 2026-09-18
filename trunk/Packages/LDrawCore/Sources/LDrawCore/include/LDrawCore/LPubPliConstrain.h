//==============================================================================
//
//  File:       LPubPliConstrain.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubPliConstrainMode
///
/// @abstract   How the part icons are packed into the parts list box.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPliConstrainMode) {
	/// Minimize the box's area. LPub3D's default, and ours.
	LPubPliConstrainModeArea	= 0,
	/// Aim for a square box.
	LPubPliConstrainModeSquare	= 1,
	/// Pin the width; the box grows downward.
	LPubPliConstrainModeWidth	= 2,
	/// Pin the height; the box grows rightward.
	LPubPliConstrainModeHeight	= 3,
	/// Pin the column count; the width follows from the widest cell per column.
	LPubPliConstrainModeColumns	= 4
};


//------------------------------------------------------------------------------
///
/// @enum       LPubPliAxis
///
/// @abstract   One of the two dimensions a CONSTRAIN can pin.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPliAxis) {
	LPubPliAxisWidth	= 0,
	LPubPliAxisHeight	= 1
};


/// The mode that pins the given axis.
static inline LPubPliConstrainMode LPubPliConstrainModeForAxis(LPubPliAxis axis)
{
	return (axis == LPubPliAxisWidth) ? LPubPliConstrainModeWidth : LPubPliConstrainModeHeight;
}


//------------------------------------------------------------------------------
///
/// @class      LPubPliConstrain
///
/// @abstract   LPub PLI CONSTRAIN command: how the parts list box is packed.
///
/// @discussion WIDTH and HEIGHT are read and written as inches, even in a DPCM
///             file.
///
//------------------------------------------------------------------------------
@interface LPubPliConstrain : LPubCommand

@property (nonatomic) LPubMetaScope			scope;
@property (nonatomic) LPubPliConstrainMode	mode;
/// Meaningful for the Width and Height modes only.
@property (nonatomic) double					inches;
/// Meaningful for the Columns mode only.
@property (nonatomic) NSInteger				columns;

@end

NS_ASSUME_NONNULL_END
