//==============================================================================
//
//  File:       LDrawPartListOrientations.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-14.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartListOrientations
///
/// @abstract   The base orientation LPub3D gives each part in a parts list,
///             read from its PLI control file.
///
/// @discussion The control file is an ordinary MPD of type-1 lines, each
///             placing a part turned the way it reads best in a list. Only a
///             line's 3x3 matrix is used; its position and color are ignored,
///             and a part listed twice takes its first line.
///
///             A line counts only with exactly fifteen tokens, as in LPub3D,
///             so a reference whose name contains spaces is not a part entry.
///
//------------------------------------------------------------------------------
@interface LDrawPartListOrientations : NSObject

/// Reads the file, or answers nil and an error when it cannot be read.
+ (nullable instancetype) orientationsWithContentsOfFile:(NSString *)path
												   error:(NSError **)error;

- (instancetype) initWithString:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// How many distinct parts the file orients.
@property (nonatomic, readonly) NSUInteger count;

/// The part's base orientation, as a matrix a point is multiplied by on the
/// left. Identity when the file does not list the part. Case does not matter.
- (Matrix4) orientationForPartName:(NSString *)partName;

/// Where LPub3D keeps its control file on this Mac: `extras/pli.mpd` or
/// `extras/LEGOPliControl.ldr` in its application support folder. nil when
/// neither exists.
+ (nullable NSString *) lpubDefaultFilePath;

@end

NS_ASSUME_NONNULL_END
