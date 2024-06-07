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

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match Metal API
// buffer set calls.
typedef enum BufferIndex {
	BufferIndexInstanceInvariantData	= 0,
	BufferIndexPerInstanceData  		= 1,
	BufferIndexVertexUniforms      		= 2,
	TexIndexUniforms      				= 3,
	BufferIndexFragmentUniforms 		= 0
} BufferIndex;

// Attribute index values shared between shader and C code to ensure Metal shader vertex attribute indices
// match Metal API vertex descriptor attribute indices.
typedef enum VertexAttribute {
	VertexAttributePosition	= 0,
	VertexAttributeNormal  	= 1,
	VertexAttributeColor	= 2,
} VertexAttribute;


#endif /* MetalCommonDefinitions_h */
