//==============================================================================
//
//  File:       LDrawPartComparison.h
//  Package:    LDrawCore
//
//  Purpose:    A part as the overrides folder has it and as the library has
//              it, each as a file that can be drawn next to the other.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawFile;
@class LDrawPaths;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartComparison
///
/// @abstract   Builds a part from the overrides folder and from the library,
///             so the two can be shown side by side.
///
/// @discussion Each side is an MPD file. Its first model is the part's file
///             from that side. After it come that side's files of every part
///             between it and an overridden part. A submodel is found before
///             the library, so each side draws only its own files, whether or
///             not the overrides folder is turned on. Parts that lead to no
///             override are the same on both sides, and come from the library.
///
///             Only the files' text is read, never the parsed library parts.
///
//------------------------------------------------------------------------------
@interface LDrawPartComparison : NSObject

/// `partName` is the name a part line gives, e.g. "s\56145s02.dat".
- (instancetype) initWithPartName:(NSString *)partName paths:(LDrawPaths *)paths NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// The part's name, lowercase.
@property (nonatomic, readonly, copy) NSString *partName;

/// The overridden parts the part is or uses, on either side, sorted. Empty when
/// the two sides are the same.
@property (nonatomic, readonly, copy) NSArray<NSString *> *changedPartNames;

/// The part's own file on each side. Nil when that side has no such part.
@property (nonatomic, readonly, copy, nullable) NSString *overridePath;
@property (nonatomic, readonly, copy, nullable) NSString *libraryPath;

/// The MPD text of one side, as lines.
- (NSArray<NSString *> *) linesUsingOverrides:(BOOL)useOverrides;

/// That text, parsed and flattened like a library part, so the part draws as
/// one smoothed mesh.
- (LDrawFile *) fileUsingOverrides:(BOOL)useOverrides;

@end

NS_ASSUME_NONNULL_END
