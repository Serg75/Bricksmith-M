//==============================================================================
//
//  File:       LDrawLibraryUpdatePolicy.h
//  Package:    LDrawLibraryUpdate
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawLibraryReleaseList;

NS_ASSUME_NONNULL_BEGIN

/// How a host keeps the LDraw folder up to date at launch. Hosts save it in
/// their defaults, so the values stay as they are.
typedef NS_ENUM(NSInteger, LDrawLibraryUpdateMode)
{
	LDrawLibraryUpdateModeNever		= 0,	// does not look for an update
	LDrawLibraryUpdateModeAsk		= 1,	// asks before installing one
	LDrawLibraryUpdateModeInstall	= 2,	// installs it
};

/// What a host does once it has the list of releases.
typedef NS_ENUM(NSInteger, LDrawLibraryUpdateAction)
{
	LDrawLibraryUpdateActionNone		= 0,	// says nothing
	LDrawLibraryUpdateActionUpToDate	= 1,	// says the folder has the newest update
	LDrawLibraryUpdateActionOffer		= 2,	// offers the releases the folder needs
	LDrawLibraryUpdateActionInstall		= 3,	// installs them without asking
	LDrawLibraryUpdateActionNoArchive	= 4,	// says no zip archive reaches the newest update
};

//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryUpdatePolicy
///
/// @abstract   When a host looks for an update of the LDraw folder, and what
///             it does with one it finds.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryUpdatePolicy : NSObject

/// Whether a launch looks for an update: never in LDrawLibraryUpdateModeNever,
/// else at most once a day. A check date in the future is no reason to wait.
+ (BOOL) isLaunchCheckDueInMode:(LDrawLibraryUpdateMode)mode
				  lastCheckDate:(nullable NSDate *)lastCheckDate
							now:(NSDate *)now
	NS_SWIFT_NAME(isLaunchCheckDue(mode:lastCheckDate:now:));

/// What to do for a folder that holds the `installed` update, given the list.
/// The releases it needs are `[list releasesToInstallAfter:installed]`.
///
/// A check the user asked for offers any, and otherwise says why there are
/// none. A check at launch says nothing when there are none or they reach the
/// skipped release. In LDrawLibraryUpdateModeInstall it installs them, except
/// the complete library, which is always offered: it replaces every file in
/// the folder.
+ (LDrawLibraryUpdateAction) actionForList:(LDrawLibraryReleaseList *)list
								 installed:(nullable NSString *)installed
									  mode:(LDrawLibraryUpdateMode)mode
							skippedRelease:(nullable NSString *)skippedRelease
							   askedByUser:(BOOL)askedByUser
	NS_SWIFT_NAME(action(for:installed:mode:skippedRelease:askedByUser:));

@end

NS_ASSUME_NONNULL_END
