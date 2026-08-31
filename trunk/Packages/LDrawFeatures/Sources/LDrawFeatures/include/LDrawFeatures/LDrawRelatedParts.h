//==============================================================================
//
//  File:       LDrawRelatedParts.h
//  Package:    LDrawFeatures
//
//  Created by bsupnik on 2/24/13.
//  Copyright 2013. All rights reserved.
//
//==============================================================================

#if WANT_RELATED_PARTS

#import <Foundation/Foundation.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawColor;
@class LDrawPart;

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
	float			transform[16];
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

@property (nonatomic, strong) NSArray<LDrawRelatedPartsMenuGroup *> *childGroups;
@property (nonatomic, strong) NSArray<LDrawRelatedPartsMenuGroup *> *roleGroups;


@end

//------------------------------------------------------------------------------
///
/// @class      LDrawRelatedParts
///
/// @abstract   Singleton related-parts database loaded from related.ldr.
///
//------------------------------------------------------------------------------
@interface LDrawRelatedParts : NSObject 
{
	NSArray *		relatedParts;

}

/// Singleton; parts are loaded from an LDR file stored in the bundle.
+ (LDrawRelatedParts*)sharedRelatedParts;

// If we only have one role or one child type of part, don't build two-level
// menus — there's no need. roleGroups is then empty (no separator / second
// section). Nil when the parent has no related parts. The host still builds
// NSMenu items.
- (LDrawRelatedPartsMenuPlan *)menuPlanForParentName:(NSString *)parentName;


/// Titles used when the host builds NSMenu items (not localized).
+ (NSString *)relatedPartsMenuTitle;
+ (NSString *)relatedPartsChoicesSubmenuTitle;

@end

#endif /* WANT_RELATED_PARTS */
