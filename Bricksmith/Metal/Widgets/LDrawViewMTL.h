//==============================================================================
//
//	LDrawViewMTL.h
//	Bricksmith
//
//	Purpose:	This is the intermediary between the operating system (events
//				and view hierarchy) and the LDrawRenderer (responsible for all
//				platform-independent drawing logic).
//
//	Info:		This category contains Metal-related code. Shared GPU methods
//				(makeCurrentContext, lockContextAndExecute:, setBackgroundColor:,
//				setViewingAngle:) are declared on LDrawView.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawView.h"


@interface LDrawView (Metal)

- (void)internalInit;
- (void)saveImageToPath:(NSString *)path;

@end
