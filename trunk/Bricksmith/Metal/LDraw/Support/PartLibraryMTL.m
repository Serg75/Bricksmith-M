//==============================================================================
//
//	File:		PartLibraryMTL.m
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
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "PartLibraryMTL.h"

#import <MetalKit/MetalKit.h>
#import "MetalGPU.h"

@implementation PartLibraryMTL

static PartLibraryMTL *SharedPartLibrary = nil;

//---------- sharedPartLibrary ---------------------------------------[static]--
//
// Purpose:		Returns the part library, which contains the part catalog, which
//				is read in from the file LDRAW_PATH_KEY/PART_CATALOG_NAME when
//				the application launches.
//				This is a rather big XML file, so it behooves us to read it
//				once then save it in memory.
//
//------------------------------------------------------------------------------
+ (PartLibraryMTL *) sharedPartLibrary
{
	if(SharedPartLibrary == nil)
	{
		SharedPartLibrary = [[PartLibraryMTL alloc] init];
	}

	return SharedPartLibrary;

}//end sharedPartLibrary


//========== textureTagForTexture: =============================================
//
// Purpose:		Returns the Metal texture object necessary to draw the image
//				represented by the high-level texture object.
//
//==============================================================================
- (id<MTLTexture>)metalTextureForTexture:(LDrawTextureGPU*)texture
{
	NSString		*name			= [texture imageReferenceName];
	id<MTLTexture> 	cachedTexture	= [self->optimizedTextures objectForKey:name];
	id<MTLTexture> 	metalTexture 	= nil;

	if (cachedTexture)
	{
		metalTexture = cachedTexture;
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
			// Use MTKTextureLoader to generate a Metal texture
			MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:MetalGPU.device];
			NSDictionary *textureLoaderOptions = @{MTKTextureLoaderOptionSRGB : @NO};

			NSData *imageData = [NSData dataWithBytesNoCopy:imageBuffer length:(canvasRect.size.width * canvasRect.size.height * 4) freeWhenDone:YES];
			CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)imageData);
			CGImageRef processedImage = CGImageCreate(
				canvasRect.size.width,
				canvasRect.size.height,
				8,
				32,
				canvasRect.size.width * 4,
				colorSpace,
				kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst,
				dataProvider,
				NULL,
				false,
				kCGRenderingIntentDefault
			);

			NSError *error = nil;
			metalTexture = [textureLoader newTextureWithCGImage:processedImage options:textureLoaderOptions error:&error];

			if (error) {
				NSLog(@"Error loading texture: %@", error.localizedDescription);
			} else {
				[self->optimizedTextures setObject:metalTexture forKey:name];
			}


			// free memory
			//	free(imageBuffer);
			CGDataProviderRelease(dataProvider);
			CGImageRelease(processedImage);
			CFRelease(colorSpace);
			CFRelease(bitmapContext);
		}
	}
	
	return metalTexture;
}


@end
