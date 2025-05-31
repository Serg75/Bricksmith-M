//==============================================================================
//
//	LDrawViewGPU.h
//	Bricksmith
//
//	Purpose:	This is the intermediary between the operating system (events
//				and view hierarchy) and the LDrawRenderer (responsible for all
//				platform-independent drawing logic).
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawView.h"


@interface LDrawView (Metal)

- (void)makeCurrentContext;
- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block;

- (void) internalInit;

// Accessors
- (void) setBackgroundColor:(NSColor *)newColor;
- (void) setViewingAngle:(Tuple3)newAngle;

// Utilities
- (void) saveImageToPath:(NSString *)path;

@end
