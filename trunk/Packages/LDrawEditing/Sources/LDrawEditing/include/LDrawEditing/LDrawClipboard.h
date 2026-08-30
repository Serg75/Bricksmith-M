//==============================================================================
//
//  File:       LDrawClipboard.h
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only archive / unarchive for copy, paste, and
//              drag-and-drop of LDraw directives.
//
//  Info:       The host still owns NSPasteboard / UIPasteboard. This class
//              turns a selection into NSData (and back), drops children whose
//              parent is already in the selection so a container is archived
//              once, packs drawable originals for a 3D-view drag, packs a new
//              named part for a part-browser drag, and names the pasteboard
//              type arrays. The host still calls declareTypes: / addTypes:.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>
#import <LDrawEditing/LDrawPasteboard.h>

@class LDrawColor;

NS_ASSUME_NONNULL_BEGIN

/// Local 3D-view drag is a move; otherwise copy. The host maps to NSDragOperation.
typedef NS_ENUM(NSInteger, LDrawViewDragKind) {
	LDrawViewDragKindMove = 0,
	LDrawViewDragKindCopy = 1
};


//------------------------------------------------------------------------------
///
/// @class      LDrawClipboard
///
/// @abstract   Foundation-only archive / unarchive for copy, paste, and
///             drag-and-drop of LDraw directives.
///
//------------------------------------------------------------------------------
@interface LDrawClipboard : NSObject

+ (nullable id)unarchivedDirectiveFromData:(NSData *)data;
+ (NSArray *)unarchivedDirectivesFromDataArray:(NSArray *)archived;

/// Archive selected movable directives for a 3D-view drag. Only drawable
/// elements are packed. outDrawables (if non-NULL) is those originals so the
/// host can hide them on a move drag. The host still writes the pasteboard
/// and deselects on a copy drag.
+ (NSArray<NSData *> *)archivedDraggingDataFromSelection:(NSArray *)selection
									   drawableOriginals:(NSArray * _Nullable * _Nullable)outDrawables;


/// Writes the current part-browser selection onto the pasteboard. Archives a
/// new part with the given name and color. Returns nil if partName is nil.
/// The host still writes LDrawDraggingPboardType and
/// LDrawDraggingIsUninitializedPboardType (YES — the part has no transform yet).
+ (nullable NSArray<NSData *> *)archivedDraggingDataForPartNamed:(nullable NSString *)partName
														   color:(LDrawColor *)color;

/// Offset of the originating click from the first dragged part’s position.
/// Re-entering the originating view must not snap part 0 under the mouse.
/// The host still writes LDrawDraggingInitialOffsetPboardType.
+ (Vector3)draggingOffsetFromModelPoint:(Point3)modelPoint
						  firstPosition:(Point3)firstPosition;

/// YES when the drag source is this view (move). Otherwise copy. The host
/// still maps that to NSDragOperation.
+ (BOOL)dragOriginatedLocallyFromSource:(nullable id)source
							destination:(nullable id)destination;

/// Move when local; otherwise copy. The host still maps to NSDragOperation.
+ (LDrawViewDragKind)viewDragKindFromSource:(nullable id)source
								destination:(nullable id)destination;


/// LDrawDirectivePboardType plus the host’s string type (NSPasteboardTypeString
/// / NSStringPboardType). The host still declareTypes: and writes both.
+ (NSArray<NSString *> *)copyPasteboardTypesIncludingStringType:(NSString *)stringType;

/// File-contents outline registerForDraggedTypes:.
+ (NSArray<NSString *> *)outlineRegisteredDragTypes;

/// Outline writeItems: extra types (source rows + disallow-to-source).
+ (NSArray<NSString *> *)outlineDragSourcePasteboardTypes;

/// Property-list value for LDrawDisallowDragToSourcePboardType when writing
/// an outline drag. The host still setPropertyList:forType:.
+ (id)outlineDragDisallowPropertyListForDisallow:(BOOL)disallow;

/// YES when the pasteboard types include the disallow flag and it is true.
+ (BOOL)outlinePasteboardDisallowsDragToSourceFromTypes:(NSArray *)types
								   disallowPropertyList:(nullable id)disallowPropertyList;

/// Collects rowForItem: for each item. rowForItemTarget must respond to
/// rowForItem:. The host still addTypes: and setPropertyList:forType:.
+ (NSArray<NSNumber *> *)outlineDragSourceRowIndexesForItems:(NSArray *)items
											rowForItemTarget:(id)rowForItemTarget;

/// Collects itemAtRow: for each index. itemAtRowTarget must respond to
/// itemAtRow:. Used when same-outline acceptDrop gathers originals to delete.
+ (NSArray *)outlineItemsAtRowIndexes:(NSIndexSet *)indexes
					  itemAtRowTarget:(id)itemAtRowTarget;

/// Private pasteboard for -duplicate: (avoids clobbering the general board).
+ (NSString *)duplicationPasteboardName;

/// Private pasteboard for 3D-view drop import via pasteFromPasteboard:.
+ (NSString *)viewDropPasteboardName;

/// Root-filter, archive, and LDR string for copy/paste. The host still
/// declareTypes: and writes both pasteboard representations.
+ (void)copyPayloadFromDirectives:(NSArray *)directives
					 archivedData:(NSArray<NSData *> * _Nullable * _Nullable)outArchived
						ldrString:(NSString * _Nullable * _Nullable)outString;

/// 3D view registerForDraggedTypes: / declareTypes: for a viewport drag.
+ (NSArray<NSString *> *)viewRegisteredDragTypes;

/// Private offset written once a viewport drag starts.
+ (NSArray<NSString *> *)viewDragOffsetPasteboardTypes;

/// Part browser: LDrawDraggingPboardType plus uninitialized flag.
+ (NSArray<NSString *> *)partBrowserDeclaredDragTypes;

/// Search panel accepts outline copies and part-browser drags.
+ (NSArray<NSString *> *)searchPanelRegisteredDragTypes;

@end

NS_ASSUME_NONNULL_END
