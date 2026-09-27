//==============================================================================
//
//  File:       LDrawSnapSolver.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Decides where a dragged part should land, from the
//              connectors around it.
//
//  Notes:      Each pair of connectors that can mate gives one placement.
//              Pairs that give the same placement are counted as votes. The
//              placement that leaves the part nearest the finger wins, and
//              votes break near ties, so a brick on eight studs beats one on
//              four beside it. Distances are in screen points, so snapping
//              feels the same at any zoom.
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
	int64_t		placement;		// while snapped, the same number for the same landing
	double		score;
	double		distance;		// screen points the part moves to land there

} LDrawSnapSolution;


/// A line from the screen through the finger, into the model, the point of the
/// dragged part the finger holds, and how far along the line the first thing
/// the finger sees is.
typedef struct
{
	Point3		origin;			// where the line leaves the screen
	Vector3		direction;		// which way it looks into the model, unit length
	Point3		grab;			// the point of the dragged part under the finger
	double		surface;		// the part is not in it; INFINITY when it sees nothing

} LDrawSightLine;


@interface LDrawSnapSolver : NSObject

- (instancetype)initWithConnectorIndex:(LDrawConnectorIndex *)connectorIndex NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) LDrawConnectorIndex *connectorIndex;

/// Screen points the part may move to snap on, and to let go again. The
/// release distance is the larger, so a held placement does not flicker.
@property (nonatomic) double acquireDistance;		// 22 pt
@property (nonatomic) double releaseDistance;		// 40 pt

/// How much nearer, in LDU, another placement must leave the part to replace
/// the held one. Under half a stud, so a part can move one stud at a time.
@property (nonatomic) double switchMargin;			// 5 LDU

/// How far down a part may be drawn onto what lies under it, in LDU, over and
/// above the distances measured on screen. At 0, the default, a part snaps
/// only to what it is already beside. A part is drawn down to the first thing
/// under it, never through it; rising always counts in full. A part drawn
/// down can still land under another part, which is a real connection but not
/// always the wanted one.
@property (nonatomic) double dropReach;				// 0

/// Screen points to one LDU: the zoom.
@property (nonatomic) double pointsPerUnit;

/// How far two axes may differ and still count as the same direction.
@property (nonatomic) double axisTolerance;			// radians

/// Whether a part may turn to one of the 24 right-angle orientations to meet
/// a connector, such as a stud on the side of a brick.
@property (nonatomic) BOOL allowsRotation;

/// How far a part may be turned from how it is held, in radians. The turns are
/// the 24 upright ones, so anything under a right angle leaves only the
/// placements that do not turn it.
@property (nonatomic) double maximumTurn;			// pi

/// Weights of the score terms. The score is in screen points.
@property (nonatomic) double countWeight;			// 4 pt a vote
@property (nonatomic) double distanceWeight;		// 1 a point the part moves
@property (nonatomic) double angleWeight;			// 20 pt a radian it turns
@property (nonatomic) double dragWeight;			// 3 pt for moving against the drag

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

/// The space the dragged part fills, where its connectors are now: one box for
/// a single part, or one for each part inside a submodel. Given these, a
/// placement that would drive the part through another part is refused. Parts
/// that only touch, or whose studs sit in each other's holes, are not.
/// Without them nothing is refused.
- (void)clearMovingBounds;
- (void)addMovingBounds:(Box3)bounds;

/// Excuses every part the dragged one already shares space with, as its boxes
/// stand now, from being refused for it when it is put back there. A model as
/// built has parts whose boxes overlap though the parts themselves fit
/// together, and a part must be able to go back where it was. Anywhere else
/// they still block it. Call it once, when the drag begins.
- (void)excusePartsItOverlaps;

/// Where a dragged part should land, looked for along the line of sight
/// through the finger instead of around where the part is. Every placement
/// that leaves the held point under the finger is a candidate however deep
/// it lies, and the nearest to the screen wins: a surface in front beats
/// anything behind it, and placements at about the same depth are ranked as
/// -solutionForConnectors:dragDirection: ranks them. Distances are measured
/// across the screen, at the zoom of the held point.
///
/// When the sight line says what the finger sees, a placement behind that is
/// hidden, and is never taken; the rest are ranked by their pairs and how
/// near the finger they leave the held point, whichever is nearer the
/// screen. The held point should then be on the part's surface, where the
/// finger touched it: a part set down where it can be seen has that point in
/// front of what lies behind it.
- (LDrawSnapSolution)solutionForConnectors:(LDrawWorldConnectors *)movingConnectors
								alongSight:(LDrawSightLine)sight
							 dragDirection:(Vector3)dragDirection;

/// How far a part must fall before it rests on what is under it: the smallest
/// gap between a hole on its underside and the stud below it. Zero when there
/// is nothing under it within the reach, so a part carried over empty space
/// keeps its height. Use it to carry a part along the surface it is over,
/// rather than at a height of its own.
- (double)restingDropForConnectors:(LDrawWorldConnectors *)movingConnectors
							within:(double)reach;

@end

NS_ASSUME_NONNULL_END
