//==============================================================================
//
//  File:       LDrawLibraryZipReader.h
//  Package:    LDrawLibraryUpdate
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryZipEntry
///
/// @abstract   One file or folder of a zip archive.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryZipEntry : NSObject

/// The path as the archive spells it, with "/" between the parts. A folder's
/// ends with "/".
@property (nonatomic, readonly, copy) NSString *path;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryZipReader
///
/// @abstract   Lists a zip archive's entries and unpacks them one at a time.
///
/// @discussion Reads stored and deflated entries, and archives in the zip64
///             format. It writes only where it is told to: an entry's path is
///             never used as a place on disk.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryZipReader : NSObject

- (nullable instancetype) initWithFileURL:(NSURL *)fileURL error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSArray<LDrawLibraryZipEntry *> *entries;

/// Unpacks the entry into a new file, and checks its size and CRC. After an
/// error no file is left.
- (BOOL) writeEntry:(LDrawLibraryZipEntry *)entry toURL:(NSURL *)fileURL error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
