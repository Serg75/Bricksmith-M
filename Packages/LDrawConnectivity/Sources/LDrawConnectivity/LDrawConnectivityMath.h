//==============================================================================
//
//  File:       LDrawConnectivityMath.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Small math the package shares: transforming a direction by a
//              matrix, and the key of a grid cell.
//
//  Created by Sergey Slobodenyuk on 2026-09-21.
//
//==============================================================================

#import <LDrawCore/MatrixMath.h>


//---------- LDrawDirectionByMatrix --------------------------------------------
///
/// Transforms a direction by a matrix acting on row vectors. The result is not
/// normalized, so its length is the scale along the direction.
///
//------------------------------------------------------------------------------
static inline Vector3 LDrawDirectionByMatrix(Vector3 direction, Matrix4 matrix)
{
	Vector3 turned;

	turned.x = direction.x * matrix.element[0][0] + direction.y * matrix.element[1][0]
			 + direction.z * matrix.element[2][0];
	turned.y = direction.x * matrix.element[0][1] + direction.y * matrix.element[1][1]
			 + direction.z * matrix.element[2][1];
	turned.z = direction.x * matrix.element[0][2] + direction.y * matrix.element[1][2]
			 + direction.z * matrix.element[2][2];

	return turned;
}


//---------- LDrawCellKey ------------------------------------------------------
///
/// One number for a cell of a 3D grid. Each index is shifted positive and kept
/// to 21 bits, so a model below the origin is named as well as one above it,
/// and no shift runs off the end of the number.
///
//------------------------------------------------------------------------------
static inline int64_t LDrawCellKey(int64_t x, int64_t y, int64_t z)
{
	uint64_t key = ((uint64_t)((x + (1 << 20)) & 0x1FFFFF) << 42)
				 | ((uint64_t)((y + (1 << 20)) & 0x1FFFFF) << 21)
				 |  (uint64_t)((z + (1 << 20)) & 0x1FFFFF);

	return (int64_t)key;
}
