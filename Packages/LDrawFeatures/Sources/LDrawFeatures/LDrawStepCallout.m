//==============================================================================
//
//  File:       LDrawStepCallout.m
//  Package:    LDrawFeatures
//
//  Purpose:    Collects the callouts of a step.
//
//  Notes:      The step's directives are walked in order, because a callout is
//              whatever lies between its BEGIN and END lines.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepCallout.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawCore/LPubAssemShowStepNumber.h>
#import <LDrawCore/LPubCalloutAlloc.h>
#import <LDrawCore/LPubCalloutPliPerStep.h>
#import <LDrawCore/LPubCalloutPointer.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawCore/LPubPliIgnore.h>
#import <LDrawCore/LPubPliSubstitute.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>

#import "LDrawStepPartListInternal.h"


@interface LDrawStepCallout ()

@property (nonatomic, readwrite) LPubCallout			*beginDirective;
@property (nonatomic, readwrite, nullable) LPubCallout	*endDirective;
@property (nonatomic, readwrite, nullable) LPubPlacement *placement;

@end


//========== IsBuilt() =========================================================
///
/// @abstract	Whether a line of a step is a part, a hose or a band that is
/// 			built. One a REMOVE GROUP in force drops is not.
///
//==============================================================================
static BOOL IsBuilt(LDrawDirective *directive)
{
	if ([directive isKindOfClass:[LDrawPart class]] == NO && [directive isKindOfClass:[LDrawLSynth class]] == NO) {
		return NO;
	}

	return [LDrawStepPartList isBuiltDirective:directive];

}//end IsBuilt


//========== IsDividerPointer() ================================================
///
/// @abstract	Whether a line is an arrow of a divider, or says how one is
/// 			drawn. Bricksmith reads neither, so both are plain LPub lines.
///
//==============================================================================
static BOOL IsDividerPointer(LDrawDirective *directive)
{
	if ([directive isMemberOfClass:[LPubCommand class]] == NO) {
		return NO;
	}

	NSArray<NSString *> *words = [(LPubCommand *)directive lPubCommandWords];

	return words.count >= 2
		&& [words[0] isEqualToString:LPUB_CALLOUT]
		&& [words[1] hasPrefix:LPUB_CALLOUT_DIVIDER_POINTER];

}//end IsDividerPointer


@implementation LDrawStepCallout
{
	NSMutableArray<LDrawStepPartListEntry *>	*_entries;
	NSMutableArray<LDrawModel *>				*_submodels;
	NSMutableArray<LDrawPart *>					*_placements;
	NSMutableArray<LPubCalloutPointer *>		*_pointers;

	/// The LPub lines between the callout's two lines, in file order.
	NSMutableArray<LDrawDirective *>			*_ownLines;

	/// The step's LPub lines before BEGIN that are in no other callout.
	NSHashTable<LDrawDirective *>				*_linesBefore;

	/// Worked out when first asked for.
	NSArray<LDrawStepPartListEntry *>			*_partEntries;
}


// MARK: - COLLECTING -


//---------- calloutsForStep: ----------------------------------------[static]--
///
/// @abstract	The callouts of a step that place at least one submodel.
///
/// @discussion	A BEGIN inside an open callout starts a new one, and an END with
/// 			nothing open does nothing. LPub3D reports both as mistakes.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepCallout *> *) calloutsForStep:(nullable LDrawStep *)step
{
	NSMutableArray<LDrawStepCallout *>	*callouts	= [NSMutableArray array];
	LDrawStepCallout					*open		= nil;
	NSHashTable<LDrawDirective *>		*outside	= nil;

	// The step's LPub lines so far that are in no callout.
	outside = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];

	for (LDrawDirective *directive in [LDrawStepPartList flattenedDirectives:[step subdirectives]]) {

		if ([directive isKindOfClass:[LPubCallout class]]) {
			LPubCallout *bracket = (LPubCallout *)directive;

			if (bracket.line == LPubCalloutLineBegin) {
				[self addCallout:open toCallouts:callouts];
				open = [[LDrawStepCallout alloc] initWithBeginDirective:bracket step:step];
				open->_linesBefore = [outside copy];
			}
			else if (bracket.line == LPubCalloutLineEnd) {
				open.endDirective = bracket;
				[self addCallout:open toCallouts:callouts];
				open = nil;
			}
			continue;
		}

		if ([directive isKindOfClass:[LPubCommand class]]) {
			if (open != nil) {
				[open->_ownLines addObject:directive];
			}
			else {
				[outside addObject:directive];
			}
		}

		if (open == nil) {
			continue;
		}

		if ([directive isKindOfClass:[LPubCalloutPointer class]]) {
			[open->_pointers addObject:(LPubCalloutPointer *)directive];
		}
		else if ([directive isKindOfClass:[LPubPlacement class]]) {
			LPubPlacement *placement = (LPubPlacement *)directive;

			// An assembly's PLACEMENT between the two lines is not the box's.
			if (placement.branch == LPubPlacementBranchCallout) {
				open.placement = placement;
			}
		}
		else if ([directive isKindOfClass:[LDrawPart class]] && [LDrawStepPartList isBuiltDirective:directive]) {
			[open addPlacement:(LDrawPart *)directive];
		}
	}

	// A callout that never closes still holds what came after its BEGIN.
	[self addCallout:open toCallouts:callouts];

	return callouts;

}//end calloutsForStep:


//---------- calloutsForVisibleStepOfModel: --------------------------[static]--
///
/// @abstract	The callouts of the step the model has on display.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepCallout *> *) calloutsForVisibleStepOfModel:(nullable LDrawModel *)model
{
	if (model == nil) {
		return @[];
	}

	// Which parts a REMOVE GROUP drops depends on the step on display.
	[model updateGroupSuppressionIfNeeded];

	return [self calloutsForStep:[model visibleStep]];

}//end calloutsForVisibleStepOfModel:


//---------- addCallout:toCallouts: ----------------------------------[static]--
///
/// @abstract	Keeps a finished callout, unless it places no submodel.
///
//------------------------------------------------------------------------------
+ (void) addCallout:(nullable LDrawStepCallout *)callout
		 toCallouts:(NSMutableArray<LDrawStepCallout *> *)callouts
{
	if (callout != nil && callout.placements.count > 0) {
		[callouts addObject:callout];
	}

}//end addCallout:toCallouts:


// MARK: - INITIALIZATION -


//========== initWithBeginDirective:step: ======================================
- (instancetype) initWithBeginDirective:(LPubCallout *)beginDirective step:(LDrawStep *)step
{
	self = [super init];
	if (self) {
		self->_beginDirective	= beginDirective;
		self->_step				= step;
		self->_entries			= [NSMutableArray array];
		self->_submodels		= [NSMutableArray array];
		self->_placements		= [NSMutableArray array];
		self->_pointers			= [NSMutableArray array];
		self->_ownLines			= [NSMutableArray array];
	}
	return self;

}//end initWithBeginDirective:step:


// MARK: - ACCESSORS -


- (LPubCalloutMode) mode
{
	return self.beginDirective.mode;
}

- (NSArray<LDrawStepPartListEntry *> *) entries
{
	return [self->_entries copy];
}

- (NSArray<LDrawModel *> *) submodels
{
	return [self->_submodels copy];
}

- (NSArray<LDrawPart *> *) placements
{
	return [self->_placements copy];
}

- (NSArray<LPubCalloutPointer *> *) pointers
{
	return [self->_pointers copy];
}

- (NSArray<LDrawDirective *> *) ownLines
{
	return [self->_ownLines copy];
}


//========== directiveInForceMatching: =========================================
///
/// @abstract	The line of one kind in force for this callout, or nil.
///
/// @discussion	LPub3D reads the lines between a callout's two lines into the
/// 			callout alone, so they win here and do not reach another callout
/// 			of the step. They do carry to later steps, like any line.
///
//==============================================================================
- (nullable __kindof LDrawDirective *) directiveInForceMatching:(BOOL (NS_NOESCAPE ^)(LDrawDirective *))predicate
{
	for (LDrawDirective *line in [self->_ownLines reverseObjectEnumerator]) {
		if (predicate(line)) {
			return line;
		}
	}

	LDrawStep						*step	= self->_step;
	NSHashTable<LDrawDirective *>	*before	= self->_linesBefore;

	return [LDrawStepPartListPolicy directiveInForceForStep:step
												  excluding:nil
												   matching:^BOOL(LDrawDirective *directive) {
		// Of this step's lines, only those ahead of the callout count.
		if ([directive enclosingDirective] == step && [before containsObject:directive] == NO) {
			return NO;
		}
		return predicate(directive);
	}];

}//end directiveInForceMatching:


//========== isVertical ========================================================
///
/// @abstract	Whether the steps in the box run down.
///
//==============================================================================
- (BOOL) isVertical
{
	LPubCalloutAlloc *alloc = [self directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutAlloc class]];
	}];

	return (alloc == nil) ? YES : alloc.isVertical;

}//end isVertical


//========== showsStepNumbers ==================================================
- (BOOL) showsStepNumbers
{
	LPubAssemShowStepNumber *shown = [self directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubAssemShowStepNumber class]];
	}];

	return (shown == nil) ? YES : shown.isShown;

}//end showsStepNumbers


//========== listsOwnParts =====================================================
- (BOOL) listsOwnParts
{
	// With no PER_STEP line in force each step in the box lists its own
	// parts, as in LPub3D.
	LPubCalloutPliPerStep *perStep = [self directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutPliPerStep class]];
	}];

	return self.mode == LPubCalloutModeUnassembled
		&& self->_step != nil
		&& (perStep == nil || perStep.isPerStep);

}//end listsOwnParts


//========== partEntries =======================================================
- (NSArray<LDrawStepPartListEntry *> *) partEntries
{
	if (self->_partEntries != nil) {
		return self->_partEntries;
	}

	self->_partEntries = @[];

	if (self.listsOwnParts) {
		self->_partEntries = [LDrawStepPartList entriesForSubmodelsPlacedByParts:self->_placements
																		 inModel:[self->_step enclosingModel]];
	}

	return self->_partEntries;

}//end partEntries


//========== stepCount =========================================================
///
/// @abstract	How many steps of the submodels build something.
///
/// @discussion	A model always ends with a step, so the blank one after the last
/// 			STEP line is not counted.
///
//==============================================================================
- (NSUInteger) stepCount
{
	NSUInteger count = 0;

	// A submodel placed in two colors has two rows, and its steps count once.
	for (LDrawModel *submodel in [NSOrderedSet orderedSetWithArray:self->_submodels]) {
		for (LDrawStep *step in [submodel steps]) {
			if ([LDrawStepCallout stepBuildsSomething:step]) {
				count += 1;
			}
		}
	}

	return count;

}//end stepCount


// MARK: - UTILITIES -


//========== addPlacement: =====================================================
///
/// @abstract	Counts a part that places a submodel. Nothing for any other
/// 			part, and for a submodel that is really a part.
///
//==============================================================================
- (void) addPlacement:(LDrawPart *)part
{
	LDrawModel *submodel = [LDrawStepPartList assemblyPlacedByPart:part];

	if (submodel == nil) {
		return;
	}

	[self->_placements addObject:part];

	// A row is measured once, not once for each placement.
	NSUInteger index = [self indexOfEntryWithKey:[LDrawStepPartList rowKeyOfPlacement:part]];

	if (index == NSNotFound) {
		[self->_entries addObject:[LDrawStepPartList entryForSubmodel:submodel
																named:[part referenceName]
																color:[part LDrawColor]]];
		[self->_submodels addObject:submodel];
	}
	else {
		self->_entries[index] = [self->_entries[index] entryByAddingInstance];
	}

}//end addPlacement:


//========== indexOfEntryWithKey: ==============================================
- (NSUInteger) indexOfEntryWithKey:(NSString *)key
{
	return [self->_entries indexOfObjectPassingTest:^BOOL(LDrawStepPartListEntry *entry, NSUInteger index, BOOL *stop) {
		return [entry.groupKey isEqualToString:key];
	}];

}//end indexOfEntryWithKey:


//---------- stepBuildsSomething: ------------------------------------[static]--
///
/// @abstract	Whether a step holds a part, a hose or a band that is built.
///
//------------------------------------------------------------------------------
+ (BOOL) stepBuildsSomething:(LDrawStep *)step
{
	for (LDrawDirective *directive in [LDrawStepPartList flattenedDirectives:[step subdirectives]]) {
		if (IsBuilt(directive)) {
			return YES;
		}
	}
	return NO;

}//end stepBuildsSomething:


// MARK: - DIVIDERS -


//---------- stepShownBeforeStep: ------------------------------------[static]--
///
/// @abstract	The nearest earlier step of the same model that builds
/// 			something, or nil.
///
//------------------------------------------------------------------------------
+ (nullable LDrawStep *) stepShownBeforeStep:(LDrawStep *)step
{
	NSArray<LDrawStep *>	*steps	= [[step enclosingModel] steps];
	NSUInteger				 index	= [steps indexOfObjectIdenticalTo:step];

	if (index == NSNotFound) {
		return nil;
	}

	while (index > 0) {
		index -= 1;

		if ([self stepBuildsSomething:steps[index]]) {
			return steps[index];
		}
	}

	return nil;

}//end stepShownBeforeStep:


//---------- dividerLinesBeforeStep: ---------------------------------[static]--
///
/// @abstract	The lines that put a divider before a step of a called-out
/// 			submodel.
///
/// @discussion	LPub3D reads a model line by line, and a DIVIDER line ends the
/// 			column or row of the step it is reading. So a line counts from
/// 			the first thing built in the step shown before, through any
/// 			steps that build nothing, up to the first thing built here.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawDirective *> *) dividerLinesBeforeStep:(LDrawStep *)step
{
	LDrawStep *before = [self stepShownBeforeStep:step];

	if (before == nil) {
		return @[];
	}

	NSArray<LDrawStep *>				*steps		= [[step enclosingModel] steps];
	NSUInteger							 first		= [steps indexOfObjectIdenticalTo:before];
	NSUInteger							 last		= [steps indexOfObjectIdenticalTo:step];
	NSMutableArray<LDrawDirective *>	*lines		= [NSMutableArray array];
	BOOL								 hasDivider	= NO;

	for (NSUInteger index = first; index <= last; index++) {
		BOOL hasBuilt = NO;

		for (LDrawDirective *directive in [LDrawStepPartList flattenedDirectives:[steps[index] subdirectives]]) {
			if (IsBuilt(directive)) {
				if (index == last) {
					break;
				}
				hasBuilt = YES;
			}
			else if (index == first && hasBuilt == NO) {
				// Before anything is built there, a line belongs to the
				// step before that one.
				continue;
			}
			else if ([directive isKindOfClass:[LPubCallout class]]) {
				if (((LPubCallout *)directive).line == LPubCalloutLineDivider) {
					[lines addObject:directive];
					hasDivider = YES;
				}
			}
			else if (IsDividerPointer(directive)) {
				[lines addObject:directive];
			}
		}
	}

	return hasDivider ? lines : @[];

}//end dividerLinesBeforeStep:



// MARK: - THE PARTS LIST'S ROWS -


//---------- placementsOfEntry:inStep: -------------------------------[static]--
///
/// @abstract	The parts of a step that a submodel's row counts, in file order:
/// 			each places that submodel, in that color, with steps to show.
///
/// @discussion	A placement inside a callout or an ignored range is no part of
/// 			the row. Neither is one inside a group, which cannot be put
/// 			between two lines of the step.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawPart *> *) placementsOfEntry:(LDrawStepPartListEntry *)entry inStep:(nullable LDrawStep *)step
{
	NSMutableArray<LDrawPart *>	*placements			= [NSMutableArray array];
	NSInteger					 listIgnoreDepth	= 0;
	NSInteger					 partIgnoreDepth	= 0;
	BOOL						 isInCallout		= NO;

	if (entry.isSubmodel == NO) {
		return placements;
	}

	for (LDrawDirective *directive in [step subdirectives]) {

		// PLI BEGIN IGN and PLI BEGIN SUB share one END. PART BEGIN IGN has
		// its own.
		if ([directive isKindOfClass:[LPubPliSubstitute class]]) {
			listIgnoreDepth += 1;
			continue;
		}

		if ([directive isKindOfClass:[LPubPliIgnore class]]) {
			LPubPliIgnore	*bracket	= (LPubPliIgnore *)directive;
			NSInteger		 change		= bracket.beginsRange ? 1 : -1;

			if (bracket.branch == LPubPliIgnoreBranchPart) {
				partIgnoreDepth = MAX(partIgnoreDepth + change, 0);
			}
			else {
				listIgnoreDepth = MAX(listIgnoreDepth + change, 0);
			}
			continue;
		}

		if ([directive isKindOfClass:[LPubCallout class]]) {
			LPubCalloutLine line = ((LPubCallout *)directive).line;

			if (line == LPubCalloutLineBegin) {
				isInCallout = YES;
			}
			else if (line == LPubCalloutLineEnd) {
				isInCallout = NO;
			}
			continue;
		}

		if (isInCallout || listIgnoreDepth > 0 || partIgnoreDepth > 0
			|| [directive isKindOfClass:[LDrawPart class]] == NO
			|| [LDrawStepPartList isBuiltDirective:directive] == NO) {
			continue;
		}

		LDrawPart *part = (LDrawPart *)directive;

		if ([LDrawStepPartList assemblyPlacedByPart:part] != nil
			&& [[LDrawStepPartList rowKeyOfPlacement:part] isEqualToString:entry.groupKey]) {
			[placements addObject:part];
		}
	}

	return placements;

}//end placementsOfEntry:inStep:


@end
