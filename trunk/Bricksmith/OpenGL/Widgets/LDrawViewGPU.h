//==============================================================================
//
//	LDrawViewGPU.h
//	Bricksmith
//
//	Purpose:	This is the intermediary between the operating system (events
//				and view hierarchy) and the LDrawRenderer (responsible for all
//				platform-independent drawing logic).
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import "LDrawView.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawView (OpenGL)

- (void)makeCurrentContext;
- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block;

- (void) internalInit;

// Drawing
- (void) draw;

// Accessors
- (void) setBackgroundColor:(NSColor *)newColor;
- (void) setViewingAngle:(Tuple3)newAngle;

// Utilities
- (void) saveImageToPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
