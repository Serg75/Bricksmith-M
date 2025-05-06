//==============================================================================
//
//  MetalUtilities.m
//  Bricksmith-Metal
//
//  Purpose:		Routines for converting matrix format.
//
//  Created by Sergey Slobodenyuk on 2025-04-30.
//
//==============================================================================

#import "MetalUtilities.h"

//========== simd_matrix_from_array ============================================
//
// Purpose:	Helper function to convert from float array to simd_float4x4.
//
//==============================================================================
simd_float4x4 simd_matrix_from_array(const float *matrix) {
	return simd_matrix(
		simd_make_float4(matrix[0], matrix[4], matrix[8], matrix[12]),
		simd_make_float4(matrix[1], matrix[5], matrix[9], matrix[13]),
		simd_make_float4(matrix[2], matrix[6], matrix[10], matrix[14]),
		simd_make_float4(matrix[3], matrix[7], matrix[11], matrix[15])
	);
}//end simd_matrix_from_array


//========== simd_matrix_to_array ==============================================
//
// Purpose:	Helper function to convert from simd_float4x4 to float array.
//
//==============================================================================
void simd_matrix_to_array(simd_float4x4 matrix, float *result) {
	result[0] = matrix.columns[0].x;
	result[4] = matrix.columns[0].y;
	result[8] = matrix.columns[0].z;
	result[12] = matrix.columns[0].w;

	result[1] = matrix.columns[1].x;
	result[5] = matrix.columns[1].y;
	result[9] = matrix.columns[1].z;
	result[13] = matrix.columns[1].w;

	result[2] = matrix.columns[2].x;
	result[6] = matrix.columns[2].y;
	result[10] = matrix.columns[2].z;
	result[14] = matrix.columns[2].w;

	result[3] = matrix.columns[3].x;
	result[7] = matrix.columns[3].y;
	result[11] = matrix.columns[3].z;
	result[15] = matrix.columns[3].w;

}//end simd_matrix_to_array
