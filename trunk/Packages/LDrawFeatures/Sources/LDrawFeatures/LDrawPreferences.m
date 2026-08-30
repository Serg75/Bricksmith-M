//==============================================================================
//
//  File:       LDrawPreferences.m
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only preferences accessor used by portable clients.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawPreferences.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/MacLDraw.h>


@interface LDrawPreferences ()
/// Document file-contents split collapsible minimum (offset 0 only).
+ (CGFloat)documentFileContentsSplitMinCoordinate;
/// Min width of the detail column before it collapses (constrainMax).
+ (CGFloat)documentDetailColumnMinWidth;
@end

@implementation LDrawPreferences

//---------- sharedPreferences --------------------------------------[static]--
//
// Purpose:		Return the process-wide preferences accessor.
//
//------------------------------------------------------------------------------
+ (instancetype)sharedPreferences
{
	static LDrawPreferences *shared = nil;
	static dispatch_once_t   onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[LDrawPreferences alloc] init];
	});
	return shared;
}


//---------- ensureDefaults ------------------------------------------[static]--
//
// Purpose:		Verifies that all expected settings exist in preferences. If a 
//				setting is not found, it is restored to its default value.
//
//				This method should be called upon program launch, so that the 
//				rest of the program need not worry about preference 
//				error-checking.
//
//------------------------------------------------------------------------------
- (void)ensureDefaults
{
	NSMutableDictionary *initialDefaults = [NSMutableDictionary dictionary];

	//
	// General
	//
	[initialDefaults setObject:@(MouseDraggingBeginImmediately)	forKey:MOUSE_DRAGGING_BEHAVIOR_KEY];
	[initialDefaults setObject:@(RightButtonContextual)			forKey:RIGHT_BUTTON_BEHAVIOR_KEY];
	[initialDefaults setObject:@(RotateModeTrackball)			forKey:ROTATE_MODE_KEY];
	[initialDefaults setObject:@(MouseWheelScrolls)				forKey:MOUSE_WHEEL_BEHAVIOR_KEY];

	[initialDefaults setObject:@YES								forKey:PART_BROWSER_PANEL_SHOW_AT_LAUNCH];
	[initialDefaults setObject:@YES								forKey:VIEWPORTS_EXPAND_TO_AVAILABLE_SIZE];
	[initialDefaults setObject:@NO								forKey:COLUMNIZE_OUTPUT_KEY]; // appease LDraw traditionalists

	//
	// Grid Spacing
	//
	[initialDefaults setObject:@1.0f							forKey:GRID_SPACING_FINE];
	[initialDefaults setObject:@10.0f							forKey:GRID_SPACING_MEDIUM];
	[initialDefaults setObject:@20.0f							forKey:GRID_SPACING_COARSE];

	//
	// Initial Window State
	//

	// GPU viewer settings -- see -restoreConfiguration in LDrawView.
	// ProjectionModeT lives in LDrawRenderCore; values are 0=perspective, 1=orthographic.
	[initialDefaults setObject:@(ViewOrientation3D)				forKey:[LDRAW_GL_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_0"]];
	[initialDefaults setObject:@0								forKey:[LDRAW_GL_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_0"]];
	[initialDefaults setObject:@(ViewOrientationFront)			forKey:[LDRAW_GL_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_1"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_GL_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_1"]];
	[initialDefaults setObject:@(ViewOrientationLeft)			forKey:[LDRAW_GL_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_2"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_GL_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_2"]];
	[initialDefaults setObject:@(ViewOrientationTop)			forKey:[LDRAW_GL_VIEW_ANGLE stringByAppendingString:@" fileGraphicView_3"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_GL_VIEW_PROJECTION stringByAppendingString:@" fileGraphicView_3"]];

	//
	// Part Browser
	//
	[initialDefaults setObject:@(SearchModeAllCategories)		forKey:PART_BROWSER_SEARCH_MODE];
	[initialDefaults setObject:NSLocalizedString(@"Brick", nil)	forKey:PART_BROWSER_PREVIOUS_CATEGORY];
	[initialDefaults setObject:@0								forKey:PART_BROWSER_PREVIOUS_SELECTED_ROW];
	[initialDefaults setObject:@[]								forKey:FAVORITE_PARTS_KEY];

	//
	// Tool Palette
	//
	[initialDefaults setObject:@NO								forKey:TOOL_PALETTE_HIDDEN];

	//
	// LSynth Palette
	//
	[initialDefaults setObject:@""								forKey:LSYNTH_EXECUTABLE_PATH_KEY];
	[initialDefaults setObject:@""								forKey:LSYNTH_CONFIGURATION_PATH_KEY];
	[initialDefaults setObject:@20								forKey:LSYNTH_SELECTION_TRANSPARENCY_KEY];
	[initialDefaults setObject:@0								forKey:LSYNTH_SELECTION_MODE_KEY];
	[initialDefaults setObject:@[@1.0f, @0.0f, @0.0f, @1.0f]	forKey:LSYNTH_SELECTION_COLOR_RGBA_KEY];
	[initialDefaults setObject:@YES								forKey:LSYNTH_SAVE_SYNTHESIZED_PARTS_KEY];
	[initialDefaults setObject:@YES								forKey:LSYNTH_SHOW_BASIC_PARTS_LIST_KEY];

	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HAT];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HEAD];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_NECK];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_TORSO];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_ARM_RIGHT];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_ARM_LEFT];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HAND_RIGHT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HAND_LEFT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_HIPS];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_LEG_RIGHT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@YES								forKey:MINIFIGURE_HAS_LEG_LEFT];
	[initialDefaults setObject:@NO								forKey:MINIFIGURE_HAS_LEG_LEFT_ACCESSORY];

	[initialDefaults setObject:@"4485.dat"						forKey:MINIFIGURE_PARTNAME_HAT];
	[initialDefaults setObject:@"3626bp01.dat"					forKey:MINIFIGURE_PARTNAME_HEAD];
	[initialDefaults setObject:@"3838.dat"						forKey:MINIFIGURE_PARTNAME_NECK];
	[initialDefaults setObject:@"973p1b.dat"					forKey:MINIFIGURE_PARTNAME_TORSO];
	[initialDefaults setObject:@"982.dat"						forKey:MINIFIGURE_PARTNAME_ARM_RIGHT];
	[initialDefaults setObject:@"981.dat"						forKey:MINIFIGURE_PARTNAME_ARM_LEFT];
	[initialDefaults setObject:@"983.dat"						forKey:MINIFIGURE_PARTNAME_HAND_RIGHT];
	[initialDefaults setObject:@"3837.dat"						forKey:MINIFIGURE_PARTNAME_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@"983.dat"						forKey:MINIFIGURE_PARTNAME_HAND_LEFT];
	[initialDefaults setObject:@"4006.dat"						forKey:MINIFIGURE_PARTNAME_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@"970.dat"						forKey:MINIFIGURE_PARTNAME_HIPS];
	[initialDefaults setObject:@"971.dat"						forKey:MINIFIGURE_PARTNAME_LEG_RIGHT];
	[initialDefaults setObject:@"6120.dat"						forKey:MINIFIGURE_PARTNAME_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@"972.dat"						forKey:MINIFIGURE_PARTNAME_LEG_LEFT];
	[initialDefaults setObject:@"6120.dat"						forKey:MINIFIGURE_PARTNAME_LEG_LEFT_ACCESSORY];

	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HEAD];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_NECK];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_TORSO];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_ARM_RIGHT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_ARM_LEFT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_RIGHT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_LEFT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_HIPS];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_RIGHT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_LEFT];
	[initialDefaults setObject:@0.0f							forKey:MINIFIGURE_ANGLE_LEG_LEFT_ACCESSORY];

	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_HAT];
	[initialDefaults setObject:@(LDrawYellow)					forKey:MINIFIGURE_COLOR_HEAD];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_NECK];
	[initialDefaults setObject:@(LDrawWhite)					forKey:MINIFIGURE_COLOR_TORSO];
	[initialDefaults setObject:@(LDrawWhite)					forKey:MINIFIGURE_COLOR_ARM_RIGHT];
	[initialDefaults setObject:@(LDrawWhite)					forKey:MINIFIGURE_COLOR_ARM_LEFT];
	[initialDefaults setObject:@(LDrawYellow)					forKey:MINIFIGURE_COLOR_HAND_RIGHT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_HAND_RIGHT_ACCESSORY];
	[initialDefaults setObject:@(LDrawYellow)					forKey:MINIFIGURE_COLOR_HAND_LEFT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_HAND_LEFT_ACCESSORY];
	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_HIPS];
	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_LEG_RIGHT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_LEG_RIGHT_ACCESSORY];
	[initialDefaults setObject:@(LDrawBlue)						forKey:MINIFIGURE_COLOR_LEG_LEFT];
	[initialDefaults setObject:@(LDrawBlack)					forKey:MINIFIGURE_COLOR_LEG_LEFT_ACCESSORY];
	[initialDefaults setObject:@4.0f							forKey:MINIFIGURE_HEAD_ELEVATION];

	[initialDefaults setObject:@(ViewOrientationFront)			forKey:[LDRAW_GL_VIEW_ANGLE stringByAppendingString:@" MinifigureGeneratorView"]];
	[initialDefaults setObject:@1								forKey:[LDRAW_GL_VIEW_PROJECTION stringByAppendingString:@" MinifigureGeneratorView"]];

	[[NSUserDefaults standardUserDefaults] registerDefaults:initialDefaults];
}


//========== shouldShowDonationDialogForBundleVersion: =========================
//
// Purpose:		Returns whether we should nag the user to pay us this time.
//
//==============================================================================
- (BOOL)shouldShowDonationDialogForBundleVersion:(NSInteger)bundleVersion
{
	NSUserDefaults *userDefaults            = [NSUserDefaults standardUserDefaults];
	BOOL            userRequestedSuppression = [userDefaults boolForKey:DONATION_SCREEN_SUPPRESS_THIS_VERSION];
	NSInteger       lastNagVersion           = [userDefaults integerForKey:DONATION_SCREEN_LAST_VERSION_DISPLAYED];
	BOOL            showDonationRequest      = YES;

	if (userRequestedSuppression == YES)
	{
		showDonationRequest = NO;
	}

	if (lastNagVersion != bundleVersion)
	{
		showDonationRequest = YES;

		// New version. Make them click the box again.
		[userDefaults setBool:NO forKey:DONATION_SCREEN_SUPPRESS_THIS_VERSION];
	}

	return showDonationRequest;
}


//========== recordDonationDialogShownForBundleVersion: ========================
//
// Purpose:		Record for next time.
//
//==============================================================================
- (void)recordDonationDialogShownForBundleVersion:(NSInteger)bundleVersion
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	[userDefaults setInteger:bundleVersion forKey:DONATION_SCREEN_LAST_VERSION_DISPLAYED];
	[userDefaults synchronize];
}


//========== setDonationSuppressedThisVersion: ================================
//
// Purpose:		Remember whether the user asked not to see the donation dialog
//				again for this bundle version.
//
//==============================================================================
- (void)setDonationSuppressedThisVersion:(BOOL)suppressed
{
	[[NSUserDefaults standardUserDefaults] setBool:suppressed
											forKey:DONATION_SCREEN_SUPPRESS_THIS_VERSION];
}


//---------- chooseLDrawFolderTitleKey -------------------------------[static]--
//
// Purpose:		Preferences pane open-panel localization keys. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)chooseLDrawFolderTitleKey
{
	return @"Choose LDraw Folder";
}


//---------- ldrawFolderChooserMessageKey ---------------------------[static]--
//
// Purpose:		Localization key for the LDraw folder chooser's message. The
//				host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)ldrawFolderChooserMessageKey
{
	return @"LDrawFolderChooserMessage";
}


//---------- choosePromptKey ----------------------------------------[static]--
//
// Purpose:		Localization key for the chooser prompt button (Choose). The
//				host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)choosePromptKey
{
	return @"Choose";
}


//---------- viewportArrangerCloseButtonTooltipKey -------------------[static]--
//
// Purpose:		Viewport-arranger button tooltips. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)viewportArrangerCloseButtonTooltipKey
{
	return @"ViewportArrangerCloseButtonTooltip";
}


//---------- viewportArrangerSplitButtonTooltipKey ------------------[static]--
//
// Purpose:		Localization key for the viewport-arranger split-button tooltip.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)viewportArrangerSplitButtonTooltipKey
{
	return @"ViewportArrangerSplitButtonTooltip";
}


//---------- documentAutosavingDelay ---------------------------------[static]--
//
// Purpose:		Debug build? Save quick — no need to lose work when an assert()
//				fires. Release: 300 s.
//
//------------------------------------------------------------------------------
+ (NSTimeInterval)documentAutosavingDelay
{
#if DEBUG
	return 30;
#else
	return 300;
#endif
}


//---------- viewingAnglePreferenceKeyForAutosaveName: ---------------[static]--
//
// Purpose:		Preference keys for a named LDrawView autosave slot.
//
//------------------------------------------------------------------------------
+ (NSString *)viewingAnglePreferenceKeyForAutosaveName:(NSString *)autosaveName
{
	return [NSString stringWithFormat:@"%@ %@", LDRAW_GL_VIEW_ANGLE, autosaveName];
}


//---------- projectionModePreferenceKeyForAutosaveName: ------------[static]--
//
// Purpose:		User-defaults key for an LDrawView's saved projection mode.
//
//------------------------------------------------------------------------------
+ (NSString *)projectionModePreferenceKeyForAutosaveName:(NSString *)autosaveName
{
	return [NSString stringWithFormat:@"%@ %@", LDRAW_GL_VIEW_PROJECTION, autosaveName];
}


//---------- colorFallbackForPreferenceKey: --------------------------[static]--
//
// Purpose:		Styles-tab / factory default when a color key is missing. The
//				host maps each case to NSColor (Teal uses getTealSyntaxColorRGBA:).
//
//------------------------------------------------------------------------------
+ (LDrawPreferenceColorFallback)colorFallbackForPreferenceKey:(NSString *)key
{
	if ([key isEqualToString:LDRAW_VIEWER_BACKGROUND_COLOR_KEY])
		return LDrawPreferenceColorFallbackControlBackground;
	if (	[key isEqualToString:SYNTAX_COLOR_MODELS_KEY]
		||	[key isEqualToString:SYNTAX_COLOR_STEPS_KEY]
		||	[key isEqualToString:SYNTAX_COLOR_PARTS_KEY] )
		return LDrawPreferenceColorFallbackText;
	if ([key isEqualToString:SYNTAX_COLOR_PRIMITIVES_KEY])
		return LDrawPreferenceColorFallbackSystemBlue;
	if ([key isEqualToString:SYNTAX_COLOR_COLORS_KEY])
		return LDrawPreferenceColorFallbackTeal;
	if ([key isEqualToString:SYNTAX_COLOR_COMMENTS_KEY])
		return LDrawPreferenceColorFallbackSystemGreen;
	if ([key isEqualToString:SYNTAX_COLOR_UNKNOWN_KEY])
		return LDrawPreferenceColorFallbackSystemGray;
	if (	[key isEqualToString:SYNTAX_COLOR_REMOVE_GROUP_KEY]
		||	[key isEqualToString:LSYNTH_SELECTION_COLOR_KEY] )
		return LDrawPreferenceColorFallbackSystemRed;
	return LDrawPreferenceColorFallbackText;
}


//---------- getTealSyntaxColorRGBA: ---------------------------------[static]--
//
// Purpose:		Device teal used for SYNTAX_COLOR_COLORS_KEY. On macOS 10.13 or
//				later this could be systemTealColor, but there is no easy system
//				equivalent currently.
//
//------------------------------------------------------------------------------
+ (void)getTealSyntaxColorRGBA:(float *)outRGBA
{
	if (outRGBA == NULL) return;
	outRGBA[0] = 0.0f / 255.0f;
	outRGBA[1] = 128.0f / 255.0f;
	outRGBA[2] = 128.0f / 255.0f;
	outRGBA[3] = 1.0f;
}


//---------- colorTableSortDescriptorsPreferenceKey ------------------[static]--
//
// Purpose:		Color-panel sort-descriptors preference key.
//
//------------------------------------------------------------------------------
+ (NSString *)colorTableSortDescriptorsPreferenceKey
{
	return @"ColorTable Sort Ordering";
}


//---------- viewsPerColumnPreferenceKeyForAutosaveName: -------------[static]--
//
// Purpose:		Viewport-arranger layout preference key for an autosave name.
//
//------------------------------------------------------------------------------
+ (NSString *)viewsPerColumnPreferenceKeyForAutosaveName:(NSString *)autosaveName
{
	return [NSString stringWithFormat:@"%@_%@", autosaveName, @"ViewsPerColumn"];
}


//---------- defaultViewsPerColumnCounts -----------------------------[static]--
//
// Purpose:		Defaults: 1 main viewer; 3 detail views to the right.
//
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *)defaultViewsPerColumnCounts
{
	return @[
			@(1),
			@(3)];
}


//---------- columnAutosaveNameForBase:columnIndex: ------------------[static]--
//
// Purpose:		Sets the autosave name for each column in the viewport. (This is
//				what saves the size of each row in each column.)
//
//------------------------------------------------------------------------------
+ (NSString *)columnAutosaveNameForBase:(NSString *)baseAutosaveName
							columnIndex:(NSUInteger)columnIndex
{
	return [NSString stringWithFormat:@"%@_Column%ld", baseAutosaveName, (long)columnIndex];
}


//---------- documentViewportAutosaveNameAtIndex: --------------------[static]--
//
// Purpose:		Document 3D viewport autosave name at index.
//
//------------------------------------------------------------------------------
+ (NSString *)documentViewportAutosaveNameAtIndex:(NSUInteger)index
{
	return [NSString stringWithFormat:@"fileGraphicView_%ld", (long)index];
}


//---------- setToolPaletteHidden: -----------------------------------[static]--
//
// Purpose:		Persist TOOL_PALETTE_HIDDEN on show/hide/close.
//
//------------------------------------------------------------------------------
+ (void)setToolPaletteHidden:(BOOL)hidden
{
	[[NSUserDefaults standardUserDefaults] setBool:hidden forKey:TOOL_PALETTE_HIDDEN];
}


//---------- partBrowserSplitMinCoordinate ---------------------------[static]--
//
// Purpose:		Don't allow the view portions to shrink too much.
//
//------------------------------------------------------------------------------
+ (CGFloat)partBrowserSplitMinCoordinate
{
	return 96;
}


//---------- documentFileContentsSplitMinCoordinate ------------------[static]--
//
// Purpose:		Allow the file Contents split view to collapse by giving it a
//				minimum size.
//
//------------------------------------------------------------------------------
+ (CGFloat)documentFileContentsSplitMinCoordinate
{
	return 100;
}


//---------- constrainedSplitMinCoordinate:forFileContents:… ---------[static]--
//
// Purpose:		Only return a collapsible minimum for the file contents pane.
//
//------------------------------------------------------------------------------
+ (CGFloat)constrainedSplitMinCoordinate:(CGFloat)proposedMin
						 forFileContents:(BOOL)isFileContentsSplit
						   subviewOffset:(NSInteger)offset
{
	if (isFileContentsSplit && offset == 0)
		return [self documentFileContentsSplitMinCoordinate];
	return proposedMin;
}


//---------- documentToolbarIdentifier -------------------------------[static]--
//
// Purpose:		Document toolbar identifier.
//
//------------------------------------------------------------------------------
+ (NSString *)documentToolbarIdentifier
{
	return @"LDrawDocumentToolbar";
}


//---------- fileContentsSplitAutosaveName ---------------------------[static]--
//
// Purpose:		Document layout split-view / arranger autosave names.
//
//------------------------------------------------------------------------------
+ (NSString *)fileContentsSplitAutosaveName
{
	return @"fileContentsSplitView";
}


//---------- documentViewportArrangerAutosaveName -------------------[static]--
//
// Purpose:		Autosave name for the document's viewport arranger.
//
//------------------------------------------------------------------------------
+ (NSString *)documentViewportArrangerAutosaveName
{
	return @"HorizontalLDrawSplitview2.1";
}


//---------- partBrowserPanelSplitAutosaveName ----------------------[static]--
//
// Purpose:		Autosave name for the part-browser panel split view.
//
//------------------------------------------------------------------------------
+ (NSString *)partBrowserPanelSplitAutosaveName
{
	return @"PartBrowserPanelSplitView";
}


//---------- documentDetailColumnMinWidth ----------------------------[static]--
//
// Purpose:		Min size of 80 for the detail column.
//
//------------------------------------------------------------------------------
+ (CGFloat)documentDetailColumnMinWidth
{
	return 80;
}


//---------- constrainedSplitMaxCoordinate:forViewportArranger:… -----[static]--
//
// Purpose:		Allow the graphics detail view to collapse by defining a
//				maximum extent for the main graphic view. (It's
//				counter-intuitive!)
//
//------------------------------------------------------------------------------
+ (CGFloat)constrainedSplitMaxCoordinate:(CGFloat)proposedMax
					 forViewportArranger:(BOOL)isViewportArranger
						   subviewOffset:(NSInteger)offset
						   containerMaxX:(CGFloat)containerMaxX
{
	// This method is NEVER called with offset == 1 for the viewport arranger.
	if (isViewportArranger && offset == 0)
		return containerMaxX - [self documentDetailColumnMinWidth];
	return proposedMax;
}


//---------- defaultMainViewportColumnWidthFraction ------------------[static]--
//
// Purpose:		The default initial view should have one viewport occupying
//				2/3rds of the viewing area.
//
//------------------------------------------------------------------------------
+ (CGFloat)defaultMainViewportColumnWidthFraction
{
	return 0.66;
}


//---------- defaultDetailViewportColumnWidthFraction ---------------[static]--
//
// Purpose:		Fresh viewport layout: detail column is about 1/3 of total
//				width.
//
//------------------------------------------------------------------------------
+ (CGFloat)defaultDetailViewportColumnWidthFraction
{
	return 0.34;
}


//---------- evenSplitPaneSizeFromTotal:dividerThickness: ------------[static]--
//
// Purpose:		Split the current viewport frame in two.
//
//------------------------------------------------------------------------------
+ (CGFloat)evenSplitPaneSizeFromTotal:(CGFloat)total
					 dividerThickness:(CGFloat)dividerThickness
{
	return (total - dividerThickness) / 2.0;
}


//---------- inheritIndexWhenRemovingAt: -----------------------------[static]--
//
// Purpose:		If removing the first column/row, the next grows to fill the
//				empty space. Otherwise, the previous grows.
//
//------------------------------------------------------------------------------
+ (NSUInteger)inheritIndexWhenRemovingAt:(NSUInteger)index
{
	if (index == 0)
		return 1;
	return index - 1;
}

@end
