//==============================================================================
//
//  File:       LDrawShaderLoader.h
//  Package:    LDrawRenderOpenGL
//
//  Created by bsupnik on 11/9/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <OpenGL/gl.h>

NS_ASSUME_NONNULL_BEGIN

// OpenGL shader loader.  attrib list is a null terminated list of strings that will
// be assigned to GL attributes starting at attribute index 0.
// Return code is a GLuint program object or 0 on fail.

GLuint	LDrawLoadShaderFromFile(NSString * file_path, const char * _Nullable const * _Nullable attrib_list);
GLuint	LDrawLoadShaderFromResource(NSString * name, const char * _Nullable const * _Nullable attrib_list);

NS_ASSUME_NONNULL_END
