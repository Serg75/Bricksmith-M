//==============================================================================
//
//	LDrawDragHandleGPU.h
//	Bricksmith
//
//	Purpose:	In-scene widget to manipulate a vertex.
//
//	Notes:		Sub-classes LDrawDrawableElement to get some dragging behavior.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawDragHandle.h"


@interface LDrawDragHandle (Metal)

// Draw
- (void) draw:(NSUInteger)optionsMask viewScale:(float)scaleFactor parentColor:(LDrawColor *)parentColor;

// Utilities
+ (void) makeSphereWithLongitudinalCount:(int)longitudeSections
						latitudinalCount:(int)latitudeSections;

@end
