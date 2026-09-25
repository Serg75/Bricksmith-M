//==============================================================================
//
//  File:       LDrawConnectorNeighborhood.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Groups one set of connectors by where they are, so a pass over
//              the set compares each connector with the few beside it instead
//              of with all of them.
//
//  Info:       Two passes need this. A drag matches the connectors it moves
//              against the ones they could meet, on every touch; a submodel
//              drops the connectors its own parts already fill, when it is
//              read. Both are all against all, and a submodel of fifty parts
//              has eight hundred connectors: comparing every pair would be
//              640,000 tests.
//
//              This is not the model's index. LDrawConnectorIndex holds the
//              whole model, follows parts as they move, and answers with
//              connectors. This one is built for a single call over a set
//              already in hand, and answers with places in that set.
//
//  Created by Sergey Slobodenyuk on 2026-09-24.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawWorldConnectors.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawConnectorNeighborhood : NSObject

/// The cell size is the range the caller asks about: the reach of a drag, or
/// the stud pitch. A connector goes into every cell its run's box covers.
- (instancetype)initWithConnectors:(LDrawWorldConnectors *)connectors cellSize:(double)cellSize;

/// The set it was built over, to read a connector an answer names.
@property (nonatomic, readonly) const LDrawWorldConnector *connectors;

/// The connectors in the cells the box covers, each once. The numbers stay
/// valid until the next call.
- (const uint32_t *)indicesNearBox:(Box3)box count:(NSUInteger *)countOut;

@end

NS_ASSUME_NONNULL_END
