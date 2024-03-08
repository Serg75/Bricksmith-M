//==============================================================================
//
//	LDrawShaderRendererGPU.h
//	Bricksmith
//
//	Purpose:	an implementation of the LDrawCoreRenderer API using GL shaders.
//
//				The renderer maintains a stack view of OpenGL state; as
//				directives push their info to the renderer, containing LDraw
//				parts push and pop state to affect the child parts that are
//				drawn via the depth-first traversal.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawShaderRenderer.h"


@interface LDrawShaderRenderer (Metal)

- (id) initWithScale:(float)scale modelView:(GLfloat *)mv_matrix projection:(GLfloat *)proj_matrix;

- (void) drawDragHandleImm:(GLfloat*)xyz withSize:(GLfloat)size;

@end
