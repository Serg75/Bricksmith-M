//==============================================================================
//
//  File:       LDrawStructure+Insertion.m
//  Package:    LDrawEditing
//
//  Purpose:    Directive insertion and step-wrapping rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>


@implementation LDrawStructure (Insertion)

//---------- insertionParentForDirective:selectedContainer:visibleStep:[static]
//
// Purpose:		Adds newDirective to the bottom of the current step, or after
//				the currently-selected element in the step if there is one.
//				We may have the model itself selected, in which case we add this
//				new element to the very bottom of the model. Prefer an
//				"interesting" selected container that accepts the directive;
//				otherwise the last visible step.
//
//------------------------------------------------------------------------------
+ (LDrawContainer *)insertionParentForDirective:(LDrawDirective *)directive
							  selectedContainer:(LDrawContainer *)selectedContainer
									visibleStep:(LDrawContainer *)visibleStep
{
	if (	selectedContainer != nil
	   &&	[selectedContainer isKindOfClass:[LDrawFile class]] == NO
	   &&	[selectedContainer isKindOfClass:[LDrawModel class]] == NO
	   &&	[selectedContainer isKindOfClass:[LDrawStep class]] == NO
	   &&	[selectedContainer acceptsDroppedDirective:directive] == YES)
	{
		return selectedContainer;
	}
	return visibleStep;
}


//---------- wrappedStepIndex:byDelta:stepCount: ---------------------[static]--
//
// Purpose:		Moves the step display forward or back, wrapping at the ends.
//
// Notes:		Wrap around? In C, the remainder of a negative dividend is
//				negative, so stepping back from 0 cannot use a raw `%`.
//
//------------------------------------------------------------------------------
+ (NSInteger)wrappedStepIndex:(NSInteger)current
					  byDelta:(NSInteger)delta
					stepCount:(NSInteger)count
{
	if (count <= 0) return 0;
	return ((current + delta) % count + count) % count;
}

@end
