//==============================================================================
//
//  File:       LDrawRelatedParts.h
//  Package:    LDrawFeatures
//
//  Purpose:    Related-parts database loaded from related.ldr.
//
//  Info:       The host passes a file path, usually from
//              +databasePathInBundle:. Parse does not look up the app
//              main bundle.
//
//  Created by bsupnik on 2/24/13.
//  Copyright 2013. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawColor;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// Modes to build a submenu for related parts:
/// list_child — list our choices in a sub-menu by child part name.
/// list_role — list our choices in a sub-menu by their role.
/// merged — list only one item with name and role — used when we only have one
/// choice to shorten menus.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawRelatedPartsMenuStyle) {
	LDrawRelatedPartsMenuListChild = 0,
	LDrawRelatedPartsMenuListRole  = 1,
	LDrawRelatedPartsMenuMerged    = 2
};

//------------------------------------------------------------------------------
///
/// @class      LDrawRelatedPart
///
/// @abstract   One parent–child related-parts relation: names, role, and the
///             offset transform from related.ldr.
///
//------------------------------------------------------------------------------
@interface LDrawRelatedPart : NSObject
{
	NSString		*parent;
	NSString		*child;
	NSString		*childName;
	NSString		*role;
	double			transform[16];			// column-major, see LDrawPart
}

/// One child per selected LDrawPart. Other selected objects are skipped.
- (NSArray<LDrawPart *> *)childPartsForSelection:(NSArray *)selection color:(LDrawColor *)color;

@end

//------------------------------------------------------------------------------
///
/// @class      LDrawRelatedPartsMenuGroup
///
/// @abstract   One related-parts submenu: a title, the LDrawRelatedPart choices, and
///             whether to list by child name, by role, or as a single merged
///             item.
///
//------------------------------------------------------------------------------
@interface LDrawRelatedPartsMenuGroup : NSObject

@property (nonatomic, copy)   NSString *title;
@property (nonatomic, strong) NSArray  *choices;
@property (nonatomic, assign) LDrawRelatedPartsMenuStyle style;

/// Unmerged: childName or role. Merged: "role: childName".
- (NSString *)titleForChoice:(LDrawRelatedPart *)relatedPart;


@end

//------------------------------------------------------------------------------
///
/// @class      LDrawRelatedPartsMenuPlan
///
/// @abstract   Menu layout for a parent part: child-name groups and role
///             groups. Nil groups mean that section is omitted.
///
//------------------------------------------------------------------------------
@interface LDrawRelatedPartsMenuPlan : NSObject

@property (nonatomic, strong, nullable) NSArray<LDrawRelatedPartsMenuGroup *> *childGroups;
@property (nonatomic, strong, nullable) NSArray<LDrawRelatedPartsMenuGroup *> *roleGroups;


@end

//------------------------------------------------------------------------------
///
/// @class      LDrawRelatedParts
///
/// @abstract   Related-parts database loaded from related.ldr.
///
//------------------------------------------------------------------------------
@interface LDrawRelatedParts : NSObject 
{
	NSArray *		relatedParts;

}

/// Bundled related.ldr, or nil if the bundle has no such resource.
+ (nullable NSString *)databasePathInBundle:(NSBundle *)bundle;

/// Loads related.ldr from filePath. Nil or unreadable path yields an empty
/// database.
- (instancetype)initWithFilePath:(nullable NSString *)filePath;

/// Process-wide database. First path wins. Host passes databasePathInBundle:
/// or a test file.
+ (instancetype)sharedRelatedPartsWithFilePath:(nullable NSString *)filePath;

// If we only have one role or one child type of part, don't build two-level
// menus — there's no need. roleGroups is then empty (no separator / second
// section). Nil when the parent has no related parts. The host still builds
// NSMenu items.
- (nullable LDrawRelatedPartsMenuPlan *)menuPlanForParentName:(NSString *)parentName;


/// Titles used when the host builds NSMenu items (not localized).
+ (NSString *)relatedPartsMenuTitle;
+ (NSString *)relatedPartsChoicesSubmenuTitle;

@end

NS_ASSUME_NONNULL_END

