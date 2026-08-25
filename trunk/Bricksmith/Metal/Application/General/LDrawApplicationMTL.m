//==============================================================================
//
//	LDrawApplicationMTL.m
//	Bricksmith
//
//	Purpose:	This is the "application controller." Here we find application-
//				wide instance variables and actions, as well as application
//				delegate code for startup and shutdown.
//
//	Note:		Do not confuse this class with BricksmithApplication, which is
//				an NSApplication subclass.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawApplicationMTL.h"

@implementation LDrawApplication (Metal)

#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== makeCurrentSharedContext ==========================================
//
// Purpose:		Metal has no shared GL context. This is a no-op so callers can
//				share code with the OpenGL target.
//
//==============================================================================
+ (void) makeCurrentSharedContext { }

//========== makeSharedContext =================================================
//
// Purpose:		Metal has no shared GL context to create at launch.
//
//==============================================================================
- (void) makeSharedContext { }

@end
