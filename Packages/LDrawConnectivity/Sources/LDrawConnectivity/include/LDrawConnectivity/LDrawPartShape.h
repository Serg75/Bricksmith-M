//==============================================================================
//
//  File:       LDrawPartShape.h
//  Package:    LDrawConnectivity
//
//  Purpose:    The solid a part fills, as a grid of small cells, to tell
//              whether two parts placed near each other go into each other.
//
//  Notes:      Built from the part's triangles. The cells the surface passes
//              through are solid, and so is everything the outside cannot
//              reach without crossing the surface. Holes, the hollow under a
//              brick and the gaps between hinge fingers stay open, so a stud
//              in a hole or a pin in a beam does not count as going in. Nor do
//              parts that only touch: a part must reach about two LDU past the
//              other part's surface, or the middle of a thinner part.
//
//  Created by Sergey Slobodenyuk on 2026-09-28.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawPartShape : NSObject

/// A shape built from the triangles the block gives, in the part's
/// coordinates, nine floats a triangle. The block is called once, when the
/// shape is first needed, so a shape costs nothing until then.
- (instancetype)initWithTriangles:(NSData * (^)(void))triangles NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Builds the shape now, as a caller may do ahead of time on another thread.
- (void)build;

/// Whether the shape is built. A caller that must not wait for it, such as a
/// drag, can look at boxes until it is.
@property (nonatomic, readonly, getter=isBuilt) BOOL built;

/// The space the part's surface fills, in its own coordinates. InvalidBox for
/// a part with no triangles.
@property (nonatomic, readonly) Box3 bounds;

/// The size of one cell in LDU: 1, or more for a large part.
@property (nonatomic, readonly) double cellSize;

/// How many cells are solid, and how many of those are inside, not at the
/// surface.
@property (nonatomic, readonly) NSUInteger solidCellCount;
@property (nonatomic, readonly) NSUInteger insideCellCount;

/// Whether the point, in the part's coordinates, is in the solid.
- (BOOL)containsPoint:(Point3)point;

/// Whether the point, in the part's coordinates, is well inside the solid,
/// not near its surface.
- (BOOL)containsPointDeeply:(Point3)point;

/// Whether this part and another, each placed in the model, go into each
/// other: the surface of either reaching well inside the other.
/// Only the cells within the region, in the model's coordinates, are looked
/// at; the caller gives where the two parts' boxes overlap.
- (BOOL)placedAt:(Matrix4)placement
		goesInto:(LDrawPartShape *)other
		placedAt:(Matrix4)otherPlacement
		  within:(Box3)region;

@end

NS_ASSUME_NONNULL_END
