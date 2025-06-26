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
+ (void) makeCurrentSharedContext;

- (void) makeSharedContext;

@end
