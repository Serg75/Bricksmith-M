//==============================================================================
//
//	LDrawDirectiveGPU.h
//	Bricksmith
//
//	Purpose:	This is an abstract base class for all elements of an LDraw
//				document.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawDirective.h"


@interface LDrawDirective (Metal)

// Directives
- (void) debugDrawboundingBox;

@end
