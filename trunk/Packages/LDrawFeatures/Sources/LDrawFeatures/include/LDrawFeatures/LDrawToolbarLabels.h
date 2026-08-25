//==============================================================================
//
//  File:       LDrawToolbarLabels.h
//  Package:    LDrawFeatures
//
//  Purpose:    Localization keys for document-toolbar item labels. Identifiers
//              are not always the same as the strings-file key (e.g.
//              PartBrowser → ShowPartBrowser). The host still localizes and
//              builds NSToolbarItem.
//
//  Created by Sergey Slobodenyuk on 2026-08-27.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Segmented zoom control: 0 = out, 1 = spacer, 2 = in.
typedef NS_ENUM(NSInteger, LDrawZoomToolbarSegmentAction) {
	LDrawZoomToolbarSegmentNone = 0,
	LDrawZoomToolbarSegmentOut  = 1,
	LDrawZoomToolbarSegmentIn   = 2
};

//------------------------------------------------------------------------------
///
/// @class      LDrawToolbarLabels
///
/// @abstract   Localization keys for document-toolbar item labels. Identifiers
///             are not always the same as the strings-file key (e.g.
///             PartBrowser → ShowPartBrowser). The host still localizes and
///             builds NSToolbarItem.
///
//------------------------------------------------------------------------------
@interface LDrawToolbarLabels : NSObject

/// Localization key for an item's label / palette label. Nil if unknown.
+ (nullable NSString *)labelKeyForItemIdentifier:(NSString *)itemIdentifier;

/// Nudge toolbar items need a non-empty selection.
+ (BOOL)toolbarRequiresNonEmptySelectionForIdentifier:(nullable NSString *)itemIdentifier;

/// Rotate toolbar items need a selected part.
+ (BOOL)toolbarRequiresSelectedPartForIdentifier:(nullable NSString *)itemIdentifier;

+ (LDrawZoomToolbarSegmentAction)zoomActionForSegmentIndex:(NSUInteger)index;

/// All Bricksmith document-toolbar item identifiers (plus Cocoa space IDs).
+ (NSArray<NSString *> *)documentToolbarAllowedItemIdentifiers;

/// Default document-toolbar set for a new user.
+ (NSArray<NSString *> *)documentToolbarDefaultItemIdentifiers;

@end

NS_ASSUME_NONNULL_END
