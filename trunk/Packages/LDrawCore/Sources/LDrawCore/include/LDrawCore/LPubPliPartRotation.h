//==============================================================================
//
//  File:       LPubPliPartRotation.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-13.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubPliPartRotationType
///
/// @abstract   How a PART_ROTATION combines with the parts list camera.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPliPartRotationType) {
	/// No type on the line. LPub3D applies no rotation at all then.
	LPubPliPartRotationTypeNone		= 0,
	/// The rotation is the whole view: the camera angles are not applied,
	/// unless CAMERA_ANGLES names a custom viewpoint.
	LPubPliPartRotationTypeAbsolute	= 1,
	/// The part is rotated, then seen through the camera angles.
	LPubPliPartRotationTypeRelative	= 2,
	/// Same as REL for a parts list icon.
	LPubPliPartRotationTypeAdditive	= 3
};


//------------------------------------------------------------------------------
///
/// @class      LPubPliPartRotation
///
/// @abstract   A rotation LPub3D applies to every icon in the parts list:
///             0 !LPUB PLI PART_ROTATION [GLOBAL|LOCAL] <x> <y> <z> [ABS|REL|ADD]
///
/// @discussion The angles and the matrix are the same as an LDraw ROTSTEP.
///             The rotation is applied to the part before the camera looks
///             at it. The line is written back token for token,
///             single-spaced.
///
//------------------------------------------------------------------------------
@interface LPubPliPartRotation : LPubCommand

@property (nonatomic, readonly) LPubMetaScope			scope;

/// Degrees about X, Y and Z.
@property (nonatomic, readonly) Tuple3					angles;

@property (nonatomic, readonly) LPubPliPartRotationType	type;

/// The rotation as a Bricksmith row-vector matrix, so a point times this is
/// the rotated point. Identity for type None.
@property (nonatomic, readonly) Matrix4					rotationMatrix;

@end

NS_ASSUME_NONNULL_END
