//==============================================================================
//
//  File:       LDrawLSynthRuntime.m
//  Package:    LDrawFeatures
//
//  Purpose:    NSUserDefaults-backed LSynth runtime: lsynthcp path, custom
//              config file, and selection-tint settings.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <LDrawFeatures/LDrawLSynthRuntime.h>

#import <LDrawCore/LDrawKeys.h>


@implementation LDrawLSynthRuntime
{
	NSUserDefaults	*userDefaults;
	NSString		*bundledExecutablePath;
}


//---------- bundledExecutablePathInBundle: --------------------------[static]--
//
// Purpose:		Bundled lsynthcp. The host still prefers a user-chosen path
//				from LSYNTH_EXECUTABLE_PATH_KEY when that string is non-empty.
//
//------------------------------------------------------------------------------
+ (NSString *)bundledExecutablePathInBundle:(NSBundle *)bundle
{
	return [bundle pathForAuxiliaryExecutable:@"lsynthcp"];
}


//========== initWithUserDefaults:bundledExecutablePath: =======================
//
// Purpose:		Read LSynth process and selection prefs from the given store.
//				bundledPath is the fallback when the executable preference is
//				empty or whitespace.
//
//==============================================================================
- (instancetype)initWithUserDefaults:(NSUserDefaults *)defaultsIn
			 bundledExecutablePath:(NSString *)bundledPath
{
	self = [super init];
	if (self)
	{
		self->userDefaults           = defaultsIn;
		self->bundledExecutablePath  = [bundledPath copy];
	}
	return self;
}


#pragma mark -
#pragma mark LDrawLSynthRuntimeSource
#pragma mark -

//========== executablePath ====================================================
//
// Purpose:		User-chosen lsynthcp if the preference is non-empty (and not
//				whitespace-only); otherwise the bundled auxiliary executable.
//
//==============================================================================
- (NSString *)executablePath
{
	NSString *custom = [self->userDefaults stringForKey:LSYNTH_EXECUTABLE_PATH_KEY];
	NSString *trimmed = [custom stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] == 0)
		return self->bundledExecutablePath;
	return custom;
}


//========== configurationPath =================================================
//
// Purpose:		Custom lsynth.mpd for LSynth’s `-c` flag. Empty means bundled
//				defaults inside the tool.
//
//==============================================================================
- (NSString *)configurationPath
{
	return [self->userDefaults stringForKey:LSYNTH_CONFIGURATION_PATH_KEY];
}


//========== saveSynthesizedParts ==============================================
//
// Purpose:		Whether write should emit SYNTHESIZED BEGIN/END blocks.
//
//==============================================================================
- (BOOL)saveSynthesizedParts
{
	return [self->userDefaults boolForKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];
}


//========== selectionMode =====================================================
//
// Purpose:		Selection-tint mode. Numeric values match the preferences
//				popup tags (LSYNTH_SELECTION_MODE_KEY).
//
//==============================================================================
- (LDrawLSynthSelectionMode)selectionMode
{
	return (LDrawLSynthSelectionMode)[self->userDefaults integerForKey:LSYNTH_SELECTION_MODE_KEY];
}


//========== selectionTransparencyPercent ======================================
//
// Purpose:		0–100 percentage stored under LSYNTH_SELECTION_TRANSPARENCY_KEY.
//
//==============================================================================
- (NSInteger)selectionTransparencyPercent
{
	return [self->userDefaults integerForKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
}


//========== getSelectionColorRGBA: ============================================
//
// Purpose:		Four floats from LSYNTH_SELECTION_COLOR_RGBA_KEY. Falls back to
//				opaque red if the key is missing or malformed.
//
//==============================================================================
- (void)getSelectionColorRGBA:(float *)outRGBA
{
	if (outRGBA == NULL)
		return;

	outRGBA[0] = 1.0f;
	outRGBA[1] = 0.0f;
	outRGBA[2] = 0.0f;
	outRGBA[3] = 1.0f;

	NSArray *components = [self->userDefaults arrayForKey:LSYNTH_SELECTION_COLOR_RGBA_KEY];
	if ([components count] >= 3)
	{
		outRGBA[0] = [[components objectAtIndex:0] floatValue];
		outRGBA[1] = [[components objectAtIndex:1] floatValue];
		outRGBA[2] = [[components objectAtIndex:2] floatValue];
		if ([components count] >= 4)
			outRGBA[3] = [[components objectAtIndex:3] floatValue];
	}
}

@end
