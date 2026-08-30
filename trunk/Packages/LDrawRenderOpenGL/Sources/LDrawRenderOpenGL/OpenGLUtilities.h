//==============================================================================
//
//  File:       OpenGLUtilities.h
//  Package:    LDrawRenderOpenGL
//
//  Purpose:    Debug helpers for querying OpenGL enable bits and integer state.
//
//  Created by bsupnik on 7/5/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
//==============================================================================

#ifndef OpenGLUtilities_h
#define OpenGLUtilities_h

#include <OpenGL/gl.h>

#if DEBUG

/// Inverse of glIsEnabled, for debug assertions.
GLboolean		glIsDisabled(GLenum cap);

/// Return GL_TRUE if integer GL state cap equals value; prints otherwise.
GLboolean		glCheckInteger(GLenum cap, GLint value);

#endif

#endif /* OpenGLUtilities_h */
