//==============================================================================
//
//  File:       LDrawPartLibraryMTL.m
//  Package:    LDrawRenderMetal
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder. The part library is
//              first created by scanning the LDraw folder and collecting all
//              the part names, categories, and drawing instructions for each
//              part. This information is then saved into an XML file and
//              retrieved each time the program is relaunched. During runtime,
//              other objects query the part library to draw and display
//              information about parts.
//
//  Info:       Metal-backed subclass of LDrawPartLibrary.
//
//  Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import <LDrawRenderMetal/LDrawPartLibraryMTL.h>

#import <LDrawRenderMetal/MetalGPU.h>

@implementation LDrawPartLibraryMTL

static LDrawPartLibraryMTL *SharedPartLibrary = nil;

//---------- load ----------------------------------------------------[static]--
//
// Purpose:		Registers this renderer's shared LDrawPartLibrary as the process-wide
//				singleton so generic model code can fetch it through
//				`+[LDrawPartLibrary sharedPartLibrary]` without naming the renderer.
//
//------------------------------------------------------------------------------
+ (void)load
{
	[LDrawPartLibrary registerSharedPartLibrary:[LDrawPartLibraryMTL sharedPartLibrary]];
} // end load


//---------- sharedPartLibrary ---------------------------------------[static]--
//
// Purpose:		Returns the part library, which contains the part catalog, which
//				is read in from the file LDRAW_PATH_KEY/PART_CATALOG_NAME when
//				the application launches.
//				This is a rather big XML file, so it behooves us to read it
//				once then save it in memory.
//
//------------------------------------------------------------------------------
+ (LDrawPartLibraryMTL *)sharedPartLibrary
{
	if (SharedPartLibrary == nil)
	{
		SharedPartLibrary = [[LDrawPartLibraryMTL alloc] init];
	}

	return SharedPartLibrary;

} // end sharedPartLibrary


//========== textureTagForTexture: =============================================
//
// Purpose:		Returns the Metal texture object necessary to draw the image
//				represented by the high-level texture object.
//
//==============================================================================
- (id<MTLTexture>)metalTextureForTexture:(LDrawTextureMTL *)texture
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
		
		if (image)
		{
			CGSize			canvasSize		= CGSizeZero;
			uint8_t 		*imageBuffer	= [LDrawPartLibrary copyPowerOfTwoPixelsForImage:image size:&canvasSize];
			CGColorSpaceRef colorSpace		= CGColorSpaceCreateDeviceRGB();
			
			NSData *imageData = [NSData dataWithBytesNoCopy:imageBuffer length:(canvasSize.width * canvasSize.height * 4) freeWhenDone:YES];
			CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)imageData);
			CGImageRef processedImage = CGImageCreate(
				canvasSize.width,
				canvasSize.height,
				8,
				32,
				canvasSize.width * 4,
				colorSpace,
				kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst,
				dataProvider,
				NULL,
				false,
				kCGRenderingIntentDefault
			);

			// Use MTKTextureLoader to generate a Metal texture
			// Note: We are using non-rectangular textures here
			MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:MetalGPU.device];
			NSDictionary *textureLoaderOptions = @{
				MTKTextureLoaderOptionSRGB: @NO,
				MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModePrivate),
				MTKTextureLoaderOptionTextureUsage: @(MTLTextureUsageShaderRead),
				MTKTextureLoaderOptionOrigin: MTKTextureLoaderOriginFlippedVertically
			};

			NSError *error = nil;
			metalTexture = [textureLoader newTextureWithCGImage:processedImage options:textureLoaderOptions error:&error];

			if (error) {
				NSLog(@"Error loading texture: %@", error.localizedDescription);
			} else {
				[self->optimizedTextures setObject:metalTexture forKey:name];
			}


			// free memory (imageBuffer belongs to imageData, which frees it)
			CGDataProviderRelease(dataProvider);
			CGImageRelease(processedImage);
			CFRelease(colorSpace);
		}
		else
		{
			NSLog(@"Error loading image texture: %@", texture.imageReferenceName);
		}
	}
	
	return metalTexture;
}


@end
