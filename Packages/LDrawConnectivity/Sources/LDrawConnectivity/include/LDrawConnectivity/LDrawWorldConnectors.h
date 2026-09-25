//==============================================================================
//
//  File:       LDrawWorldConnectors.h
//  Package:    LDrawConnectivity
//
//  Purpose:    The connectors of one or more placed parts, in the model's
//              coordinates.
//
//  Notes:      A model has thousands of connectors and a drag compares
//              thousands of pairs a touch, so they are kept in one buffer
//              rather than one object each. Build a set by adding parts to
//              it, then read it.
//
//  Created by Sergey Slobodenyuk on 2026-09-25.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawConnectorSet.h>
#import <LDrawConnectivity/LDrawWorldConnector.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawWorldConnectors : NSObject <NSCopying>

/// Empty, to be built up.
+ (instancetype)connectors;

/// Every place the part can connect, placed by its own matrix.
+ (instancetype)connectorsFromSet:(LDrawConnectorSet *)set
						placement:(Matrix4)placement
							owner:(uint32_t)owner;

- (void)addConnectorsFromSet:(LDrawConnectorSet *)set
				   placement:(Matrix4)placement
					   owner:(uint32_t)owner;
- (void)addConnectors:(LDrawWorldConnectors *)connectors;
- (void)addConnector:(LDrawWorldConnector)connector;

@property (nonatomic, readonly) NSUInteger count;

/// One connector, or an empty one when the index is past the end.
- (LDrawWorldConnector)connectorAtIndex:(NSUInteger)index;

/// All of them at once, for a loop that reads every one. Valid until the set
/// is added to again.
@property (nonatomic, readonly) const LDrawWorldConnector *all NS_RETURNS_INNER_POINTER;

/// The same connectors somewhere else. A drag reads its part's connectors
/// once and places them again on every touch.
- (LDrawWorldConnectors *)connectorsPlacedBy:(Matrix4)placement;

/// The connectors another part can still reach. Drops any whose mouth is
/// already filled by another connector in the same set, such as a stud with a
/// plate on it. Keeps sliding connectors: part of a run being taken leaves
/// the rest free.
- (LDrawWorldConnectors *)connectorsStillFree:(double)axisTolerance;

@end

NS_ASSUME_NONNULL_END
