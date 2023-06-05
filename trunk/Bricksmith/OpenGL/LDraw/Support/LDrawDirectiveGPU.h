//==============================================================================
//
//	LDrawDirectiveGPU.h
//	Bricksmith
//
//	Purpose:	This is an abstract base class for all elements of an LDraw
//				document.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-10.
//
//==============================================================================

#import "LDrawDirective.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawDirective (OpenGL)

// Directives
- (void) debugDrawboundingBox;

@end

NS_ASSUME_NONNULL_END
