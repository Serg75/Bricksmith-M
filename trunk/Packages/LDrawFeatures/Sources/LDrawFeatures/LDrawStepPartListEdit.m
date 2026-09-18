//==============================================================================
//
//  File:       LDrawStepPartListEdit.m
//  Package:    LDrawFeatures
//
//  Purpose:    Decides what a committed frame resize does to the document.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListEdit.h>

#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>


/// Two widths closer than this count as the same width. Drags give continuous
/// values and the meta keeps four decimals, so an exact match would almost
/// never happen.
static const double INCHES_EPSILON = 0.0005;


@interface LDrawStepPartListEdit ()

@property (nonatomic, readwrite) LDrawStepPartListEditKind	kind;
@property (nonatomic, readwrite, nullable) LPubPliConstrain	*directiveToInsert;
@property (nonatomic, readwrite) NSUInteger					insertIndex;
@property (nonatomic, readwrite, nullable) LPubPliConstrain	*existingDirective;
@property (nonatomic, readwrite) LPubPliConstrainMode		targetMode;
@property (nonatomic, readwrite) double						targetInches;
@property (nonatomic, readwrite, copy) NSString				*undoActionKey;
@property (nonatomic, readwrite) BOOL						resetsAxis;

@end


@implementation LDrawStepPartListEdit

//---------- editSettingAxis:toInches:inStep:inheritedInches: --------[static]--
///
/// @abstract	The edit that pins one axis of a step's frame to a size.
///
//------------------------------------------------------------------------------
+ (instancetype) editSettingAxis:(LPubPliAxis)axis
						toInches:(double)inches
						  inStep:(LDrawStep *)step
				 inheritedInches:(double)inheritedInches
{
	LDrawStepPartListEdit	*edit		= [LDrawStepPartListEdit new];
	LPubPliConstrain		*existing	= [LDrawStepPartListPolicy constrainDirectiveInStep:step];

	edit.existingDirective	= existing;
	edit.undoActionKey		= @"UndoStepPartListResize";

	LPubPliConstrainMode mode = LPubPliConstrainModeForAxis(axis);

	// Asking for the inherited size: drop the step's own line instead of
	// writing one that says nothing. The inherited line pins this axis, so it
	// applies once the step's line is gone, whatever that line pinned.
	BOOL matchesInherited = (inheritedInches > 0.0)
						 && (fabs(inches - inheritedInches) < INCHES_EPSILON);

	if (matchesInherited) {
		// An earlier line of the step's own can still pin this axis.
		LPubPliConstrain *remainingDirective = [LDrawStepPartListPolicy constrainDirectiveInStep:step
																					   excluding:existing];

		edit.kind = (existing != nil) ? LDrawStepPartListEditKindRemove : LDrawStepPartListEditKindNone;

		if (remainingDirective == nil || remainingDirective.mode != mode) {
			edit.undoActionKey	= @"UndoStepPartListResetSize";
			edit.resetsAxis		= YES;
		}
		return edit;
	}

	edit.targetMode		= mode;
	edit.targetInches	= inches;

	if (existing != nil) {
		// Already the same line, so record nothing. Otherwise every mouse-up
		// would put a no-op on the undo stack.
		if (existing.mode == mode
			&& existing.scope == LPubMetaScopeLocal
			&& fabs((double)existing.inches - inches) < INCHES_EPSILON) {
			edit.kind = LDrawStepPartListEditKindNone;
			return edit;
		}

		// WIDTH and HEIGHT cannot both apply, so the one directive changes
		// mode instead of a second one appearing beside it.
		edit.kind = LDrawStepPartListEditKindUpdate;
		return edit;
	}

	LPubPliConstrain *directive = [LPubPliConstrain new];

	directive.scope		= LPubMetaScopeLocal;
	directive.mode		= mode;
	directive.inches	= inches;

	edit.kind				= LDrawStepPartListEditKindInsert;
	edit.directiveToInsert	= directive;
	edit.insertIndex		= [self indexAfterLastConstrainInStep:step];

	return edit;

}//end editSettingAxis:toInches:inStep:inheritedInches:


//---------- editForDraggingAxis:toInches:inModel: -------------------[static]--
///
/// @abstract	The edit a resize drag on the visible step would make if it
/// 			ended at this size.
///
//------------------------------------------------------------------------------
+ (instancetype) editForDraggingAxis:(LPubPliAxis)axis
							toInches:(double)inches
							 inModel:(nullable LDrawModel *)model
{
	double inherited = [LDrawStepPartListPolicy inheritedInchesForAxis:axis inModel:model];

	return [self editSettingAxis:axis
						toInches:inches
						  inStep:[model visibleStep]
				 inheritedInches:inherited];

}//end editForDraggingAxis:toInches:inModel:


//---------- editClearingAxis:inStep: --------------------------------[static]--
///
/// @abstract	The edit that removes the step's own pin on one axis.
///
//------------------------------------------------------------------------------
+ (instancetype) editClearingAxis:(LPubPliAxis)axis inStep:(LDrawStep *)step
{
	LDrawStepPartListEdit *edit = [LDrawStepPartListEdit new];

	edit.existingDirective	= [LDrawStepPartListPolicy constrainDirectiveInStep:step];
	edit.undoActionKey		= @"UndoStepPartListResetSize";
	edit.resetsAxis			= YES;

	// Only the axis being cleared. A directive pinning the other one stays.
	edit.kind = [LDrawStepPartListPolicy isAxis:axis pinnedInStep:step]
			  ? LDrawStepPartListEditKindRemove
			  : LDrawStepPartListEditKindNone;

	return edit;

}//end editClearingAxis:inStep:


//---------- indexAfterLastConstrainInStep: --------------------------[static]--
///
/// @abstract	The index just after the step's last CONSTRAIN, or 0 when it
/// 			has none.
///
//------------------------------------------------------------------------------
+ (NSUInteger) indexAfterLastConstrainInStep:(LDrawStep *)step
{
	NSArray		*directives	= [step subdirectives];
	NSUInteger	 index		= 0;

	for (NSUInteger counter = 0; counter < [directives count]; counter++) {
		if ([directives[counter] isKindOfClass:[LPubPliConstrain class]]) {
			index = counter + 1;
		}
	}

	return index;

}//end indexAfterLastConstrainInStep:


@end
