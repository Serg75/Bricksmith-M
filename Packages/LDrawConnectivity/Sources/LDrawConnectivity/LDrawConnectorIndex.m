//==============================================================================
//
//  File:       LDrawConnectorIndex.m
//  Package:    LDrawConnectivity
//
//  Purpose:    A grid hash of the connectors of a model being edited.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <LDrawConnectivity/LDrawConnectorIndex.h>

#import "LDrawConnectivityMath.h"

// Stud pitch and plate height, so a cell holds about one connector.
static const double CellWidth	= 20.0;
static const double CellHeight	= 8.0;

// A guard against bad data. Real connectors cross far fewer cells.
static const NSUInteger MaximumConnectorCells = 4096;


/// One connector in a cell: its owner and its index in the owner's list.
typedef struct
{
	uint32_t	owner;
	uint32_t	index;

} LDrawConnectorPlace;


@implementation LDrawConnectorIndex
{
	NSMutableDictionary<NSNumber *, LDrawWorldConnectors *>	*_connectorsByOwner;
	NSMutableDictionary<NSNumber *, NSMutableData *>		*_cells;		// cell key -> places
	NSUInteger												_connectorCount;
}

//========== init ==============================================================
//==============================================================================
- (instancetype)init
{
	self = [super init];
	if (self != nil)
	{
		_connectorsByOwner	= [NSMutableDictionary dictionary];
		_cells				= [NSMutableDictionary dictionary];
	}
	return self;
}


#pragma mark - Cells

//---------- CellSizes -------------------------------------------------[static]--
//
// Purpose:		The cell size along x, y and z.
//
//------------------------------------------------------------------------------
static const double *CellSizes(void)
{
	static const double sizes[3] = { CellWidth, CellHeight, CellWidth };

	return sizes;
}


//---------- CellIndices -----------------------------------------------[static]--
//
// Purpose:		The cell a point falls in, along each axis.
//
//------------------------------------------------------------------------------
static void CellIndices(Point3 point, int64_t *into)
{
	const double *sizes = CellSizes();

	into[0] = (int64_t)floor(point.x / sizes[0]);
	into[1] = (int64_t)floor(point.y / sizes[1]);
	into[2] = (int64_t)floor(point.z / sizes[2]);
}


//---------- EnumerateCellsAlongRun ------------------------------------[static]--
//
// Purpose:		Visits every cell a connector's run passes through, once each,
//				in order.
//
// Notes:		Steps from one cell wall to the next, so a slanted run does
//				not skip a cell it only clips.
//
//------------------------------------------------------------------------------
static void EnumerateCellsAlongRun(LDrawWorldConnector connector, void (^visit)(int64_t key))
{
	const double	*sizes	= CellSizes();
	Point3			from	= LDrawWorldConnectorMouth(connector);
	Vector3			along	= V3MulScalar(connector.axis, MAX(connector.length, 0.0));
	double			start[3]	= { from.x, from.y, from.z };
	double			run[3]		= { along.x, along.y, along.z };
	int64_t			cell[3], last[3], step[3];
	double			nextWall[3], wallToWall[3];

	CellIndices(from, cell);
	CellIndices(V3Add(from, along), last);

	for (NSUInteger axis = 0; axis < 3; axis++)
	{
		double wall = 0.0;

		if (run[axis] == 0.0)
		{
			step[axis]		= 0;
			nextWall[axis]	= INFINITY;
			wallToWall[axis]= INFINITY;
			continue;
		}
		step[axis]		= (run[axis] > 0.0) ? 1 : -1;
		wall			= (double)(cell[axis] + ((run[axis] > 0.0) ? 1 : 0)) * sizes[axis];
		nextWall[axis]	= (wall - start[axis]) / run[axis];
		wallToWall[axis]= fabs(sizes[axis] / run[axis]);
	}

	for (NSUInteger visited = 0; visited < MaximumConnectorCells; visited++)
	{
		NSUInteger nearest = 0;

		visit(LDrawCellKey(cell[0], cell[1], cell[2]));

		if (cell[0] == last[0] && cell[1] == last[1] && cell[2] == last[2])
		{
			return;
		}
		for (NSUInteger axis = 1; axis < 3; axis++)
		{
			nearest = (nextWall[axis] < nextWall[nearest]) ? axis : nearest;
		}
		if (nextWall[nearest] > 1.0)
		{
			return;			// the run ends inside this cell
		}
		cell[nearest]		+= step[nearest];
		nextWall[nearest]	+= wallToWall[nearest];
	}
}


//---------- RunReachesBox ---------------------------------------------[static]--
//
// Purpose:		Whether any of a connector's run lies in the box.
//
//------------------------------------------------------------------------------
static BOOL RunReachesBox(LDrawWorldConnector connector, Box3 box)
{
	Point3	mouth	= LDrawWorldConnectorMouth(connector);
	Point3	end		= V3Add(mouth, V3MulScalar(connector.axis, connector.length));
	Box3	run		= V3BoundsFromPoints(mouth, end);

	return (run.min.x <= box.max.x) && (run.max.x >= box.min.x)
		&& (run.min.y <= box.max.y) && (run.max.y >= box.min.y)
		&& (run.min.z <= box.max.z) && (run.max.z >= box.min.z);
}


#pragma mark - Contents

//========== setConnectors:forOwner: ===========================================
//==============================================================================
- (void)setConnectors:(LDrawWorldConnectors *)connectors forOwner:(uint32_t)owner
{
	const LDrawWorldConnector	*placed	= connectors.all;
	NSUInteger					count	= connectors.count;

	[self removeOwner:owner];

	if (count == 0)
	{
		return;
	}
	// A copy, because the caller may go on adding to the set it passed, and
	// the cells below record where each connector is by its place in it.
	_connectorsByOwner[@(owner)] = [connectors copy];
	_connectorCount += count;

	for (NSUInteger index = 0; index < count; index++)
	{
		LDrawConnectorPlace place = { .owner = owner, .index = (uint32_t)index };

		EnumerateCellsAlongRun(placed[index], ^(int64_t key) {
			NSMutableData *cell = self->_cells[@(key)];

			if (cell == nil)
			{
				cell = [NSMutableData data];
				self->_cells[@(key)] = cell;
			}
			[cell appendBytes:&place length:sizeof(place)];
		});
	}
}


//========== removeOwner: ======================================================
//==============================================================================
- (void)removeOwner:(uint32_t)owner
{
	LDrawWorldConnectors		*connectors	= _connectorsByOwner[@(owner)];
	const LDrawWorldConnector	*placed		= connectors.all;
	NSUInteger					count		= connectors.count;

	if (connectors == nil)
	{
		return;
	}
	for (NSUInteger index = 0; index < count; index++)
	{
		EnumerateCellsAlongRun(placed[index], ^(int64_t key) {
			NSMutableData *cell = self->_cells[@(key)];

			if (cell != nil)
			{
				[self removeOwner:owner fromCell:cell];
				if (cell.length == 0)
				{
					[self->_cells removeObjectForKey:@(key)];
				}
			}
		});
	}
	_connectorCount -= count;
	[_connectorsByOwner removeObjectForKey:@(owner)];
}


//========== removeOwner:fromCell: =============================================
//==============================================================================
- (void)removeOwner:(uint32_t)owner fromCell:(NSMutableData *)cell
{
	LDrawConnectorPlace	*places	= cell.mutableBytes;
	NSUInteger			count	= cell.length / sizeof(LDrawConnectorPlace);
	NSUInteger			kept	= 0;

	for (NSUInteger index = 0; index < count; index++)
	{
		if (places[index].owner != owner)
		{
			places[kept] = places[index];
			kept++;
		}
	}
	cell.length = kept * sizeof(LDrawConnectorPlace);
}


//========== removeAllConnectors ===============================================
//==============================================================================
- (void)removeAllConnectors
{
	[_connectorsByOwner removeAllObjects];
	[_cells removeAllObjects];
	_connectorCount = 0;
}


//========== connectorCount ====================================================
//==============================================================================
- (NSUInteger)connectorCount
{
	return _connectorCount;
}


//========== ownerCount ========================================================
//==============================================================================
- (NSUInteger)ownerCount
{
	return _connectorsByOwner.count;
}


#pragma mark - Queries

//========== connectorsInBox:excludingOwner: ===================================
//==============================================================================
- (LDrawWorldConnectors *)connectorsInBox:(Box3)box excludingOwner:(uint32_t)owner
{
	LDrawWorldConnectors	*found		= [LDrawWorldConnectors connectors];
	CFMutableSetRef			answered	= NULL;

	if (box.max.x < box.min.x || box.max.y < box.min.y || box.max.z < box.min.z)
	{
		return found;			// an empty box; checked before the cell count overflows
	}

	int64_t			firstX		= (int64_t)floor(box.min.x / CellWidth);
	int64_t			lastX		= (int64_t)floor(box.max.x / CellWidth);
	int64_t			firstY		= (int64_t)floor(box.min.y / CellHeight);
	int64_t			lastY		= (int64_t)floor(box.max.y / CellHeight);
	int64_t			firstZ		= (int64_t)floor(box.min.z / CellWidth);
	int64_t			lastZ		= (int64_t)floor(box.max.z / CellWidth);
	NSUInteger		cellCount	= (NSUInteger)((lastX - firstX + 1) * (lastY - firstY + 1) * (lastZ - firstZ + 1));

	// Reading a cell costs about what reading a connector costs. A box with
	// more cells than the model has connectors is faster to answer by walking
	// the model.
	if (cellCount > _connectorCount)
	{
		for (NSNumber *other in _connectorsByOwner)
		{
			if (other.unsignedIntValue != owner)
			{
				[self addConnectorsOfOwner:other.unsignedIntValue inBox:box to:found];
			}
		}
		return found;
	}

	// A long connector is in several cells, so skip the ones already found.
	answered = CFSetCreateMutable(NULL, 0, NULL);

	for (int64_t x = firstX; x <= lastX; x++)
	{
		for (int64_t y = firstY; y <= lastY; y++)
		{
			for (int64_t z = firstZ; z <= lastZ; z++)
			{
				NSData						*cell	= _cells[@(LDrawCellKey(x, y, z))];
				const LDrawConnectorPlace	*places	= cell.bytes;
				NSUInteger					count	= cell.length / sizeof(LDrawConnectorPlace);

				for (NSUInteger index = 0; index < count; index++)
				{
					uint64_t token = (((uint64_t)places[index].owner << 32) | places[index].index) + 1;

					if (places[index].owner == owner)
					{
						continue;
					}
					if (CFSetContainsValue(answered, (const void *)(uintptr_t)token))
					{
						continue;
					}
					CFSetAddValue(answered, (const void *)(uintptr_t)token);
					[self addConnectorAtPlace:places[index] inBox:box to:found];
				}
			}
		}
	}
	CFRelease(answered);

	return found;
}


//========== addConnectorAtPlace:inBox:to: =====================================
//==============================================================================
- (void)addConnectorAtPlace:(LDrawConnectorPlace)place inBox:(Box3)box to:(LDrawWorldConnectors *)found
{
	LDrawWorldConnectors		*connectors	= _connectorsByOwner[@(place.owner)];
	const LDrawWorldConnector	*placed		= connectors.all;

	if (place.index >= connectors.count)
	{
		return;
	}
	if (RunReachesBox(placed[place.index], box))
	{
		[found addConnector:placed[place.index]];
	}
}


//========== addConnectorsOfOwner:inBox:to: ====================================
//==============================================================================
- (void)addConnectorsOfOwner:(uint32_t)owner inBox:(Box3)box to:(LDrawWorldConnectors *)found
{
	LDrawWorldConnectors		*connectors	= _connectorsByOwner[@(owner)];
	const LDrawWorldConnector	*placed		= connectors.all;
	NSUInteger					count		= connectors.count;

	for (NSUInteger index = 0; index < count; index++)
	{
		if (RunReachesBox(placed[index], box))
		{
			[found addConnector:placed[index]];
		}
	}
}


@end
