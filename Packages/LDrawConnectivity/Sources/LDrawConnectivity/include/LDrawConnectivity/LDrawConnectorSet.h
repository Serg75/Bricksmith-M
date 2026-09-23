//==============================================================================
//
//  File:       LDrawConnectorSet.h
//  Package:    LDrawConnectivity
//
//  Purpose:    The connectors of one part, in the part's own coordinates.
//              Immutable, so every placement of the part can share one set.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawConnector.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawConnectorSet : NSObject

- (instancetype)initWithConnectors:(const LDrawConnector *)connectors
					connectorCount:(NSUInteger)connectorCount
						  sections:(const LDrawConnectorSection *)sections
					  sectionCount:(NSUInteger)sectionCount NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Connector records. A record with a grid stands for several connectors.
@property (nonatomic, readonly) NSUInteger connectorCount;
- (LDrawConnector)connectorAtIndex:(NSUInteger)index;

/// One section of a cylinder's profile. All connectors of the set share one
/// list of sections.
- (LDrawConnectorSection)sectionAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
