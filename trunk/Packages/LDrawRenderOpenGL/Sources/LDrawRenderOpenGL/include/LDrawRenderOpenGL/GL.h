//==============================================================================
//
//  File:       GL.h
//  Package:    LDrawRenderOpenGL
//
//  Created by Sergey Slobodenyuk on 2023-03-30.
//
//==============================================================================

#ifndef GL_h
#define GL_h

#define LDrawApplicationGPU_h		"LDrawApplicationGL.h"
#define LDrawDocumentGPU_h			"LDrawDocumentGL.h"
#define LDrawRendererGPU_h			<LDrawRenderOpenGL/LDrawRendererGL.h>
#define LDrawTextureGPU_h			<LDrawRenderOpenGL/LDrawTextureGL.h>
#define LDrawViewGPU_h				"LDrawViewGL.h"
#define PartLibraryGPU_h			<LDrawRenderOpenGL/PartLibraryGL.h>

#define OPEN_GL_HEADER				<OpenGL/gl.h>
#define OPEN_GL_EXT_HEADER			<OpenGL/glext.h>

#define GPUView						NSOpenGLView
#define TexType						GLuint
#define LDrawTextureGPU 			LDrawTextureGL
#define PartLibraryGPU				PartLibraryGL

#endif /* GL_h */
