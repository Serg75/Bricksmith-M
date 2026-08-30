//==============================================================================
//
//  File:       LDrawInsertion.h
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only helpers for placing new primitives, parts,
//              comments, meta/LPub commands, and steps, and for deciding
//              whether a submodel reference is legal.
//
//  Info:       Line, triangle, quad, and conditional-line vertices are offset
//              from the last-selected part (or the origin). Named parts copy
//              that part’s transform. Step insert index is “after the selected
//              step,” or append. Submodel insert is blocked when the referenced
//              model already points at the destination. The host still owns
//              undo, color from the panel, addStepComponent:, and alerts.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawColor;
@class LDrawComment;
@class LDrawConditionalLine;
@class LDrawContainer;
@class LDrawDirective;
@class LDrawFile;
@class LDrawLine;
@class LDrawMetaCommand;
@class LDrawMPDModel;
@class LDrawPart;
@class LDrawQuadrilateral;
@class LDrawTriangle;
@class LPubCommand;
@class LPubRemoveGroup;

NS_ASSUME_NONNULL_BEGIN

/// Localization keys for undo after inserting an object. The host still
/// localizes (and formats UndoAddLSynth with the type name).
typedef NS_ENUM(NSInteger, LDrawInsertUndoKind) {
	LDrawInsertUndoLine              = 0,
	LDrawInsertUndoTriangle          = 1,
	LDrawInsertUndoQuadrilateral     = 2,
	LDrawInsertUndoConditionalLine   = 3,
	LDrawInsertUndoComment           = 4,
	LDrawInsertUndoMetaCommand       = 5,
	LDrawInsertUndoLPubCommand       = 6,
	LDrawInsertUndoRemoveGroup       = 7,
	LDrawInsertUndoRelatedPart       = 8,
	LDrawInsertUndoLSynthConstraint  = 9,
	LDrawInsertUndoModel             = 10,
	LDrawInsertUndoStep              = 11,
	LDrawInsertUndoPart              = 12
};


//------------------------------------------------------------------------------
///
/// @class      LDrawInsertion
///
/// @abstract   Foundation-only helpers for placing new primitives, parts,
///             comments, meta/LPub commands, and steps, and for deciding
///             whether a submodel reference is legal.
///
//------------------------------------------------------------------------------
@interface LDrawInsertion : NSObject

/// Last-selected part position, or the origin if there is no part.
+ (Point3)anchorPositionForPart:(nullable LDrawPart *)part;

+ (LDrawLine *)lineAtAnchor:(Point3)anchor color:(LDrawColor *)color;
+ (LDrawTriangle *)triangleAtAnchor:(Point3)anchor color:(LDrawColor *)color;
+ (LDrawQuadrilateral *)quadrilateralAtAnchor:(Point3)anchor color:(LDrawColor *)color;
+ (LDrawConditionalLine *)conditionalLineAtAnchor:(Point3)anchor color:(LDrawColor *)color;

/// Index after `directive` in `parent`. NSNotFound means append (last child,
/// missing parent/directive, or directive not in parent).
+ (NSInteger)indexAfterDirective:(nullable LDrawDirective *)directive
						inParent:(nullable LDrawContainer *)parent;

/// Copies `anchor`’s transform when it is non-nil. nil `partName` skips
/// `setDisplayName:` but still returns a part.
+ (LDrawPart *)partNamed:(nullable NSString *)partName
				   color:(LDrawColor *)color
	copyingTransformFrom:(nullable LDrawPart *)anchor;

/// Selected model, or the active model when nothing is selected.
+ (nullable LDrawMPDModel *)destinationModelPreferring:(nullable LDrawMPDModel *)selected
										 fallingBackTo:(nullable LDrawMPDModel *)active;

/// YES when the named submodel already references the destination (a cycle).
+ (BOOL)insertingSubmodelNamed:(nullable NSString *)partName
						inFile:(nullable LDrawFile *)file
	 wouldCycleWithDestination:(nullable LDrawMPDModel *)destination;

/// Menu enable: cannot insert a reference to the model currently being edited.
+ (BOOL)canInsertSubmodel:(nullable id)representedModel
		  intoActiveModel:(nullable id)activeModel;

/// LSynth constraint: selection is an LSynth, or a child of one.
+ (BOOL)canInsertLSynthConstraintForPart:(nullable id)selectedPart;

/// Returns the part transform which would be nice applied to new parts.
/// Identity if there is no previously-selected part.
+ (TransformComponents)preferredPartTransformFromPart:(nullable LDrawPart *)part;

/// Adds a new comment primitive to the currently-displayed model.
+ (LDrawComment *)comment;

/// Adds a new raw command to the currently-displayed model.
+ (LDrawMetaCommand *)metaCommand;

/// Adds a new generic LPub command to the currently-displayed model.
+ (LPubCommand *)lpubCommand;

/// Adds a new LPub Remove Group command. Placeholder group name is
/// @"group name"; the host still inserts and names the undo action.
+ (LPubRemoveGroup *)lpubRemoveGroup;

/// Undo localization key for a successful insert. The host still localizes.
+ (NSString *)undoActionKeyForInsertKind:(LDrawInsertUndoKind)kind;

/// Format key for UndoAddLSynth (takes the synth type name). The host still
/// localizes and formats.
+ (NSString *)undoActionFormatKeyForAddingLSynth;

/// YES when partName is non-nil and the insert would not create a cycle.
+ (BOOL)shouldInsertSubmodelNamed:(nullable NSString *)partName
			whenCircularReference:(BOOL)circularReference;

/// Alert keys when a submodel insert would cycle. The host still localizes.
+ (NSString *)circularReferenceMessageKey;
+ (NSString *)circularReferenceInformativeKey;

@end

NS_ASSUME_NONNULL_END
