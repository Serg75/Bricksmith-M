//==============================================================================
//
//  File:       LDrawStructure.h
//  Package:    LDrawEditing
//
//  Purpose:    Delete, split, origin-change, submodel, LSynth-insert, step
//              navigation, high-res conversion, and export/name-compliance
//              rules. The host still applies undo.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawEditing/LDrawCompliantNameChange.h>
#import <LDrawEditing/LDrawOriginPartUpdate.h>
#import <LDrawEditing/LDrawSplitExpansion.h>
#import <LDrawEditing/LDrawStepExportFile.h>

@class LDrawContainer;
@class LDrawDirective;
@class LDrawFile;
@class LDrawModel;
@class LDrawMPDModel;
@class LDrawPart;
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


//------------------------------------------------------------------------------
///
/// @class      LDrawStructure
///
/// @abstract   Document-structure rules: nesting / delete / split / origin /
///             move-to-parent / model-from-selection / LSynth-insert /
///             goto-model / compliant-name / step-export.
///
//------------------------------------------------------------------------------
@interface LDrawStructure : NSObject

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

/// Localization keys for structural edits. The host still localizes.
+ (NSString *)splitStepUndoActionKey;
+ (NSString *)splitModelUndoActionKey;
+ (NSString *)moveToParentModelUndoActionKey;
+ (NSString *)changeOriginUndoActionKey;
+ (NSString *)modelFromSelectionUndoActionKey;
+ (NSString *)convertPrimitivesUndoActionKey;

/// Format key for the delete-refusal alert message (takes browsingDescription).
+ (NSString *)deleteDirectiveErrorMessageKey;

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

/// Wraps at the ends. C remainder of a negative dividend is negative, so
/// stepping back from 0 must not use a raw `%`. The host still sets the
/// current step.
+ (NSInteger)wrappedStepIndex:(NSInteger)current
					  byDelta:(NSInteger)delta
					stepCount:(NSInteger)count;

/// If nothing is selected, all directives in the first step are converted.
+ (NSArray *)highResSourceDirectivesFromSelection:(NSArray *)selection
									  activeModel:(nullable LDrawModel *)model;

@end

NS_ASSUME_NONNULL_END
