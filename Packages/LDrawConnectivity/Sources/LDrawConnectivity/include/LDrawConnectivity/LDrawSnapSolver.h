//==============================================================================
//
//  File:       LDrawSnapSolver.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Decides where a dragged part should land, from the
//              connectors around it.
//
//  Notes:      Each pair of connectors that can mate gives one placement.
//              Pairs that give the same placement are counted as votes, so a
//              brick on eight studs beats a placement on one stud. Distances
//              are in screen points, so snapping feels the same at any zoom.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawConnectorIndex.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct
{
	bool		snapped;
	Matrix4		transform;		// apply to the dragged part's current placement
	uint32_t	voteCount;		// connectors the placement satisfies
	double		score;
	double		distance;		// screen points the part moves to land there

} LDrawSnapSolution;


@interface LDrawSnapSolver : NSObject

- (instancetype)initWithConnectorIndex:(LDrawConnectorIndex *)connectorIndex NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) LDrawConnectorIndex *connectorIndex;

/// Screen points the part may move to snap on, and to let go again. The
/// release distance is the larger, so a held placement does not flicker.
@property (nonatomic) double acquireDistance;		// 22 pt
@property (nonatomic) double releaseDistance;		// 40 pt

/// How much better another placement must score to replace the held one, as
/// a fraction of the held score.
@property (nonatomic) double switchMargin;			// 0.15

/// Screen points to one LDU: the zoom.
@property (nonatomic) double pointsPerUnit;

/// How far two axes may differ and still count as the same direction.
@property (nonatomic) double axisTolerance;			// radians

/// Whether a part may turn to one of the 24 right-angle orientations to meet
/// a connector, such as a stud on the side of a brick.
@property (nonatomic) BOOL allowsRotation;

/// Weights of the score terms. Votes count for much more than the rest.
@property (nonatomic) double countWeight;
@property (nonatomic) double distanceWeight;
@property (nonatomic) double angleWeight;
@property (nonatomic) double dragWeight;
@property (nonatomic) double switchWeight;

/// Where the dragged part should go. The connectors are the dragged part's,
/// already at the place the pointer asks for. The drag direction is in model
/// coordinates and may be zero.
///
/// The connectors are taken as given. A caller that builds them from several
/// parts should drop the ones filled inside the group first, once per drag,
/// with -connectorsStillFree:.
- (LDrawSnapSolution)solutionForConnectors:(LDrawWorldConnectors *)movingConnectors
							 dragDirection:(Vector3)dragDirection;

/// Forgets the placement being held, for the end of a drag.
- (void)releaseHold;

@end

NS_ASSUME_NONNULL_END
