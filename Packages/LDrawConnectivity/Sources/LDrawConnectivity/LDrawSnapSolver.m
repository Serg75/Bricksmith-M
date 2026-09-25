//==============================================================================
//
//  File:       LDrawSnapSolver.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Ranks the placements the connectors around a dragged part
//              give, and holds the chosen one.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <LDrawConnectivity/LDrawSnapSolver.h>

#import "LDrawConnectivityMath.h"
#import "LDrawConnectorNeighborhood.h"

// Placements are rounded to half an LDU before they are compared. Library
// positions are whole LDU, so this only hides float noise.
static const double LatticeStep = 0.5;

// Two connectors closer than this are at the same point.
static const double CoincidentDistance = 0.25;

// Runs that overlap by less than this do not share a hole.
static const double OccupiedOverlap = 0.5;

// The turn index for no rotation. The 24 cube rotations use 0 to 23.
static const NSUInteger NoTurn = 24;


//---------- CubeRotations ---------------------------------------------[static]--
//
// Purpose:		The 24 rotations of a cube onto itself. Automatic turning uses
//				only these, so a part never lands at an odd angle.
//
//------------------------------------------------------------------------------
static const Matrix4 *CubeRotations(NSUInteger *countOut)
{
	static Matrix4			rotations[24];
	static NSUInteger		count	= 0;
	static dispatch_once_t	once;

	dispatch_once(&once, ^{
		const int axes[6][3] = { {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1} };

		for (NSUInteger first = 0; first < 6; first++)
		{
			for (NSUInteger second = 0; second < 6; second++)
			{
				int x[3] = { axes[first][0], axes[first][1], axes[first][2] };
				int y[3] = { axes[second][0], axes[second][1], axes[second][2] };
				int z[3] = { x[1] * y[2] - x[2] * y[1],
							 x[2] * y[0] - x[0] * y[2],
							 x[0] * y[1] - x[1] * y[0] };

				if ((x[0] * y[0] + x[1] * y[1] + x[2] * y[2]) != 0)
				{
					continue;	// not at right angles
				}

				Matrix4 rotation = IdentityMatrix4;

				for (NSUInteger column = 0; column < 3; column++)
				{
					rotation.element[0][column] = x[column];
					rotation.element[1][column] = y[column];
					rotation.element[2][column] = z[column];
				}
				rotations[count] = rotation;
				count++;
			}
		}
	});
	*countOut = count;

	return rotations;
}


//---------- PlacementTakingPointToPoint -------------------------------[static]--
//
// Purpose:		The placement that rotates the part and then moves the point
//				"from" onto the point "to".
//
//------------------------------------------------------------------------------
static Matrix4 PlacementTakingPointToPoint(Point3 from, Point3 to, Matrix4 rotation)
{
	Vector3	turned	= LDrawDirectionByMatrix(V3Make(from.x, from.y, from.z), rotation);
	Matrix4	placement = rotation;

	placement.element[3][0] = to.x - turned.x;
	placement.element[3][1] = to.y - turned.y;
	placement.element[3][2] = to.z - turned.z;

	return placement;
}


//---------- RotationAngle ---------------------------------------------[static]--
//------------------------------------------------------------------------------
static double RotationAngle(Matrix4 rotation)
{
	double trace = rotation.element[0][0] + rotation.element[1][1] + rotation.element[2][2];

	return acos(MAX(-1.0, MIN(1.0, (trace - 1.0) / 2.0)));
}


#pragma mark -

/// A connector the dragged part would mate with, the dragged connector's
/// gender, and the length it would fill, measured from the met mouth.
typedef struct
{
	LDrawWorldConnector		met;
	LDrawConnectorGender	movingGender;
	double					start;
	double					finish;

} LDrawSnapMeeting;


//==============================================================================
//
// One placement, and the pairs of connectors that give it.
//
//==============================================================================
@interface LDrawSnapCluster : NSObject

@property (nonatomic) Matrix4			placement;
@property (nonatomic) NSUInteger		votes;
@property (nonatomic) double			distance;		// LDU the part moves
@property (nonatomic) double			angle;			// radians it turns
@property (nonatomic) Vector3			displacement;
@property (nonatomic) double			score;
@property (nonatomic) int64_t			identifier;
@property (nonatomic, readonly) NSMutableData *meetings;	// LDrawSnapMeeting

@end


@implementation LDrawSnapCluster

- (instancetype)init
{
	self = [super init];
	if (self != nil)
	{
		_meetings = [NSMutableData data];
	}
	return self;
}

@end


#pragma mark -

// No placement, for when nothing is held.
static const int64_t NoPlacement = INT64_MIN;


//==============================================================================
//
// The placements found so far, in order, with a map from identifier to
// placement. The map uses raw integer keys to avoid boxing them in NSNumber.
//
//==============================================================================
@interface LDrawSnapClusterTable : NSObject

@property (nonatomic, readonly) NSMutableArray<LDrawSnapCluster *> *clusters;

- (nullable LDrawSnapCluster *)clusterWithIdentifier:(int64_t)identifier;
- (void)addCluster:(LDrawSnapCluster *)cluster;

@end


@implementation LDrawSnapClusterTable
{
	CFMutableDictionaryRef _byIdentifier;		// identifier -> cluster; not retained
}

- (instancetype)init
{
	self = [super init];
	if (self != nil)
	{
		_clusters		= [NSMutableArray array];
		_byIdentifier	= CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
	}
	return self;
}


- (void)dealloc
{
	CFRelease(_byIdentifier);
}


- (nullable LDrawSnapCluster *)clusterWithIdentifier:(int64_t)identifier
{
	return (__bridge LDrawSnapCluster *)CFDictionaryGetValue(_byIdentifier,
															 (const void *)(intptr_t)identifier);
}


- (void)addCluster:(LDrawSnapCluster *)cluster
{
	[_clusters addObject:cluster];			// the array owns the cluster
	CFDictionarySetValue(_byIdentifier, (const void *)(intptr_t)cluster.identifier,
						 (__bridge const void *)cluster);
}

@end


#pragma mark -

@implementation LDrawSnapSolver
{
	int64_t	_heldPlacement;
}

//========== initWithConnectorIndex: ===========================================
//==============================================================================
- (instancetype)initWithConnectorIndex:(LDrawConnectorIndex *)connectorIndex
{
	self = [super init];
	if (self != nil)
	{
		_connectorIndex		= connectorIndex;
		_acquireDistance	= 22.0;
		_releaseDistance	= 40.0;
		_switchMargin		= 0.15;
		_pointsPerUnit		= 1.0;
		_axisTolerance		= 0.05;
		_allowsRotation		= YES;
		_countWeight		= 100.0;
		_distanceWeight		= 1.0;
		_angleWeight		= 20.0;
		_dragWeight			= 30.0;
		_switchWeight		= 15.0;
		_heldPlacement		= NoPlacement;
	}
	return self;
}


//========== releaseHold =======================================================
//==============================================================================
- (void)releaseHold
{
	_heldPlacement = NoPlacement;
}


#pragma mark - Solving


//========== solutionForConnectors:dragDirection: ==============================
//==============================================================================
- (LDrawSnapSolution)solutionForConnectors:(LDrawWorldConnectors *)movingConnectors
							 dragDirection:(Vector3)dragDirection
{
	const LDrawWorldConnector	*moving		= movingConnectors.all;
	NSUInteger					movingCount	= movingConnectors.count;
	LDrawWorldConnectors		*met		= nil;
	NSArray<LDrawSnapCluster *>	*clusters	= nil;

	if (movingCount == 0 || self.pointsPerUnit <= 0.0)
	{
		return (LDrawSnapSolution){ .snapped = false, .transform = IdentityMatrix4 };
	}
	met			= [self.connectorIndex connectorsInBox:[self searchBoxForConnectors:movingConnectors]
										excludingOwner:moving[0].owner];
	clusters	= [self clustersForConnectors:movingConnectors
										  met:met
									   anchor:[self anchorOfConnectors:movingConnectors]];
	clusters	= [self rankedClusters:clusters owner:moving[0].owner dragDirection:dragDirection];

	return [self solutionFromRankedClusters:clusters];
}


//========== anchorOfConnectors: ===============================================
//
// Purpose:		The point where a placement's distance is measured: the middle
//				of the dragged part's connector mouths.
//
// Notes:		A rotation moves each connector a different distance. A fixed
//				point keeps the distance independent of the search order.
//
//==============================================================================
- (Point3)anchorOfConnectors:(LDrawWorldConnectors *)movingConnectors
{
	const LDrawWorldConnector	*moving	= movingConnectors.all;
	NSUInteger					count	= movingConnectors.count;
	Point3						middle	= V3Make(0, 0, 0);

	for (NSUInteger index = 0; index < count; index++)
	{
		middle = V3Add(middle, LDrawWorldConnectorMouth(moving[index]));
	}
	return (count > 0) ? V3MulScalar(middle, 1.0 / (double)count) : middle;
}


//========== searchBoxForConnectors: ===========================================
//
// Purpose:		The box to search: the whole length of each dragged connector,
//				widened by the release distance.
//
//==============================================================================
- (Box3)searchBoxForConnectors:(LDrawWorldConnectors *)movingConnectors
{
	const LDrawWorldConnector	*moving	= movingConnectors.all;
	NSUInteger					count	= movingConnectors.count;
	double						reach	= self.releaseDistance / self.pointsPerUnit;
	Box3						box		= InvalidBox;

	for (NSUInteger index = 0; index < count; index++)
	{
		box = V3UnionBoxAndPoint(box, LDrawWorldConnectorMouth(moving[index]));
		box = V3UnionBoxAndPoint(box, V3Add(LDrawWorldConnectorMouth(moving[index]),
											V3MulScalar(moving[index].axis, moving[index].length)));
	}
	box.min.x -= reach;	box.min.y -= reach;	box.min.z -= reach;
	box.max.x += reach;	box.max.y += reach;	box.max.z += reach;

	return box;
}


//========== searchBoxForConnector:reach: ======================================
//
// Purpose:		The volume one dragged connector could reach.
//
//==============================================================================
- (Box3)searchBoxForConnector:(LDrawWorldConnector)connector reach:(double)reach
{
	Point3	mouth	= LDrawWorldConnectorMouth(connector);
	Point3	end		= V3Add(mouth, V3MulScalar(connector.axis, connector.length));
	Box3	box		= V3BoundsFromPoints(mouth, end);

	box.min.x -= reach;	box.min.y -= reach;	box.min.z -= reach;
	box.max.x += reach;	box.max.y += reach;	box.max.z += reach;

	return box;
}


//========== clustersForConnectors:met: ========================================
//
// Purpose:		Turns every pair that can mate into a placement, and groups
//				the pairs that give the same placement.
//
//==============================================================================
- (NSArray<LDrawSnapCluster *> *)clustersForConnectors:(LDrawWorldConnectors *)movingConnectors
												   met:(LDrawWorldConnectors *)metConnectors
												anchor:(Point3)anchor
{
	const LDrawWorldConnector	*moving			= movingConnectors.all;
	NSUInteger					movingCount		= movingConnectors.count;
	double						reach			= self.releaseDistance / self.pointsPerUnit;
	double						pairing			= self.allowsRotation ? M_PI : self.axisTolerance;
	NSUInteger					rotationCount	= 0;
	const Matrix4				*rotations		= CubeRotations(&rotationCount);
	LDrawSnapClusterTable		*clusters		= [[LDrawSnapClusterTable alloc] init];
	LDrawConnectorNeighborhood	*nearby			= [[LDrawConnectorNeighborhood alloc]
												   initWithConnectors:metConnectors cellSize:reach];
	const LDrawWorldConnector	*met			= [nearby connectors];

	for (NSUInteger one = 0; one < movingCount; one++)
	{
		NSUInteger		count	= 0;
		const uint32_t	*close	= [nearby indicesNearBox:[self searchBoxForConnector:moving[one] reach:reach]
													count:&count];

		for (NSUInteger index = 0; index < count; index++)
		{
			NSUInteger	other	= close[index];
			double		depth	= 0.0;

			if (met[other].owner == moving[one].owner)
			{
				continue;			// a part does not hold itself
			}
			if (LDrawWorldConnectorsMate(moving[one], met[other], pairing, &depth) == NO)
			{
				continue;
			}
			if (V3Dot(moving[one].axis, met[other].axis) >= cos(self.axisTolerance))
			{
				// Already aligned, so the part only moves.
				[self addMeeting:met[other]
							from:moving[one]
						   depth:depth
						rotation:IdentityMatrix4
							turn:NoTurn
						  anchor:anchor
							  to:clusters];
				continue;
			}
			if (self.allowsRotation == NO)
			{
				continue;
			}
			for (NSUInteger turn = 0; turn < rotationCount; turn++)
			{
				if (V3Dot(LDrawDirectionByMatrix(moving[one].axis, rotations[turn]), met[other].axis)
					< cos(self.axisTolerance))
				{
					continue;
				}
				[self addMeeting:met[other]
							from:moving[one]
						   depth:depth
						rotation:rotations[turn]
							turn:turn
						  anchor:anchor
							  to:clusters];
			}
		}
	}
	return clusters.clusters;
}


//========== landingForMoving:meeting:depth:turn: ==============================
//
// Purpose:		Where the dragged connector's mouth goes: into the met mouth,
//				at the depth the profiles need.
//
// Notes:		When both connectors slide, such as an axle in a hole, the part
//				keeps its position along the axis, clamped to the shared length
//				and rounded to the grid.
//
//==============================================================================
- (Point3)landingForMoving:(LDrawWorldConnector)moving
				   meeting:(LDrawWorldConnector)met
					 depth:(double)depth
					  turn:(NSUInteger)turn
{
	Point3	mouth	= LDrawWorldConnectorMouth(met);
	double	along	= depth;

	// A part that must turn is not on the met axis yet, so it has no depth
	// to keep.
	if (moving.slide && met.slide && turn == NoTurn)
	{
		Point3	seated	= V3Add(mouth, V3MulScalar(met.axis, depth));
		double	shared	= met.length - moving.length;
		double	wanted	= V3Dot(V3Sub(LDrawWorldConnectorMouth(moving), seated), met.axis);

		wanted	= MAX(MIN(shared, 0.0), MIN(MAX(shared, 0.0), wanted));
		along  += round(wanted / LatticeStep) * LatticeStep;
	}
	return V3Add(mouth, V3MulScalar(met.axis, along));
}


//========== addMeeting:from:depth:rotation:turn:anchor:to: ====================
//
// Purpose:		Adds this pair to the cluster for its placement, creating the
//				cluster if needed.
//
//==============================================================================
- (void)addMeeting:(LDrawWorldConnector)met
			  from:(LDrawWorldConnector)moving
			 depth:(double)depth
		  rotation:(Matrix4)rotation
			  turn:(NSUInteger)turn
			anchor:(Point3)anchor
				to:(LDrawSnapClusterTable *)clusters
{
	Point3				mouth		= LDrawWorldConnectorMouth(moving);
	Point3				landing		= [self landingForMoving:moving meeting:met depth:depth turn:turn];
	Matrix4				placement	= PlacementTakingPointToPoint(mouth, landing, rotation);
	Point3				anchorLands	= V3MulPointByProjMatrix(anchor, placement);
	int64_t				identifier	= [self identifierForLanding:anchorLands turn:turn];
	LDrawSnapCluster	*cluster	= [clusters clusterWithIdentifier:identifier];
	double				seated		= V3Dot(V3Sub(landing, LDrawWorldConnectorMouth(met)), met.axis);
	LDrawSnapMeeting	meeting		= {
		.met			= met,
		.movingGender	= moving.gender,
		.start			= seated,
		.finish			= seated + moving.length,	// once placed, it lies along the met axis
	};

	if (cluster == nil)
	{
		cluster = [[LDrawSnapCluster alloc] init];
		cluster.identifier	= identifier;
		cluster.placement	= placement;
		cluster.angle		= RotationAngle(rotation);
		cluster.displacement = V3Sub(anchorLands, anchor);
		cluster.distance	= V3Length(cluster.displacement);
		[clusters addCluster:cluster];
	}
	cluster.votes++;
	[cluster.meetings appendBytes:&meeting length:sizeof(meeting)];
}


//========== identifierForLanding:turn: ========================================
//
// Purpose:		One number for a placement, from where the part lands and its
//				turn. Placements that land at the same spot the same way up
//				get the same number.
//
// Notes:		It uses the landing, not the move, so the number stays the same
//				while the pointer moves. Each coordinate keeps 18 bits, which
//				covers 65,000 LDU from the origin.
//
//==============================================================================
- (int64_t)identifierForLanding:(Point3)landing turn:(NSUInteger)turn
{
	int64_t	x		= llround(landing.x / LatticeStep) & 0x3FFFF;
	int64_t	y		= llround(landing.y / LatticeStep) & 0x3FFFF;
	int64_t	z		= llround(landing.z / LatticeStep) & 0x3FFFF;

	return ((int64_t)turn << 54) | (x << 36) | (y << 18) | z;
}


#pragma mark - Ranking


//========== rankedClusters:owner:dragDirection: ===============================
//
// Purpose:		Scores the placements within reach and sorts the best first.
//				More votes win over a shorter distance.
//
//==============================================================================
- (NSArray<LDrawSnapCluster *> *)rankedClusters:(NSArray<LDrawSnapCluster *> *)clusters
										  owner:(uint32_t)owner
								  dragDirection:(Vector3)dragDirection
{
	double				reach		= self.releaseDistance / self.pointsPerUnit;
	NSMutableArray		*scored		= [NSMutableArray arrayWithCapacity:clusters.count];
	NSMutableArray		*inReach	= [NSMutableArray arrayWithCapacity:clusters.count];
	LDrawSnapCluster	*held		= nil;
	double				best		= -INFINITY;

	for (LDrawSnapCluster *cluster in clusters)
	{
		if (cluster.distance <= reach)
		{
			[inReach addObject:cluster];
			if (cluster.identifier == _heldPlacement)
			{
				held = cluster;
			}
		}
	}

	// The placement being held is scored first, whatever it is worth. The
	// walk below stops early, and the part can only stay where it is while
	// its own placement is among the answers.
	if (held != nil)
	{
		[self scoreCluster:held owner:owner dragDirection:dragDirection];
		if (held.votes > 0)
		{
			[scored addObject:held];
			best = held.score;
		}
	}

	// Most pairs first. A placement can score no more than its pairs are
	// worth, so once that ceiling falls below the best score that could be
	// taken up, nothing further can win and the rest need not be looked at:
	// reading whether a connector is free costs a question to the index.
	[inReach sortUsingComparator:^NSComparisonResult(LDrawSnapCluster *one,
													 LDrawSnapCluster *other) {
		if (one.votes == other.votes)
		{
			return (one.identifier < other.identifier) ? NSOrderedAscending : NSOrderedDescending;
		}
		return (one.votes > other.votes) ? NSOrderedAscending : NSOrderedDescending;
	}];

	for (LDrawSnapCluster *cluster in inReach)
	{
		if (cluster == held)
		{
			continue;
		}
		if (self.countWeight * (double)cluster.votes <= best)
		{
			break;
		}
		[self scoreCluster:cluster owner:owner dragDirection:dragDirection];

		if (cluster.votes == 0)
		{
			continue;			// every connector it would use is taken
		}
		[scored addObject:cluster];

		// Only a placement that could be taken up raises the bar. One too far
		// to latch on to cannot be chosen, so it must not stop nearer ones
		// from being looked at.
		if ([self screenDistance:cluster] <= self.acquireDistance)
		{
			best = MAX(best, cluster.score);
		}
	}

	return [scored sortedArrayUsingComparator:^NSComparisonResult(LDrawSnapCluster *one,
																  LDrawSnapCluster *other) {
		if (one.score == other.score)
		{
			// Break ties by identifier so the order is stable.
			return (one.identifier < other.identifier) ? NSOrderedAscending : NSOrderedDescending;
		}
		return (one.score > other.score) ? NSOrderedAscending : NSOrderedDescending;
	}];
}


//========== scoreCluster:owner:dragDirection: =================================
//
// Purpose:		Counts the pairs a placement still has free and scores it by
//				them. A placement with none left scores nothing.
//
//==============================================================================
- (void)scoreCluster:(LDrawSnapCluster *)cluster owner:(uint32_t)owner
	   dragDirection:(Vector3)dragDirection
{
	cluster.votes = [self freeMeetingsOfCluster:cluster owner:owner];
	cluster.score = (cluster.votes > 0) ? [self scoreOfCluster:cluster dragDirection:dragDirection] : 0.0;
}


//========== scoreOfCluster:dragDirection: =====================================
//
// Purpose:		What a placement is worth: the pairs that hold it, less how
//				far the part moves on screen, how far it turns, whether it
//				moves against the drag, and whether it is the one being held.
//
//==============================================================================
- (double)scoreOfCluster:(LDrawSnapCluster *)cluster dragDirection:(Vector3)dragDirection
{
	double drag = 0.0;

	if (V3Length(dragDirection) > 0.0 && cluster.distance > 0.0)
	{
		double along = V3Dot(V3Normalize(dragDirection), V3Normalize(cluster.displacement));

		drag = (1.0 - along) / 2.0;
	}
	return self.countWeight * (double)cluster.votes
		 - self.distanceWeight * cluster.distance * self.pointsPerUnit
		 - self.angleWeight * cluster.angle
		 - self.dragWeight * drag
		 - self.switchWeight * ((cluster.identifier == _heldPlacement) ? 0.0 : 1.0);
}


//========== solutionFromRankedClusters: =======================================
//
// Purpose:		Picks the placement to hold. A part snaps to the best placement
//				within the acquire distance. It keeps that placement until it
//				is dragged past the release distance, or another placement
//				scores better by the switch margin.
//
//==============================================================================
- (LDrawSnapSolution)solutionFromRankedClusters:(NSArray<LDrawSnapCluster *> *)clusters
{
	LDrawSnapCluster	*held	= nil;
	LDrawSnapCluster	*best	= nil;

	for (LDrawSnapCluster *cluster in clusters)
	{
		double		distance	= [self screenDistance:cluster];
		BOOL		isHeld		= (cluster.identifier == _heldPlacement);
		BOOL		couldHold	= (best == nil) && (distance <= self.acquireDistance);

		if (isHeld == NO && couldHold == NO)
		{
			continue;
		}
		if (isHeld && distance > self.releaseDistance)
		{
			continue;			// dragged past the release distance
		}
		if (isHeld && held == nil)
		{
			held = cluster;
		}
		if (couldHold)
		{
			best = cluster;
		}
	}

	if (held != nil)
	{
		double margin = self.switchMargin * MAX(fabs(held.score), self.countWeight);

		if (best != nil && best != held && best.score - held.score > margin)
		{
			return [self holdCluster:best];
		}
		return [self holdCluster:held];
	}
	if (best != nil)
	{
		return [self holdCluster:best];
	}

	[self releaseHold];

	return (LDrawSnapSolution){ .snapped = false, .transform = IdentityMatrix4 };
}


//========== holdCluster: ======================================================
//==============================================================================
- (LDrawSnapSolution)holdCluster:(LDrawSnapCluster *)cluster
{
	_heldPlacement = cluster.identifier;

	return (LDrawSnapSolution){
		.snapped	= true,
		.transform	= cluster.placement,
		.voteCount	= (uint32_t)cluster.votes,
		.score		= cluster.score,
		.distance	= [self screenDistance:cluster],
	};
}


//========== screenDistance: ===================================================
//==============================================================================
- (double)screenDistance:(LDrawSnapCluster *)cluster
{
	return cluster.distance * self.pointsPerUnit;
}


//========== freeMeetingsOfCluster:owner: ======================================
//
// Purpose:		How many of the connectors this placement meets are free.
//
// Notes:		A connector another part already holds does not hold this one,
//				so it does not count. It does not rule the placement out
//				either: a part over eight studs of which one is taken is
//				still held by the other seven, and a model always has parts
//				that touch without being connected.
//
//				The dragged part is left out: a part is often still in the
//				index while it is dragged, and its own connectors would make
//				the place it is leaving look taken.
//
//==============================================================================
- (NSUInteger)freeMeetingsOfCluster:(LDrawSnapCluster *)cluster owner:(uint32_t)owner
{
	const LDrawSnapMeeting	*meetings	= cluster.meetings.bytes;
	NSUInteger				count		= cluster.meetings.length / sizeof(LDrawSnapMeeting);
	NSUInteger				free		= 0;

	for (NSUInteger index = 0; index < count; index++)
	{
		LDrawWorldConnector	met			= meetings[index].met;
		Point3				mouth		= LDrawWorldConnectorMouth(met);
		Point3				end			= V3Add(mouth, V3MulScalar(met.axis, met.length));
		Box3				run			= V3BoundsFromPoints(mouth, end);
		BOOL				taken		= NO;

		run.min.x -= CoincidentDistance;	run.min.y -= CoincidentDistance;	run.min.z -= CoincidentDistance;
		run.max.x += CoincidentDistance;	run.max.y += CoincidentDistance;	run.max.z += CoincidentDistance;

		LDrawWorldConnectors	*neighbors	= [self.connectorIndex connectorsInBox:run excludingOwner:met.owner];

		const LDrawWorldConnector	*near		= neighbors.all;
		NSUInteger					found		= neighbors.count;

		for (NSUInteger other = 0; other < found && taken == NO; other++)
		{
			if (near[other].owner == owner || near[other].gender != meetings[index].movingGender)
			{
				continue;		// the part being dragged, or not after the same place
			}
			taken = [self connector:near[other] takesPlaceOf:meetings[index]];
		}
		free += (taken ? 0 : 1);

	}
	return free;
}


//========== connector:takesPlaceOf: ===========================================
//
// Purpose:		Whether a connector already lies where the dragged one would:
//				on the same line, over the same length.
//
// Notes:		Only the length the dragged connector would fill is checked,
//				so a long axle can hold a second beam further along.
//
//==============================================================================
- (BOOL)connector:(LDrawWorldConnector)one takesPlaceOf:(LDrawSnapMeeting)meeting
{
	LDrawWorldConnector	met		= meeting.met;
	Point3				mouth	= LDrawWorldConnectorMouth(met);
	Vector3				apart	= V3Sub(LDrawWorldConnectorMouth(one), mouth);
	double				start	= V3Dot(apart, met.axis);
	double				finish	= start + one.length * V3Dot(one.axis, met.axis);
	double				shared	= MIN(MAX(start, finish), MAX(meeting.start, meeting.finish))
								- MAX(MIN(start, finish), MIN(meeting.start, meeting.finish));

	if (fabs(V3Dot(one.axis, met.axis)) < cos(self.axisTolerance))
	{
		return NO;			// not parallel
	}
	if (V3Length(V3Sub(apart, V3MulScalar(met.axis, start))) > CoincidentDistance)
	{
		return NO;			// off the line
	}
	return (shared > OccupiedOverlap);
}


@end
