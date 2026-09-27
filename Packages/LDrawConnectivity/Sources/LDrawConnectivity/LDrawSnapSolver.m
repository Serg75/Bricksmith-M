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

// How wide the column under a hole is: half a stud pitch, so a part rides the
// surface between studs as well as over them.
static const double RestingColumn = 10.0;

// The stud pitch, which the columns are counted in.
static const double RestingPitch = 20.0;

// How much higher than the lowest hole a hole may be and still be asked about.
static const double RestingBand = 24.0;


// How far behind the first surface along the line of sight placements are
// still looked at, and ranked by their pairs. Further back than this they
// are behind it, and never paired: a surface in front always wins.
static const double LayerTolerance = 12.0;

// How much nearer the held placement counts, so an edge between two surfaces
// does not flick the part from one to the other.
static const double HeldDepthMargin = 8.0;

// How far a seated connector may sit from the mouth it meets, which a
// placement's distance from the line of sight can grow by.
static const double SightSlack = 8.0;

// How far behind what the finger sees a held point may land: a stud's height,
// for a stud that stands in the hole it is seen through.
static const double SurfaceSlack = 4.0;

// How much of the line of sight is fetched and paired at a time, at least.
static const double SightStretch = 64.0;

// How many surfaces along the line of sight are looked at before giving up.
// A surface whose placements are all taken or in the way leads to the next,
// and a line through a whole model can meet dozens.
static const NSUInteger MaximumSightSurfaces = 8;

// How deep two parts may share space and still be counted as joined rather
// than through each other: a stud's height.
static const double ClashDepth = 4.5;

// How far a placement may leave a part from where it was picked up and still
// count as putting it back: a model as built can sit a little off where its
// connectors meet.
static const double BackWhereItWas = 2.0;

// How much of a sliding line must show on the screen, as the squared sine of
// its angle to the sight, for the finger alone to say how far along it the
// part goes. Nearer the sight, the part keeps more of the depth it is held at.
static const double SlideFollowsSight = 0.1;

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


//---------- TurnAngle -------------------------------------------------[static]--
//
// Purpose:		How far each of the cube rotations turns a part, worked out
//				once.
//
//------------------------------------------------------------------------------
static double TurnAngle(NSUInteger turn)
{
	static double			angles[24];
	static dispatch_once_t	once;

	dispatch_once(&once, ^{
		NSUInteger		count		= 0;
		const Matrix4	*rotations	= CubeRotations(&count);

		for (NSUInteger index = 0; index < count; index++)
		{
			angles[index] = RotationAngle(rotations[index]);
		}
	});
	return (turn < 24) ? angles[turn] : 0.0;
}


//---------- AxesMeet --------------------------------------------------[static]--
//
// Purpose:		Whether a dragged connector pointing along the given axis lines
//				up with a met one. Opposite axes line up too when either is
//				open at both ends.
//
//------------------------------------------------------------------------------
static BOOL AxesMeet(Vector3 axis, LDrawWorldConnector moving, LDrawWorldConnector met, double agreeing)
{
	double cosine = V3Dot(axis, met.axis);

	return (cosine >= agreeing) || (cosine <= -agreeing && (moving.bothEndsOpen || met.bothEndsOpen));
}


//---------- FaceEachOther ---------------------------------------------[static]--
//
// Purpose:		Describes one of a pair from its far end when the dragged
//				connector, pointing along the given axis, meets the other from
//				there.
//
//------------------------------------------------------------------------------
static void FaceEachOther(Vector3 axis, LDrawWorldConnector *moving, LDrawWorldConnector *met)
{
	if (V3Dot(axis, met->axis) >= 0.0)
	{
		return;
	}
	if (moving->bothEndsOpen)
	{
		*moving = LDrawWorldConnectorReversed(*moving);
	}
	else if (met->bothEndsOpen)
	{
		*met = LDrawWorldConnectorReversed(*met);
	}
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
@property (nonatomic) double			depth;			// how far along the line of sight it lands
@property (nonatomic) BOOL				checked;		// votes are the free pairs, 0 if it clashes
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
	int64_t			_heldPlacement;
	NSMutableData	*_movingBounds;			// Box3 a part, in the model's coordinates
	NSMutableIndexSet *_excused;			// owners it may share space with where it started
	Box3			_startBounds;			// the space it filled where it started
	NSMutableData	*_movedBounds;			// Box3 a part, for one placement
	double			_nearestDepth;			// of the placements within reach, along the sight
	BOOL			_sighting;				// placements are measured along _sight
	LDrawSightLine	_sight;
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
		_switchMargin		= 5.0;
		_dropReach			= 0.0;
		_maximumTurn		= M_PI;
		_movingBounds		= [NSMutableData data];
		_excused			= [NSMutableIndexSet indexSet];
		_startBounds		= InvalidBox;
		_movedBounds		= [NSMutableData data];
		_pointsPerUnit		= 1.0;
		_axisTolerance		= 0.05;
		_allowsRotation		= YES;
		_countWeight		= 4.0;
		_distanceWeight		= 1.0;
		_angleWeight		= 20.0;
		_dragWeight			= 3.0;
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


//---------- ReachDistance ---------------------------------------------[static]--
//
// Purpose:		How far a placement counts as moving the part. A move down
//				counts for less, because a part let go over a stud field is
//				meant to land on it. Up counts in full: nothing should be
//				drawn into the air.
//
//------------------------------------------------------------------------------
static double ReachDistance(Vector3 displacement, double dropReach)
{
	double down = (displacement.y > 0.0) ? MAX(0.0, displacement.y - dropReach) : displacement.y;

	return V3Length(V3Make(displacement.x, down, displacement.z));
}


//---------- StudIsCovered ---------------------------------------------[static]--
//
// Purpose:		Whether a part already sits on a stud. A stud inside a stack is
//				covered by the part above it, and nothing else can rest there.
//
//------------------------------------------------------------------------------
static BOOL StudIsCovered(LDrawWorldConnector stud, Point3 mouth, const int64_t *keys,
						  CFMutableDictionaryRef taken, const LDrawWorldConnector *found)
{
	for (int at = 0; at < 9; at++)
	{
		NSData			*column	= (__bridge NSData *)
								  CFDictionaryGetValue(taken, (const void *)(intptr_t)keys[at]);
		const uint32_t	*places	= column.bytes;
		NSUInteger		count	= column.length / sizeof(uint32_t);

		for (NSUInteger place = 0; place < count; place++)
		{
			if (found[places[place]].owner != stud.owner
				&& V3Length(V3Sub(LDrawWorldConnectorMouth(found[places[place]]), mouth)) <= CoincidentDistance)
			{
				return YES;
			}
		}
	}
	return NO;
}


//---------- ColumnKey -------------------------------------------------[static]--
//
// Purpose:		Which column of the stud lattice a point stands in, ignoring
//				its height.
//
//------------------------------------------------------------------------------
static int64_t ColumnKey(Point3 point)
{
	return LDrawCellKey((int64_t)floor(point.x / RestingPitch), 0,
						(int64_t)floor(point.z / RestingPitch));
}


//---------- FileByColumn ----------------------------------------------[static]--
//
// Purpose:		Files a connector's place under its column, so a stud can find
//				what shares its column without looking at all of them.
//
//------------------------------------------------------------------------------
static void FileByColumn(CFMutableDictionaryRef columns, Point3 mouth, uint32_t place)
{
	int64_t			key		= ColumnKey(mouth);
	NSMutableData	*column	= (__bridge NSMutableData *)
							  CFDictionaryGetValue(columns, (const void *)(intptr_t)key);

	if (column == nil)
	{
		column = [NSMutableData data];
		CFDictionarySetValue(columns, (const void *)(intptr_t)key, (__bridge const void *)column);
	}
	[column appendBytes:&place length:sizeof(place)];
}


//---------- ColumnsAround ---------------------------------------------[static]--
//
// Purpose:		The columns a point can reach across, which is its own and the
//				ones around it: a stud holds anything within half a pitch.
//
//------------------------------------------------------------------------------
static void ColumnsAround(Point3 mouth, int64_t *keys)
{
	int64_t	x	= (int64_t)floor(mouth.x / RestingPitch);
	int64_t	z	= (int64_t)floor(mouth.z / RestingPitch);
	int		at	= 0;

	for (int64_t alongX = -1; alongX <= 1; alongX++)
	{
		for (int64_t alongZ = -1; alongZ <= 1; alongZ++)
		{
			keys[at++] = LDrawCellKey(x + alongX, 0, z + alongZ);
		}
	}
}


#pragma mark - Along the line of sight

/// Two directions across the screen, and the rectangle the dragged part's
/// connectors cover on it, from the held point, widened by the reach.
typedef struct
{
	Vector3		across;
	Vector3		up;
	double		left, right, bottom, top;

} LDrawSightFrame;


/// A dragged connector and a met one that could bring the held point under
/// the finger, turned one way, and how deep along the sight it would land.
typedef struct
{
	uint32_t	moving;
	uint32_t	met;
	uint32_t	turn;
	double		depth;

} LDrawSightPair;

//---------- ClipLineToBox ---------------------------------------------[static]--
//
// Purpose:		Where a line runs through a box, as distances along it from its
//				origin. Only what is in front of the origin counts.
//
//------------------------------------------------------------------------------
static BOOL ClipLineToBox(Point3 origin, Vector3 direction, Box3 box, double *outNear, double *outFar)
{
	double	near	= 0.0;
	double	far		= INFINITY;
	double	start[3]	= { origin.x, origin.y, origin.z };
	double	step[3]		= { direction.x, direction.y, direction.z };
	double	low[3]		= { box.min.x, box.min.y, box.min.z };
	double	high[3]		= { box.max.x, box.max.y, box.max.z };

	for (int axis = 0; axis < 3; axis++)
	{
		if (fabs(step[axis]) < 1e-12)
		{
			if (start[axis] < low[axis] || start[axis] > high[axis])
			{
				return NO;		// parallel to this side and outside it
			}
			continue;
		}
		double one		= (low[axis] - start[axis]) / step[axis];
		double other	= (high[axis] - start[axis]) / step[axis];

		near	= MAX(near, MIN(one, other));
		far		= MIN(far, MAX(one, other));
	}
	*outNear	= near;
	*outFar		= far;

	return near <= far;
}


//---------- DistanceFromSight -----------------------------------------[static]--
//
// Purpose:		How far a point is from the line of sight, and how far along it.
//
//------------------------------------------------------------------------------
static double DistanceFromSight(Point3 point, LDrawSightLine sight, double *outAlong, Vector3 *outAside)
{
	Vector3	relative	= V3Sub(point, sight.origin);
	double	along		= V3Dot(relative, sight.direction);
	Vector3	aside		= V3Sub(relative, V3MulScalar(sight.direction, along));

	if (outAlong != NULL)
	{
		*outAlong = along;
	}
	if (outAside != NULL)
	{
		*outAside = aside;
	}
	return V3Length(aside);
}


//========== solutionForConnectors:alongSight:dragDirection: ===================
//
// Notes:		Walks out from the screen along the line a stretch at a time,
//				pairing the nearest first, and stops once it is past the first
//				surface it can land on. A line through a solid model meets far
//				more connectors than could ever win.
//
//==============================================================================
- (LDrawSnapSolution)solutionForConnectors:(LDrawWorldConnectors *)movingConnectors
								alongSight:(LDrawSightLine)sight
							 dragDirection:(Vector3)dragDirection
{
	const LDrawWorldConnector	*moving		= movingConnectors.all;
	NSUInteger					count		= movingConnectors.count;
	double						reach		= self.releaseDistance / self.pointsPerUnit;
	double						extent		= 0.0;		// how far the part reaches from the held point
	double						deep		= 0.0;		// how far of that is along the line
	double						near		= 0.0;
	double						far			= 0.0;
	BOOL						turning		= (self.allowsRotation && self.maximumTurn >= M_PI_2 - 1e-9);
	NSArray<LDrawSnapCluster *>	*ranked		= @[];

	if (count == 0 || self.pointsPerUnit <= 0.0)
	{
		return (LDrawSnapSolution){ .snapped = false, .transform = IdentityMatrix4 };
	}
	for (NSUInteger index = 0; index < count; index++)
	{
		Vector3 way = V3Sub(LDrawWorldConnectorMouth(moving[index]), sight.grab);

		extent	= MAX(extent, V3Length(way));
		deep	= MAX(deep, fabs(V3Dot(way, sight.direction)));
	}
	// A part that may turn can bring any of its reach to lie along the line.
	if (turning)
	{
		deep = extent;
	}

	double radius = reach + extent + SightSlack;

	if ([self clipSight:sight within:radius near:&near far:&far] == NO)
	{
		return [self solutionFromRankedClusters:ranked];
	}

	// What the finger sees hides everything behind it. The held point of a
	// placement there lands deeper than it, and a met connector lies within
	// the part's depth of the held point.
	BOOL	seeing		= isfinite(sight.surface);
	double	furthest	= seeing ? sight.surface + SurfaceSlack : INFINITY;

	if (seeing)
	{
		far = MIN(far, furthest + deep);

		if (near > far)
		{
			return [self solutionFromRankedClusters:ranked];
		}
	}

	LDrawSightFrame			frame		= [self frameForConnectors:movingConnectors alongSight:sight];
	LDrawWorldConnectors	*fetched	= [LDrawWorldConnectors connectors];
	NSMutableData			*pending	= [NSMutableData data];
	Point3					anchor		= [self anchorOfConnectors:movingConnectors];
	LDrawSnapClusterTable	*clusters	= [[LDrawSnapClusterTable alloc] init];
	double					stretch		= MAX(SightStretch, 2.0 * deep);
	double					from		= near;
	BOOL					decided		= NO;
	NSUInteger				surfaces	= 0;		// passed over, all taken or in the way

	_sighting		= YES;
	_sight			= sight;
	_nearestDepth	= INFINITY;

	while (decided == NO)
	{
		if (from < far)
		{
			double to = MIN(from + stretch, far);

			[self appendPairsAlongSight:sight frame:frame moving:movingConnectors from:from to:to
								fetched:fetched pairs:pending];
			from = to;
		}

		// A pair from further on lands no nearer than where the rest of the
		// line starts, less how deep the part reaches along it. Nearer than
		// that, the order is settled.
		double settled = (from < far) ? from - deep - SightSlack : INFINITY;

		qsort_b(pending.mutableBytes, pending.length / sizeof(LDrawSightPair), sizeof(LDrawSightPair),
				^int(const void *one, const void *other) {
			double first	= ((const LDrawSightPair *)one)->depth;
			double second	= ((const LDrawSightPair *)other)->depth;

			return (first < second) ? -1 : (first > second) ? 1 : 0;
		});

		const LDrawSightPair		*pairs		= pending.bytes;
		NSUInteger					pairCount	= pending.length / sizeof(LDrawSightPair);
		const LDrawWorldConnector	*met		= fetched.all;
		NSUInteger					marched		= 0;

		for (; marched < pairCount && pairs[marched].depth < settled; marched++)
		{
			if (pairs[marched].depth > furthest)
			{
				continue;		// hidden behind what the finger sees
			}
			// Past the first surface something landed on. Ranking checks
			// which placements can be taken, and moves the surface back to
			// the first of those: one in front may be taken or in the way.
			// Stop once past a surface that offers something, and look
			// further on when none does. When the finger sees what it is
			// over, everything in front of that is ranked together instead.
			if (seeing == NO
				&& pairs[marched].depth - SightSlack > _nearestDepth + LayerTolerance + HeldDepthMargin)
			{
				ranked = [self rankedClusters:clusters.clusters owner:moving[0].owner dragDirection:dragDirection];

				if ([self rankedClustersOfferAPlacement:ranked])
				{
					if (pairs[marched].depth - SightSlack > _nearestDepth + LayerTolerance + HeldDepthMargin)
					{
						decided = YES;
						break;
					}
				}
				else if (++surfaces >= MaximumSightSurfaces)
				{
					decided = YES;
					break;
				}
				else
				{
					_nearestDepth = INFINITY;
				}
			}
			[self addPlacementOfConnector:moving[pairs[marched].moving]
								  meeting:met[pairs[marched].met]
									 turn:pairs[marched].turn
								   anchor:anchor
									   to:clusters];
		}
		[pending replaceBytesInRange:NSMakeRange(0, marched * sizeof(LDrawSightPair)) withBytes:NULL length:0];

		if (decided == NO && from >= far && pending.length == 0)
		{
			ranked	= [self rankedClusters:clusters.clusters owner:moving[0].owner dragDirection:dragDirection];
			decided	= YES;			// the end of the line
		}
	}
	_sighting = NO;

	return [self solutionFromRankedClusters:ranked];
}


//========== clipSight:within:near:far: ========================================
//
// Purpose:		Where the line runs through the model, widened by how far from
//				it a connector can be and still bring the part under the finger.
//
//==============================================================================
- (BOOL)clipSight:(LDrawSightLine)sight within:(double)radius near:(double *)outNear far:(double *)outFar
{
	Box3 model = self.connectorIndex.occupiedBounds;

	if (V3EqualBoxes(model, InvalidBox))
	{
		return NO;
	}
	model.min.x -= radius;	model.min.y -= radius;	model.min.z -= radius;
	model.max.x += radius;	model.max.y += radius;	model.max.z += radius;

	return ClipLineToBox(sight.origin, sight.direction, model, outNear, outFar);
}


//========== frameForConnectors:alongSight: ====================================
//
// Purpose:		Where on the screen the dragged part's connectors lie around
//				the held point, for each way it may be turned. A met connector
//				outside that, less the reach, cannot hold it with the held
//				point under the finger.
//
//==============================================================================
- (LDrawSightFrame)frameForConnectors:(LDrawWorldConnectors *)movingConnectors
						   alongSight:(LDrawSightLine)sight
{
	const LDrawWorldConnector	*moving			= movingConnectors.all;
	NSUInteger					count			= movingConnectors.count;
	Vector3						side			= (fabs(sight.direction.y) < 0.9) ? V3Make(0, 1, 0)
																				  : V3Make(1, 0, 0);
	double						room			= self.releaseDistance / self.pointsPerUnit + SightSlack;
	NSUInteger					rotationCount	= 0;
	const Matrix4				*rotations		= CubeRotations(&rotationCount);
	LDrawSightFrame				frame			= {
		.left	= INFINITY,		.right	= -INFINITY,
		.bottom	= INFINITY,		.top	= -INFINITY,
	};

	frame.across	= V3Normalize(V3Cross(sight.direction, side));
	frame.up		= V3Cross(frame.across, sight.direction);

	for (NSUInteger turn = 0; turn <= rotationCount; turn++)
	{
		BOOL	turned		= (turn < rotationCount);
		Matrix4	rotation	= turned ? rotations[turn] : IdentityMatrix4;

		if (turned && [self turnIsAllowed:turn] == NO)
		{
			continue;
		}
		for (NSUInteger one = 0; one < count; one++)
		{
			Vector3 way = LDrawDirectionByMatrix(V3Sub(LDrawWorldConnectorMouth(moving[one]), sight.grab),
												 rotation);

			frame.left		= MIN(frame.left, V3Dot(way, frame.across));
			frame.right		= MAX(frame.right, V3Dot(way, frame.across));
			frame.bottom	= MIN(frame.bottom, V3Dot(way, frame.up));
			frame.top		= MAX(frame.top, V3Dot(way, frame.up));
		}
	}
	frame.left		-= room;	frame.right	+= room;
	frame.bottom	-= room;	frame.top	+= room;

	return frame;
}


//========== turnIsAllowed: ====================================================
//
// Purpose:		Whether a part may be turned this way, other than not at all.
//
//==============================================================================
- (BOOL)turnIsAllowed:(NSUInteger)turn
{
	return self.allowsRotation && TurnAngle(turn) <= self.maximumTurn + 1e-9 && TurnAngle(turn) > 1e-9;
}


//========== appendPairsAlongSight:frame:moving:from:to:fetched:pairs: =========
//
// Purpose:		The pairs of connectors, from one stretch of the line, that
//				would bring the held point under the finger.
//
// Notes:		A pair moves the held point to where the met connector is, less
//				the way from the held point to the dragged connector, turned as
//				the pair turns the part. Seen on the screen, that is within
//				reach of the finger only when the met connector is within reach
//				of that way. So the met connectors are filed by where they are
//				on the screen, and each dragged connector looks in one place:
//				pairing every dragged connector with every met one costs many
//				frames for a part the size of a door.
//
//				A sliding pair can land anywhere along the met run, not only at
//				its mouth. Those few are paired directly, and measured where
//				they would land.
//
//==============================================================================
- (void)appendPairsAlongSight:(LDrawSightLine)sight
						frame:(LDrawSightFrame)frame
					   moving:(LDrawWorldConnectors *)movingConnectors
						 from:(double)from
						   to:(double)to
					  fetched:(LDrawWorldConnectors *)fetched
						pairs:(NSMutableData *)pairs
{
	const LDrawWorldConnector	*moving		= movingConnectors.all;
	NSUInteger					movingCount	= movingConnectors.count;
	Vector3						across		= frame.across;
	Vector3						up			= frame.up;
	double						room		= self.releaseDistance / self.pointsPerUnit + SightSlack;
	Box3						around		= InvalidBox;
	LDrawWorldConnectors		*flat		= [LDrawWorldConnectors connectors];
	NSMutableData				*placesData	= [NSMutableData data];		// uint32_t a place in fetched
	NSMutableData				*alongData	= [NSMutableData data];		// double a place
	NSMutableData				*slidingData = [NSMutableData data];	// uint32_t a place in fetched
	NSUInteger					rotationCount = 0;
	const Matrix4				*rotations	= CubeRotations(&rotationCount);
	double						agreeing	= cos(self.axisTolerance);

	// Only the part's outline on the screen, through this stretch of the line:
	// a box around the whole reach of the part fetches a whole model.
	for (NSUInteger corner = 0; corner < 8; corner++)
	{
		double	x		= (corner & 1) ? frame.right : frame.left;
		double	y		= (corner & 2) ? frame.top : frame.bottom;
		double	along	= (corner & 4) ? to + SightSlack : from - SightSlack;
		Point3	point	= V3Add(V3Add(V3Add(sight.origin, V3MulScalar(across, x)), V3MulScalar(up, y)),
								V3MulScalar(sight.direction, along));

		around = V3UnionBoxAndPoint(around, point);
	}

	LDrawWorldConnectors		*found		= [self.connectorIndex connectorsInBox:around
															   excludingOwner:moving[0].owner];
	const LDrawWorldConnector	*candidates	= found.all;
	NSUInteger					foundCount	= found.count;

	// Each connector of this stretch where it is on the screen, as a point
	// with no depth. One whose mouth is in another stretch is left to it,
	// unless it slides: its run may cross this stretch.
	for (NSUInteger index = 0; index < foundCount; index++)
	{
		Vector3				relative	= V3Sub(LDrawWorldConnectorMouth(candidates[index]), sight.origin);
		double				along		= V3Dot(relative, sight.direction);
		BOOL				here		= (along >= from && along < to);
		uint32_t			place		= (uint32_t)fetched.count;
		LDrawWorldConnector	seen		= {};

		if (here == NO && candidates[index].slide == NO)
		{
			continue;
		}
		[fetched addConnector:candidates[index]];

		if (candidates[index].slide)
		{
			[slidingData appendBytes:&place length:sizeof(place)];
		}
		if (here)
		{
			seen.position	= V3Make(V3Dot(relative, across), V3Dot(relative, up), 0.0);
			seen.axis		= V3Make(0, 0, 1);
			[flat addConnector:seen];
			[placesData appendBytes:&place length:sizeof(place)];
			[alongData appendBytes:&along length:sizeof(along)];
		}
	}
	if (flat.count == 0 && slidingData.length == 0)
	{
		return;
	}

	const LDrawWorldConnector	*known			= fetched.all;
	const uint32_t				*places			= placesData.bytes;
	const double				*along			= alongData.bytes;
	const uint32_t				*sliding		= slidingData.bytes;
	NSUInteger					slidingCount	= slidingData.length / sizeof(uint32_t);
	LDrawConnectorNeighborhood	*screen			= [[LDrawConnectorNeighborhood alloc] initWithConnectors:flat
																							cellSize:room];

	for (NSUInteger turn = 0; turn <= rotationCount; turn++)
	{
		BOOL	turned		= (turn < rotationCount);
		Matrix4	rotation	= turned ? rotations[turn] : IdentityMatrix4;

		if (turned && [self turnIsAllowed:turn] == NO)
		{
			continue;			// not allowed, or the same as not turning
		}
		for (NSUInteger one = 0; one < movingCount; one++)
		{
			Vector3			way		= LDrawDirectionByMatrix(V3Sub(LDrawWorldConnectorMouth(moving[one]),
																   sight.grab), rotation);
			double			x		= V3Dot(way, across);
			double			y		= V3Dot(way, up);
			double			deep	= V3Dot(way, sight.direction);
			NSUInteger		count	= 0;
			const uint32_t	*close	= [screen indicesNearBox:V3BoundsFromPoints(V3Make(x - room, y - room, -1),
																				V3Make(x + room, y + room, 1))
													   count:&count];

			for (NSUInteger index = 0; index < count; index++)
			{
				LDrawSightPair pair = {
					.moving	= (uint32_t)one,
					.met	= places[close[index]],
					.turn	= (uint32_t)(turned ? turn : NoTurn),
					.depth	= along[close[index]] - deep,
				};

				if (moving[one].slide && known[pair.met].slide)
				{
					continue;			// paired along its run below
				}
				[pairs appendBytes:&pair length:sizeof(pair)];
			}
			for (NSUInteger index = 0; moving[one].slide && index < slidingCount; index++)
			{
				LDrawWorldConnector	mover	= moving[one];
				LDrawWorldConnector	met		= known[sliding[index]];
				Vector3				axis	= LDrawDirectionByMatrix(mover.axis, rotation);

				if (mover.gender == met.gender || AxesMeet(axis, mover, met, agreeing) == NO)
				{
					continue;
				}
				FaceEachOther(axis, &mover, &met);

				Point3	seated	= LDrawWorldConnectorMouth(met);
				double	shared	= met.length - mover.length;
				double	slide	= [self slideOfMoving:mover meeting:met seated:seated rotation:rotation
												turn:(turned ? turn : NoTurn)];
				Point3	landing	= V3Add(seated, V3MulScalar(met.axis, MAX(MIN(shared, 0.0),
																		  MIN(MAX(shared, 0.0), slide))));
				Point3	held	= V3Add(landing, LDrawDirectionByMatrix(V3Sub(sight.grab,
																			  LDrawWorldConnectorMouth(mover)),
																		rotation));
				double	reached	= V3Dot(V3Sub(landing, sight.origin), sight.direction);
				double	depth	= 0.0;

				// Each stretch the run crosses fetches it, and the one it
				// lands in pairs it.
				if (reached < from || reached >= to || DistanceFromSight(held, sight, &depth, NULL) > room)
				{
					continue;
				}
				LDrawSightPair pair = {
					.moving	= (uint32_t)one,
					.met	= sliding[index],
					.turn	= (uint32_t)(turned ? turn : NoTurn),
					.depth	= depth,
				};
				[pairs appendBytes:&pair length:sizeof(pair)];
			}
		}
	}
}


//========== measureClusterAlongSight: =========================================
//
// Purpose:		How far a placement leaves the held point from the finger,
//				across the screen, and how deep along the sight it lands.
//
//==============================================================================
- (void)measureClusterAlongSight:(LDrawSnapCluster *)cluster
{
	Point3	held	= V3MulPointByProjMatrix(_sight.grab, cluster.placement);
	double	along	= 0.0;
	Vector3	aside	= ZeroPoint3;

	cluster.distance		= DistanceFromSight(held, _sight, &along, &aside);
	cluster.displacement	= aside;
	cluster.depth			= along;

	if (cluster.distance * self.pointsPerUnit <= self.releaseDistance)
	{
		_nearestDepth = MIN(_nearestDepth, along);
	}
}


//========== rankedClustersOfferAPlacement: ====================================
//
// Purpose:		Whether any ranked placement would be taken up or kept.
//
//==============================================================================
- (BOOL)rankedClustersOfferAPlacement:(NSArray<LDrawSnapCluster *> *)ranked
{
	for (LDrawSnapCluster *cluster in ranked)
	{
		double distance = [self screenDistance:cluster];

		if (distance <= self.acquireDistance
			|| (cluster.identifier == _heldPlacement && distance <= self.releaseDistance))
		{
			return YES;
		}
	}
	return NO;
}


#pragma mark - Resting on what is under it

//========== restingDropForConnectors:within: ==================================
//
// Purpose:		How far the part falls before something stops it.
//
// Notes:		Only holes are asked, because only they can sit on a stud, and
//				only those in the lowest band of the part: what hangs lowest
//				touches first. A stud counts as under a hole when it is inside
//				the same column, half a stud pitch across, so a part rides the
//				surface between studs as well as over them.
//
//				The answer can be negative, which lifts a part onto something
//				taller it has slid onto instead of leaving it inside, however
//				much taller that is. A stud with a part already on it is
//				passed over, so a part cannot rest inside a stack.
//
//				It asks the index once for everything under the part and files
//				both sides by column. A part made of fifty others has hundreds
//				of holes, and a question each would cost a frame.
//
//==============================================================================
- (double)restingDropForConnectors:(LDrawWorldConnectors *)movingConnectors
							within:(double)reach
{
	const LDrawWorldConnector	*moving		= movingConnectors.all;
	NSUInteger					count		= movingConnectors.count;
	double						lowest		= -INFINITY;
	double						drop		= INFINITY;
	Box3						footprint	= InvalidBox;

	if (count == 0 || reach <= 0.0)
	{
		return 0.0;
	}
	for (NSUInteger index = 0; index < count; index++)
	{
		if (moving[index].gender == LDrawConnectorGenderFemale)
		{
			lowest = MAX(lowest, LDrawWorldConnectorMouth(moving[index]).y);
		}
	}
	if (lowest == -INFINITY)
	{
		return 0.0;				// nothing on it can sit on a stud
	}

	CFMutableDictionaryRef holes = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);

	for (NSUInteger index = 0; index < count; index++)
	{
		Point3 mouth = LDrawWorldConnectorMouth(moving[index]);

		if (moving[index].gender == LDrawConnectorGenderFemale && mouth.y >= lowest - RestingBand)
		{
			FileByColumn(holes, mouth, (uint32_t)index);
			footprint = V3UnionBoxAndPoint(footprint, mouth);
		}
	}

	footprint.min.x -= RestingColumn;	footprint.min.z -= RestingColumn;
	footprint.max.x += RestingColumn;	footprint.max.z += RestingColumn;
	footprint.min.y -= reach;			footprint.max.y += reach;

	LDrawWorldConnectors		*under	= [self.connectorIndex connectorsInBox:footprint
															   excludingOwner:moving[0].owner];
	const LDrawWorldConnector	*found	= under.all;
	NSUInteger					nearby	= under.count;
	CFMutableDictionaryRef		taken	= CFDictionaryCreateMutable(NULL, 0, NULL,
																	&kCFTypeDictionaryValueCallBacks);

	// The holes of the parts already there, so a stud under one is passed over.
	for (NSUInteger index = 0; index < nearby; index++)
	{
		if (found[index].gender == LDrawConnectorGenderFemale)
		{
			FileByColumn(taken, LDrawWorldConnectorMouth(found[index]), (uint32_t)index);
		}
	}

	for (NSUInteger index = 0; index < nearby; index++)
	{
		Point3	stud	= LDrawWorldConnectorMouth(found[index]);
		int64_t	keys[9];

		if (found[index].gender != LDrawConnectorGenderMale)
		{
			continue;
		}
		ColumnsAround(stud, keys);

		if (StudIsCovered(found[index], stud, keys, taken, found))
		{
			continue;
		}
		for (int at = 0; at < 9; at++)
		{
			NSData			*column	= (__bridge NSData *)
									  CFDictionaryGetValue(holes, (const void *)(intptr_t)keys[at]);
			const uint32_t	*places	= column.bytes;
			NSUInteger		places_count = column.length / sizeof(uint32_t);

			for (NSUInteger place = 0; place < places_count; place++)
			{
				Point3 mouth = LDrawWorldConnectorMouth(moving[places[place]]);

				if (fabs(mouth.x - stud.x) <= RestingColumn && fabs(mouth.z - stud.z) <= RestingColumn)
				{
					drop = MIN(drop, stud.y - mouth.y);
				}
			}
		}
	}
	CFRelease(holes);
	CFRelease(taken);

	return (drop == INFINITY) ? 0.0 : drop;
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
	_nearestDepth	= 0.0;
	met				= [self.connectorIndex connectorsInBox:[self searchBoxForConnectors:movingConnectors]
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
	box.max.y += self.dropReach;			// +Y is down

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
	box.max.y += self.dropReach;			// +Y is down

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
	LDrawSnapClusterTable		*clusters		= [[LDrawSnapClusterTable alloc] init];
	LDrawConnectorNeighborhood	*nearby			= [[LDrawConnectorNeighborhood alloc]
												   initWithConnectors:metConnectors cellSize:reach];
	const LDrawWorldConnector	*met			= [nearby connectors];

	for (NSUInteger one = 0; one < movingCount; one++)
	{
		NSUInteger		count	= 0;
		const uint32_t	*close	= [nearby indicesNearBox:[self searchBoxForConnector:moving[one] reach:reach]
													count:&count];
		double			landing	= [self nearestLandingBelow:moving[one] among:met indices:close
													  count:count reach:reach];

		for (NSUInteger index = 0; index < count; index++)
		{
			NSUInteger	other	= close[index];
			double		below	= LDrawWorldConnectorMouth(met[other]).y
								  - LDrawWorldConnectorMouth(moving[one]).y;

			if (below > reach && below > landing + CoincidentDistance)
			{
				continue;			// buried under the first thing the part can land on
			}
			[self addPlacementsOfConnector:moving[one] meeting:met[other] anchor:anchor to:clusters];
		}
	}
	return clusters.clusters;
}


//========== addPlacementsOfConnector:meeting:anchor:to: =======================
//
// Purpose:		Every placement one pair of connectors gives: the one that only
//				moves the part when their axes already agree, or one for each
//				upright turn that makes them agree.
//
//==============================================================================
- (void)addPlacementsOfConnector:(LDrawWorldConnector)moving
						 meeting:(LDrawWorldConnector)met
						  anchor:(Point3)anchor
							  to:(LDrawSnapClusterTable *)clusters
{
	NSUInteger		rotationCount	= 0;
	const Matrix4	*rotations		= CubeRotations(&rotationCount);
	double			agreeing		= cos(self.axisTolerance);

	if (AxesMeet(moving.axis, moving, met, agreeing))
	{
		[self addPlacementOfConnector:moving meeting:met turn:NoTurn anchor:anchor to:clusters];
		return;
	}
	if (self.allowsRotation == NO)
	{
		return;
	}
	for (NSUInteger turn = 0; turn < rotationCount; turn++)
	{
		// The cheap test first: most turns do not bring the axes together.
		if (AxesMeet(LDrawDirectionByMatrix(moving.axis, rotations[turn]), moving, met, agreeing))
		{
			[self addPlacementOfConnector:moving meeting:met turn:turn anchor:anchor to:clusters];
		}
	}
}


//========== addPlacementOfConnector:meeting:turn:anchor:to: ===================
//
// Purpose:		The placement one pair of connectors gives when the part is
//				turned one given way, if that turn is allowed and brings their
//				axes together.
//
// Notes:		A pair whose axes already agree is only moved. Turning it as
//				well would only spin the part about the connector.
//
//==============================================================================
- (void)addPlacementOfConnector:(LDrawWorldConnector)moving
						meeting:(LDrawWorldConnector)met
						   turn:(NSUInteger)turn
						 anchor:(Point3)anchor
							 to:(LDrawSnapClusterTable *)clusters
{
	NSUInteger		rotationCount	= 0;
	const Matrix4	*rotations		= CubeRotations(&rotationCount);
	Matrix4			rotation		= (turn == NoTurn) ? IdentityMatrix4 : rotations[turn];
	Vector3			turned			= LDrawDirectionByMatrix(moving.axis, rotation);
	double			agreeing		= cos(self.axisTolerance);
	BOOL			aligned			= AxesMeet(moving.axis, moving, met, agreeing);
	double			depth			= 0.0;

	if (met.owner == moving.owner)
	{
		return;					// a part does not hold itself
	}
	if (turn != NoTurn && (aligned || self.allowsRotation == NO
						   || TurnAngle(turn) > self.maximumTurn + 1e-9))
	{
		return;
	}
	if (AxesMeet(turned, moving, met, agreeing) == NO)
	{
		return;
	}
	FaceEachOther(turned, &moving, &met);

	if (LDrawWorldConnectorsMate(moving, met, (turn == NoTurn) ? self.axisTolerance : M_PI, &depth) == NO)
	{
		return;
	}
	[self addMeeting:met from:moving depth:depth rotation:rotation turn:turn anchor:anchor to:clusters];
}


//========== nearestLandingBelow:among:indices:count:reach: ====================
//
// Purpose:		How far under a connector the first thing it could land on
//				lies. A part let go over a wall lands on top of it, not inside
//				it, so the connectors below that are left out of the search.
//
// Notes:		Only what lies further down than the ordinary reach is
//				measured. Everything within reach is a placement in its own
//				right, whichever way it lies.
//
//==============================================================================
- (double)nearestLandingBelow:(LDrawWorldConnector)moving
					   among:(const LDrawWorldConnector *)met
					 indices:(const uint32_t *)close
					   count:(NSUInteger)count
					   reach:(double)reach
{
	double	mouth	= LDrawWorldConnectorMouth(moving).y;
	double	nearest	= INFINITY;

	if (self.dropReach <= 0.0)
	{
		return INFINITY;			// nothing is drawn down, so nothing is buried
	}
	for (NSUInteger index = 0; index < count; index++)
	{
		double below = LDrawWorldConnectorMouth(met[close[index]]).y - mouth;

		if (below > reach && below < nearest)
		{
			nearest = below;
		}
	}
	return nearest;
}


//========== slideOfMoving:meeting:seated:rotation:turn: =======================
//
// Purpose:		How far past its seat on the met axis a sliding pair wants the
//				dragged connector.
//
// Notes:		Off the line of sight the part keeps the depth it is held at.
//				Along it, the held point comes as near the finger as it can,
//				unless the line runs nearly along the sight.
//
//==============================================================================
- (double)slideOfMoving:(LDrawWorldConnector)moving
				meeting:(LDrawWorldConnector)met
				 seated:(Point3)seated
			   rotation:(Matrix4)rotation
				   turn:(NSUInteger)turn
{
	Point3	mouth	= LDrawWorldConnectorMouth(moving);
	double	kept	= 0.0;

	// A part that must turn is not on the met axis yet, so it has no depth
	// to keep.
	if (turn == NoTurn)
	{
		kept = V3Dot(V3Sub(mouth, seated), met.axis);
	}
	if (_sighting == NO)
	{
		return kept;
	}
	Point3	held	= V3Add(seated, LDrawDirectionByMatrix(V3Sub(_sight.grab, mouth), rotation));
	Vector3	apart	= V3Sub(held, _sight.origin);
	double	cosine	= V3Dot(met.axis, _sight.direction);
	double	across	= 1.0 - cosine * cosine;		// how much of the axis shows on the screen
	double	toward	= cosine * V3Dot(apart, _sight.direction) - V3Dot(apart, met.axis);

	// The slide that brings the held point nearest the line is toward / across.
	if (across >= SlideFollowsSight)
	{
		return toward / across;
	}
	return kept * (1.0 - across / SlideFollowsSight) + toward / SlideFollowsSight;
}


//========== landingForMoving:meeting:depth:rotation:turn: =====================
//
// Purpose:		Where the dragged connector's mouth goes: into the met mouth,
//				at the depth the profiles need.
//
// Notes:		When both connectors slide, such as an axle in a hole, the part
//				may sit anywhere along the shared length, short of what already
//				fills it, rounded to the grid.
//
//==============================================================================
- (Point3)landingForMoving:(LDrawWorldConnector)moving
				   meeting:(LDrawWorldConnector)met
					 depth:(double)depth
				  rotation:(Matrix4)rotation
					  turn:(NSUInteger)turn
{
	Point3	seated	= V3Add(LDrawWorldConnectorMouth(met), V3MulScalar(met.axis, depth));
	double	shared	= met.length - moving.length;
	double	lowest	= MIN(shared, 0.0);
	double	highest	= MAX(shared, 0.0);
	double	slide	= 0.0;

	if (moving.slide == NO || met.slide == NO)
	{
		return seated;
	}
	slide = [self slideOfMoving:moving meeting:met seated:seated rotation:rotation turn:turn];
	slide = MAX(lowest, MIN(highest, slide));
	slide = [self freeSlide:slide of:moving along:met seated:depth lowest:lowest highest:highest];

	return V3Add(seated, V3MulScalar(met.axis, round(slide / LatticeStep) * LatticeStep));
}


//========== freeSlide:of:along:seated:lowest:highest: =========================
//
// Purpose:		The slide nearest the wanted one that keeps the dragged
//				connector clear of what already fills the met line, so a part
//				pushed along an axle stops at the next part on it.
//
// Notes:		When no slide in range is clear, the wanted one is kept, and
//				the placement is refused as taken.
//
//==============================================================================
- (double)freeSlide:(double)wanted
				 of:(LDrawWorldConnector)moving
			  along:(LDrawWorldConnector)met
			 seated:(double)depth
			 lowest:(double)lowest
			highest:(double)highest
{
	Point3			mouth		= LDrawWorldConnectorMouth(met);
	Box3			run			= V3BoundsFromPoints(mouth, V3Add(mouth, V3MulScalar(met.axis, met.length)));
	NSMutableData	*spansData	= [NSMutableData data];		// two doubles a span: start, finish
	double			best		= wanted;
	BOOL			found		= NO;

	run.min.x -= CoincidentDistance;	run.min.y -= CoincidentDistance;	run.min.z -= CoincidentDistance;
	run.max.x += CoincidentDistance;	run.max.y += CoincidentDistance;	run.max.z += CoincidentDistance;

	LDrawWorldConnectors		*neighbors	= [self.connectorIndex connectorsInBox:run excludingOwner:met.owner];
	const LDrawWorldConnector	*near		= neighbors.all;

	for (NSUInteger other = 0; other < neighbors.count; other++)
	{
		double span[2] = { 0.0, 0.0 };

		if (near[other].owner == moving.owner || near[other].gender != moving.gender)
		{
			continue;
		}
		if ([self connector:near[other] liesAlong:met start:&span[0] finish:&span[1]])
		{
			[spansData appendBytes:span length:sizeof(span)];
		}
	}

	const double	*spans		= spansData.bytes;
	NSUInteger		spanCount	= spansData.length / (2 * sizeof(double));

	// Where it wants to be, and against either end of each filled span.
	for (NSUInteger candidate = 0; candidate <= 2 * spanCount; candidate++)
	{
		double	slide	= wanted;
		BOOL	clear	= YES;

		if (candidate > 0)
		{
			NSUInteger span = (candidate - 1) / 2;

			slide = (candidate % 2) ? spans[2 * span + 1] - depth
									: spans[2 * span] - depth - moving.length;
		}
		slide = MAX(lowest, MIN(highest, slide));

		if (found && fabs(slide - wanted) >= fabs(best - wanted))
		{
			continue;
		}
		for (NSUInteger span = 0; span < spanCount && clear; span++)
		{
			double shared = MIN(depth + slide + moving.length, spans[2 * span + 1])
						  - MAX(depth + slide, spans[2 * span]);

			clear = (shared <= OccupiedOverlap);
		}
		if (clear)
		{
			best	= slide;
			found	= YES;
		}
	}
	return best;
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
	Point3				landing		= [self landingForMoving:moving meeting:met depth:depth
													rotation:rotation turn:turn];
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
		cluster.distance	= ReachDistance(cluster.displacement, self.dropReach);

		if (_sighting)
		{
			[self measureClusterAlongSight:cluster];
		}
		[clusters addCluster:cluster];
	}
	// Another pair may free a placement a check refused, so it is checked
	// again.
	[cluster.meetings appendBytes:&meeting length:sizeof(meeting)];
	cluster.votes	= cluster.meetings.length / sizeof(LDrawSnapMeeting);
	cluster.checked	= NO;
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


//---------- PlacementJoins --------------------------------------------[static]--
//
// Purpose:		Whether a placement holds the dragged part to this one. Parts
//				that hold each other share space by design: a stud stands in a
//				hole, a hinge pin runs through its socket, a clip closes round
//				a bar. Only parts that are not joined may not overlap.
//
//------------------------------------------------------------------------------
static BOOL PlacementJoins(LDrawSnapCluster *cluster, uint32_t owner)
{
	const LDrawSnapMeeting	*meetings	= cluster.meetings.bytes;
	NSUInteger				count		= cluster.meetings.length / sizeof(LDrawSnapMeeting);

	for (NSUInteger index = 0; index < count; index++)
	{
		if (meetings[index].met.owner == owner)
		{
			return YES;
		}
	}
	return NO;
}


//---------- BoxesClash ------------------------------------------------[static]--
//
// Purpose:		Whether two parts share more space than parts that are joined
//				do. A stud stands in the hole it is in, so parts that hold
//				each other always share a little.
//
//------------------------------------------------------------------------------
static BOOL BoxesClash(Box3 one, Box3 other)
{
	double alongX = MIN(one.max.x, other.max.x) - MAX(one.min.x, other.min.x);
	double alongY = MIN(one.max.y, other.max.y) - MAX(one.min.y, other.min.y);
	double alongZ = MIN(one.max.z, other.max.z) - MAX(one.min.z, other.min.z);

	return (alongX > ClashDepth) && (alongY > ClashDepth) && (alongZ > ClashDepth);
}


//---------- BoxesAlike ------------------------------------------------[static]--
//
// Purpose:		Whether two boxes have every side within the tolerance of each
//				other.
//
//------------------------------------------------------------------------------
static BOOL BoxesAlike(Box3 one, Box3 other, double tolerance)
{
	return fabs(one.min.x - other.min.x) <= tolerance && fabs(one.max.x - other.max.x) <= tolerance
		&& fabs(one.min.y - other.min.y) <= tolerance && fabs(one.max.y - other.max.y) <= tolerance
		&& fabs(one.min.z - other.min.z) <= tolerance && fabs(one.max.z - other.max.z) <= tolerance;
}


//========== clearMovingBounds =================================================
//==============================================================================
- (void)clearMovingBounds
{
	_movingBounds.length = 0;
}


//========== addMovingBounds: ==================================================
//==============================================================================
- (void)addMovingBounds:(Box3)bounds
{
	[_movingBounds appendBytes:&bounds length:sizeof(bounds)];
}


//========== excusePartsItOverlaps =============================================
//==============================================================================
- (void)excusePartsItOverlaps
{
	const Box3	*parts	= _movingBounds.bytes;
	NSUInteger	count	= _movingBounds.length / sizeof(Box3);
	Box3		whole	= InvalidBox;

	[_excused removeAllIndexes];

	for (NSUInteger index = 0; index < count; index++)
	{
		whole = V3UnionBox(whole, parts[index]);
	}
	_startBounds = whole;

	if (count == 0)
	{
		return;
	}

	LDrawWorldConnectors		*nearby	= [self.connectorIndex connectorsInBox:whole excludingOwner:UINT32_MAX];
	const LDrawWorldConnector	*around	= nearby.all;

	for (NSUInteger index = 0; index < nearby.count; index++)
	{
		uint32_t owner = around[index].owner;

		if ([_excused containsIndex:owner] == NO && [self parts:parts count:count clashWithOwner:owner])
		{
			[_excused addIndex:owner];
		}
	}
}


//========== cluster:clashesForOwner: ==========================================
//
// Purpose:		Whether a placement would put the dragged part through one
//				that is already there.
//
// Notes:		Only the parts whose connectors are near the placement are
//				asked, which is every part it could be through: a part filling
//				the same space has connectors in it.
//
//==============================================================================
- (BOOL)cluster:(LDrawSnapCluster *)cluster clashesForOwner:(uint32_t)owner
{
	const Box3	*parts	= _movingBounds.bytes;
	NSUInteger	count	= _movingBounds.length / sizeof(Box3);
	Box3		whole	= InvalidBox;

	if (count == 0)
	{
		return NO;				// the caller did not say what space it fills
	}
	_movedBounds.length = count * sizeof(Box3);

	Box3 *moved = _movedBounds.mutableBytes;

	for (NSUInteger index = 0; index < count; index++)
	{
		moved[index] = LDrawBoxByMatrix(parts[index], cluster.placement);
		whole = V3UnionBox(whole, moved[index]);
	}

	BOOL goingBack = BoxesAlike(whole, _startBounds, BackWhereItWas);

	LDrawWorldConnectors		*nearby	= [self.connectorIndex connectorsInBox:whole
															   excludingOwner:owner];
	const LDrawWorldConnector	*around	= nearby.all;
	NSUInteger					found	= nearby.count;
	uint32_t					asked	= UINT32_MAX;

	for (NSUInteger index = 0; index < found; index++)
	{
		if (around[index].owner == asked)
		{
			continue;			// that part has been looked at already
		}
		asked = around[index].owner;

		if (PlacementJoins(cluster, asked) || (goingBack && [_excused containsIndex:asked]))
		{
			continue;			// held by this part, or put back against it: they fit
		}
		if (BoxesClash(whole, [self.connectorIndex boundsOfOwner:asked]) == NO)
		{
			continue;			// nowhere near it, whatever it is made of
		}
		if ([self parts:moved count:count clashWithOwner:asked])
		{
			return YES;
		}
	}
	return NO;
}


//========== parts:count:clashWithOwner: =======================================
//
// Purpose:		Whether any part of the dragged thing shares space with any
//				part of another. Both sides are asked part by part, because a
//				box around a submodel covers space its parts leave free.
//
//==============================================================================
- (BOOL)parts:(const Box3 *)moved count:(NSUInteger)count clashWithOwner:(uint32_t)owner
{
	NSUInteger theirs = [self.connectorIndex partBoundsCountOfOwner:owner];

	for (NSUInteger other = 0; other < theirs; other++)
	{
		Box3 box = [self.connectorIndex partBoundsOfOwner:owner atIndex:other];

		for (NSUInteger index = 0; index < count; index++)
		{
			if (BoxesClash(moved[index], box))
			{
				return YES;
			}
		}
	}
	return NO;
}


#pragma mark - Ranking


//========== rankedClusters:owner:dragDirection: ===============================
//
// Purpose:		Scores the placements within reach and sorts the best first.
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

	// Along the sight, only a placement that could be taken up says where the
	// first surface is. One that is taken, in the way, or too far to latch
	// on to would end the search before the good ones behind it.
	if (_sighting)
	{
		double nearest = INFINITY;

		for (LDrawSnapCluster *cluster in inReach)
		{
			double distance = [self screenDistance:cluster];

			[self checkCluster:cluster owner:owner];

			if (cluster.votes > 0
				&& (distance <= self.acquireDistance || cluster.identifier == _heldPlacement))
			{
				nearest = MIN(nearest, cluster.depth);
			}
		}
		if (nearest != INFINITY)
		{
			_nearestDepth = nearest;
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

	// Best possible score first: its pairs all free, and nothing against the
	// drag. Once that ceiling falls below the best score that could be taken
	// up, nothing further can win and the rest need not be looked at: reading
	// whether a connector is free costs a question to the index.
	[inReach sortUsingComparator:^NSComparisonResult(LDrawSnapCluster *one,
													 LDrawSnapCluster *other) {
		double first	= [self ceilingOfCluster:one];
		double second	= [self ceilingOfCluster:other];

		if (first == second)
		{
			return (one.identifier < other.identifier) ? NSOrderedAscending : NSOrderedDescending;
		}
		return (first > second) ? NSOrderedAscending : NSOrderedDescending;
	}];

	for (LDrawSnapCluster *cluster in inReach)
	{
		if (cluster == held)
		{
			continue;
		}
		if ([self ceilingOfCluster:cluster] <= best)
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
	[self checkCluster:cluster owner:owner];
	cluster.score = (cluster.votes > 0) ? [self scoreOfCluster:cluster dragDirection:dragDirection] : 0.0;
}


//========== checkCluster:owner: ===============================================
//
// Purpose:		Counts the pairs a placement still has free, and none if it
//				would stand where another part already is. Once for each
//				placement: the search along the sight ranks the same ones
//				again as it goes further.
//
//==============================================================================
- (void)checkCluster:(LDrawSnapCluster *)cluster owner:(uint32_t)owner
{
	if (cluster.checked)
	{
		return;
	}
	cluster.votes	= [self freeMeetingsOfCluster:cluster owner:owner];
	cluster.checked	= YES;

	if (cluster.votes > 0 && [self cluster:cluster clashesForOwner:owner])
	{
		cluster.votes = 0;
	}
}


//========== scoreOfCluster:dragDirection: =====================================
//
// Purpose:		What a placement is worth, in screen points: the pairs that
//				hold it, less how far the part moves on screen, how far it
//				turns, and whether it moves against the drag.
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
	return [self ceilingOfCluster:cluster] - self.dragWeight * drag;
}


//========== ceilingOfCluster: =================================================
//
// Purpose:		The most a placement can score: its votes before any are found
//				taken, and nothing against the drag.
//
//==============================================================================
- (double)ceilingOfCluster:(LDrawSnapCluster *)cluster
{
	return self.countWeight * (double)cluster.votes
		 - self.distanceWeight * cluster.distance * self.pointsPerUnit
		 - self.angleWeight * cluster.angle;
}


//========== solutionFromRankedClusters: =======================================
//
// Purpose:		Picks the placement to hold. A part snaps to the best placement
//				within the acquire distance. It keeps that placement until it
//				is dragged past the release distance, or another placement
//				scores better by what the switch margin is worth on screen.
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
		double margin = self.distanceWeight * self.switchMargin * self.pointsPerUnit;

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
		.placement	= cluster.identifier,
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
	double start	= 0.0;
	double finish	= 0.0;

	if ([self connector:one liesAlong:meeting.met start:&start finish:&finish] == NO)
	{
		return NO;
	}
	double shared = MIN(finish, MAX(meeting.start, meeting.finish))
				  - MAX(start, MIN(meeting.start, meeting.finish));

	return (shared > OccupiedOverlap);
}


//========== connector:liesAlong:start:finish: =================================
//
// Purpose:		Whether a connector lies on the met connector's line, and the
//				length it fills there, measured from the met mouth.
//
//==============================================================================
- (BOOL)connector:(LDrawWorldConnector)one
		liesAlong:(LDrawWorldConnector)met
			start:(double *)outStart
		   finish:(double *)outFinish
{
	Point3	mouth	= LDrawWorldConnectorMouth(met);
	Vector3	apart	= V3Sub(LDrawWorldConnectorMouth(one), mouth);
	double	start	= V3Dot(apart, met.axis);
	double	finish	= start + one.length * V3Dot(one.axis, met.axis);

	if (fabs(V3Dot(one.axis, met.axis)) < cos(self.axisTolerance))
	{
		return NO;			// not parallel
	}
	if (V3Length(V3Sub(apart, V3MulScalar(met.axis, start))) > CoincidentDistance)
	{
		return NO;			// off the line
	}
	*outStart	= MIN(start, finish);
	*outFinish	= MAX(start, finish);

	return YES;
}


@end
