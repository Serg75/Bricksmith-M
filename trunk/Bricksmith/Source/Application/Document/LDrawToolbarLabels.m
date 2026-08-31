//==============================================================================
//
// File:		LDrawToolbarLabels.m
//
// Purpose:		Localization keys for document-toolbar item labels.
//
// Created by Sergey Slobodenyuk on 2026-08-27.
//
//==============================================================================

#import "LDrawToolbarLabels.h"

@implementation LDrawToolbarLabels

//---------- labelKeyForItemIdentifier: ------------------------------[static]--
//
// Purpose:		Map toolbar item identifiers to strings-file keys. Rotation
//				identifiers match both the localized string key and image name.
//				Some other identifiers differ (PartBrowser → ShowPartBrowser,
//				"Snap To Grid" → SnapToGrid, "Specify Zoom" → Zoom).
//
//------------------------------------------------------------------------------
+ (NSString *)labelKeyForItemIdentifier:(NSString *)itemIdentifier
{
	if (itemIdentifier == nil)
		return nil;

	// Identifiers that equal their localization key.
	static NSSet *identityKeys = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		identityKeys = [NSSet setWithObjects:
			@"GridSpacing",
			@"GridOrientation",
			@"NudgeX",
			@"NudgeY",
			@"NudgeZ",
			@"Rotate+X",
			@"Rotate-X",
			@"Rotate+Y",
			@"Rotate-Y",
			@"Rotate+Z",
			@"Rotate-Z",
			@"ShowColors",
			@"ShowInspector",
			nil];
	});

	if ([identityKeys containsObject:itemIdentifier])
		return itemIdentifier;

	if ([itemIdentifier isEqualToString:@"PartBrowser"])
		return @"ShowPartBrowser";
	if ([itemIdentifier isEqualToString:@"Snap To Grid"])
		return @"SnapToGrid";
	if ([itemIdentifier isEqualToString:@"Zoom In"])
		return @"ZoomIn";
	if ([itemIdentifier isEqualToString:@"Zoom Out"])
		return @"ZoomOut";
	if ([itemIdentifier isEqualToString:@"Specify Zoom"])
		return @"Zoom";

	return nil;
}


//---------- toolbarRequiresNonEmptySelectionForIdentifier: ----------[static]--
//
// Purpose:		Nudge toolbar items need a non-empty selection.
//
//------------------------------------------------------------------------------
+ (BOOL)toolbarRequiresNonEmptySelectionForIdentifier:(NSString *)itemIdentifier
{
	return (		[itemIdentifier isEqualToString:@"NudgeX"]
				||	[itemIdentifier isEqualToString:@"NudgeY"]
				||	[itemIdentifier isEqualToString:@"NudgeZ"] );
}


//---------- toolbarRequiresSelectedPartForIdentifier: ---------------[static]--
//
// Purpose:		Rotate toolbar items need a selected part.
//
//------------------------------------------------------------------------------
+ (BOOL)toolbarRequiresSelectedPartForIdentifier:(NSString *)itemIdentifier
{
	return (		[itemIdentifier isEqualToString:@"Rotate+X"]
				||	[itemIdentifier isEqualToString:@"Rotate-X"]
				||	[itemIdentifier isEqualToString:@"Rotate+Y"]
				||	[itemIdentifier isEqualToString:@"Rotate-Y"]
				||	[itemIdentifier isEqualToString:@"Rotate+Z"]
				||	[itemIdentifier isEqualToString:@"Rotate-Z"] );
}


//---------- zoomActionForSegmentIndex: ------------------------------[static]--
//
// Purpose:		For nicer modern looks, the zoom control is a segmented cell
//				which acts like push buttons. Center cell is a spacer.
//
//------------------------------------------------------------------------------
+ (LDrawZoomToolbarSegmentAction)zoomActionForSegmentIndex:(NSUInteger)index
{
	switch (index)
	{
		case 0:  return LDrawZoomToolbarSegmentOut;
		case 2:  return LDrawZoomToolbarSegmentIn;
		default: return LDrawZoomToolbarSegmentNone;
	}
}


//---------- documentToolbarAllowedItemIdentifiers -------------------[static]--
//
// Purpose:		Returns the list of all possible toolbar buttons.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)documentToolbarAllowedItemIdentifiers
{
	return @[
			@"GridSpacing",
			@"GridOrientation",
			@"NudgeX",
			@"NudgeY",
			@"NudgeZ",
			@"PartBrowser",
			@"Rotate-X",
			@"Rotate-Y",
			@"Rotate-Z",
			@"Rotate+X",
			@"Rotate+Y",
			@"Rotate+Z",
			@"ShowColors",
			@"ShowInspector",
			@"Snap To Grid",
			@"Specify Zoom",
			@"NSToolbarSpaceItem",
			@"NSToolbarFlexibleSpaceItem"];
}


//---------- documentToolbarDefaultItemIdentifiers -------------------[static]--
//
// Purpose:		Returns the list of toolbar buttons in the default set. These
//				will appear when the application is opened for the first time.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)documentToolbarDefaultItemIdentifiers
{
	return @[
			@"Specify Zoom",
			@"NSToolbarSpaceItem",
			@"Snap To Grid",
			@"GridSpacing",
			@"NSToolbarSpaceItem",
			@"Rotate+X",
			@"Rotate-X",
			@"Rotate+Y",
			@"Rotate-Y",
			@"Rotate+Z",
			@"Rotate-Z",
			@"NSToolbarFlexibleSpaceItem",
			@"ShowInspector",
			@"PartBrowser"];
}

@end
