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

//========== simd_matrix4x4_from_array ========================================
//
// Purpose:   Helper function to convert from float array to matrix_float4x4.
//
//==============================================================================
matrix_float4x4 simd_matrix4x4_from_array(const float *matrix) {
	return simd_matrix(
		simd_make_float4(matrix[0], matrix[4], matrix[8], matrix[12]),
		simd_make_float4(matrix[1], matrix[5], matrix[9], matrix[13]),
		simd_make_float4(matrix[2], matrix[6], matrix[10], matrix[14]),
		simd_make_float4(matrix[3], matrix[7], matrix[11], matrix[15])
	);
}//end simd_matrix4x4_from_array


//========== simd_matrix4x4_from_array_transposed =============================
//
// Purpose:   Helper function to convert from float array to matrix_float4x4,
//            returning the transpose of the constructed matrix.
//            Useful when you need the row-major version or want to swap axes.
//
//==============================================================================
matrix_float4x4 simd_matrix4x4_from_array_transposed(const float *matrix) {
	matrix_float4x4 m = simd_matrix4x4_from_array(matrix);
	return simd_transpose(m);
}


//========== simd_normal_matrix_from_matrix4x4 =================================
//
// Purpose:		Normal vectors (for lighting) cannot be transformed by the same
//				matrix which transforms vertexes. This method returns the
//				correct matrix to transform normals for the given vertex
//				transform (modelview) matrix.
//
// Notes:		See "Matrices" notes in Bricksmith/Information for derivation.
//
//				We only need a 3x3 matrix because the translation in the 4x4
//				transform (row 4) is undesirable anyway (a 4D vector should be
//				[x y z 0]), and column 4 isn't used.
//
//==============================================================================
matrix_float3x3 simd_normal_matrix_from_matrix4x4(matrix_float4x4 m) {
	matrix_float3x3 upperLeft = (matrix_float3x3){
		m.columns[0].xyz,
		m.columns[1].xyz,
		m.columns[2].xyz
	};
	return simd_transpose(simd_inverse(upperLeft));

}//end simd_normal_matrix_from_matrix4x4


//========== simd_matrix_to_array ==============================================
//
// Purpose:   Helper function to convert from matrix_float4x4 to float array.
//
//==============================================================================
void simd_matrix_to_array(matrix_float4x4 matrix, float *result) {
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
