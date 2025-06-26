//
//  GL.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-03-30.
//

#ifndef GL_h
#define GL_h

#define LDrawApplicationGPU_h		"LDrawApplicationGL.h"
#define LDrawDirectiveGPU_h			"LDrawDirectiveGL.h"
#define LDrawDisplayList_h			"LDrawDisplayListGL.h"
#define LDrawDocumentGPU_h			"LDrawDocumentGL.h"
#define LDrawRendererGPU_h			"LDrawRendererGL.h"
#define LDrawShaderRendererGPU_h	"LDrawShaderRendererGL.h"
#define LDrawTextureGPU_h			"LDrawTextureGL.h"
#define LDrawViewGPU_h				"LDrawViewGL.h"
#define PartLibraryGPU_h			"PartLibraryGL.h"

#define OPEN_GL_HEADER				<OpenGL/gl.h>
#define OPEN_GL_EXT_HEADER			<OpenGL/glext.h>

#define GPUView						NSOpenGLView
#define TexType						GLuint
#define LDrawTextureGPU 			LDrawTextureGL
#define PartLibraryGPU				PartLibraryGL

#endif /* GL_h */
