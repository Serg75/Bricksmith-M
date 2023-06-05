//==============================================================================
//
//	LDrawDragHandleGPU.h
//	Bricksmith
//
//	Purpose:	In-scene widget to manipulate a vertex.
//
//	Notes:		Sub-classes LDrawDrawableElement to get some dragging behavior.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-29.
//
//==============================================================================

#import "LDrawDragHandle.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawDragHandle (OpenGL)

// Draw
- (void) draw:(NSUInteger)optionsMask viewScale:(float)scaleFactor parentColor:(LDrawColor *)parentColor;

// Utilities
+ (void) makeSphereWithLongitudinalCount:(int)longitudeSections
						latitudinalCount:(int)latitudeSections;

@end

NS_ASSUME_NONNULL_END
