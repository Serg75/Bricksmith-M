//==============================================================================
//
//	File:		PartLibraryGL.m
//
//	Purpose:	This is the centralized repository for obtaining information
//				about the contents of the LDraw folder. The part library is
//				first created by scanning the LDraw folder and collecting all
//				the part names, categories, and drawing instructions for each
//				part. This information is then saved into an XML file and
//				retrieved each time the program is relaunched. During runtime,
//				other objects query the part library to draw and display
//				information about parts.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import "PartLibraryGL.h"

#include OPEN_GL_HEADER

@implementation PartLibraryGL

static PartLibraryGL *SharedPartLibrary = nil;

//---------- sharedPartLibrary ---------------------------------------[static]--
//
// Purpose:		Returns the part library, which contains the part catalog, which
//				is read in from the file LDRAW_PATH_KEY/PART_CATALOG_NAME when
//				the application launches.
//				This is a rather big XML file, so it behooves us to read it
//				once then save it in memory.
//
//------------------------------------------------------------------------------
+ (PartLibraryGL *) sharedPartLibrary
{
	if(SharedPartLibrary == nil)
	{
		SharedPartLibrary = [[PartLibraryGL alloc] init];
	}

	return SharedPartLibrary;

}//end sharedPartLibrary


//========== textureTagForTexture: =============================================
//
// Purpose:		Returns the OpenGL tag necessary to draw the image represented
//				by the high-level texture object.
//
//==============================================================================
- (GLuint) textureTagForTexture:(LDrawTextureGPU*)texture
{
	NSString	*name		= [texture imageReferenceName];
	NSNumber	*tagNumber	= [self->optimizedTextures objectForKey:name];
	GLuint		textureTag	= 0;
	
	if(tagNumber)
	{
		textureTag = [tagNumber unsignedIntValue];
	}
	else
	{
		CGImageRef	image	= [self imageForTexture:texture];
		
		if(image)
		{
			CGRect			canvasRect		= CGRectMake( 0, 0, FloorPowerOfTwo(CGImageGetWidth(image)), FloorPowerOfTwo(CGImageGetHeight(image)) );
			uint8_t 		*imageBuffer	= malloc( (canvasRect.size.width) * (canvasRect.size.height) * 4 );
			CGColorSpaceRef colorSpace		= CGColorSpaceCreateDeviceRGB();
			CGContextRef	bitmapContext	= CGBitmapContextCreate(imageBuffer,
																	canvasRect.size.width,
																	canvasRect.size.height,
																	8, // bits per component
																	canvasRect.size.width * 4, // bytes per row
																	colorSpace,
																	kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst
																	);
			
			// Draw the image into the bitmap context. By doing so, we use the mighty
			// power of Quartz handle the nasty conversion details necessary to fill up
			// a pixel buffer in an OpenGL-friendly storage format and color space.
			CGContextSetBlendMode(bitmapContext, kCGBlendModeCopy);
			CGContextDrawImage(bitmapContext, canvasRect, image);
			
//			CGImageRef output = CGBitmapContextCreateImage(bitmapContext);
//			CGImageDestinationRef myImageDest = CGImageDestinationCreateWithURL((CFURLRef)[NSURL fileURLWithPath:@"/out.png"], kUTTypePNG, 1, nil);
//			//NSDictionary* options = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt:1.0], kCGImageDestinationLossyCompressionQuality, nil]; // Don't know if this is necessary
//			CGImageDestinationAddImage(myImageDest, output, NULL);
//			CGImageDestinationFinalize(myImageDest);
//			CFRelease(myImageDest);
			
			// Generate a tag for the texture we're about to generate, then set it as
			// the active texture.
			// Note: We are using non-rectangular textures here, which started as an
			//		 extension (_EXT) and is now ratified by the review board (_ARB)
			glGenTextures(1, &textureTag);
			glBindTexture(GL_TEXTURE_2D, textureTag);
			
			// Generate Texture!
			glPixelStorei(GL_PACK_ROW_LENGTH,	canvasRect.size.width * 4);
			glPixelStorei(GL_PACK_ALIGNMENT,	1); // byte alignment
			
			glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA8,			// texture type params
						 canvasRect.size.width, canvasRect.size.height, 0,	// source image (w, h)
						 GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV,				// source storage format
						 imageBuffer );
						// see function notes about the source storage format.
			
			// This requires GL_EXT_framebuffer_object, available on all renderers on 10.6.8 and beyond.
			// Build mipmaps so we can use linear-mipmap-linear
			glGenerateMipmapEXT(GL_TEXTURE_2D);

			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);	// This enables mip-mapping - makes textures look good when small.
			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 4.0);				// Max anisotropic filtering of all renderers on 10.6.8 is 16.0.
																							// This keeps texture res high when looking at a tile from a low angle.

			glBindTexture(GL_TEXTURE_2D, 0);
			
			[self->optimizedTextures setObject:[NSNumber numberWithUnsignedInt:textureTag] forKey:name];
			
			// free memory
			//	free(imageBuffer);
			CFRelease(colorSpace);
			CFRelease(bitmapContext);
		}
	}
	
	return textureTag;
}


@end
