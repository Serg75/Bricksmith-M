//==============================================================================
//
// File:		LDrawHostChrome.m
//
// Purpose:		Bricksmith window, dialog, and layout policy.
//
// Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import "LDrawHostChrome.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawFeatures/LDrawHostKeys.h>


@interface LDrawHostChrome ()
/// Document file-contents split collapsible minimum (offset 0 only).
+ (CGFloat)documentFileContentsSplitMinCoordinate;
/// Min width of the detail column before it collapses (constrainMax).
+ (CGFloat)documentDetailColumnMinWidth;
@end

@implementation LDrawHostChrome

//========== shouldShowDonationDialogForBundleVersion: =========================
//
// Purpose:		Returns whether we should nag the user to pay us this time.
//
//==============================================================================
+ (BOOL)shouldShowDonationDialogForBundleVersion:(NSInteger)bundleVersion
{
	NSUserDefaults *userDefaults             = [NSUserDefaults standardUserDefaults];
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
+ (void)recordDonationDialogShownForBundleVersion:(NSInteger)bundleVersion
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
+ (void)setDonationSuppressedThisVersion:(BOOL)suppressed
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


//---------- chooseLSynthExecutableTitleKey --------------------------[static]--
//
// Purpose:		LSynth preferences open-panel localization keys. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)chooseLSynthExecutableTitleKey
{
	return @"Choose an LSynth executable";
}


//---------- lsynthExecutableChooserMessageKey ----------------------[static]--
//
// Purpose:		Localization key for the LSynth executable open panel. The host
//				still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)lsynthExecutableChooserMessageKey
{
	return @"lsynthExecutableChooserMessage";
}


//---------- chooseLSynthConfigurationTitleKey ----------------------[static]--
//
// Purpose:		Localization key for the LSynth config-file chooser title. The
//				host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)chooseLSynthConfigurationTitleKey
{
	return @"Choose an LSynth configuration file";
}


//---------- lsynthConfigurationChooserMessageKey -------------------[static]--
//
// Purpose:		Localization key for the LSynth config-file chooser message.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)lsynthConfigurationChooserMessageKey
{
	return @"lsynthConfigurationChooserMessage";
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


//---------- colorFallbackForPreferenceKey: --------------------------[static]--
//
// Purpose:		Styles-tab / factory default when a color key is missing. The
//				host maps each case to NSColor (Teal uses getTealSyntaxColorRGBA:).
//
//------------------------------------------------------------------------------
+ (LDrawHostColorFallback)colorFallbackForPreferenceKey:(NSString *)key
{
	if ([key isEqualToString:LDRAW_VIEWER_BACKGROUND_COLOR_KEY])
		return LDrawHostColorFallbackControlBackground;
	if (	[key isEqualToString:SYNTAX_COLOR_MODELS_KEY]
		||	[key isEqualToString:SYNTAX_COLOR_STEPS_KEY]
		||	[key isEqualToString:SYNTAX_COLOR_PARTS_KEY] )
		return LDrawHostColorFallbackText;
	if ([key isEqualToString:SYNTAX_COLOR_PRIMITIVES_KEY])
		return LDrawHostColorFallbackSystemBlue;
	if ([key isEqualToString:SYNTAX_COLOR_COLORS_KEY])
		return LDrawHostColorFallbackTeal;
	if ([key isEqualToString:SYNTAX_COLOR_COMMENTS_KEY])
		return LDrawHostColorFallbackSystemGreen;
	if ([key isEqualToString:SYNTAX_COLOR_UNKNOWN_KEY])
		return LDrawHostColorFallbackSystemGray;
	if (	[key isEqualToString:SYNTAX_COLOR_REMOVE_GROUP_KEY]
		||	[key isEqualToString:LSYNTH_SELECTION_COLOR_KEY] )
		return LDrawHostColorFallbackSystemRed;
	return LDrawHostColorFallbackText;
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
	return @[@(1), @(3)];
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
