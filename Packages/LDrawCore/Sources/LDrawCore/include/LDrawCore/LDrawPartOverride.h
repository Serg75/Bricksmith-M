//==============================================================================
//
//  File:       LDrawPartOverride.h
//  Package:    LDrawCore
//
//  Purpose:    A part in the overrides folder, and whether the library has a
//              newer version of it.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawPaths;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartOverride
///
/// @abstract   A part in the overrides folder, which Bricksmith uses in place
///             of the library part of the same name.
///
/// @discussion The release of a file is the one in its "!LDRAW_ORG" line, such
///             as "UPDATE 2022-01". A part copied from the library and fixed
///             keeps the release it was copied from, so a later release in the
///             library's file means the library has changed the part since.
///
//------------------------------------------------------------------------------
@interface LDrawPartOverride : NSObject

/// The name a part line uses for it, lowercase, e.g. "3001.dat" or
/// "s\3001s01.dat".
@property (nonatomic, readonly, copy) NSString *partName;

/// The library file it replaces, or for a high or low version the library does
/// not have, the library's file of the part itself. Nil when there is none.
@property (nonatomic, readonly, copy, nullable) NSString *libraryPath;

/// The release in each file's header, e.g. "2022-01" or "ORIGINAL". Nil when
/// the header names none, as an unofficial part's does.
@property (nonatomic, readonly, copy, nullable) NSString *update;
@property (nonatomic, readonly, copy, nullable) NSString *libraryUpdate;

/// Whether the library's file is from a later release than this one. No when
/// either release is unknown.
@property (nonatomic, readonly) BOOL libraryIsNewer;

/// The parts in the overrides folder of `paths`, sorted by name. Every folder
/// below its parts and p folders is read, and only the file headers. Hidden
/// files and folders are skipped.
+ (NSArray<LDrawPartOverride *> *) overridesWithPaths:(LDrawPaths *)paths
	NS_SWIFT_NAME(overrides(paths:));

/// The same list, read on a background queue from a copy of `paths`, so a
/// change made meanwhile cannot switch folders. The handler runs on the main
/// queue.
+ (void) readOverridesWithPaths:(LDrawPaths *)paths
			  completionHandler:(void (^)(NSArray<LDrawPartOverride *> *overrides))completionHandler;

/// The release in the "!LDRAW_ORG" line of a file's header, or nil.
+ (nullable NSString *) updateInText:(NSString *)text NS_SWIFT_NAME(update(inText:));

/// The release in the header of the file at path, or nil. Only the header is
/// read.
+ (nullable NSString *) updateOfFileAtPath:(nullable NSString *)path NS_SWIFT_NAME(update(ofFileAtPath:));

@end

NS_ASSUME_NONNULL_END
