//
//  MetalCommonDefinitions.h
//  Bricksmith-Metal
//
//  Abstract:
//  Header that contains types and enumeration constants shared between Metal shaders and C/Objective-C source.
//
//  Created by Sergey Slobodenyuk on 2024-04-24.
//

#ifndef MetalCommonDefinitions_h
#define MetalCommonDefinitions_h

#include <simd/simd.h>


// MARK: - Constants -

// Stride of our vertices - we always write  X Y Z   NX NY NZ   R G B A
#define VERT_STRIDE 10
// The number of float values in InstanceInput struct
#define InstanceInputLength 24
// The size in bytes of InstanceInput struct
#define InstanceInputStructSize (InstanceInputLength * sizeof(float))


// MARK: - Indices -

// Buffer index values shared between shader and CPU code to ensure Metal shader buffer inputs
// match Metal API buffer set calls.
typedef enum BufferIndex {
	BufferIndexInstanceInvariantData	= 0,
	BufferIndexPerInstanceData  		= 1,
	BufferIndexVertexUniforms      		= 2,
	BufferIndexTexturePlane      		= 3,
	BufferIndexFragmentUniforms 		= 0
} BufferIndex;

// Attribute index values shared between shader and CPU code to ensure Metal shader vertex attribute indices
// match Metal API vertex descriptor attribute indices.
typedef enum VertexAttribute {
	VertexAttributePosition	= 0,
	VertexAttributeNormal  	= 1,
	VertexAttributeColor	= 2,
} VertexAttribute;


// MARK: - Vertex shader -

// Note: each column in matrix_float3x3 is aligned to 16 bytes
typedef struct VertexUniform {
	matrix_float4x4 model_view_matrix;
	matrix_float4x4 projection_matrix;
	matrix_float3x3 normal_matrix;
} VertexUniform;

// Instance data shared between CPU and GPU for hardware instancing
typedef struct InstanceInput {
	vector_float4	transform_x;
	vector_float4	transform_y;
	vector_float4	transform_z;
	vector_float4	transform_w;
	vector_float4	color_current;
	vector_float4	color_compliment;
} InstanceInput;

// Texture plane generation data for automatic texture coordinate generation
typedef struct TexturePlaneData {
	vector_float4	plane_s;
	vector_float4	plane_t;
} TexturePlaneData;


// MARK: - Fragment shader -

typedef struct LightSourceParameters {
    vector_float4 diffuse;
    vector_float4 position;
} LightSourceParameters;

typedef struct LightModelParameters {
    vector_float4 ambient;
} LightModelParameters;

typedef struct FragmentUniform {
    LightSourceParameters light_source[2];
    LightModelParameters light_model;
} FragmentUniform;


#endif /* MetalCommonDefinitions_h */
