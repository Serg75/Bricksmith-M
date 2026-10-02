//==============================================================================
//
//  File:       LDrawPartShape.m
//  Package:    LDrawConnectivity
//
//  Purpose:    The solid a part fills, as a grid of small cells.
//
//  Created by Sergey Slobodenyuk on 2026-09-28.
//
//==============================================================================

#import <LDrawConnectivity/LDrawPartShape.h>

#import <stdatomic.h>

#import <LDrawConnectivity/LDrawWorldConnector.h>

// The most cells a shape may have. A larger part gets larger cells.
static const double MaximumCells = 8.0e6;

// How many cells of one part must lie inside the other for the two to go into
// each other. A single one can be float noise at a surface.
static const NSUInteger MinimumCellsInside = 3;

// Distances from the outside are kept in quarter cells, up to what a byte
// holds: a step to the next cell costs 4, across its edge 6, across its
// corner 7.
static const uint8_t FaceStep	= 4;
static const uint8_t EdgeStep	= 6;
static const uint8_t CornerStep	= 7;
static const uint8_t FarAway	= 255;

// A cell this far from the outside, 3 cells, is inside the solid. The surface
// passes through the cells beside the outside, so a plate 2 LDU thick fills 3
// rows of cells, and the middle one is only half an LDU inside it.
static const uint8_t DeepDistance = 12;

// A thinner part is inside where it is deepest, but no less than 2 cells in:
// a part that only touches it reaches its outer cells.
static const uint8_t ThinDeepDistance = 8;

// A cell no further than this from the outside is on the surface.
static const uint8_t SurfaceDistance = 6;

// How finely a triangle is sampled, in cells, so that it leaves no gap for the
// outside to slip through.
static const double SampleStep = 1.0 / 3.0;

// While building, a cell is marked as solid surface, not reached yet, or
// reached from the outside. Once built it holds its distance from the outside.
typedef NS_ENUM(uint8_t, LDrawShapeMark)
{
	LDrawShapeMarkSurface	= 1,
	LDrawShapeMarkUnknown	= 2,
	LDrawShapeMarkReached	= 3,
};


@implementation LDrawPartShape
{
	NSData *		(^_source)(void);
	atomic_bool		_built;
	Box3			_bounds;
	double			_cellSize;
	NSUInteger		_solidCellCount;
	NSUInteger		_insideCellCount;
	uint8_t			_deepDistance;		// how far in a cell is inside
	Point3			_origin;			// the corner of the first cell, in the part's coordinates
	NSInteger		_size[3];
	NSMutableData	*_cells;			// one distance a cell, X fastest; 0 outside
}

//========== initWithTriangles: ================================================
//==============================================================================
- (instancetype)initWithTriangles:(NSData * (^)(void))triangles
{
	self = [super init];
	if (self != nil)
	{
		_source	= [triangles copy];
		_bounds			= InvalidBox;
		_deepDistance	= DeepDistance;
		atomic_init(&_built, false);
	}
	return self;
}


//========== build =============================================================
//==============================================================================
- (void)build
{
	if (atomic_load_explicit(&_built, memory_order_acquire))
	{
		return;
	}
	@synchronized (self)
	{
		if (atomic_load_explicit(&_built, memory_order_relaxed) == false)
		{
			[self buildFromTriangles:_source()];
			_source = nil;
			atomic_store_explicit(&_built, true, memory_order_release);
		}
	}
}


//========== isBuilt ===========================================================
//==============================================================================
- (BOOL)isBuilt
{
	return atomic_load_explicit(&_built, memory_order_acquire);
}


//========== bounds ============================================================
//==============================================================================
- (Box3)bounds
{
	[self build];
	return _bounds;
}


//========== cellSize ==========================================================
//==============================================================================
- (double)cellSize
{
	[self build];
	return _cellSize;
}


//========== solidCellCount ====================================================
//==============================================================================
- (NSUInteger)solidCellCount
{
	[self build];
	return _solidCellCount;
}


//========== insideCellCount ===================================================
//==============================================================================
- (NSUInteger)insideCellCount
{
	[self build];
	return _insideCellCount;
}


#pragma mark - Building

//========== buildFromTriangles: ===============================================
//
// Purpose:		Marks the cells the surface passes through, lets the outside in
//				from all round, and measures how far each cell it did not reach
//				is from the outside.
//
//==============================================================================
- (void)buildFromTriangles:(NSData *)triangles
{
	const float	*corners	= triangles.bytes;
	NSUInteger	count		= triangles.length / (9 * sizeof(float));
	Box3		box			= InvalidBox;

	for (NSUInteger corner = 0; corner < count * 3; corner++)
	{
		box = V3UnionBoxAndPoint(box, V3Make(corners[3 * corner], corners[3 * corner + 1],
											 corners[3 * corner + 2]));
	}
	_bounds = box;

	if (count == 0)
	{
		return;
	}

	// Two layers of empty cells all round let the outside reach every side,
	// and keep every neighbor of a solid cell in the grid.
	Vector3	extent	= V3Sub(box.max, box.min);
	double	cells	= 0.0;

	_cellSize = 1.0;
	do
	{
		_size[0]	= (NSInteger)ceil(extent.x / _cellSize) + 5;
		_size[1]	= (NSInteger)ceil(extent.y / _cellSize) + 5;
		_size[2]	= (NSInteger)ceil(extent.z / _cellSize) + 5;
		cells		= (double)_size[0] * (double)_size[1] * (double)_size[2];
		_cellSize	*= (cells > MaximumCells) ? 2.0 : 1.0;
	}
	while (cells > MaximumCells);

	_origin	= V3Sub(box.min, V3Make(2.0 * _cellSize, 2.0 * _cellSize, 2.0 * _cellSize));
	_cells	= [NSMutableData dataWithLength:(NSUInteger)cells];
	memset(_cells.mutableBytes, LDrawShapeMarkUnknown, _cells.length);

	for (NSUInteger triangle = 0; triangle < count; triangle++)
	{
		[self markTriangle:corners + 9 * triangle];
	}
	[self letTheOutsideIn];
	[self measureDistances];
}


//========== markTriangle: =====================================================
//
// Purpose:		Marks every cell a triangle passes through as solid, by
//				sampling it more finely than the cells.
//
//==============================================================================
- (void)markTriangle:(const float *)corner
{
	uint8_t	*cells	= _cells.mutableBytes;
	Point3	a		= [self gridPoint:V3Make(corner[0], corner[1], corner[2])];
	Point3	b		= [self gridPoint:V3Make(corner[3], corner[4], corner[5])];
	Point3	c		= [self gridPoint:V3Make(corner[6], corner[7], corner[8])];
	Vector3	ab		= V3Sub(b, a);
	Vector3	ac		= V3Sub(c, a);
	double	longest	= MAX(V3Length(ab), MAX(V3Length(ac), V3Length(V3Sub(c, b))));
	NSInteger steps	= MAX((NSInteger)1, (NSInteger)ceil(longest / SampleStep));

	for (NSInteger along = 0; along <= steps; along++)
	{
		for (NSInteger across = 0; across <= steps - along; across++)
		{
			Point3		p		= V3Add(a, V3Add(V3MulScalar(ab, (double)along / steps),
												 V3MulScalar(ac, (double)across / steps)));
			NSInteger	x		= MAX(1, MIN(_size[0] - 2, (NSInteger)floor(p.x)));
			NSInteger	y		= MAX(1, MIN(_size[1] - 2, (NSInteger)floor(p.y)));
			NSInteger	z		= MAX(1, MIN(_size[2] - 2, (NSInteger)floor(p.z)));

			// Rounding may put a sample just past the part's box, but never
			// in the outer layer, which the outside must reach all round.
			cells[x + _size[0] * (y + _size[1] * z)] = LDrawShapeMarkSurface;
		}
	}
}


//========== letTheOutsideIn ===================================================
//
// Purpose:		Marks every cell the outside reaches through faces of cells
//				that are not solid, starting from the empty layer all round.
//
//==============================================================================
- (void)letTheOutsideIn
{
	uint8_t			*cells	= _cells.mutableBytes;
	NSMutableData	*queue	= [NSMutableData dataWithLength:_cells.length * sizeof(uint32_t)];
	uint32_t		*next	= queue.mutableBytes;
	NSUInteger		head	= 0;
	NSUInteger		tail	= 0;
	NSInteger		steps[6] = { 1, -1, _size[0], -_size[0], _size[0] * _size[1], -_size[0] * _size[1] };

	cells[0]		= LDrawShapeMarkReached;
	next[tail++]	= 0;

	while (head < tail)
	{
		uint32_t	index	= next[head++];
		NSInteger	x		= index % _size[0];
		NSInteger	y		= (index / _size[0]) % _size[1];
		NSInteger	z		= index / (_size[0] * _size[1]);
		BOOL		inside[6] = { x + 1 < _size[0], x > 0, y + 1 < _size[1], y > 0, z + 1 < _size[2], z > 0 };

		for (NSUInteger way = 0; way < 6; way++)
		{
			NSInteger neighbor = (NSInteger)index + steps[way];

			if (inside[way] && cells[neighbor] == LDrawShapeMarkUnknown)
			{
				cells[neighbor]	= LDrawShapeMarkReached;
				next[tail++]	= (uint32_t)neighbor;
			}
		}
	}
}


//========== measureDistances ==================================================
//
// Purpose:		How far each solid cell is from the outside, in quarter cells:
//				two sweeps through the grid, each passing on the nearest
//				distance from the 13 cells around that it has already been
//				through, first forward and then back.
//
//==============================================================================
- (void)measureDistances
{
	uint8_t		*cells		= _cells.mutableBytes;
	NSInteger	count		= (NSInteger)_cells.length;
	NSInteger	offsets[13];
	NSInteger	costs[13];
	NSUInteger	around		= 0;

	for (NSInteger dz = -1; dz <= 1; dz++)
	{
		for (NSInteger dy = -1; dy <= 1; dy++)
		{
			for (NSInteger dx = -1; dx <= 1; dx++)
			{
				NSInteger offset	= dx + _size[0] * (dy + _size[1] * dz);
				NSInteger moved		= labs(dx) + labs(dy) + labs(dz);

				if (offset < 0)
				{
					offsets[around]	= offset;
					costs[around]	= (moved == 1) ? FaceStep : (moved == 2) ? EdgeStep : CornerStep;
					around++;
				}
			}
		}
	}
	for (NSInteger index = 0; index < count; index++)
	{
		cells[index] = (cells[index] == LDrawShapeMarkReached) ? 0 : FarAway;
	}

	// The outer layer is never solid, so every neighbor of a solid cell is in
	// the grid.
	for (NSInteger sweep = 0; sweep < 2; sweep++)
	{
		for (NSInteger step = 0; step < count; step++)
		{
			NSInteger	index	= (sweep == 0) ? step : count - 1 - step;
			NSInteger	best	= cells[index];

			if (best == 0)
			{
				continue;
			}
			for (NSUInteger neighbor = 0; neighbor < around; neighbor++)
			{
				NSInteger offset = (sweep == 0) ? offsets[neighbor] : -offsets[neighbor];

				best = MIN(best, (NSInteger)cells[index + offset] + costs[neighbor]);
			}
			cells[index] = (uint8_t)best;
		}
	}
	uint8_t deepest = 0;

	for (NSInteger index = 0; index < count; index++)
	{
		deepest = MAX(deepest, cells[index]);
	}
	_deepDistance = MAX(ThinDeepDistance, MIN(DeepDistance, deepest));

	for (NSInteger index = 0; index < count; index++)
	{
		_solidCellCount		+= (cells[index] > 0) ? 1 : 0;
		_insideCellCount	+= (cells[index] >= _deepDistance) ? 1 : 0;
	}
}


#pragma mark - Cells

//========== gridPoint: ========================================================
//
// Purpose:		A point in the part's coordinates, in cells from the grid's
//				corner.
//
//==============================================================================
- (Point3)gridPoint:(Point3)point
{
	return V3MulScalar(V3Sub(point, _origin), 1.0 / _cellSize);
}


//========== indexOfGridPoint: =================================================
//
// Purpose:		The cell a point in cells falls in, or -1 outside the grid.
//
//==============================================================================
- (NSInteger)indexOfGridPoint:(Point3)point
{
	NSInteger x = (NSInteger)floor(point.x);
	NSInteger y = (NSInteger)floor(point.y);
	NSInteger z = (NSInteger)floor(point.z);

	if (x < 0 || y < 0 || z < 0 || x >= _size[0] || y >= _size[1] || z >= _size[2])
	{
		return -1;
	}
	return x + _size[0] * (y + _size[1] * z);
}


//========== distanceAt: =======================================================
//
// Purpose:		How far the cell a point falls in is from the outside, in
//				quarter cells: 0 outside the solid.
//
//==============================================================================
- (uint8_t)distanceAt:(Point3)point
{
	NSInteger index = (_cells != nil) ? [self indexOfGridPoint:[self gridPoint:point]] : -1;

	return (index >= 0) ? ((const uint8_t *)_cells.bytes)[index] : 0;
}


//========== containsPoint: ====================================================
//==============================================================================
- (BOOL)containsPoint:(Point3)point
{
	[self build];
	return [self distanceAt:point] > 0;
}


//========== containsPointDeeply: ==============================================
//==============================================================================
- (BOOL)containsPointDeeply:(Point3)point
{
	[self build];
	return [self distanceAt:point] >= _deepDistance;
}


#pragma mark - Going into each other

//========== placedAt:goesInto:placedAt:within: ================================
//
// Notes:		Both ways round: a small part can be wholly inside a large one,
//				with none of the large one's surface inside it.
//
//==============================================================================
- (BOOL)placedAt:(Matrix4)placement
		goesInto:(LDrawPartShape *)other
		placedAt:(Matrix4)otherPlacement
		  within:(Box3)region
{
	[self build];
	[other build];

	return [self edgeCellsPlacedAt:placement inside:other placedAt:otherPlacement within:region]
			>= MinimumCellsInside
		|| [other edgeCellsPlacedAt:otherPlacement inside:self placedAt:placement within:region]
			>= MinimumCellsInside;
}


//========== edgeCellsPlacedAt:inside:placedAt:within: =========================
//
// Purpose:		How many of this part's surface cells within the region lie
//				inside the other part, up to the most that matters.
//
//==============================================================================
- (NSUInteger)edgeCellsPlacedAt:(Matrix4)placement
						 inside:(LDrawPartShape *)other
					   placedAt:(Matrix4)otherPlacement
						 within:(Box3)region
{
	const uint8_t	*cells		= _cells.bytes;
	Matrix4			toOther		= Matrix4Multiply(placement, Matrix4Invert(otherPlacement));
	Box3			local		= LDrawBoxByMatrix(region, Matrix4Invert(placement));
	Point3			low			= [self gridPoint:local.min];
	Point3			high		= [self gridPoint:local.max];
	NSInteger		from[3]		= { MAX(0, (NSInteger)floor(low.x)), MAX(0, (NSInteger)floor(low.y)),
									MAX(0, (NSInteger)floor(low.z)) };
	NSInteger		to[3]		= { MIN(_size[0] - 1, (NSInteger)floor(high.x)),
									MIN(_size[1] - 1, (NSInteger)floor(high.y)),
									MIN(_size[2] - 1, (NSInteger)floor(high.z)) };
	NSUInteger		found		= 0;

	if (_cells == nil || other->_cells == nil || V3EqualBoxes(region, InvalidBox))
	{
		return 0;
	}
	for (NSInteger z = from[2]; z <= to[2]; z++)
	{
		for (NSInteger y = from[1]; y <= to[1]; y++)
		{
			for (NSInteger x = from[0]; x <= to[0]; x++)
			{
				uint8_t distance = cells[x + _size[0] * (y + _size[1] * z)];

				if (distance == 0 || distance > SurfaceDistance)
				{
					continue;
				}
				Point3 middle = V3Add(_origin, V3MulScalar(V3Make(x + 0.5, y + 0.5, z + 0.5), _cellSize));

				if ([other distanceAt:V3MulPointByProjMatrix(middle, toOther)] >= other->_deepDistance
					&& ++found >= MinimumCellsInside)
				{
					return found;
				}
			}
		}
	}
	return found;
}

@end
