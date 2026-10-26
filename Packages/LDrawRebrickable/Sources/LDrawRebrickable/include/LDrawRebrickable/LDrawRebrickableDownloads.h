//==============================================================================
//
//  File:       LDrawRebrickableDownloads.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableDownloads
///
/// @abstract   Keeps Rebrickable's CSV downloads in a folder, and fetches them
///             again when they change.
///
/// @discussion Rebrickable's terms allow automated downloads at most once a
///             day, so a file asked for within a day is not asked for again,
///             unless forced. A request carries the file's last ETag and
///             date, so a file that has not changed is not sent again.
///
///             The folder holds `<name>.csv.gz` for each file, and
///             `downloads.json` with when each was asked for.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableDownloads : NSObject

@property (nonatomic, readonly, copy) NSURL *folderURL;

/// Where the files come from. Default
/// https://cdn.rebrickable.com/media/downloads/
@property (nonatomic, copy) NSURL *baseURL;

/// The session's configuration. Tests give one with a stub protocol.
@property (nonatomic, copy) NSURLSessionConfiguration *sessionConfiguration;

/// How long after asking for a file it is not asked for again. Default a day.
@property (nonatomic) NSTimeInterval minimumCheckInterval;

- (instancetype) initWithFolderURL:(NSURL *)folderURL NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// The files the catalog, the set list and set imports read.
+ (NSArray<NSString *> *) catalogFileNames;

/// Where a file is kept, e.g. `<folder>/sets.csv.gz`.
- (NSURL *) localURLForFileNamed:(NSString *)name;

- (BOOL) hasFilesNamed:(NSArray<NSString *> *)names NS_SWIFT_NAME(hasFiles(named:));

/// When the server was last asked for the file, or nil.
- (nullable NSDate *) checkDateForFileNamed:(NSString *)name;

/// The date the server gave the file, or nil.
- (nullable NSDate *) dataDateForFileNamed:(NSString *)name;

/// Fetches the files one after another. A file asked for within
/// `minimumCheckInterval` is skipped, unless `force`. The completion gets the
/// names of the files that changed, or an error, on `completionQueue` (main
/// when nil). Cancel through the progress.
- (NSProgress *) updateFilesNamed:(NSArray<NSString *> *)names
							force:(BOOL)force
				  completionQueue:(nullable dispatch_queue_t)completionQueue
					   completion:(void (^)(NSArray<NSString *> *changedNames, NSError * _Nullable error))completion
	NS_SWIFT_NAME(updateFiles(named:force:completionQueue:completion:));

@end

NS_ASSUME_NONNULL_END
