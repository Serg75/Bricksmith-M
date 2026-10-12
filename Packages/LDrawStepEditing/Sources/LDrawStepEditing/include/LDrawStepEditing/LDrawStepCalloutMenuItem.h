//==============================================================================
//
//  File:       LDrawStepCalloutMenuItem.h
//  Package:    LDrawStepEditing
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawModel;
@class LDrawStepCalloutBox;
@class LDrawStepCalloutEdit;
@class LDrawStepPartListEntry;
@class LDrawStepPartListPresentation;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutMenuItem
///
/// @abstract   One thing a host's menu offers for a point of the overlay.
///
/// @discussion The host builds its own menu from these, with its own titles.
///             Each item carries its edit, worked out when the menu is asked
///             for, so choosing it only has to apply the edit.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutMenuItem : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// What a menu offers at a point of the view. On a callout's box: a divider
/// before the step that is there, or its removal, the other way for the steps
/// to run, and the removal of the callout. On a submodel's row of the parts
/// list: calling the submodel out. Empty for anything else. `model` is the
/// model on display.
+ (NSArray<LDrawStepCalloutMenuItem *> *) itemsAtPoint:(Point2)point
										  presentation:(nullable LDrawStepPartListPresentation *)presentation
												 model:(nullable LDrawModel *)model
	NS_SWIFT_NAME(items(at:presentation:model:));

/// The same for a point that is on a callout's box. `isOnPage` says whether
/// the box was laid out on LPub3D's page. Off it a box shows no steps, so
/// there is no way for them to run.
+ (NSArray<LDrawStepCalloutMenuItem *> *) itemsForBox:(LDrawStepCalloutBox *)box
											  atPoint:(Point2)point
											   onPage:(BOOL)isOnPage
	NS_SWIFT_NAME(items(for:at:onPage:));

/// The same for a row of the parts list. Empty unless the row is a submodel
/// that can be called out.
+ (NSArray<LDrawStepCalloutMenuItem *> *) itemsForEntry:(LDrawStepPartListEntry *)entry
												inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(items(for:inModel:));

/// YES for the line between two groups of items. It has no title and no edit.
@property (nonatomic, readonly) BOOL isSeparator;

/// The key of the item's title. The host localizes it.
@property (nonatomic, readonly, copy, nullable) NSString *titleKey;

/// The step the title names, counted from 1, or 0 when it names none.
@property (nonatomic, readonly) NSInteger stepNumber;

/// The change that choosing the item makes.
@property (nonatomic, readonly, nullable) LDrawStepCalloutEdit *edit;

/// The item's title, from the text the host has for its key. For an item that
/// names a step, the text is a format that takes the step number as a long.
- (NSString *) titleFromLocalizedText:(NSString *)text NS_SWIFT_NAME(title(fromLocalizedText:));

@end

NS_ASSUME_NONNULL_END
