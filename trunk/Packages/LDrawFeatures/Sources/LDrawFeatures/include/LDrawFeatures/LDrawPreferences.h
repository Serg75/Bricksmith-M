//==============================================================================
//
//  File:       LDrawPreferences.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only schema and accessor wrapper around
//              NSUserDefaults for Bricksmith preference keys.
//
//  Info:       Seeds factory defaults that do not require AppKit (NSColor). The
//              macOS preferences pane still registers archived-color defaults
//              for its own UI. Donation-nag policy (suppress this version vs
//              new version) lives here so any host can ask without the AppKit
//              dialog.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Fallback when user-defaults color unarchiving fails for the Styles tab /
/// factory defaults. The host maps each case to NSColor (Teal uses
/// -getTealSyntaxColorRGBA:).
typedef NS_ENUM(NSInteger, LDrawPreferenceColorFallback) {
	LDrawPreferenceColorFallbackControlBackground = 0,
	LDrawPreferenceColorFallbackText              = 1,
	LDrawPreferenceColorFallbackSystemBlue        = 2,
	LDrawPreferenceColorFallbackTeal              = 3,
	LDrawPreferenceColorFallbackSystemGreen       = 4,
	LDrawPreferenceColorFallbackSystemGray        = 5,
	LDrawPreferenceColorFallbackSystemRed         = 6
};


//------------------------------------------------------------------------------
///
/// @class      LDrawPreferences
///
/// @abstract   Foundation-only schema and accessor wrapper around
///             NSUserDefaults for Bricksmith preference keys.
///
//------------------------------------------------------------------------------
@interface LDrawPreferences : NSObject

+ (instancetype)sharedPreferences;

// Seeds the standard user defaults with Bricksmith's factory settings
// (numeric, boolean, and string keys). Safe to call repeatedly.
- (void)ensureDefaults;

/// Returns whether we should nag the user to pay us this time. If last
/// displayed version != bundleVersion, always YES and clears suppress-this-
/// version. If the user requested suppression for this version, NO.
/// The host still reads CFBundleGetVersionNumber and shows the dialog.
- (BOOL)shouldShowDonationDialogForBundleVersion:(NSInteger)bundleVersion;

/// Record for next time: store the version we just showed.
- (void)recordDonationDialogShownForBundleVersion:(NSInteger)bundleVersion;

- (void)setDonationSuppressedThisVersion:(BOOL)suppressed;

/// Preferences pane open-panel localization keys. The host still localizes.
+ (NSString *)chooseLDrawFolderTitleKey;
+ (NSString *)ldrawFolderChooserMessageKey;
+ (NSString *)choosePromptKey;

/// Viewport-arranger button tooltips. The host still localizes.
+ (NSString *)viewportArrangerCloseButtonTooltipKey;
+ (NSString *)viewportArrangerSplitButtonTooltipKey;

/// Document autosaving delay: 30 s in DEBUG, 300 s otherwise.
+ (NSTimeInterval)documentAutosavingDelay;

/// Preference keys for a named LDrawView autosave slot.
+ (NSString *)viewingAnglePreferenceKeyForAutosaveName:(NSString *)autosaveName;
+ (NSString *)projectionModePreferenceKeyForAutosaveName:(NSString *)autosaveName;

/// Styles-tab / factory default when a color key is missing. Nil key → Text.
+ (LDrawPreferenceColorFallback)colorFallbackForPreferenceKey:(nullable NSString *)key;

/// Device teal used for SYNTAX_COLOR_COLORS_KEY (0, 128, 128)/255.
+ (void)getTealSyntaxColorRGBA:(float *)outRGBA;

/// Color-panel sort-descriptors preference key.
+ (NSString *)colorTableSortDescriptorsPreferenceKey;

/// Viewport-arranger layout preference key for an autosave name.
+ (NSString *)viewsPerColumnPreferenceKeyForAutosaveName:(NSString *)autosaveName;

/// Default layout: 1 main viewer; 3 detail views to the right.
+ (NSArray<NSNumber *> *)defaultViewsPerColumnCounts;

/// Split-view autosave name for one column within a viewport arranger.
+ (NSString *)columnAutosaveNameForBase:(NSString *)baseAutosaveName
							columnIndex:(NSUInteger)columnIndex;

/// Document 3D viewport autosave name at index (fileGraphicView_N).
+ (NSString *)documentViewportAutosaveNameAtIndex:(NSUInteger)index;

/// Persist TOOL_PALETTE_HIDDEN.
+ (void)setToolPaletteHidden:(BOOL)hidden;

/// Part-browser panel split: don’t allow the view portions to shrink too much.
+ (CGFloat)partBrowserSplitMinCoordinate;

/// File-contents pane: return the collapsible min when offset is 0; else proposedMin.
+ (CGFloat)constrainedSplitMinCoordinate:(CGFloat)proposedMin
						 forFileContents:(BOOL)isFileContentsSplit
						   subviewOffset:(NSInteger)offset;

/// Document toolbar identifier.
+ (NSString *)documentToolbarIdentifier;

/// Document layout split-view / arranger autosave names.
+ (NSString *)fileContentsSplitAutosaveName;
+ (NSString *)documentViewportArrangerAutosaveName;
+ (NSString *)partBrowserPanelSplitAutosaveName;

/// Viewport-arranger max coordinate so the detail column can collapse.
+ (CGFloat)constrainedSplitMaxCoordinate:(CGFloat)proposedMax
					 forViewportArranger:(BOOL)isViewportArranger
						   subviewOffset:(NSInteger)offset
						   containerMaxX:(CGFloat)containerMaxX;


/// Fresh viewport layout: main ≈ 2/3, detail ≈ 1/3 of total width.
+ (CGFloat)defaultMainViewportColumnWidthFraction;
+ (CGFloat)defaultDetailViewportColumnWidthFraction;

/// New pane size = (total − dividerThickness) / 2.
+ (CGFloat)evenSplitPaneSizeFromTotal:(CGFloat)total
					 dividerThickness:(CGFloat)dividerThickness;

/// Removing index 0 → inherit index 1; otherwise inherit index − 1.
+ (NSUInteger)inheritIndexWhenRemovingAt:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
