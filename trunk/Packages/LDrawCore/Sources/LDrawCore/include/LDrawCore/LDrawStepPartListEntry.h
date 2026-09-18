//==============================================================================
//
//  File:       LDrawStepPartListEntry.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawColor;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListEntry
///
/// @abstract   One row of a step's parts list: a part design in a color, and
///             how many of it the step consumes.
///
/// @discussion Immutable. Counting a second instance of the same design and
///             color makes a new entry instead of changing this one, so a
///             collected list can be passed around without copying.
///
///             The list says what the step uses, not what is on screen now: a
///             part hidden in the editor is still listed.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListEntry : NSObject

/// Canonical (lower-case) part reference, e.g. "3001.dat".
@property (nonatomic, readonly, copy) NSString *partName;

/// The part library's description, or `partName` when there is none: an
/// unresolved reference, or no part library registered.
@property (nonatomic, readonly, copy) NSString *displayTitle;

/// nil only for a part carrying no color at all, which a well-formed file
/// does not produce.
@property (nonatomic, readonly, nullable) LDrawColor *color;

/// How many of this design-and-color the step places.
@property (nonatomic, readonly) NSUInteger quantity;

/// Bounds of the referenced model, untransformed: the part as the library
/// defines it, not as this step places it. `InvalidBox3` when the reference
/// does not resolve.
@property (nonatomic, readonly) Box3 modelBounds;

/// The reference does not resolve to anything. Listed anyway, so a broken
/// reference is visible instead of silently dropped.
@property (nonatomic, readonly) BOOL isMissing;

/// The reference is to a submodel or a peer file rather than a catalog part.
@property (nonatomic, readonly) BOOL isSubmodel;

/// Corners of each part's box, tighter than `modelBounds`, packed as `Point3`
/// values. Nil when there are none.
@property (nonatomic, readonly, copy, nullable) NSData *outlinePoints;

/// The turn this part gets before it is drawn in the list: the part's line in
/// LPub3D's PLI control file, or identity. Applied before the list's own
/// view, so it turns the part, not the camera.
@property (nonatomic, readonly) Matrix4 listOrientation;

- (instancetype) initWithPartName:(NSString *)partName
					 displayTitle:(NSString *)displayTitle
							color:(nullable LDrawColor *)color
						 quantity:(NSUInteger)quantity
					  modelBounds:(Box3)modelBounds
						isMissing:(BOOL)isMissing
					   isSubmodel:(BOOL)isSubmodel NS_DESIGNATED_INITIALIZER;

- (instancetype) init NS_UNAVAILABLE;

/// A copy of this entry outlined by these points. See `outlinePoints`.
- (LDrawStepPartListEntry *) entryWithOutlinePoints:(nullable NSData *)outlinePoints;

/// A copy of this entry turned by this matrix. See `listOrientation`.
- (LDrawStepPartListEntry *) entryWithListOrientation:(Matrix4)listOrientation;

/// A copy of this entry with one more instance counted.
- (LDrawStepPartListEntry *) entryByAddingInstance;

/// Identity for grouping: part design plus color. Two entries with the same
/// key are the same row.
@property (nonatomic, readonly, copy) NSString *groupKey;

@end

NS_ASSUME_NONNULL_END
