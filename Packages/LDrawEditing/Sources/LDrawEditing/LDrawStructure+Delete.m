//==============================================================================
//
//  File:       LDrawStructure+Delete.m
//  Package:    LDrawEditing
//
//  Purpose:    Delete eligibility and ordering rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>


@implementation LDrawStructure (Delete)

//---------- deleteRefusalForDirective: ------------------------------[static]--
//
// Purpose:		Tests whether the specified directive should be allowed to be
//				deleted. The last remaining model or step in its parent cannot
//				be deleted. The host still displays the error sheet.
//
//------------------------------------------------------------------------------
+ (LDrawDeleteRefusal)deleteRefusalForDirective:(LDrawDirective *)directive
{
	LDrawContainer *parentDirective = [directive enclosingDirective];
	BOOL isLastDirective = ([[parentDirective subdirectives] count] <= 1);

	if ([directive isKindOfClass:[LDrawModel class]] && isLastDirective == YES)
	{
		return LDrawDeleteLastModel;
	}
	if ([directive isKindOfClass:[LDrawStep class]] && isLastDirective == YES)
	{
		return LDrawDeleteLastStep;
	}
	return LDrawDeleteAllowed;
}


//---------- deleteRefusalInformativeKey: ---------------------------[static]--
//
// Purpose:		Localization key explaining why a delete was refused (last model
//				or last step). Returns nil when the delete is allowed. The host
//				still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)deleteRefusalInformativeKey:(LDrawDeleteRefusal)refusal
{
	if (refusal == LDrawDeleteAllowed) return nil;
	if (refusal == LDrawDeleteLastModel) return @"DeleteLastModelInformative";
	return @"DeleteLastStepInformative";
}


//---------- directivesInReverseDeletionOrder: -----------------------[static]--
//
// Purpose:		We'll just try to delete everything. Count backwards so that if
//				a deletion fails, it's the thing at the top rather than the
//				bottom that remains. The host still checks can-delete and
//				deletes (undo).
//
//------------------------------------------------------------------------------
+ (NSArray *)directivesInReverseDeletionOrder:(NSArray *)directives
{
	return [[directives reverseObjectEnumerator] allObjects];
}


//---------- deleteDirectiveErrorMessageKey --------------------------[static]--
//
// Purpose:		Format key for the delete-refusal alert (takes
//				browsingDescription). The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)deleteDirectiveErrorMessageKey
{
	return @"DeleteDirectiveError";
}

@end
