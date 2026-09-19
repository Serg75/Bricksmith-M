//==============================================================================
//
//  File:       LDrawViewportDrop.h
//  Package:    LDrawEditing
//
//  Purpose:    3D-viewport drop moves and hidden originals after a drag leaves
//              the document. The host still applies undo.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawEditing/LDrawViewportDropMove.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawViewportDrop
///
/// @abstract   Same-document 3D-viewport drop vs paste, and “oblivion” ghosts
///             when a move drag leaves the document.
///
//------------------------------------------------------------------------------
@interface LDrawViewportDrop : NSObject

/// Localization key for a 3D-viewport paste drop (not a same-document move).
+ (NSString *)viewportDropPasteUndoActionKey;

/// Being dragged within the same document. We must simply apply the
/// transforms from the dragged parts to the original parts, which have been
/// hidden during the drag.
///
/// Exception: If we have no current selection, it means this was a copy
///			  drag. Just paste instead of updating. The host still reads
///			  the AppKit dragging source.
+ (BOOL)viewportDropIsSameDocumentMoveFromSource:(nullable id)sourceFile
									  toDocument:(nullable id)documentFile
								  selectionCount:(NSInteger)selectionCount;

/// Pair selected drawables with dropped copies in order. Displacement is
/// dropped position minus original. The host still moves (undo) and unhides.
+ (NSArray *)viewportDropMovesForSelection:(NSArray *)selection
							 droppedCopies:(NSArray *)droppedCopies;

/// Hidden ghosts left after a move drag leaves the document. The host still
/// deleteDirective: (undo).
+ (NSArray *)viewportDragOblivionDirectivesFromSelection:(NSArray *)selection;

/// Unhide originals after a same-document 3D-viewport drop move.
+ (void)unhideDirectivesInViewportDropMoves:(NSArray *)moves;

/// Unhide before undoable delete when a move drag leaves the document.
+ (void)restoreVisibilityBeforeDeletingViewportDragOblivionDirectives:(NSArray *)directives;

/// Drawable elements in the selection. When a drag leaves the document, these
/// are the hidden originals the host must unhide and delete.
+ (NSArray *)drawableDirectivesInSelection:(NSArray *)selection;

@end

NS_ASSUME_NONNULL_END
