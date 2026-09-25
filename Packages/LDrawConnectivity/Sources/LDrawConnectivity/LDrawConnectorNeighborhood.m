//==============================================================================
//
//  File:       LDrawConnectorNeighborhood.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Groups connectors by where they are, in a grid of cells.
//
//  Created by Sergey Slobodenyuk on 2026-09-24.
//
//==============================================================================

#import "LDrawConnectorNeighborhood.h"

#import "LDrawConnectivityMath.h"

// A guard against bad data, as the world index uses. A real run crosses far
// fewer cells, and a small cell size with a long run would fill memory.
static const NSUInteger MaximumConnectorCells = 4096;

@implementation LDrawConnectorNeighborhood
{
	LDrawWorldConnectors	*_connectors;
	CFMutableDictionaryRef	_cells;			// cell -> NSMutableData of indices
	double					_cellSize;
	NSMutableData			*_found;		// the answer, reused
	NSMutableData			*_stamps;		// one per connector, to answer it once
	uint32_t				_stamp;
}

- (instancetype)initWithConnectors:(LDrawWorldConnectors *)connectors cellSize:(double)cellSize
{
	self = [super init];
	if (self != nil)
	{
		const LDrawWorldConnector	*met	= connectors.all;
		NSUInteger					count	= connectors.count;

		_connectors	= connectors;
		_cellSize	= MAX(cellSize, 1.0);
		_cells		= CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
		_found		= [NSMutableData data];
		_stamps		= [NSMutableData dataWithLength:count * sizeof(uint32_t)];

		for (NSUInteger index = 0; index < count; index++)
		{
			Point3	mouth	= LDrawWorldConnectorMouth(met[index]);
			Point3	end		= V3Add(mouth, V3MulScalar(met[index].axis, met[index].length));

			[self addIndex:(uint32_t)index inBox:V3BoundsFromPoints(mouth, end)];
		}
	}
	return self;
}


- (void)dealloc
{
	CFRelease(_cells);
}


//========== addIndex:inBox: ===================================================
//
// Purpose:		Files a connector in every cell its box covers.
//
// Notes:		The box is enough. This only picks what to compare, and the
//				real test follows.
//
//==============================================================================
- (void)addIndex:(uint32_t)index inBox:(Box3)box
{
	int64_t first[3], last[3];

	[self cellOfPoint:box.min into:first];
	[self cellOfPoint:box.max into:last];

	NSUInteger filed = 0;

	for (int64_t x = first[0]; x <= last[0] && filed < MaximumConnectorCells; x++)
	{
		for (int64_t y = first[1]; y <= last[1] && filed < MaximumConnectorCells; y++)
		{
			for (int64_t z = first[2]; z <= last[2] && filed < MaximumConnectorCells; z++)
			{
				int64_t			key		= LDrawCellKey(x, y, z);
				NSMutableData	*cell	= (__bridge NSMutableData *)
										  CFDictionaryGetValue(_cells, (const void *)(intptr_t)key);

				if (cell == nil)
				{
					cell = [NSMutableData data];
					CFDictionarySetValue(_cells, (const void *)(intptr_t)key, (__bridge const void *)cell);
				}
				[cell appendBytes:&index length:sizeof(index)];
				filed++;
			}
		}
	}
}


- (void)cellOfPoint:(Point3)point into:(int64_t *)cell
{
	cell[0] = (int64_t)floor(point.x / _cellSize);
	cell[1] = (int64_t)floor(point.y / _cellSize);
	cell[2] = (int64_t)floor(point.z / _cellSize);
}


//========== indicesNearBox:count: =============================================
//==============================================================================
- (const uint32_t *)indicesNearBox:(Box3)box count:(NSUInteger *)countOut
{
	int64_t		first[3], last[3];
	uint32_t	*stamps	= _stamps.mutableBytes;

	_found.length = 0;
	_stamp++;

	[self cellOfPoint:box.min into:first];
	[self cellOfPoint:box.max into:last];

	for (int64_t x = first[0]; x <= last[0]; x++)
	{
		for (int64_t y = first[1]; y <= last[1]; y++)
		{
			for (int64_t z = first[2]; z <= last[2]; z++)
			{
				int64_t			key		= LDrawCellKey(x, y, z);
				NSData			*cell	= (__bridge NSData *)
										  CFDictionaryGetValue(_cells, (const void *)(intptr_t)key);
				const uint32_t	*inside	= cell.bytes;
				NSUInteger		count	= cell.length / sizeof(uint32_t);

				for (NSUInteger index = 0; index < count; index++)
				{
					if (stamps[inside[index]] == _stamp)
					{
						continue;			// already answered from another cell
					}
					stamps[inside[index]] = _stamp;
					[_found appendBytes:&inside[index] length:sizeof(uint32_t)];
				}
			}
		}
	}
	*countOut = _found.length / sizeof(uint32_t);

	return _found.bytes;
}


- (const LDrawWorldConnector *)connectors
{
	return _connectors.all;
}

@end
