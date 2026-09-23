//==============================================================================
//
//  File:       LDrawConnectorIndex.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Finds the connectors near a place, for a model being edited.
//
//  Notes:      A hash of 20 x 8 x 20 LDU cells, which matches the stud pitch
//              and plate height. A connector is stored in every cell along its
//              length, so a long axle is found anywhere along it.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawWorldConnector.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawConnectorIndex : NSObject

/// Replaces an owner's connectors with these.
- (void)setConnectors:(NSData *)connectors forOwner:(uint32_t)owner;

- (void)removeOwner:(uint32_t)owner;
- (void)removeAllConnectors;

@property (nonatomic, readonly) NSUInteger connectorCount;
@property (nonatomic, readonly) NSUInteger ownerCount;

/// The connectors whose run reaches into the box, each returned once,
/// leaving out the given owner's. The caller widens the box by the snap
/// distance.
- (NSData *)connectorsInBox:(Box3)box excludingOwner:(uint32_t)owner;

@end

NS_ASSUME_NONNULL_END
