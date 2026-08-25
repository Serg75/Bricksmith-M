//==============================================================================
//
//	LDrawApplicationMTL.h
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawApplication.h"


@interface LDrawApplication (Metal)

//Accessors
/// No-op on Metal; keeps callers shared with the OpenGL target.
+ (void) makeCurrentSharedContext;

/// No-op on Metal; there is no shared GL context to create.
- (void) makeSharedContext;

@end
