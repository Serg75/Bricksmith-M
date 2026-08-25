//==============================================================================
//
//  File:       LDrawSearchOps.h
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only helpers for finding parts by scope, color, and
//              name. The host still owns the search panel and selection.
//
//  Info:       Scope / color / part-criteria tags match the search-panel radio
//              buttons (1-based). Empty-selection remapping, warning keys,
//              container expansion, match filtering, the search-drop pasteboard
//              type, and empty-selection warning assembly live here so any host
//              can run the same search.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawModel.h>

@class LDrawColor;
@class LDrawContainer;
@class LDrawFile;

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	ScopeFile      = 1,
	ScopeModel     = 2,
	ScopeStep      = 3,
	ScopeSelection = 4
} ScopeT;

typedef enum {
	ColorNoFilter        = 1,
	ColorSelectionFilter = 2,
	ColorFilter          = 3
} ColorFilterT;

typedef enum {
	SearchAllParts      = 1,
	SearchSpecificPart  = 2,
	SearchSelectedParts = 3
} SearchPartCriteriaT;


//------------------------------------------------------------------------------
///
/// @class      LDrawSearchOps
///
/// @abstract   Foundation-only helpers for finding parts by scope, color, and
///             name. The host still owns the search panel and selection.
///
//------------------------------------------------------------------------------
@interface LDrawSearchOps : NSObject

/// When the selection is empty, Step/Selection become File, color-from-selection
/// becomes no filter, and selected-parts becomes all parts.
+ (void)normalizeEmptySelectionScope:(ScopeT *)ioScope
						 colorFilter:(ColorFilterT *)ioColor
					   partCriterion:(SearchPartCriteriaT *)ioCriterion;

/// Localization keys for the empty-selection warning, in order: root, what,
/// color, where. Nil when the selection is non-empty or the options would
/// not silently remap. The host still localizes each key.
+ (nullable NSArray<NSString *> *)emptySelectionWarningKeysWithCount:(NSUInteger)selectionCount
															   scope:(ScopeT)scope
														 colorFilter:(ColorFilterT)colorFilter
													   partCriterion:(SearchPartCriteriaT)partCriterion;

/// Joins four localized parts with English “of”/“in” and a period. Nil if
/// parts is not four items. The host still localizes and shows the text.
+ (nullable NSString *)emptySelectionWarningFromLocalizedParts:(NSArray<NSString *> *)parts;

/// Collect the containers to search given the panel's scope radio, the current
/// selection, and the active model / file.
///
/// An empty selection at ScopeModel searches the active model; at ScopeFile
/// it searches the whole file.
+ (NSArray *)searchableObjectsForScope:(ScopeT)scope
							 selection:(NSArray *)selectedObjects
						   activeModel:(nullable LDrawModel *)activeModel
								  file:(nullable LDrawFile *)file;

/// Build the color list used to filter search hits, or nil for no color filter.
+ (nullable NSArray *)colorFilterForCriterion:(ColorFilterT)colorCriterion
									wellColor:(nullable LDrawColor *)wellColor
									selection:(NSArray *)selectedObjects;

/// nil means “any part”. Specific names are comma-separated, trimmed, lowercased,
/// with .dat added when there is no .dat/.ldr suffix.
+ (nullable NSArray *)partFilterForCriterion:(SearchPartCriteriaT)criterion
							   specificNames:(nullable NSString *)commaSeparatedNames
								   selection:(NSArray *)selectedObjects;

/// Expand searchable containers into the leaf directives that can actually
/// match (parts, LSynth, etc.).
+ (NSArray *)matchablesInSearchableObjects:(NSArray *)searchableObjects
					 includeLSynthContents:(BOOL)includeLSynthContents;

/// Removes color/name mismatches. excludeHiddenParts YES drops hidden matchables.
+ (NSArray *)filterMatchables:(NSArray *)matchables
				  colorFilter:(nullable NSArray *)colorFilter
				   partFilter:(nullable NSArray *)partFilter
		   excludeHiddenParts:(BOOL)excludeHiddenParts;

/// displayName of each directive, newline-joined. Empty string if none.
/// The host still localizes the alert prefix and shows the sheet.
+ (NSString *)newlineSeparatedDisplayNamesFromDirectives:(NSArray *)directives;

/// Outline copies use LDrawDirectivePboardType; the part browser uses
/// LDrawDraggingPboardType. GLView drags remove pieces once they leave the
/// window, so they are ignored (nil). The host still checks the dragging-
/// source class and reads the pasteboard.
+ (nullable NSString *)searchDropPasteboardTypeFromOutline:(BOOL)fromOutline
										   fromPartBrowser:(BOOL)fromPartBrowser;

/// Unarchives outline/browser drag data and returns unique part reference
/// names, comma-joined. Nil when archivedDirectives is nil or empty.
+ (nullable NSString *)commaSeparatedPartNamesFromArchivedDirectivesData:(NSArray *)archivedDirectives;

@end

NS_ASSUME_NONNULL_END
