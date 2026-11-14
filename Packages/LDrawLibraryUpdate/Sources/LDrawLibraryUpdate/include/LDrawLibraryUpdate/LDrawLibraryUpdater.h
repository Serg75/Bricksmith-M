//==============================================================================
//
//  File:       LDrawLibraryUpdater.h
//  Package:    LDrawLibraryUpdate
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawLibraryRelease;
@class LDrawLibraryReleaseList;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryUpdater
///
/// @abstract   Brings an LDraw folder up to date with the releases of LDraw's
///             part library.
///
/// @discussion An update writes the files its archives hold under "ldraw/",
///             over the folder's own. It removes nothing, and leaves the
///             "Unofficial" folder alone. The files are put in place only once
///             every archive has come and unpacked, and are taken back out when
///             that fails, so after an error or a cancel the folder holds the
///             old files. One run at a time can update a folder: it is locked
///             for the run.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryUpdater : NSObject

@property (nonatomic, readonly, copy) NSURL *folderURL;

/// The URL session's configuration. Default `defaultSessionConfiguration`.
@property (nonatomic, copy) NSURLSessionConfiguration *sessionConfiguration;

- (instancetype) initWithFolderURL:(NSURL *)folderURL NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// The newest update a folder holds, such as "2026-10", or nil. Every update
/// leaves its release notes in "models", and this reads their names.
+ (nullable NSString *) installedReleaseInFolderURL:(NSURL *)folderURL
	NS_SWIFT_NAME(installedRelease(inFolder:));

/// Asks the server for the list of releases. The completion comes on
/// `completionQueue` (main when nil).
- (void) fetchReleaseListWithCompletionQueue:(nullable dispatch_queue_t)completionQueue
								  completion:(void (^)(LDrawLibraryReleaseList * _Nullable list,
													   NSError * _Nullable error))completion
	NS_SWIFT_NAME(fetchReleaseList(completionQueue:completion:));

/// Downloads the releases and writes their files into the folder, in the
/// order given. The completion gets the names of the files that are new in
/// "parts", such as "3001.dat", or an error, on `completionQueue` (main when
/// nil). Cancel through the progress, which works until the files are being
/// put in place.
- (NSProgress *) installReleases:(NSArray<LDrawLibraryRelease *> *)releases
				 completionQueue:(nullable dispatch_queue_t)completionQueue
					  completion:(void (^)(NSArray<NSString *> *addedPartNames, NSError * _Nullable error))completion
	NS_SWIFT_NAME(install(_:completionQueue:completion:));

@end

NS_ASSUME_NONNULL_END
