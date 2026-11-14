//==============================================================================
//
//  File:       LDrawLibraryInstallation.h
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    One run of an update. Not exported.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawLibraryRelease;

NS_ASSUME_NONNULL_BEGIN

/// The folder of an LDraw library that holds the release notes.
extern NSString * const LDrawLibraryModelsFolderName;

//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryInstallation
///
/// @abstract   Downloads the releases, unpacks them into a staging folder
///             inside the LDraw folder, then moves the files into place.
///
/// @discussion It works on the thread that runs it, and waits there for each
///             download. A file it replaces is kept in the staging folder
///             until every file is in, and put back when a move fails.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryInstallation : NSObject

- (instancetype) initWithReleases:(NSArray<LDrawLibraryRelease *> *)releases
						folderURL:(NSURL *)folderURL
					configuration:(NSURLSessionConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// The downloads and the unpacking. Canceling it stops the run until the
/// files are being put in place.
@property (nonatomic, readonly) NSProgress *progress;

/// Runs the update. Returns the names of the files that are new in "parts",
/// or nil and an error.
- (nullable NSArray<NSString *> *) install:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
