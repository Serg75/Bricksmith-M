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

simd_float4x4 simd_matrix_from_array(const float *matrix);
void simd_matrix_to_array(simd_float4x4 matrix, float *result);

NS_ASSUME_NONNULL_END

#endif /* MetalUtilities_h */
