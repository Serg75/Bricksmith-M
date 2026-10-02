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

// Part boxes go in coarser cells: a box covers many connector cells.
static const double BoxCellSize = 40.0;

// A guard against bad data. The largest baseplate covers about 2,500 cells.
static const NSUInteger MaximumBoxCells = 65536;


/// One connector in a cell: its owner and its index in the owner's list.
typedef struct
{
	uint32_t	owner;
	uint32_t	index;

} LDrawConnectorPlace;


@implementation LDrawConnectorIndex
{
	NSMutableDictionary<NSNumber *, LDrawWorldConnectors *>	*_connectorsByOwner;
	NSMutableDictionary<NSNumber *, NSMutableData *>		*_boundsByOwner;		// owner -> Box3 a part
	NSMutableDictionary<NSNumber *, NSMutableData *>		*_placementsByOwner;	// owner -> Matrix4 a part
	NSMutableDictionary<NSNumber *, NSMutableArray *>		*_shapesByOwner;		// owner -> shape or NSNull a part
	NSMutableDictionary<NSNumber *, NSNumber *>				*_shapelessByOwner;		// owner -> parts without one
	Box3													_occupied;
	BOOL													_occupiedIsKnown;
	CFMutableDictionaryRef									_cells;			// cell key -> NSMutableData of places
	CFMutableDictionaryRef									_boxCells;		// cell key -> NSMutableData of owners
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
		_boundsByOwner		= [NSMutableDictionary dictionary];
		_placementsByOwner	= [NSMutableDictionary dictionary];
		_shapesByOwner		= [NSMutableDictionary dictionary];
		_shapelessByOwner	= [NSMutableDictionary dictionary];
		// Keyed by the raw number: a cell key is too large to box without
		// allocating, and a query looks up thousands of cells.
		_cells				= CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
		_boxCells			= CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
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


//---------- BoxCellRange ----------------------------------------------[static]--
//
// Purpose:		The first and last cell of the box grid that a box reaches into
//				along each axis, and how many cells that makes: none for an
//				empty box.
//
//------------------------------------------------------------------------------
static double BoxCellRange(Box3 box, int64_t *first, int64_t *last)
{
	if ((box.min.x <= box.max.x && box.min.y <= box.max.y && box.min.z <= box.max.z) == NO)
	{
		return 0.0;			// empty, or not a number
	}
	first[0]	= (int64_t)floor(box.min.x / BoxCellSize);
	first[1]	= (int64_t)floor(box.min.y / BoxCellSize);
	first[2]	= (int64_t)floor(box.min.z / BoxCellSize);
	last[0]		= (int64_t)floor(box.max.x / BoxCellSize);
	last[1]		= (int64_t)floor(box.max.y / BoxCellSize);
	last[2]		= (int64_t)floor(box.max.z / BoxCellSize);

	return (double)(last[0] - first[0] + 1) * (double)(last[1] - first[1] + 1) * (double)(last[2] - first[2] + 1);
}


//---------- EnumerateBoxCells -----------------------------------------[static]--
//
// Purpose:		Visits every cell of the box grid that a box reaches into. A box
//				too large for real data visits none.
//
//------------------------------------------------------------------------------
static void EnumerateBoxCells(Box3 box, void (^visit)(int64_t key))
{
	int64_t	first[3]	= { 0, 0, 0 };
	int64_t	last[3]		= { 0, 0, 0 };
	double	cells		= BoxCellRange(box, first, last);

	if (cells == 0.0 || cells > (double)MaximumBoxCells)
	{
		return;
	}
	for (int64_t x = first[0]; x <= last[0]; x++)
	{
		for (int64_t y = first[1]; y <= last[1]; y++)
		{
			for (int64_t z = first[2]; z <= last[2]; z++)
			{
				visit(LDrawCellKey(x, y, z));
			}
		}
	}
}


//---------- CellAtKey -------------------------------------------------[static]--
//------------------------------------------------------------------------------
static NSMutableData *CellAtKey(CFMutableDictionaryRef cells, int64_t key)
{
	return (__bridge NSMutableData *)CFDictionaryGetValue(cells, (const void *)(intptr_t)key);
}


//---------- RemoveOwnerFromBoxCell ------------------------------------[static]--
//------------------------------------------------------------------------------
static void RemoveOwnerFromBoxCell(NSMutableData *cell, uint32_t owner)
{
	uint32_t	*owners	= cell.mutableBytes;
	NSUInteger	count	= cell.length / sizeof(uint32_t);
	NSUInteger	kept	= 0;

	for (NSUInteger index = 0; index < count; index++)
	{
		if (owners[index] != owner)
		{
			owners[kept] = owners[index];
			kept++;
		}
	}
	cell.length = kept * sizeof(uint32_t);
}


//---------- BoxesMeet -------------------------------------------------[static]--
//
// Purpose:		Whether two boxes overlap or touch.
//
//------------------------------------------------------------------------------
static BOOL BoxesMeet(Box3 one, Box3 other)
{
	return (one.min.x <= other.max.x) && (one.max.x >= other.min.x)
		&& (one.min.y <= other.max.y) && (one.max.y >= other.min.y)
		&& (one.min.z <= other.max.z) && (one.max.z >= other.min.z);
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

	return BoxesMeet(run, box);
}


#pragma mark - Contents

//========== dealloc ===========================================================
//==============================================================================
- (void)dealloc
{
	CFRelease(_cells);
	CFRelease(_boxCells);
}


//========== setConnectors:forOwner: ===========================================
//==============================================================================
- (void)setConnectors:(LDrawWorldConnectors *)connectors forOwner:(uint32_t)owner
{
	[self setConnectors:connectors bounds:InvalidBox forOwner:owner];
}


//========== setConnectors:bounds:forOwner: ====================================
//==============================================================================
- (void)setConnectors:(LDrawWorldConnectors *)connectors
			   bounds:(Box3)bounds
			 forOwner:(uint32_t)owner
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
	_occupiedIsKnown = NO;

	if (V3EqualBoxes(bounds, InvalidBox) == NO)
	{
		[self addBounds:bounds forOwner:owner];
	}
	_connectorCount += count;

	for (NSUInteger index = 0; index < count; index++)
	{
		LDrawConnectorPlace place = { .owner = owner, .index = (uint32_t)index };

		EnumerateCellsAlongRun(placed[index], ^(int64_t key) {
			NSMutableData *cell = CellAtKey(self->_cells, key);

			if (cell == nil)
			{
				cell = [NSMutableData data];
				CFDictionarySetValue(self->_cells, (const void *)(intptr_t)key, (__bridge const void *)cell);
			}
			[cell appendBytes:&place length:sizeof(place)];
		});
	}
}


//========== addBounds:forOwner: ===============================================
//==============================================================================
- (void)addBounds:(Box3)bounds forOwner:(uint32_t)owner
{
	[self addBounds:bounds shape:nil placement:IdentityMatrix4 forOwner:owner];
}


//========== addBounds:shape:placement:forOwner: ===============================
//==============================================================================
- (void)addBounds:(Box3)bounds
			shape:(nullable LDrawPartShape *)shape
		placement:(Matrix4)placement
		 forOwner:(uint32_t)owner
{
	NSNumber		*key		= @(owner);
	NSMutableData	*boxes		= _boundsByOwner[key];

	if (boxes == nil)
	{
		boxes						= [NSMutableData data];
		_boundsByOwner[key]			= boxes;
		_placementsByOwner[key]		= [NSMutableData data];
		_shapesByOwner[key]			= [NSMutableArray array];
	}
	[boxes appendBytes:&bounds length:sizeof(bounds)];
	[_placementsByOwner[key] appendBytes:&placement length:sizeof(placement)];
	[_shapesByOwner[key] addObject:shape ?: (id)[NSNull null]];

	EnumerateBoxCells(bounds, ^(int64_t cellKey) {
		NSMutableData *cell = CellAtKey(self->_boxCells, cellKey);

		if (cell == nil)
		{
			cell = [NSMutableData data];
			CFDictionarySetValue(self->_boxCells, (const void *)(intptr_t)cellKey, (__bridge const void *)cell);
		}

		// An owner's parts come one after another, so this keeps most cells
		// to one entry an owner.
		const uint32_t	*owners	= cell.bytes;
		NSUInteger		count	= cell.length / sizeof(uint32_t);

		if (count == 0 || owners[count - 1] != owner)
		{
			[cell appendBytes:&owner length:sizeof(owner)];
		}
	});

	if (shape == nil)
	{
		_shapelessByOwner[key] = @(_shapelessByOwner[key].unsignedIntegerValue + 1);
	}
}


//========== occupiedBounds ====================================================
//
// Purpose:		Worked out when first asked after a change, because a drag asks
//				on every touch and the model does not change during one.
//
//==============================================================================
- (Box3)occupiedBounds
{
	if (_occupiedIsKnown == NO)
	{
		_occupied = InvalidBox;

		for (LDrawWorldConnectors *connectors in _connectorsByOwner.objectEnumerator)
		{
			const LDrawWorldConnector	*placed	= connectors.all;
			NSUInteger					count	= connectors.count;

			for (NSUInteger index = 0; index < count; index++)
			{
				_occupied = V3UnionBoxAndPoint(_occupied, LDrawWorldConnectorMouth(placed[index]));
			}
		}
		_occupiedIsKnown = YES;
	}
	return _occupied;
}


//========== boundsOfOwner: ====================================================
//==============================================================================
- (Box3)boundsOfOwner:(uint32_t)owner
{
	NSUInteger	count	= 0;
	const Box3	*boxes	= [self partBoundsOfOwner:owner count:&count];
	Box3		bounds	= InvalidBox;

	for (NSUInteger index = 0; index < count; index++)
	{
		bounds = V3UnionBox(bounds, boxes[index]);
	}
	return bounds;
}


//========== partBoundsCountOfOwner: ===========================================
//==============================================================================
- (NSUInteger)partBoundsCountOfOwner:(uint32_t)owner
{
	return _boundsByOwner[@(owner)].length / sizeof(Box3);
}


//========== partBoundsOfOwner:atIndex: ========================================
//==============================================================================
- (Box3)partBoundsOfOwner:(uint32_t)owner atIndex:(NSUInteger)index
{
	const Box3 *boxes = _boundsByOwner[@(owner)].bytes;

	if (index >= [self partBoundsCountOfOwner:owner])
	{
		return InvalidBox;
	}
	return boxes[index];
}


//========== partShapeOfOwner:atIndex: =========================================
//==============================================================================
- (nullable LDrawPartShape *)partShapeOfOwner:(uint32_t)owner atIndex:(NSUInteger)index
{
	NSArray *shapes = _shapesByOwner[@(owner)];
	id		shape	= (index < shapes.count) ? shapes[index] : nil;

	return (shape == [NSNull null]) ? nil : shape;
}


//========== partPlacementOfOwner:atIndex: =====================================
//==============================================================================
- (Matrix4)partPlacementOfOwner:(uint32_t)owner atIndex:(NSUInteger)index
{
	NSData *placements = _placementsByOwner[@(owner)];

	if (index >= placements.length / sizeof(Matrix4))
	{
		return IdentityMatrix4;
	}
	return ((const Matrix4 *)placements.bytes)[index];
}


//========== partBoundsOfOwner:count: ==========================================
//==============================================================================
- (nullable const Box3 *)partBoundsOfOwner:(uint32_t)owner count:(NSUInteger *)count
{
	NSData *boxes = _boundsByOwner[@(owner)];

	*count = boxes.length / sizeof(Box3);
	return boxes.bytes;
}


//========== partPlacementsOfOwner: ============================================
//==============================================================================
- (nullable const Matrix4 *)partPlacementsOfOwner:(uint32_t)owner
{
	return _placementsByOwner[@(owner)].bytes;
}


//========== partShapesOfOwner: ================================================
//==============================================================================
- (NSArray *)partShapesOfOwner:(uint32_t)owner
{
	return _shapesByOwner[@(owner)] ?: @[];
}


//========== partsWithoutShapeOfOwner: =========================================
//==============================================================================
- (NSUInteger)partsWithoutShapeOfOwner:(uint32_t)owner
{
	return _shapelessByOwner[@(owner)].unsignedIntegerValue;
}


//========== removeOwner: ======================================================
//==============================================================================
- (void)removeOwner:(uint32_t)owner
{
	LDrawWorldConnectors		*connectors	= _connectorsByOwner[@(owner)];
	const LDrawWorldConnector	*placed		= connectors.all;
	NSUInteger					count		= connectors.count;
	NSUInteger					boxCount	= 0;
	const Box3					*boxes		= [self partBoundsOfOwner:owner count:&boxCount];

	for (NSUInteger index = 0; index < boxCount; index++)
	{
		EnumerateBoxCells(boxes[index], ^(int64_t key) {
			NSMutableData *cell = CellAtKey(self->_boxCells, key);

			if (cell != nil)
			{
				RemoveOwnerFromBoxCell(cell, owner);
				if (cell.length == 0)
				{
					CFDictionaryRemoveValue(self->_boxCells, (const void *)(intptr_t)key);
				}
			}
		});
	}
	for (NSUInteger index = 0; index < count; index++)
	{
		EnumerateCellsAlongRun(placed[index], ^(int64_t key) {
			NSMutableData *cell = CellAtKey(self->_cells, key);

			if (cell != nil)
			{
				[self removeOwner:owner fromCell:cell];
				if (cell.length == 0)
				{
					CFDictionaryRemoveValue(self->_cells, (const void *)(intptr_t)key);
				}
			}
		});
	}
	_connectorCount -= count;
	[_connectorsByOwner removeObjectForKey:@(owner)];
	[_boundsByOwner removeObjectForKey:@(owner)];
	[_placementsByOwner removeObjectForKey:@(owner)];
	[_shapesByOwner removeObjectForKey:@(owner)];
	[_shapelessByOwner removeObjectForKey:@(owner)];
	_occupiedIsKnown = NO;
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
	[_boundsByOwner removeAllObjects];
	[_placementsByOwner removeAllObjects];
	[_shapesByOwner removeAllObjects];
	[_shapelessByOwner removeAllObjects];
	CFDictionaryRemoveAllValues(_cells);
	CFDictionaryRemoveAllValues(_boxCells);
	_connectorCount		= 0;
	_occupiedIsKnown	= NO;
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
				NSData						*cell	= CellAtKey(_cells, LDrawCellKey(x, y, z));
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


//========== ownersInBox:excludingOwner: =======================================
//==============================================================================
- (NSIndexSet *)ownersInBox:(Box3)box excludingOwner:(uint32_t)owner
{
	NSMutableIndexSet	*found		= [NSMutableIndexSet indexSet];
	NSMutableIndexSet	*asked		= [NSMutableIndexSet indexSet];
	int64_t				first[3]	= { 0, 0, 0 };
	int64_t				last[3]		= { 0, 0, 0 };
	double				cells		= BoxCellRange(box, first, last);

	if (cells == 0.0)
	{
		return found;
	}

	// A box with more cells than the model has owners is faster to answer by
	// walking the model.
	if (cells > (double)_boundsByOwner.count || cells > (double)MaximumBoxCells)
	{
		for (NSNumber *other in _boundsByOwner)
		{
			if (other.unsignedIntValue != owner && [self owner:other.unsignedIntValue hasPartInBox:box])
			{
				[found addIndex:other.unsignedIntValue];
			}
		}
		return found;
	}
	EnumerateBoxCells(box, ^(int64_t key) {
		NSData			*cell	= CellAtKey(self->_boxCells, key);
		const uint32_t	*owners	= cell.bytes;
		NSUInteger		count	= cell.length / sizeof(uint32_t);

		for (NSUInteger index = 0; index < count; index++)
		{
			if (owners[index] == owner || [asked containsIndex:owners[index]])
			{
				continue;
			}
			[asked addIndex:owners[index]];

			if ([self owner:owners[index] hasPartInBox:box])
			{
				[found addIndex:owners[index]];
			}
		}
	});
	return found;
}


//========== owner:hasPartInBox: ===============================================
//==============================================================================
- (BOOL)owner:(uint32_t)owner hasPartInBox:(Box3)box
{
	NSUInteger	count	= 0;
	const Box3	*boxes	= [self partBoundsOfOwner:owner count:&count];

	for (NSUInteger index = 0; index < count; index++)
	{
		if (BoxesMeet(boxes[index], box))
		{
			return YES;
		}
	}
	return NO;
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
