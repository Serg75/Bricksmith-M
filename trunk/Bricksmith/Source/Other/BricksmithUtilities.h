//==============================================================================
//
// File:		BricksmithUtilities.h
//
// Purpose:		Miscellaneous utility methods for the Bricksmith application.
//
// Notes:		Utility methods specific to LDraw syntax, manipulation, or 
//				display or found in LDrawUtilities. 
//
// Modified:	02/07/2011 Allen Smith. Creation Date.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

////////////////////////////////////////////////////////////////////////////////
//
// BricksmithUtilities
//
////////////////////////////////////////////////////////////////////////////////
@interface BricksmithUtilities : NSObject
{

}

+ (NSImage *) dragImageWithOffset:(NSPointPointer)dragImageOffset;

@end
