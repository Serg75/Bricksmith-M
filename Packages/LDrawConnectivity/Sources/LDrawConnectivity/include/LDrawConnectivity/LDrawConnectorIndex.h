//==============================================================================
//
//  File:       LDrawConnectorIndex.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Finds the connectors near a place, for a model being edited.
//
//  Notes:      A hash of 20 x 8 x 20 LDU cells, which matches the stud pitch
//              and plate height. A connector is stored in every cell along its
//              length, so a long axle is found anywhere along it. The boxes of
//              the parts go in a second hash of 40 LDU cells.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawPartShape.h>
#import <LDrawConnectivity/LDrawWorldConnectors.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawConnectorIndex : NSObject

/// Replaces an owner's connectors with these.
- (void)setConnectors:(LDrawWorldConnectors *)connectors forOwner:(uint32_t)owner;

/// The same, with the space the owner fills. A solver uses it to refuse a
/// placement that would put one part through another. Without it an owner
/// takes up no space and nothing is refused.
- (void)setConnectors:(LDrawWorldConnectors *)connectors
			   bounds:(Box3)bounds
			 forOwner:(uint32_t)owner;

/// The space one part of an owner fills. An owner standing for a submodel adds
/// one box for each part inside it, because one box around the whole of it
/// covers space the parts leave free, and a placement beside it would be
/// refused for no reason.
- (void)addBounds:(Box3)bounds forOwner:(uint32_t)owner;

/// The same, with the part's shape and where it is placed in the model, so a
/// solver can tell whether parts whose boxes overlap really go into each
/// other.
- (void)addBounds:(Box3)bounds
			shape:(nullable LDrawPartShape *)shape
		placement:(Matrix4)placement
		 forOwner:(uint32_t)owner;

/// The space all of an owner's parts fill together, or InvalidBox when it was
/// given none.
- (Box3)boundsOfOwner:(uint32_t)owner;

/// The boxes that make up an owner, one for each of its parts.
- (NSUInteger)partBoundsCountOfOwner:(uint32_t)owner;
- (Box3)partBoundsOfOwner:(uint32_t)owner atIndex:(NSUInteger)index;
- (nullable LDrawPartShape *)partShapeOfOwner:(uint32_t)owner atIndex:(NSUInteger)index;
- (Matrix4)partPlacementOfOwner:(uint32_t)owner atIndex:(NSUInteger)index;

/// The same for all of an owner's parts at once, for a caller that goes
/// through many. The pointers last until the owner changes. A shape is
/// NSNull where a part has none.
- (nullable const Box3 *)partBoundsOfOwner:(uint32_t)owner count:(NSUInteger *)count;
- (nullable const Matrix4 *)partPlacementsOfOwner:(uint32_t)owner;
- (NSArray *)partShapesOfOwner:(uint32_t)owner;

/// How many of an owner's parts were given no shape.
- (NSUInteger)partsWithoutShapeOfOwner:(uint32_t)owner;

- (void)removeOwner:(uint32_t)owner;
- (void)removeAllConnectors;

@property (nonatomic, readonly) NSUInteger connectorCount;
@property (nonatomic, readonly) NSUInteger ownerCount;

/// The space every connector's mouth lies in, or InvalidBox when there are
/// none. A line of sight is clipped to it before anything is looked for.
@property (nonatomic, readonly) Box3 occupiedBounds;

/// The connectors whose run reaches into the box, each returned once,
/// leaving out the given owner's. The caller widens the box by the snap
/// distance.
- (LDrawWorldConnectors *)connectorsInBox:(Box3)box excludingOwner:(uint32_t)owner;

/// The owners with a part whose box reaches into the box, leaving out the
/// given owner. This finds a part where its connectors are not, such as a
/// baseplate between its studs.
- (NSIndexSet *)ownersInBox:(Box3)box excludingOwner:(uint32_t)owner;

@end

NS_ASSUME_NONNULL_END
