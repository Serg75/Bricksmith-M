//==============================================================================
//
//  File:       LDrawOutline.h
//  Package:    LDrawEditing
//
//  Purpose:    Outline data source, drop validation, and syntax coloring.
//              The host still owns NSOutlineView. Tree apply after classify
//              uses these helpers plus host row lookup (LDrawFileOutlineView).
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawContainer;
@class LDrawFile;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LDrawOutlineDropKind) {
	LDrawOutlineDropNone = 0,
	LDrawOutlineDropMove = 1,
	LDrawOutlineDropCopy = 2
};

/// Foundation-only fallback when user-defaults unarchiving fails for outline
/// syntax colors. The host maps each case to the matching NSColor.
typedef NS_ENUM(NSInteger, LDrawOutlineSyntaxFallbackColor) {
	LDrawOutlineSyntaxFallbackSystemGreen  = 0,
	LDrawOutlineSyntaxFallbackSystemBlue   = 1,
	LDrawOutlineSyntaxFallbackSystemOrange = 2,
	LDrawOutlineSyntaxFallbackSystemPurple = 3,
	LDrawOutlineSyntaxFallbackSystemYellow = 4,
	LDrawOutlineSyntaxFallbackSystemPink   = 5,
	LDrawOutlineSyntaxFallbackSystemRed    = 6,
	LDrawOutlineSyntaxFallbackLabel        = 7
};


//------------------------------------------------------------------------------
///
/// @class      LDrawOutline
///
/// @abstract   Outline data-source queries, drop kind, and syntax-color keys.
///
//------------------------------------------------------------------------------
@interface LDrawOutline : NSObject

/// Dragging the model’s only step out of the outline is disallowed (it would
/// leave the model with no steps).
+ (BOOL)shouldDisallowDraggingItems:(NSArray *)items;

/// Outline root is the file; otherwise the proposed parent.
+ (nullable id)outlineDropParent:(nullable id)proposedParent file:(nullable LDrawFile *)file;

/// validateDrop glue: resolves parent, reads directive preview data, returns
/// move/copy/none. archivedDirectiveObjects is the LDrawDirectivePboardType
/// property list; the host still reads the pasteboard.
+ (LDrawOutlineDropKind)outlineDropKindForValidateDropWithProposedParent:(nullable id)proposedParent
																	file:(nullable LDrawFile *)file
															  dropOnItem:(BOOL)dropOnItem
														 pasteboardTypes:(NSArray *)types
													disallowDragToSource:(BOOL)disallow
															 sameOutline:(BOOL)sameOutline
												archivedDirectiveObjects:(nullable NSArray *)archivedDirectiveObjects;

/// Localization key for the undo action after an outline drop. @"UndoReorder"
/// for same-outline moves; nil for cross-outline paste (host may leave default).
+ (nullable NSString *)outlineDropUndoActionKeyForSameOutline:(BOOL)sameOutline;

/// Unique enclosing parents of moved items. File (outline root) is omitted.
+ (NSSet *)donatingParentsFromMovedDirectives:(NSArray *)directives;

/// LSynth-style cleanupAfterDropIsDonor: on donors (YES) and destination (NO).
+ (void)cleanupAfterOutlineDropDonors:(NSSet *)donors destination:(nullable id)newParent;

/// Returns the number of items which should be displayed under an expanded
/// item. Root is the file’s submodels; a container uses its subdirectives.
+ (NSInteger)outlineChildCountOfItem:(nullable id)item file:(nullable LDrawFile *)file;

/// You can expand models and steps.
+ (BOOL)outlineItemIsExpandable:(nullable id)item;

/// If the outline item is a container, that item; otherwise its enclosing
/// directive. The host still picks the outline row (and the original
/// selection during a copy drag).
+ (nullable LDrawContainer *)containerEnclosingOutlineItem:(nullable id)item;

/// Returns the child of item at the position index. Root children are the
/// file’s submodels; a container’s children are its subdirectives.
+ (id)outlineChild:(NSInteger)index ofItem:(nullable id)item file:(nullable LDrawFile *)file;

/// Preference key for the directive’s outline syntax color.
+ (NSString *)outlineSyntaxColorKeyForDirective:(id)item;

+ (LDrawOutlineSyntaxFallbackColor)outlineSyntaxFallbackColorForKey:(NSString *)colorKey;

/// Hidden directives are italicized (0.5); others are upright (0.0).
+ (double)outlineObliquenessForDirective:(id)item;

/// Image name for an outline cell. Nil if the item is not a directive or
/// has no icon. The host still instantiates NSImage.
+ (nullable NSString *)outlineIconNameForItem:(nullable id)item;

/// browsingDescription, or a fallback error string if the item is not a
/// directive. The host still applies syntax coloring.
+ (NSString *)outlineDescriptionForItem:(nullable id)item;

/// Nil if the outline item is missing or is a file, model, or step.
/// Anything else is the selected step component.
+ (nullable id)stepComponentFromOutlineItem:(nullable id)item;

@end

NS_ASSUME_NONNULL_END
