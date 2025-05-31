/*
 *  MatrixMathEx.h
 *  Bricksmith
 *
 *  Created by bsupnik on 9/24/13.
 *  Copyright 2013 __MyCompanyName__. All rights reserved.
 *
 */

#ifndef MatrixMathEx_H
#define MatrixMathEx_H

//
//	MatrixMathEx
//
//	These APIs operate directly on 16-float column-major matrices, that is, OpenGL's matrix format of choice; they
//	are used to emulate fixed function behavior.



// Apply matrix transform ot input vec4.
void applyMatrixInPlace(float v[4], const float m[16]);
void applyMatrix(float dst[4], const float m[16], const float v[4]);

// Apply perspective divide to homogeneous vec4.
void perspectiveDivideInPlace(float p[4]);
void perspectiveDivide(float o[3], const float p[4]);

// Apply transpose(M) to vec4.
void applyMatrixTranspose(float dst[4], const float m[16], const float v[4]);

// Compose two 4x4 matrices (e.g. dst = a * b.
void multMatrices(float dst[16], const float a[16], const float b[16]);


// These routines build the matrices that are normally built for you via the 
// OpenGL fixed function transform stack.  Function arguments match their
// OpenGL counterparts.
void buildRotationMatrix(float m[16], float angle, float x, float y, float z);
void buildTranslationMatrix(float m[16], float x, float y, float z);
void buildIdentity(float m[16]);
void buildOrthoMatrix(float m[16], float left, float right, float bottom, float top, float zNear, float zFar);
void buildFrustumMatrix(float m[16], float left, float right, float bottom, float top, float zNear, float zFar);

void applyRotationMatrix(float m[16], float angle, float x, float y, float z);



void meshToClipbox(float * vertices, int vcount, const int * lines, const float m[16], float out_aabb_ndc[6]);
void aabbToClipbox(const float aabb_mv[6], const float m[16], float aabb_ndc[6]);

int clipTriangle(const float in_tri[12], float out_tri[18]);


#endif
