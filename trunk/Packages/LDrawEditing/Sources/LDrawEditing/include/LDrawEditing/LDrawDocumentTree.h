//==============================================================================
//
//  File:       LDrawDocumentTree.h
//  Package:    LDrawEditing
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawContainer;
@class LDrawDirective;
@class LDrawDrawableElement;
@class LDrawFile;
@class LDrawModel;
@class LDrawMPDModel;
@class LDrawOriginPartUpdate;
@class LDrawPart;
@class LDrawSplitExpansion;
@class LDrawColor;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LDrawDeleteRefusal) {
	LDrawDeleteAllowed   = 0,
	LDrawDeleteLastModel = 1,
	LDrawDeleteLastStep  = 2
};

typedef NS_ENUM(NSInteger, LDrawOriginChangeKind) {
	LDrawOriginChangeByPosition      = 0,
	LDrawOriginChangeByRotationAxis  = 1,
	LDrawOriginChangeByAxesAlignment = 2
};

typedef NS_ENUM(NSInteger, LDrawMoveToParentCleanup) {
	LDrawMoveToParentCleanupNone       = 0,
	LDrawMoveToParentCleanupEmptyStep  = 1,
	LDrawMoveToParentCleanupEmptyModel = 2
};

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
/// @class      LDrawDocumentTree
///
/// @abstract   Methods to examine document structure and the nesting / delete /
///             split / origin-change / move-to-parent / model-from-selection /
///             paste-placement / MLCAD-group / LSynth-insert / goto-model /
///             outline-drag / outline-drop / outline data-source / outline
///             syntax-color / 3D-view drop / compliant-name / step-export rules
///             the editor uses.
///
//------------------------------------------------------------------------------
@interface LDrawDocumentTree : NSObject

+ (NSSet<NSString *> *)groupsBeforeStep:(LDrawStep *)step;

/// Last remaining model or step in its parent cannot be deleted.
+ (LDrawDeleteRefusal)deleteRefusalForDirective:(LDrawDirective *)directive;

/// Localization key for the delete-refusal informative text, or nil if
/// deletion is allowed. The host still localizes and shows the sheet.
+ (nullable NSString *)deleteRefusalInformativeKey:(LDrawDeleteRefusal)refusal;

/// Count backwards so that if a deletion fails, the leftover is at the top
/// rather than the bottom. The host still checks can-delete and deletes.
+ (NSArray *)directivesInReverseDeletionOrder:(NSArray *)directives;

/// Prefer an "interesting" selected container (texture, etc.) that accepts
/// the directive; otherwise the last visible step.
+ (LDrawContainer *)insertionParentForDirective:(LDrawDirective *)directive
							  selectedContainer:(nullable LDrawContainer *)selectedContainer
									visibleStep:(LDrawContainer *)visibleStep;

/// Direct children of steps that share one containing model (first model wins).
/// Returns an empty array when nothing can move; out parameters are then left
/// unchanged. The host still deletes and reinserts (undo).
+ (NSArray *)splitStepDirectivesFromSelection:(NSArray *)selection
							  containingModel:(LDrawContainer * _Nullable * _Nullable)outModel
								   sourceStep:(LDrawStep * _Nullable * _Nullable)outSourceStep
								  insertIndex:(NSInteger * _Nullable)outInsertIndex;

/// Copy rotation from source onto destination, then clear the source type.
+ (void)transferRotationFromStep:(LDrawStep *)source toStep:(LDrawStep *)destination;

/// Selected parts that reference an MPD or peer model, with the expanded
/// brick copies. The host still deletes the anchor and inserts the copies
/// (undo).
+ (NSArray<LDrawSplitExpansion *> *)splitExpansionsInSelection:(NSArray *)selection;

/// Menu-tag mapping for change-origin commands (MacLDraw.h tags).
+ (BOOL)originChangeKind:(nullable LDrawOriginChangeKind *)outKind forMenuTag:(NSInteger)tag;

/// Matrices for every part in the anchor's model, plus instances of that
/// model in sibling submodels. Empty if the first selected object is not a
/// part. The host still applies them (undo).
+ (NSArray<LDrawOriginPartUpdate *> *)originPartUpdatesForSelection:(NSArray *)selection
															   kind:(LDrawOriginChangeKind)kind;

+ (BOOL)selectionCanSplitStep:(NSArray *)selection;
+ (BOOL)selectionCanSplitModel:(NSArray *)selection;
+ (BOOL)selectionCanChangeOrigin:(NSArray *)selection;
+ (BOOL)selectionCanChangeOriginByRotation:(NSArray *)selection;
+ (BOOL)selectionCanMoveToParentModel:(NSArray *)selection;
+ (BOOL)selectionCanSetGroup:(NSArray *)selection;

/// Selected directives keyed by enclosing model fileName.
+ (NSDictionary<NSString *, NSArray<LDrawDirective *> *> *)directivesGroupedByEnclosingModelName:(NSArray *)directives;

/// Part copies get the instance's world transform; other directives are copies.
+ (LDrawDirective *)copyOfDirective:(LDrawDirective *)directive
				  placedAtReference:(LDrawPart *)reference;

/// After the host deletes a directive, empty models (and their instances) or
/// empty steps should be removed.
+ (LDrawMoveToParentCleanup)cleanupAfterRemovingFromModel:(LDrawModel *)model
													 step:(nullable LDrawStep *)step;

/// First part in selection order; used as the origin of a new submodel.
+ (nullable LDrawPart *)anchorPartInSelection:(NSArray *)selection;

/// Anchor world matrix and its inverse (to rebase nested parts into the
/// submodel). Returns NO if the anchor is nil.
+ (BOOL)modelFromSelectionAnchorMatrix:(Matrix4 *)outAnchorMatrix
							correction:(Matrix4 *)outCorrection
							 forAnchor:(LDrawPart *)anchor;

/// Inverse of the anchor transform applied to nested parts so they sit at
/// the new submodel origin. The host still applies them (undo).
+ (NSArray<LDrawOriginPartUpdate *> *)rebasedPartUpdatesInSelection:(NSArray *)selection
														 correction:(Matrix4)correction;

/// Last step of a newly created model; destination for moved directives.
+ (nullable LDrawStep *)lastStepOfModel:(LDrawModel *)model;

/// Reference part that stands in for the new submodel at the old origin.
+ (LDrawPart *)referencePartForSubmodelName:(NSString *)modelName
							   anchorMatrix:(Matrix4)anchorMatrix
									  color:(LDrawColor *)color;

/// Reset default icons, then bucket unarchived objects into models / steps /
/// other directives. Paste inserts the first non-empty bucket.
+ (void)partitionPastedObjects:(NSArray *)objects
						models:(NSMutableArray *)models
						 steps:(NSMutableArray *)steps
					directives:(NSMutableArray *)directives;

/// Step paste goes into an MPD model. Nil if parent is not one.
+ (nullable LDrawMPDModel *)pasteModelParentFromParent:(nullable id)parent;

/// Index immediately after model in its file, or NSNotFound if model is nil
/// or not in the file. Used for "next model" insert and model duplicate.
+ (NSInteger)insertIndexAfterModel:(nullable LDrawModel *)model inFile:(LDrawFile *)file;

/// Resolves parent/index for one pasted step component. nextToSimilar uses
/// fallbackParentStep when no similar part is found.
+ (void)resolveStepPasteParent:(LDrawContainer * _Nullable * _Nullable)outParent
						 index:(NSInteger * _Nullable)outIndex
				  forDirective:(LDrawDirective *)directive
						parent:(nullable id)parent
				 insertAtIndex:(NSInteger)insertAtIndex
				 nextToSimilar:(BOOL)nextToSimilar
				   inSelection:(NSArray *)selection
			fallbackParentStep:(nullable LDrawContainer *)fallbackParentStep;

/// insertAtIndex when not NSNotFound; otherwise defaultIndex (e.g. next model).
+ (NSInteger)modelPasteStartIndexForInsertAtIndex:(NSInteger)insertAtIndex
									 defaultIndex:(NSInteger)defaultIndex;

/// index + 1 for sequential model paste, or NSNotFound when index is NSNotFound.
+ (NSInteger)nextSequentialModelInsertIndexAfter:(NSInteger)index;

/// Duplicate paste index: defaultNextModelIndex when duplicating a model;
/// otherwise NSNotFound (next-to-similar placement).
+ (NSInteger)duplicatePasteIndexForSelection:(NSArray *)selection
					   defaultNextModelIndex:(NSInteger)defaultNextModelIndex;

/// Unique current group names (nil stored as @""). Returns nil if any
/// selected object cannot take a group.
+ (nullable NSSet<NSString *> *)groupNamesInSelection:(NSArray *)selection;

/// Non-empty names for a combo list. Order is that of the set.
+ (NSArray<NSString *> *)nonEmptyGroupNamesFromSet:(NSSet<NSString *> *)groups;

/// Trim whitespace; nil stays nil.
+ (nullable NSString *)normalizedGroupName:(nullable NSString *)name;

/// LDrawObjectWithValue pairs for directives whose group differs from newName.
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

/// Parent LSynth and insert index for a new constraint or INSIDE/OUTSIDE
/// directive. YES when lastSelected is an LSynth or a child of one.
+ (BOOL)lsynthInsertionParent:(LDrawContainer * _Nullable * _Nullable)outParent
						index:(NSInteger * _Nullable)outIndex
			  forLastSelected:(nullable id)lastSelected;

/// INSIDE / OUTSIDE / CROSS from MacLDraw.h menu tags; nil if the tag is unrelated.
+ (nullable NSString *)lsynthDirectionCommandForMenuTag:(NSInteger)tag;

/// Localization keys for the INSIDE / OUTSIDE / CROSS undo action. CROSS is
/// the default for any other tag. The host still localizes.
+ (NSString *)lsynthInsertUndoKeyForMenuTag:(NSInteger)tag;

/// MPD submodel to make active. Nil unless the selection is a single object
/// whose referencedMPDSubmodel is an LDrawMPDModel.
+ (nullable LDrawMPDModel *)mpdSubmodelToActivateFromSelection:(NSArray *)selection;

/// YES when the selection is a single object with a referenced peer file.
/// outPath is that file’s disk path (may be nil). The host still opens it.
+ (BOOL)peerFileFromSelection:(NSArray *)selection
						 path:(NSString * _Nullable * _Nullable)outPath;

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

/// Host maps Move → NSDragOperationMove, Copy → Copy, None → None.
/// Same-outline drop is a move: delete the original objects after paste.

/// Localization key for the undo action after an outline drop. @"UndoReorder"
/// for same-outline moves; nil for cross-outline paste (host may leave default).
+ (nullable NSString *)outlineDropUndoActionKeyForSameOutline:(BOOL)sameOutline;

/// Localization key for a 3D-view paste drop (not a same-document move).
+ (NSString *)viewDropPasteUndoActionKey;

/// Localization key for -duplicate:. The host still localizes.
+ (NSString *)duplicateUndoActionKey;

/// Localization keys for structural edits. The host still localizes.
+ (NSString *)splitStepUndoActionKey;
+ (NSString *)splitModelUndoActionKey;
+ (NSString *)moveToParentModelUndoActionKey;
+ (NSString *)changeOriginUndoActionKey;
+ (NSString *)modelFromSelectionUndoActionKey;
+ (NSString *)convertPrimitivesUndoActionKey;

/// Format key for the delete-refusal alert message (takes browsingDescription).
+ (NSString *)deleteDirectiveErrorMessageKey;

/// Missing / moved pieces and external-change alert keys. The host still
/// localizes and presents.
+ (NSString *)missingPiecesMessageKey;
+ (NSString *)missingPiecesInformativeKey;
+ (NSString *)movedPiecesMessageKey;
+ (NSString *)movedPiecesInformativeKey;
+ (NSString *)openingFileFormatKey;
+ (NSString *)unsavedDocumentMessageFormatKey;
+ (NSString *)unsavedDocumentInformativeKey;
+ (NSString *)unsavedDocumentRevertButtonKey;
+ (NSString *)unsavedDocumentKeepButtonKey;
+ (NSString *)okButtonNameKey;
+ (NSString *)cancelButtonNameKey;

/// File on disk newer than last known date: prompt if edited, else silent revert.
+ (BOOL)shouldPromptUnsavedExternalChangeWhenDocumentEdited:(BOOL)edited
										 fileNewerThanKnown:(BOOL)fileNewer;
+ (BOOL)shouldSilentRevertExternalChangeWhenDocumentEdited:(BOOL)edited
										fileNewerThanKnown:(BOOL)fileNewer;

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

/// AppKit color method name used when unarchiving that preference fails
/// (e.g. @"systemGreenColor"). Host still instantiates NSColor.

/// Hidden directives are italicized (0.5); others are upright (0.0).
+ (double)outlineObliquenessForDirective:(id)item;

/// Image name for an outline cell. Nil if the item is not a directive or
/// has no icon. The host still instantiates NSImage.
+ (nullable NSString *)outlineIconNameForItem:(nullable id)item;

/// browsingDescription, or a fallback error string if the item is not a
/// directive. The host still applies syntax coloring.
+ (NSString *)outlineDescriptionForItem:(nullable id)item;

/// Being dragged within the same document. We must simply apply the
/// transforms from the dragged parts to the original parts, which have been
/// hidden during the drag.
///
/// Exception: If we have no current selection, it means this was a copy
///			  drag. Just paste instead of updating. The host still reads
///			  the AppKit dragging source.
+ (BOOL)viewDropIsSameDocumentMoveFromSource:(nullable id)sourceFile
								  toDocument:(nullable id)documentFile
							  selectionCount:(NSInteger)selectionCount;

/// Pair selected drawables with dropped copies in order. Displacement is
/// dropped position minus original. The host still moves (undo) and unhides.
+ (NSArray *)viewDropMovesForSelection:(NSArray *)selection
						 droppedCopies:(NSArray *)droppedCopies;

/// Hidden ghosts left after a move drag leaves the document. The host still
/// deleteDirective: (undo).
+ (NSArray *)viewDragOblivionDirectivesFromSelection:(NSArray *)selection;

/// Unhide originals after a same-document 3D-view drop move.
+ (void)unhideDirectivesInViewDropMoves:(NSArray *)moves;

/// Unhide before undoable delete when a move drag leaves the document.
+ (void)restoreVisibilityBeforeDeletingViewDragOblivionDirectives:(NSArray *)directives;

/// Drawable elements in the selection. When a drag leaves the document, these
/// are the hidden originals the host must unhide and delete.
+ (NSArray *)drawableDirectivesInSelection:(NSArray *)selection;

/// Submodels whose names lack a recognized LDraw extension (.ldr, .dat).
/// Direct rename is used when the file has a single submodel; otherwise the
/// host must use renameModel:toName: so references update.
+ (NSArray *)compliantNameChangesForSubmodels:(NSArray *)submodels;

/// Copies the file, promotes each submodel to the top (so L3P renders it),
/// then peels steps last-to-first. folderNameFormat / fileNameFormat are
/// host-localized (`%@ Steps` / `%@, Step %ld.ldr`). The host still writes
/// the folders and files.
+ (NSArray *)stepExportFilesFromFile:(nullable LDrawFile *)file
					folderNameFormat:(NSString *)folderNameFormat
					  fileNameFormat:(NSString *)fileNameFormat;

/// Localization format keys for step export. The host still localizes.
+ (NSString *)exportedStepsFolderFormatKey;
+ (NSString *)exportedStepsFileFormatKey;

/// Duplicate model-name alert keys. The host still localizes.
+ (NSString *)duplicateModelNameMessageFormatKey;
+ (NSString *)duplicateModelNameInformativeKey;

/// YES when renaming to a different name that already exists in the file.
+ (BOOL)shouldRejectDuplicateModelRenameFrom:(nullable NSString *)oldValue
										  to:(nullable NSString *)newValue
						 whenModelNameExists:(BOOL)nameExists;

/// Applying the viewing angle on every step change is pretty annoying
/// while building and flipping between steps. YES only when the step
/// demands a change (rotation type is not none). The host still updates

/// Wraps at the ends. C remainder of a negative dividend is negative, so
/// stepping back from 0 must not use a raw `%`. The host still sets the
/// current step.
+ (NSInteger)wrappedStepIndex:(NSInteger)current
					  byDelta:(NSInteger)delta
					stepCount:(NSInteger)count;

/// Nil if the outline item is missing or is a file, model, or step.
/// Anything else is the selected step component.
+ (nullable id)stepComponentFromOutlineItem:(nullable id)item;

/// If nothing is selected, all directives in the first step are converted.
+ (NSArray *)highResSourceDirectivesFromSelection:(NSArray *)selection
									  activeModel:(nullable LDrawModel *)model;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawViewDropMove
///
/// @abstract   Drawable original plus the displacement to apply after a
///             same-document 3D-view drop.
///
//------------------------------------------------------------------------------
@interface LDrawViewDropMove : NSObject

@property (nonatomic, strong) LDrawDrawableElement *directive;
@property (nonatomic, assign) Vector3 displacement;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawCompliantNameChange
///
/// @abstract   A submodel that must be given a spec-compliant name (.ldr /
///             .dat).
///
//------------------------------------------------------------------------------
@interface LDrawCompliantNameChange : NSObject

@property (nonatomic, strong) LDrawMPDModel *model;
@property (nonatomic, copy)   NSString      *compliantName;

/// Single-submodel files can setModelName: directly. MPD files need
/// renameModel:toName: so references update, then the host marks dirty.
@property (nonatomic) BOOL renameInPlace;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawOriginPartUpdate
///
/// @abstract   One part whose origin-change matrix is ready to apply.
///             previousComponents is the pre-change transform for undo.
///
//------------------------------------------------------------------------------
@interface LDrawOriginPartUpdate : NSObject

@property (nonatomic, strong) LDrawPart *part;
@property (nonatomic, assign) Matrix4 matrix;
@property (nonatomic, assign) TransformComponents previousComponents;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawSplitExpansion
///
/// @abstract   One selected part that can be split into its referenced model's
///             bricks.
///
//------------------------------------------------------------------------------
@interface LDrawSplitExpansion : NSObject

@property (nonatomic, strong) LDrawPart *anchor;
@property (nonatomic, strong) LDrawModel *model;
@property (nonatomic, strong) NSArray<LDrawPart *> *expandedParts;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepExportFile
///
/// @abstract   One LDR file in a step-export: per-model folder name, file name,
///             and file contents. The host still creates directories and writes
///             bytes.
///
//------------------------------------------------------------------------------
@interface LDrawStepExportFile : NSObject

@property (nonatomic, copy) NSString *folderName;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *ldrString;

@end

NS_ASSUME_NONNULL_END
