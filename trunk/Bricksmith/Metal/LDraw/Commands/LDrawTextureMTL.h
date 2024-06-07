//
//  LDrawTextureMTL.h
//  Bricksmith-Metal
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

#import "LDrawTexture.h"

@interface LDrawTextureMTL : LDrawTexture
{
	id<MTLTexture> metalTexture;
}

@end
