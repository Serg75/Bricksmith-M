//==============================================================================
//
//  File:       LDrawSubfileReader.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Reads only the subfile references (type 1 lines) of library
//              files, and caches them per file.
//
//  Notes:      The part library is not used because it flattens parts on
//              load, which removes the references connectors come from.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

/// One type 1 line: which file, placed how.
@interface LDrawSubfileReference : NSObject
@property (nonatomic, readonly) NSString	*name;			// lowercase, with / separators
@property (nonatomic, readonly) Matrix4		transform;		// acts on row vectors
@end


@interface LDrawSubfileReader : NSObject

/// Reads through the given paths, or the shared ones when none are given.
- (instancetype)initWithPaths:(nullable LDrawPaths *)paths NS_DESIGNATED_INITIALIZER;

/// The name in lowercase with / separators. Library names are
/// case-insensitive, and files write them with DOS separators.
+ (NSString *)normalizedName:(NSString *)name;

/// The references in a library file such as "3001.dat" or "s/3001s01.dat",
/// found through LDrawPaths. Nil when there is no such file.
- (nullable NSArray<LDrawSubfileReference *> *)referencesInFileNamed:(NSString *)name;

/// The library-relative path of a file, such as "parts/s/3001s01.dat".
- (nullable NSString *)relativePathForFileNamed:(NSString *)name;

/// Forgets every file read so far, for when the LDraw folder changes.
- (void)removeAllReferences;

@end

NS_ASSUME_NONNULL_END
