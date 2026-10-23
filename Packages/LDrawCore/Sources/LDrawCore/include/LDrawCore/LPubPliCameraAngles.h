//==============================================================================
//
//  File:       LPubPliCameraAngles.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-13.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubCameraAnglesBranch
///
/// @abstract   Which picture a CAMERA_ANGLES line turns.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubCameraAnglesBranch) {
	/// The parts list's icons.
	LPubCameraAnglesBranchPli		= 0,
	/// The step's assembly picture.
	LPubCameraAnglesBranchAssembly	= 1
};


//------------------------------------------------------------------------------
///
/// @class      LPubPliCameraAngles
///
/// @abstract   The angle LPub3D draws the parts list icons or the step's
///             assembly from:
///             0 !LPUB (PLI | ASSEM) CAMERA_ANGLES [GLOBAL|LOCAL]
///                 <latitude> <longitude>
///
/// @discussion A named view can stand in for the numbers: FRONT, BACK, TOP,
///             BOTTOM, LEFT, RIGHT, HOME, LAT_LON. HOME and LAT_LON may carry
///             two numbers of their own, which win. VIEW_ANGLE is an older
///             name for the same line.
///
///             Latitude tilts the camera up over the model, longitude turns
///             it around the vertical axis. The line is written back token
///             for token, single-spaced.
///
//------------------------------------------------------------------------------
@interface LPubPliCameraAngles : LPubCommand

@property (nonatomic, readonly) LPubCameraAnglesBranch branch;
@property (nonatomic, readonly) LPubMetaScope scope;

/// Degrees, resolved from the numbers or the named view.
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;

/// YES for a HOME or LAT_LON view with numbers of its own. LPub3D keeps these
/// angles even under an ABS PART_ROTATION, which otherwise replaces them.
@property (nonatomic, readonly, getter=isCustomViewpoint) BOOL customViewpoint;

/// LPub3D's default parts list angles, used when a document gives none:
/// latitude 23, longitude -45.
+ (double) defaultLatitude;
+ (double) defaultLongitude;

/// The angles LPub3D gives a named view: FRONT, BACK, TOP, BOTTOM, LEFT,
/// RIGHT, HOME, or LAT_LON for the branch's default. NO for another name.
+ (BOOL) getLatitude:(double *)latitude
		   longitude:(double *)longitude
		 ofNamedView:(NSString *)name
			  branch:(LPubCameraAnglesBranch)branch
	NS_SWIFT_NAME(getLatitude(_:longitude:ofNamedView:branch:));

@end

NS_ASSUME_NONNULL_END
