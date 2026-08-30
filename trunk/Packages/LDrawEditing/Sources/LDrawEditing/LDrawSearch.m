//==============================================================================
//
//  File:       LDrawSearch.m
//  Package:    LDrawEditing
//
//  Purpose:    Scope, color, and name matching for the find-parts command.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawEditing/LDrawSearch.h>

#import <LDrawEditing/LDrawClipboard.h>
#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>

@interface LDrawSearch (Private)
+ (NSArray *)partsInContainer:(LDrawContainer *)container
		includeLSynthContents:(BOOL)includeLSynthContents;
@end


@interface LDrawSearch ()
/// Unique LDrawPart reference names, comma-joined. Empty string if none.
+ (NSString *)commaSeparatedReferenceNamesFromDirectives:(NSArray *)directives;
@end

@implementation LDrawSearch

//========== doSearchAndSelect: ================================================
//
// Purpose:		The main search method.  This operates as follows:
//
//              - Determine where to search (the scope): File, Model, Step or within
//                the current selection
//              - Collect all potential matches up
//              - Filter out parts that don't match our criteria, based on part
//                type and colour
//              - Select the remaining matching parts
//
//==============================================================================
+ (void)normalizeEmptySelectionScope:(ScopeT *)ioScope
						 colorFilter:(ColorFilterT *)ioColor
					   partCriterion:(SearchPartCriteriaT *)ioCriterion
{
	// First up, adjust the options if there's no selection

	if (ioScope != NULL && (*ioScope == ScopeStep || *ioScope == ScopeSelection))
	{
		*ioScope = ScopeFile;
	}
	if (ioColor != NULL && *ioColor == ColorSelectionFilter)
	{
		*ioColor = ColorNoFilter;
	}
	if (ioCriterion != NULL && *ioCriterion == SearchSelectedParts)
	{
		*ioCriterion = SearchAllParts;
	}
}


//---------- emptySelectionWarningKeysWithCount:scope:colorFilter:partCriterion:
//
// Purpose:		We don't change the user's options, merely warn them what we'll
//				do. No selection so display a suitable warning message.
//
// Notes:		Even if we have nothing selected the combination of options
//				might not be cause for alarm.
//
//------------------------------------------------------------------------------
+ (nullable NSArray<NSString *> *)emptySelectionWarningKeysWithCount:(NSUInteger)selectionCount
															   scope:(ScopeT)scope
														 colorFilter:(ColorFilterT)colorFilter
													   partCriterion:(SearchPartCriteriaT)partCriterion
{
	if (selectionCount > 0) return nil;

	if (scope != ScopeSelection
	   && scope != ScopeStep
	   && colorFilter != ColorSelectionFilter
	   && partCriterion != SearchSelectedParts)
	{
		return nil;
	}

	// The "what"
	NSString *whatKey = @"SearchWarningAllParts";
	if (partCriterion == SearchSpecificPart)
	{
		whatKey = @"SearchWarningSpecifiedParts";
	}

	// The color
	NSString *colorKey = @"SearchWarningAnyColor";
	if (colorFilter == ColorFilter)
	{
		colorKey = @"SearchWarningSpecifiedColor";
	}

	// The "where"
	NSString *whereKey = @"SearchWarningFileScope";
	if (scope == ScopeModel)
	{
		whereKey = @"SearchWarningModelScope";
	}

	return @[
		@"SearchWarningRoot",
		whatKey,
		colorKey,
		whereKey,
	];
}


//---------- emptySelectionWarningFromLocalizedParts: ----------------[static]--
//
// Purpose:		We don't change the user's options, merely warn them what we'll
//				do. No selection so display a suitable warning message.
//
//------------------------------------------------------------------------------
+ (nullable NSString *)emptySelectionWarningFromLocalizedParts:(NSArray<NSString *> *)parts
{
	if ([parts count] != 4) return nil;

	NSArray *components = @[
		[parts objectAtIndex:0],
		[parts objectAtIndex:1],
		@"of", // preposition
		[parts objectAtIndex:2],
		@"in", // preposition
		[parts objectAtIndex:3],
	];
	return [[components componentsJoinedByString:@" "] stringByAppendingString:@"."];
}


//---------- searchableObjectsForScope:selection:activeModel:file: --[static]--
//
// Purpose:		Collect the containers to search given the panel's scope radio,
//				the current selection, and the active model / file.
//
//				An empty selection at ScopeModel searches the active model; at
//				ScopeFile it searches the whole file.
//
//------------------------------------------------------------------------------
+ (NSArray *)searchableObjectsForScope:(ScopeT)scope
							 selection:(NSArray *)selectedObjects
						   activeModel:(nullable LDrawModel *)activeModel
								  file:(nullable LDrawFile *)file
{
	if (scope == ScopeSelection)
	{
		return [selectedObjects mutableCopy];
	}

	NSMutableArray *searchableObjects = [NSMutableArray array];

	if ([selectedObjects count] == 0)
	{
		if (scope == ScopeModel)
		{
			if (activeModel != nil)
			{
				[searchableObjects addObject:activeModel];
			}
		}
		else if (file != nil)
		{
			[searchableObjects addObject:file];
		}
	}

	NSMutableArray *selectedParts = [NSMutableArray array];
	for (id obj in selectedObjects)
	{
		if ([obj isKindOfClass:[LDrawPart class]] || [obj isKindOfClass:[LDrawLSynth class]]
		   || ([obj isKindOfClass:[LDrawStep class]] && scope == ScopeStep)
		   || ([obj isKindOfClass:[LDrawModel class]] && scope == ScopeModel))
		{
			[selectedParts addObject:obj];
		}
	}

	for (id part in selectedParts)
	{
		id scopedContainer = nil;
		if (scope == ScopeStep)
		{
			scopedContainer = [part enclosingStep];
		}
		else if (scope == ScopeModel)
		{
			scopedContainer = [part enclosingModel];
		}
		else if (scope == ScopeFile)
		{
			scopedContainer = [part enclosingFile];
		}

		if (scopedContainer != nil && [searchableObjects indexOfObject:scopedContainer] == NSNotFound)
		{
			[searchableObjects addObject:scopedContainer];
		}
	}

	return searchableObjects;
}


//---------- colorFilterForCriterion:selectedColor:selectedObjects: -[static]--
//
// Purpose:		Build the color list used to filter search hits, or nil for no
//				color filter.
//
//------------------------------------------------------------------------------
+ (nullable NSArray *)colorFilterForCriterion:(ColorFilterT)colorCriterion
									wellColor:(nullable LDrawColor *)wellColor
									selection:(NSArray *)selectedObjects
{
	if (colorCriterion == ColorFilter)
	{
		if (wellColor == nil)
		{
			return nil;
		}
		return @[wellColor];
	}
	if (colorCriterion == ColorSelectionFilter)
	{
		NSMutableArray *colors = [NSMutableArray array];
		for (id obj in selectedObjects)
		{
			if ([obj isKindOfClass:[LDrawPart class]] || [obj isKindOfClass:[LDrawLSynth class]])
			{
				if ([colors indexOfObject:[obj LDrawColor]] == NSNotFound)
				{
					[colors addObject:[obj LDrawColor]];
				}
			}
		}
		return colors;
	}
	return nil;
}


//---------- partFilterForCriterion:specificPartName:selectedObjects: -[static]--
//
// Purpose:		Build the part-name list used to filter search hits, or nil to
//				match all parts.
//
//------------------------------------------------------------------------------
+ (nullable NSArray *)partFilterForCriterion:(SearchPartCriteriaT)criterion
							   specificNames:(nullable NSString *)commaSeparatedNames
								   selection:(NSArray *)selectedObjects
{
	if (criterion == SearchSpecificPart)
	{
		NSArray        *tmpParts  = [(commaSeparatedNames ?: @"") componentsSeparatedByString:@","];
		NSMutableArray *partNames = [NSMutableArray array];
		for (id obj in tmpParts)
		{
			NSString *part = [[obj stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
			if ([part hasSuffix:@".dat"] == NO && [part hasSuffix:@".ldr"] == NO)
			{
				part = [NSString stringWithFormat:@"%@.dat", part];
			}
			[partNames addObject:part];
		}
		return partNames;
	}
	if (criterion == SearchSelectedParts)
	{
		NSMutableArray *partNames = [NSMutableArray array];
		for (id obj in selectedObjects)
		{
			if ([obj isKindOfClass:[LDrawPart class]])
			{
				[partNames addObject:[obj referenceName]];
			}
			else if ([obj isKindOfClass:[LDrawLSynth class]])
			{
				[partNames addObject:[obj lsynthType]];
			}
		}
		return partNames;
	}
	return nil;
}


//========== partsInContainer: =================================================
//
// Purpose:		A recursive helper function to find all parts in a container
//
//==============================================================================
+ (NSArray *)partsInContainer:(LDrawContainer *)container
		includeLSynthContents:(BOOL)includeLSynthContents
{
	NSMutableArray *parts = [NSMutableArray array];
	for (id directive in [container subdirectives])
	{
		if ([directive isKindOfClass:[LDrawPart class]])
		{
			[parts addObject:directive];
		}
		// Recurse on subcontainers
		else if (([directive isKindOfClass:[LDrawContainer class]] && [directive isKindOfClass:[LDrawLSynth class]] == NO)
			 || ([directive isKindOfClass:[LDrawLSynth class]] && includeLSynthContents))
		{
			[parts addObjectsFromArray:[self partsInContainer:directive includeLSynthContents:includeLSynthContents]];
		}

		if ([directive isKindOfClass:[LDrawLSynth class]])
		{
			// Add LSynth "Parts" specifically. Their contents are handled above
			[parts addObject:directive];
		}
	}
	return parts;
}


//---------- matchablesInSearchableObjects: -------------------------[static]--
//
// Purpose:		Expand searchable containers into the leaf directives that can
//				actually match (parts, LSynth, etc.).
//
//------------------------------------------------------------------------------
+ (NSArray *)matchablesInSearchableObjects:(NSArray *)searchableObjects
					 includeLSynthContents:(BOOL)includeLSynthContents
{
	NSMutableArray *matchables = [NSMutableArray array];
	for (id searchableObject in searchableObjects)
	{
		if ([searchableObject isKindOfClass:[LDrawPart class]])
		{
			[matchables addObject:searchableObject];
		}
		else if ([searchableObject isKindOfClass:[LDrawContainer class]])
		{
			[matchables addObjectsFromArray:[self partsInContainer:searchableObject
											 includeLSynthContents:includeLSynthContents]];
		}

		if ([searchableObject isKindOfClass:[LDrawLSynth class]])
		{
			[matchables addObject:searchableObject];
		}
	}
	return matchables;
}


//---------- filterMatchables:colorFilter:partFilter: ---------------[static]--
//
// Purpose:		Keep matchables whose color and part name pass the filters.
//				A nil filter means no restriction on that axis.
//
//------------------------------------------------------------------------------
+ (NSArray *)filterMatchables:(NSArray *)matchables
				  colorFilter:(NSArray *)colorFilter
				   partFilter:(NSArray *)partFilter
		   excludeHiddenParts:(BOOL)excludeHiddenParts
{
	NSMutableArray *remaining        = [matchables mutableCopy];
	NSMutableArray *nonMatchingParts = [NSMutableArray array];

	for (id part in remaining)
	{
		if (colorFilter != nil && [colorFilter indexOfObject:[part LDrawColor]] == NSNotFound)
		{
			[nonMatchingParts addObject:part];
			continue;
		}

		NSString *name = nil;
		if ([part isKindOfClass:[LDrawPart class]])
		{
			name = [part referenceName];
		}
		else if ([part isKindOfClass:[LDrawLSynth class]])
		{
			name = [part lsynthType];
		}

		if (partFilter != nil && [partFilter indexOfObject:name] == NSNotFound)
		{
			[nonMatchingParts addObject:part];
			continue;
		}
	}

	if (excludeHiddenParts)
	{
		for (id obj in remaining)
		{
			if ([obj respondsToSelector:@selector(setHidden:)] && [obj isHidden]
			   && [nonMatchingParts indexOfObject:obj] == NSNotFound)
			{
				[nonMatchingParts addObject:obj];
			}
		}
	}

	[remaining removeObjectsInArray:nonMatchingParts];
	return remaining;
}


//---------- commaSeparatedReferenceNamesFromDirectives: ------------[static]--
//
// Purpose:		Unique LDrawPart reference names, comma-joined. Empty string if
//				none.
//
//------------------------------------------------------------------------------
+ (NSString *)commaSeparatedReferenceNamesFromDirectives:(NSArray *)directives
{
	NSMutableArray *directiveNames = [NSMutableArray array];
	for (id currentObject in directives)
	{
		if ([currentObject isKindOfClass:[LDrawPart class]]
		   && [directiveNames indexOfObject:[currentObject referenceName]] == NSNotFound)
		{
			[directiveNames addObject:[currentObject referenceName]];
		}
	}
	return [directiveNames componentsJoinedByString:@","];
}


//---------- newlineSeparatedDisplayNamesFromDirectives: ------------[static]--
//
// Purpose:		Join browsing descriptions with newlines for the search-drop
//				string pasteboard.
//
//------------------------------------------------------------------------------
+ (NSString *)newlineSeparatedDisplayNamesFromDirectives:(NSArray *)directives
{
	// I love Cocoa.
	return [[directives valueForKey:@"displayName"] componentsJoinedByString:@"\n"];
}


//---------- searchDropPasteboardTypeFromOutline:fromPartBrowser: ----[static]--
//
// Purpose:		Parts can be dragged from the outline view or the part browser.
//				GLView drags remove the pieces once they leave the window, so
//				we ignore those.
//
//------------------------------------------------------------------------------
+ (NSString *)searchDropPasteboardTypeFromOutline:(BOOL)fromOutline
								  fromPartBrowser:(BOOL)fromPartBrowser
{
	// Outline View
	if (fromOutline) return LDrawDirectivePboardType;

	// Part browser
	if (fromPartBrowser) return LDrawDraggingPboardType;

	return nil;
}


//---------- commaSeparatedPartNamesFromArchivedDirectivesData: -------[static]--
//
// Purpose:		Someone wants to drop parts on the search panel. We don't want
//				to accept the drop, but we do want to know what parts they
//				wanted to drop on us.
//
//------------------------------------------------------------------------------
+ (NSString *)commaSeparatedPartNamesFromArchivedDirectivesData:(NSArray *)archivedDirectives
{
	if (archivedDirectives == nil || [archivedDirectives count] == 0)
		return nil;

	return [self commaSeparatedReferenceNamesFromDirectives:
			[LDrawClipboard unarchivedDirectivesFromDataArray:archivedDirectives]];
}

@end
