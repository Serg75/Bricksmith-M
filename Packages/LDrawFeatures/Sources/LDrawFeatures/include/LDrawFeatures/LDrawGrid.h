//==============================================================================
//
//  File:       LDrawGrid.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only grid spacing and rotation policy.
//
//  Info:       Reads GRID_SPACING_* keys from a host-provided NSUserDefaults
//              (seeded by LDrawPreferences). Rotation step sizes are the
//              compile-time GRID_ROTATION_* constants below. Hosts use this
//              instead of duplicating the fine/medium/coarse switches.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#define GRID_SPACING_COARSE				@"Grid Spacing: Coarse"
#define GRID_SPACING_FINE				@"Grid Spacing: Fine"
#define GRID_SPACING_MEDIUM				@"Grid Spacing: Medium"

// Number of degrees to rotate in each grid mode.
#define GRID_ROTATION_SUPERFINE			1
#define GRID_ROTATION_FINE				15
#define GRID_ROTATION_MEDIUM			45
#define GRID_ROTATION_COARSE			90

NS_ASSUME_NONNULL_BEGIN

// How much parts move when you nudge them. Numeric values match the
// document-toolbar segmented control tags.
typedef NS_ENUM(NSInteger, LDrawGridSpacingMode)
{
	LDrawGridModeFine	= 0,
	LDrawGridModeMedium	= 1,
	LDrawGridModeCoarse	= 2

};

// Are movements aligned to the overall model or the individual selected part.
typedef NS_ENUM(NSInteger, LDrawGridOrientationMode)
{
	LDrawGridOrientationModel = 0,
	LDrawGridOrientationPart  = 1

};

// Fine-grid rotation differs: axis nudges use 1°, snap-to-grid uses 15°.
typedef NS_ENUM(NSInteger, LDrawGridRotationKind) {
	LDrawGridRotationAxis = 0,
	LDrawGridRotationSnap = 1
};

//------------------------------------------------------------------------------
///
/// @class      LDrawGrid
///
/// @abstract   Foundation-only grid spacing and rotation policy.
///
//------------------------------------------------------------------------------
@interface LDrawGrid : NSObject

+ (float)spacingForMode:(LDrawGridSpacingMode)mode fromUserDefaults:(NSUserDefaults *)userDefaults;
+ (float)rotationDegreesForMode:(LDrawGridSpacingMode)mode kind:(LDrawGridRotationKind)kind;
+ (float)rotationDegreesForMode:(LDrawGridSpacingMode)mode
						   kind:(LDrawGridRotationKind)kind
					  extraFine:(BOOL)extraFine;

/// Grid menu checkmarks in validateMenuItem:. Tags are LDrawGridFineMenuTag, etc.
+ (BOOL)menuItemShouldBeSelectedForGridModeTag:(NSInteger)tag
								   currentMode:(LDrawGridSpacingMode)currentMode;

/// Grid-orientation menu checkmarks. Tags are LDrawCoordModelMenuTag, etc.
+ (BOOL)menuItemShouldBeSelectedForGridOrientationTag:(NSInteger)tag
								   currentOrientation:(LDrawGridOrientationMode)currentOrientation;

/// Inverse of the checkmark helpers for menu actions.
+ (BOOL)gridSpacingMode:(LDrawGridSpacingMode *)outMode forMenuTag:(NSInteger)tag;
+ (BOOL)gridOrientationMode:(LDrawGridOrientationMode *)outMode forMenuTag:(NSInteger)tag;

@end

NS_ASSUME_NONNULL_END
