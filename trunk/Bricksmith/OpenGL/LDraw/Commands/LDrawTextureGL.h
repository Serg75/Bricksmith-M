//
//  LDrawTextureGL.h
//  Bricksmith-OpenGL
//
//  Created by Sergey Slobodenyuk on 2024-05-10.
//
#import <Cocoa/Cocoa.h>

#import "LDrawTexture.h"

#import "LDrawContainer.h"

@interface LDrawTextureGL : LDrawTexture
{
	GLuint			textureTag;
}

@end
