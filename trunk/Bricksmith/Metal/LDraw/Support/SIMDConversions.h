//==============================================================================
//
//  SIMDConversions.h
//  Bricksmith-Metal
//
//  Purpose:    SIMD/C-data-type conversion helpers for CPU-side code.
//
//  Created by Sergey Slobodenyuk on 2025-05-30.
//
//==============================================================================

#ifndef SIMDConversions_h
#define SIMDConversions_h

#include <simd/simd.h>
#include "MatrixMath.h" // for Tuple4/Point4

#ifdef __cplusplus
extern "C" {
#endif

// Converts a Tuple4 or Point4 to a vector_float4 (simd float4)
static inline vector_float4 tuple4_to_float4(const Tuple4 t) {
	return (vector_float4){ t.x, t.y, t.z, t.w };
}

#ifdef __cplusplus
}
#endif

#endif /* SIMDConversions_h */
