//==============================================================================
//
//  File:       LDrawLibraryUpdatePolicy.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    When a host looks for an update, and what it does with one.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <LDrawLibraryUpdate/LDrawLibraryUpdatePolicy.h>

#import <LDrawLibraryUpdate/LDrawLibraryRelease.h>

static const NSTimeInterval OneDay = 24 * 60 * 60;


@implementation LDrawLibraryUpdatePolicy

//---------- isLaunchCheckDueInMode:lastCheckDate:now: ---------------[static]--
//------------------------------------------------------------------------------
+ (BOOL) isLaunchCheckDueInMode:(LDrawLibraryUpdateMode)mode
				  lastCheckDate:(NSDate *)lastCheckDate
							now:(NSDate *)now
{
	NSTimeInterval age = 0;

	if (mode == LDrawLibraryUpdateModeNever)
		return NO;
	if (lastCheckDate == nil)
		return YES;

	age = [now timeIntervalSinceDate:lastCheckDate];
	return age < 0 || age >= OneDay;

}//end isLaunchCheckDueInMode:lastCheckDate:now:


//---------- actionForList:installed:mode:skippedRelease:askedByUser: [static]--
//------------------------------------------------------------------------------
+ (LDrawLibraryUpdateAction) actionForList:(LDrawLibraryReleaseList *)list
								 installed:(NSString *)installed
									  mode:(LDrawLibraryUpdateMode)mode
							skippedRelease:(NSString *)skippedRelease
							   askedByUser:(BOOL)askedByUser
{
	NSArray<LDrawLibraryRelease *>	*releases	= [list releasesToInstallAfter:installed];
	BOOL							 hasNewest	= (	installed != nil
												 &&	[installed compare:list.latestIdentifier] != NSOrderedAscending );

	if ([releases count] == 0 && askedByUser == NO)
		return LDrawLibraryUpdateActionNone;
	if ([releases count] == 0)
		return hasNewest ? LDrawLibraryUpdateActionUpToDate : LDrawLibraryUpdateActionNoArchive;
	if (askedByUser)
		return LDrawLibraryUpdateActionOffer;

	if ([skippedRelease isEqualToString:[LDrawLibraryRelease identifierReachedByReleases:releases]])
		return LDrawLibraryUpdateActionNone;

	if (mode == LDrawLibraryUpdateModeInstall && [[releases firstObject] isComplete] == NO)
		return LDrawLibraryUpdateActionInstall;
	return LDrawLibraryUpdateActionOffer;

}//end actionForReleases:mode:skippedRelease:askedByUser:

@end
