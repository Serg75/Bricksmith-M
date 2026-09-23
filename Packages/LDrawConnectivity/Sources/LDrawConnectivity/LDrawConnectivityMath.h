//==============================================================================
//
//  File:       LDrawConnectivityMath.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Transforms a direction by a matrix, ignoring the translation.
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
