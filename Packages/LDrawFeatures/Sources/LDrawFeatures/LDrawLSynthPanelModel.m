//==============================================================================
//
//  File:       LDrawLSynthPanelModel.m
//  Package:    LDrawFeatures
//
//  Purpose:    LSynth menu specs, inspector popup packing, and bundled config
//              path. Parse and lookup stay on LSynthConfiguration.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <LDrawCore/LDrawKeys.h>
#import <LDrawFeatures/LDrawLSynthPanelModel.h>
#import <LDrawFeatures/LSynthConfiguration.h>


@implementation LDrawLSynthPanelModel

//---------- configPathInBundle: -------------------------------------[static]--
//
// Purpose:		Bundled lsynth.mpd. The host still decides whether to use this
//				or a user-chosen path from preferences.
//
//------------------------------------------------------------------------------
+ (NSString *)configPathInBundle:(NSBundle *)bundle
{
	return [bundle pathForResource:@"lsynth" ofType:@"mpd"];
}


//========== typeLabelForClass: ================================================
//
// Purpose:		Show the label type.
//
//==============================================================================
+ (NSString *)typeLabelForClass:(LDrawLSynthClass)classType
{
	// Update the type title according to our class of synthesized part
	if (classType == LDrawLSynthClassPart) return @"Part Type:";
	if (classType == LDrawLSynthClassHose) return @"Hose Type:";
	if (classType == LDrawLSynthClassBand) return @"Band Type:";
	return nil;
}


//---------- selectionControlEnablementForMode: ---------------------[static]--
//
// Purpose:		Which inspector controls (color vs transparency) should be
//				enabled for the current LSynth selection-tint mode.
//
//------------------------------------------------------------------------------
+ (LSynthSelectionControlEnablement)selectionControlEnablementForMode:(LDrawLSynthSelectionMode)mode
{
	// Enable the correct bits of the selection section
	LSynthSelectionControlEnablement enablement = { NO, NO };
	if (mode == LDrawLSynthSelectionTransparent)
	{
		enablement.transparencyEnabled = YES;
		enablement.colorWellEnabled    = NO;
	}
	else if (mode == LDrawLSynthSelectionColored)
	{
		enablement.transparencyEnabled = NO;
		enablement.colorWellEnabled    = YES;
	}
	else if (mode == LDrawLSynthSelectionTransparentColored)
	{
		enablement.transparencyEnabled = YES;
		enablement.colorWellEnabled    = YES;
	}
	return enablement;
}


//========== applicationMenuSpecs ==============================================
//
// Purpose:		Populate the LSynth Model menus dynamically from configuration
//				file.
//
//==============================================================================
+ (NSArray *)applicationMenuSpecs
{
	// A declarative encoding of our LSynth menus
	// We process this, along with associated LSynthConfiguration data to generate our Model LSynth menu
	return @[
		@{
			@"tag": @(LDrawLSynthPartMenuTag),
			@"kind": @(LDrawLSynthMenuParts),
			@"entry_key": @"title",
			@"action": NSStringFromSelector(@selector(insertSynthesizableDirective:)),
			@"shouldFilter": @YES,
		},
		@{
			@"tag": @(LDrawLSynthHoseMenuTag),
			@"kind": @(LDrawLSynthMenuHoseTypes),
			@"entry_key": @"title",
			@"action": NSStringFromSelector(@selector(insertSynthesizableDirective:)),
			@"shouldFilter": @YES,
		},
		@{
			@"tag": @(LDrawLSynthHoseConstraintMenuTag),
			@"kind": @(LDrawLSynthMenuHoseConstraints),
			@"entry_key": @"description",
			@"action": NSStringFromSelector(@selector(insertLSynthConstraint:)),
			@"shouldFilter": @NO,
		},
		@{
			@"tag": @(LDrawLSynthBandMenuTag),
			@"kind": @(LDrawLSynthMenuBandTypes),
			@"entry_key": @"title",
			@"action": NSStringFromSelector(@selector(insertSynthesizableDirective:)),
			@"shouldFilter": @YES,
		},
		@{
			@"tag": @(LDrawLSynthBandConstraintMenuTag),
			@"kind": @(LDrawLSynthMenuBandConstraints),
			@"entry_key": @"description",
			@"action": NSStringFromSelector(@selector(insertLSynthConstraint:)),
			@"shouldFilter": @NO,
		},
	];
}


//---------- insideOutsideInsertMenuSpecs ---------------------------[static]--
//
// Purpose:		Menu specs for inserting LSynth INSIDE / OUTSIDE commands.
//
//------------------------------------------------------------------------------
+ (NSArray *)insideOutsideInsertMenuSpecs
{
	NSString *action = NSStringFromSelector(@selector(insertINSIDEOUTSIDELSynthDirective:));
	return @[
		@{
			@"title": @"Insert INSIDE",
			@"action": action,
			@"tag": @(LDrawLSynthInsertInsideTag),
		},
		@{
			@"title": @"Insert OUTSIDE",
			@"action": action,
			@"tag": @(LDrawLSynthInsertOutsideTag),
		},
		@{
			@"title": @"Insert CROSS",
			@"action": action,
			@"tag": @(LDrawLSynthInsertCrossTag),
		},
	];
}


//---------- shouldIncludeMenuEntry: --------------------------------[static]--
//
// Purpose:		Return YES if the LSynth menu should show this type, honoring
//				the basic-parts-list preference.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldIncludeMenuEntry:(NSDictionary *)entry
				  shouldFilter:(BOOL)shouldFilter
				  visibleTypes:(NSArray *)visibleTypes
			  showOnlyOfficial:(BOOL)showOnlyOfficial
{
	// The MLCad.ini file contains a list of semi-official LSynth types.  The
	// lsynth.mpd file also contains legacy entries for backward compatibility.
	// We want to filter out non-semi-official synth parts unless the user has
	// turned this off in the preferences.  Parts get filtered, constraints
	// don't.
	if (shouldFilter
	   && [visibleTypes indexOfObject:[entry valueForKey:@"LSYNTH_TYPE"]] != NSNotFound)
	{
		return YES;
	}
	if (shouldFilter == NO) return YES;
	if (showOnlyOfficial == NO) return YES;
	return NO;
}


//---------- indexOfConstraintNamed:inConstraints: ------------------[static]--
//
// Purpose:		Find a constraint by part name in the given list. Returns
//				NSNotFound when missing.
//
//------------------------------------------------------------------------------
+ (NSUInteger)indexOfConstraintNamed:(NSString *)name inConstraints:(NSArray *)constraints
{
	NSString *target = [name uppercaseString];
	NSUInteger index = 0;
	for (NSDictionary *constraint in constraints)
	{
		if ([[[constraint valueForKey:@"partName"] uppercaseString] isEqualToString:target])
		{
			return index;
		}
		index++;
	}
	return NSNotFound;
}


//---------- typePopupTitlesFromTypes: ------------------------------[static]--
//
// Purpose:		Build inspector popup titles from LSynth type dictionaries.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)typePopupTitlesFromTypes:(NSArray *)types
{
	return [types valueForKey:@"title"];
}


//---------- constraintPopupDescriptionsFromConstraints: ------------[static]--
//
// Purpose:		Build inspector popup titles from constraint dictionaries.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)constraintPopupDescriptionsFromConstraints:(NSArray *)constraints
{
	return [constraints valueForKey:@"description"];
}


//---------- indexOfTypeNamed:inTypes: ------------------------------[static]--
//
// Purpose:		Find an LSynth type by name. Returns NSNotFound when missing.
//
//------------------------------------------------------------------------------
+ (NSUInteger)indexOfTypeNamed:(NSString *)typeName inTypes:(NSArray *)types
{
	NSUInteger index = 0;
	for (NSDictionary *type in types)
	{
		if ([[type valueForKey:@"LSYNTH_TYPE"] isEqualToString:typeName])
		{
			return index;
		}
		index++;
	}
	return NSNotFound;
}


//---------- typeNameAtIndex:inTypes: -------------------------------[static]--
//
// Purpose:		Return the type name at index, or nil if out of range.
//
//------------------------------------------------------------------------------
+ (NSString *)typeNameAtIndex:(NSInteger)index inTypes:(NSArray *)types
{
	return [[self entryAtIndex:index inEntries:types] valueForKey:@"LSYNTH_TYPE"];
}


//---------- entryAtIndex:inEntries: --------------------------------[static]--
//
// Purpose:		Return the dictionary at index, or nil if out of range.
//
//------------------------------------------------------------------------------
+ (NSDictionary *)entryAtIndex:(NSInteger)index inEntries:(NSArray *)entries
{
	if (index < 0 || index >= (NSInteger)[entries count]) return nil;
	return [entries objectAtIndex:(NSUInteger)index];
}


//---------- selectedTypeForClass:atIndex:inTypes: ------------------[static]--
//
// Purpose:		Return the type dictionary at index for classTag. Hose/band
//				classes do not consult the type popup.
//
//------------------------------------------------------------------------------
+ (NSDictionary *)selectedTypeForClass:(LDrawLSynthClass)classTag
							   atIndex:(NSInteger)index
							   inTypes:(NSArray *)types
{
	if (classTag != LDrawLSynthClassPart) return nil;
	return [self entryAtIndex:index inEntries:types];
}


//---------- approximatePieceCountFormatKey --------------------------[static]--
//
// Purpose:		Inspector: “(approx. %i pieces)” format. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)approximatePieceCountFormatKey
{
	return @"(approx. %i pieces)";
}

@end
