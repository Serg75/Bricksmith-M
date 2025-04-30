//==============================================================================
//
//	LDrawPartGPU.m
//	Bricksmith
//
//	Purpose:	Part command.
//				Inserts a part defined in another LDraw file.
//
//				Line format:
//				1 colour x y z a b c d e f g h i part.dat
//
//				where
//
//				* colour is a colour code: 0-15, 16, 24, 32-47, 256-511
//				* x, y, z is the position of the part
//				* a - i are orientation & scaling parameters
//				* part.dat is the filename of the included file
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawPartGPU.h"

#import "LDrawModel.h"
#import "PartLibraryMTL.h"

@implementation LDrawPart (Metal)

#pragma mark -
#pragma mark DIRECTIVES
#pragma mark -

//========== debugDrawBoundingBox ==============================================
//
// Purpose:		Draw a translucent visualization of our bounding box to test
//				bounding box caching.
//
// Notes:		This part is not implemented in Metal as being of not much value
//
//==============================================================================
- (void) debugDrawBoundingBox
{
}


@end
