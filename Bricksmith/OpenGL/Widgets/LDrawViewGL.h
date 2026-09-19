//==============================================================================
//
//	LDrawViewGL.h
//	Bricksmith
//
//	Purpose:	This is the intermediary between the operating system (events
//				and view hierarchy) and the LDrawRenderer (responsible for all
//				platform-independent drawing logic).
//
//	Info:		This category contains OpenGL-related code. Shared GPU methods
//				(makeCurrentContext, lockContextAndExecute:, setBackgroundColor:,
//				setViewingAngle:) are declared on LDrawView.
//
//	Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import "LDrawView.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawView (OpenGL)

- (void)internalInit;
- (void)draw;
- (void)saveImageToPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
