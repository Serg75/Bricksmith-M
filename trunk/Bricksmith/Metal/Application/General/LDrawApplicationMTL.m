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

+ (void) makeCurrentSharedContext { }

- (void) makeSharedContext { }

@end
