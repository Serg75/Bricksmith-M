//==============================================================================
//
//  File:       LDrawMLCadGroup.h
//  Package:    LDrawEditing
//
//  Purpose:    MLCAD group names and group-change undo pairs. The host still
//              shows the alert and registers undo.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawStep;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMLCadGroup
///
/// @abstract   MLCAD group query, normalize, and apply.
///
//------------------------------------------------------------------------------
@interface LDrawMLCadGroup : NSObject

/// Gathers all group names declared until the given step.
+ (NSSet<NSString *> *)groupsBeforeStep:(LDrawStep *)step;

+ (BOOL)selectionCanSetGroup:(NSArray *)selection;

/// Unique current group names (nil stored as @""). Returns nil if any
/// selected object cannot take a group.
+ (nullable NSSet<NSString *> *)groupNamesInSelection:(NSArray *)selection;

/// Non-empty names for a combo list. Order is that of the set.
+ (NSArray<NSString *> *)nonEmptyGroupNamesFromSet:(NSSet<NSString *> *)groups;

/// Trim whitespace; nil stays nil.
+ (nullable NSString *)normalizedGroupName:(nullable NSString *)name;

/// LDrawGroupedObject pairs for directives whose group differs from newName.
+ (NSArray *)groupChangesInSelection:(NSArray *)selection
						 toGroupName:(nullable NSString *)newName;

/// Current groups of the same objects, for undo. Must run before applying.
+ (NSArray *)invertedGroupChanges:(NSArray *)directivesAndGroups;

/// Sets each pair's group name. The host still registers undo.
+ (void)applyGroupChanges:(NSArray *)directivesAndGroups;

/// MLCAD group dialog localization keys. The host still localizes and shows
/// the alert.
+ (NSString *)mlcadGroupDialogMessageKey;
+ (NSString *)mlcadGroupDialogInformativeKey;
+ (NSString *)mlcadGroupDialogSetButtonKey;
+ (NSString *)mlcadGroupDialogCancelButtonKey;

@end

NS_ASSUME_NONNULL_END
