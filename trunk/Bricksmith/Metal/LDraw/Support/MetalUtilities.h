//==============================================================================
//
//  MetalUtilities.h
//  Bricksmith-Metal
//
//  Purpose:		Routines for converting matrix format.
//
//  Created by Sergey Slobodenyuk on 2025-04-30.
//
//==============================================================================

#ifndef MetalUtilities_h
#define MetalUtilities_h

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

// Converts a float[16] array (row-major) to a Metal-compatible 4x4 matrix.
matrix_float4x4 simd_matrix4x4_from_array(const float *matrix);
// Converts a float[16] array (row-major) to a 4x4 matrix, then returns its transpose.
matrix_float4x4 simd_matrix4x4_from_array_transposed(const float *matrix);
// Converts a 4x4 matrix to a float[16] array (row-major, Metal layout).
void simd_matrix_to_array(matrix_float4x4 matrix, float *result);
// Copies a float[16] matrix (column-major) directly to a float buffer in transposed (row-major) form.
void copy_matrix_transposed(float *dest, const float *source);
// Computes the normal matrix (inverse transpose of the upper-left 3x3 of a 4x4 matrix).
matrix_float3x3 simd_normal_matrix_from_matrix4x4(matrix_float4x4 m);

NS_ASSUME_NONNULL_END

#endif /* MetalUtilities_h */
