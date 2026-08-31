//==============================================================================
//
//  File:		OpenGLDebugState.h
//  Package:	LDrawRenderOpenGL
//
//  Purpose:	Debug helpers for querying OpenGL enable bits and integer state.
//				Not a sibling of MetalUtilities (matrix conversion).
//
//  Created by bsupnik on 7/5/12.
//
//==============================================================================

#ifndef OpenGLDebugState_h
#define OpenGLDebugState_h

#include <OpenGL/gl.h>

#if DEBUG

/// Inverse of glIsEnabled, for debug assertions.
GLboolean		glIsDisabled(GLenum cap);

/// Return GL_TRUE if integer GL state cap equals value; prints otherwise.
GLboolean		glCheckInteger(GLenum cap, GLint value);

#endif

#endif /* OpenGLDebugState_h */
