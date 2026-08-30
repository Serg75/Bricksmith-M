//==============================================================================
//
//  File:       LDrawGrid.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only grid spacing and rotation policy.
//
//  Info:       Reads GRID_SPACING_* keys from NSUserDefaults (seeded by
//              LDrawPreferences). Rotation step sizes are the compile-time
//              GRID_ROTATION_* constants below. Hosts use this instead of
//              duplicating the fine/medium/coarse switches.
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
typedef enum gridSpacingMode
{
	gridModeFine	= 0,
	gridModeMedium	= 1,
	gridModeCoarse	= 2

} gridSpacingModeT;

// Are movements aligned to the overall model or the individual selected part.
typedef enum gridOrientationMode
{
	gridOrientationModel = 0,
	gridOrientationPart  = 1

} gridOrientationModeT;

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

+ (float)spacingForMode:(gridSpacingModeT)mode;
+ (float)rotationDegreesForMode:(gridSpacingModeT)mode kind:(LDrawGridRotationKind)kind;
+ (float)rotationDegreesForMode:(gridSpacingModeT)mode
						   kind:(LDrawGridRotationKind)kind
					  extraFine:(BOOL)extraFine;

/// Grid menu checkmarks in validateMenuItem:. Tags are gridFineMenuTag, etc.
+ (BOOL)menuItemShouldBeSelectedForGridModeTag:(NSInteger)tag
								   currentMode:(gridSpacingModeT)currentMode;

/// Grid-orientation menu checkmarks. Tags are coordModelMenuTag, etc.
+ (BOOL)menuItemShouldBeSelectedForGridOrientationTag:(NSInteger)tag
								   currentOrientation:(gridOrientationModeT)currentOrientation;

/// Inverse of the checkmark helpers for menu actions.
+ (BOOL)gridSpacingMode:(gridSpacingModeT *)outMode forMenuTag:(NSInteger)tag;
+ (BOOL)gridOrientationMode:(gridOrientationModeT *)outMode forMenuTag:(NSInteger)tag;

@end

NS_ASSUME_NONNULL_END
