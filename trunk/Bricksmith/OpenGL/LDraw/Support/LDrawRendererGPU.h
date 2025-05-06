//==============================================================================
//
//	LDrawRendererGPU.h
//	Bricksmith
//
//	Purpose:	Draws an LDrawFile with OpenGL.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import "LDrawRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawRenderer (OpenGL)

// Initialization
- (void) prepareOpenGL;

// Drawing
- (void) draw;

// Accessors
- (void) setBackgroundColorRed:(float)red green:(float)green blue:(float)blue;

@end

NS_ASSUME_NONNULL_END
