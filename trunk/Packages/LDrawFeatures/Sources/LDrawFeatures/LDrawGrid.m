//==============================================================================
//
//  File:       LDrawGrid.m
//  Package:    LDrawFeatures
//
//  Purpose:    Looks up user-configured grid spacing and the rotation step
//              that matches a grid mode.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawGrid.h>

#import <LDrawCore/LDrawKeys.h>

@implementation LDrawGrid

//---------- gridSpacingForMode: -------------------------------------[static]--
//
// Purpose:		Translates the given grid spacing granularity into an actual 
//				number of LDraw units, according to the user's preferences. 
//
// Notes:		This value represents distances "along the studs"--that is, 
//			    horizontal along the brick. Vertical distances may be adjusted. 
//
//------------------------------------------------------------------------------
+ (float)spacingForMode:(LDrawGridSpacingMode)mode
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

	switch (mode)
	{
		case LDrawGridModeFine:
			return [userDefaults floatForKey:GRID_SPACING_FINE];
		case LDrawGridModeMedium:
			return [userDefaults floatForKey:GRID_SPACING_MEDIUM];
		case LDrawGridModeCoarse:
			return [userDefaults floatForKey:GRID_SPACING_COARSE];
	}
	return 0.0f;
}


//---------- rotationDegreesForMode:kind: ---------------------------[static]--
//
// Purpose:		Return the rotation step in degrees for the grid mode and kind
//				(snap vs extra-fine), without the extraFine divisor.
//
//------------------------------------------------------------------------------
+ (float)rotationDegreesForMode:(LDrawGridSpacingMode)mode kind:(LDrawGridRotationKind)kind
{
	return [self rotationDegreesForMode:mode kind:kind extraFine:NO];
}


//---------- rotationDegreesForMode:kind:extraFine: -----------------[static]--
//
// Purpose:		Return the rotation step in degrees for the grid mode.
//
//				extraFine divides the step by 5, matching the Shift-modified
//				fine rotation in the original ToolPalette.
//
//------------------------------------------------------------------------------
+ (float)rotationDegreesForMode:(LDrawGridSpacingMode)mode
						   kind:(LDrawGridRotationKind)kind
					  extraFine:(BOOL)extraFine
{
	float degrees = 0.0f;

	switch (mode)
	{
		case LDrawGridModeFine:
			degrees = (kind == LDrawGridRotationSnap)
						? GRID_ROTATION_FINE
						: GRID_ROTATION_SUPERFINE;
			break;
		case LDrawGridModeMedium:
			degrees = GRID_ROTATION_MEDIUM;
			break;
		case LDrawGridModeCoarse:
			degrees = GRID_ROTATION_COARSE;
			break;
	}

	if (extraFine)
	{
		degrees /= 5.0f;
	}
	return degrees;
}


//---------- menuItemShouldBeSelectedForGridModeTag:currentMode: -----[static]--
//
// Purpose:		The grid menus are always enabled, but this is a fine place to
//				keep track of their state.
//
//------------------------------------------------------------------------------
+ (BOOL)menuItemShouldBeSelectedForGridModeTag:(NSInteger)tag
								   currentMode:(LDrawGridSpacingMode)currentMode
{
	switch (tag)
	{
		case LDrawGridFineMenuTag:
			return currentMode == LDrawGridModeFine;
		case LDrawGridMediumMenuTag:
			return currentMode == LDrawGridModeMedium;
		case LDrawGridCoarseMenuTag:
			return currentMode == LDrawGridModeCoarse;
	}
	return NO;
}


//---------- menuItemShouldBeSelectedForGridOrientationTag:... -------[static]--
//
// Purpose:		Grid-orientation menu checkmarks in validateMenuItem:.
//
//------------------------------------------------------------------------------
+ (BOOL)menuItemShouldBeSelectedForGridOrientationTag:(NSInteger)tag
								   currentOrientation:(LDrawGridOrientationMode)currentOrientation
{
	switch (tag)
	{
		case LDrawCoordModelMenuTag:
			return currentOrientation == LDrawGridOrientationModel;
		case LDrawCoordPartMenuTag:
			return currentOrientation == LDrawGridOrientationPart;
	}
	return NO;
}


//---------- gridSpacingMode:forMenuTag: -----------------------------[static]--
//
// Purpose:		Map grid menu tags to spacing modes for menu actions.
//
//------------------------------------------------------------------------------
+ (BOOL)gridSpacingMode:(LDrawGridSpacingMode *)outMode forMenuTag:(NSInteger)tag
{
	if (outMode == NULL)
		return NO;

	switch (tag)
	{
		case LDrawGridFineMenuTag:
			*outMode = LDrawGridModeFine;
			return YES;
		case LDrawGridMediumMenuTag:
			*outMode = LDrawGridModeMedium;
			return YES;
		case LDrawGridCoarseMenuTag:
			*outMode = LDrawGridModeCoarse;
			return YES;
	}
	return NO;
}


//---------- gridOrientationMode:forMenuTag: -------------------------[static]--
//
// Purpose:		Map orientation menu tags for menu actions.
//
//------------------------------------------------------------------------------
+ (BOOL)gridOrientationMode:(LDrawGridOrientationMode *)outMode forMenuTag:(NSInteger)tag
{
	if (outMode == NULL)
		return NO;

	switch (tag)
	{
		case LDrawCoordModelMenuTag:
			*outMode = LDrawGridOrientationModel;
			return YES;
		case LDrawCoordPartMenuTag:
			*outMode = LDrawGridOrientationPart;
			return YES;
	}
	return NO;
}

@end
