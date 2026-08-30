/*
 *  OpenGLUtilities.c
 *  Bricksmith
 *
 *  Created by bsupnik on 7/5/12.
 *  Copyright 2012 __MyCompanyName__. All rights reserved.
 *
 */

#include "OpenGLUtilities.h"
#include <stdio.h>

#if DEBUG

//========== glIsDisabled ======================================================
//
// Purpose:		Convenience inverse of glIsEnabled for debug assertions.
//
//==============================================================================
GLboolean	glIsDisabled(GLenum cap)
{
	return !glIsEnabled(cap);
}

//========== glCheckInteger ====================================================
//
// Purpose:		Read integer GL state cap and return GL_TRUE if it equals value.
//				Prints a diagnostic when it does not.
//
//==============================================================================
GLboolean	glCheckInteger(GLenum cap, GLint value)
{
	GLint v = 0;
	glGetIntegerv(cap, &v);
	if (v != value)
		printf("Expected tag %04x to be %d but was %d\n", cap, value, v);
	return (v == value);
}

#endif
