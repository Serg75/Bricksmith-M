//==============================================================================
//
//  File:       LDrawLibraryRelease.h
//  Package:    LDrawLibraryUpdate
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryRelease
///
/// @abstract   One archive of LDraw's part library: a parts update, or the
///             complete library.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryRelease : NSObject

/// The update's year and number, such as "2026-10". For the complete library,
/// the newest update it holds.
@property (nonatomic, readonly, copy) NSString *identifier;

@property (nonatomic, readonly, copy) NSURL *URL;

/// The archive's size.
@property (nonatomic, readonly) int64_t byteCount;

/// The archive's MD5, in lowercase hex.
@property (nonatomic, readonly, copy) NSString *md5;

/// Whether this is the complete library and not one update.
@property (nonatomic, readonly, getter=isComplete) BOOL complete;

- (instancetype) init NS_UNAVAILABLE;

/// The size of the archives together.
+ (int64_t) byteCountOfReleases:(NSArray<LDrawLibraryRelease *> *)releases NS_SWIFT_NAME(byteCount(of:));

/// The update that installing the releases, oldest first, brings a folder to:
/// the last one's. Nil for none.
+ (nullable NSString *) identifierReachedByReleases:(NSArray<LDrawLibraryRelease *> *)releases
	NS_SWIFT_NAME(identifierReached(by:));

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryReleaseList
///
/// @abstract   LDraw's list of its releases, read from the tab-separated text
///             the library's server gives.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryReleaseList : NSObject

/// Nil when the text names no complete library.
- (nullable instancetype) initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// The updates that come as zip archives, oldest first.
@property (nonatomic, readonly, copy) NSArray<LDrawLibraryRelease *> *updates;

@property (nonatomic, readonly) LDrawLibraryRelease *complete;

/// The newest update, such as "2026-10", of the complete library and the
/// updates.
@property (nonatomic, readonly, copy) NSString *latestIdentifier;

/// What brings a folder that holds the `installed` update up to date: the
/// updates after it, oldest first, or nothing when it has the newest. The
/// complete library takes their place when `installed` is nil, when an update
/// in between has no zip archive, or when the updates are the bigger download.
/// When the complete library is older than the newest update, the updates
/// after it follow it.
- (NSArray<LDrawLibraryRelease *> *) releasesToInstallAfter:(nullable NSString *)installed
	NS_SWIFT_NAME(releasesToInstall(after:));

@end

NS_ASSUME_NONNULL_END
