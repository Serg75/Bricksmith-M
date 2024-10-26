//==============================================================================
//
//	LDrawViewGPU.m
//	Bricksmith
//
//	Purpose:	This is the intermediary between the operating system (events
//				and view hierarchy) and the LDrawRenderer (responsible for all
//				platform-independent drawing logic).
//
//				Certain interactions must be handed off to an LDrawDocument in
//				order for them to effect the object being drawn.
//
//				This class also provides for a number of mouse-based viewing
//				tools triggered by hotkeys. However, we don't track them here!
//				(We want *all* LDrawViews to respond to hotkeys at once.) So
//				there is a symbiotic relationship with ToolPalette to track
//				which tool mode we're in; we get notifications when it changes.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawViewGPU.h"

#import "FocusRingView.h"
#import "LDrawApplicationMTL.h"
#import "LDrawRendererMTL.h"
#import "MetalGPU.h"
#import "OverlayViewCategory.h"

//========== NSSizeToSize2 =====================================================
//
// Purpose:		Convert Cocoa sizes to our internal format.
//
//==============================================================================
static Size2 NSSizeToSize2(NSSize size)
{
	Size2 sizeOut = V2MakeSize(size.width, size.height);

	return sizeOut;
}


@implementation LDrawView (Metal)

- (void)makeCurrentContext
{
}

- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block
{
	block();
}

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== initWithFrame: ====================================================
//
// Purpose:		For programmatically-created GL views.
//
//==============================================================================
- (id) initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect device:MetalGPU.device];

	[self internalInit];
	
	return self;
	
}//end initWithFrame:


//========== internalInit ======================================================
//
// Purpose:		Set up the beautiful Metal view.
//
//==============================================================================
- (void) internalInit
{
	NSNotificationCenter    *notificationCenter = [NSNotificationCenter defaultCenter];

	self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
	self.framebufferOnly = YES;
	self.sampleCount = 1;

	self.paused = YES;
	self.enableSetNeedsDisplay = YES;

	selectionIsMarquee = NO;
	marqueeSelectionMode = SelectionReplace;

	//---------- Load UI -------------------------------------------------------

	// Yes, we have a nib file. Don't laugh. This view has accessories.
	[NSBundle loadNibNamed:@"LDrawViewAccessories" owner:self];

	self->focusRingView = [[FocusRingView alloc] initWithFrame:[self bounds]];
	[focusRingView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[focusRingView setFocusSource:self];

	[self addOverlayView:focusRingView];


	//---------- Initialize instance variables ---------------------------------

	[self setAcceptsFirstResponder:YES];

	renderer = [[LDrawRenderer alloc] initWithBounds:NSSizeToSize2([self bounds].size)];
	[renderer setDelegate:self withScroller:self];
	[renderer setLDrawColor:[[ColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor]];
	[renderer prepareMetal];
	self.delegate = renderer;

	[self takeBackgroundColorFromUserDefaults];
	[self setViewOrientation:ViewOrientation3D];


	//---------- Register notifications ----------------------------------------

	[notificationCenter addObserver:self
						   selector:@selector(mouseToolDidChange:)
							   name:LDrawMouseToolDidChangeNotification
							 object:nil ];

	[notificationCenter addObserver:self
						   selector:@selector(backgroundColorDidChange:)
							   name:LDrawViewBackgroundColorDidChangeNotification
							 object:nil ];

	NSTrackingAreaOptions	options 		= (		NSTrackingMouseEnteredAndExited
											   |	NSTrackingMouseMoved
											   |	NSTrackingActiveInActiveApp
											   |	NSTrackingInVisibleRect
											  );
	NSTrackingArea			*trackingArea	= [[NSTrackingArea alloc] initWithRect:NSZeroRect
																  options:options
																	owner:self
																 userInfo:nil];
	[self addTrackingArea:trackingArea];

}//end internalInit


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== setBackgroundColor: ===============================================
///
/// @abstract	Updates the color used behind the model
///
//==============================================================================
- (void) setBackgroundColor:(NSColor *)newColor
{
//	NSColor			*rgbColor		= nil;
//
//	if(newColor == nil)
//		newColor = [NSColor windowBackgroundColor];
//
//	// the new color may not be in the RGB colorspace, so we need to convert.
//	rgbColor = [newColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
//
//	CGLLockContext([[self openGLContext] CGLContextObj]);
//	{
//		//This method can get called from -prepareOpenGL, which is itself called
//		// from -makeCurrentContext. That's a recipe for infinite recursion. So,
//		// we only makeCurrentContext if we *need* to.
//		if([NSOpenGLContext currentContext] != [self openGLContext])
//			[[self openGLContext] makeCurrentContext];
//
//		[self->renderer setBackgroundColorRed:[rgbColor redComponent]
//										green:[rgbColor greenComponent]
//										 blue:[rgbColor blueComponent] ];
//	}
//	CGLUnlockContext([[self openGLContext] CGLContextObj]);

	[self setNeedsDisplay:YES];
	
}//end setBackgroundColor:


//========== setViewingAngle: ==================================================
//
// Purpose:		Sets the modelview rotation, in degrees. The angle is applied in
//				x-y-z order.
//
// Notes:		These numbers do *not* include the fact that LDraw has an
//				upside-down coordinate system. So if this method returns
//				(0,0,0), that means "Front, looking right-side up."
//
//==============================================================================
- (void) setViewingAngle:(Tuple3)newAngle
{
//	CGLLockContext([[self openGLContext] CGLContextObj]);
//	{
//		//This method can get called from -prepareOpenGL, which is itself called
//		// from -makeCurrentContext. That's a recipe for infinite recursion. So,
//		// we only makeCurrentContext if we *need* to.
//		if([NSOpenGLContext currentContext] != [self openGLContext])
//			[[self openGLContext] makeCurrentContext];
//
//		[self->renderer setViewingAngle:newAngle];
//
//		[self setNeedsDisplay:YES];
//	}
//	CGLUnlockContext([[self openGLContext] CGLContextObj]);
	
}//end setViewingAngle:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== saveImage =========================================================
//
// Purpose:		Dumps the current glReadBuffer to the given file. Debugging aid.
//
//==============================================================================
- (void) saveImageToPath:(NSString *)path
{
//	[[self openGLContext] makeCurrentContext];
//	
//	GLint   viewport [4]  = {0};
//	NSSize  viewportSize    = NSZeroSize;
//	size_t  byteWidth       = 0;
//	uint8_t *byteBuffer     = NULL;
//	
//	glGetIntegerv(GL_VIEWPORT, viewport);
//	viewportSize    = NSMakeSize(viewport[2], viewport[3]);
//	
//	byteWidth   = viewportSize.width * 4;	// Assume 4 bytes/pixel for now
//	byteWidth   = (byteWidth + 3) & ~3;    // Align to 4 bytes
//	
//	byteBuffer  = malloc(byteWidth * viewportSize.height);
//	
//	glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
//	{
//		glPixelStorei(GL_PACK_ALIGNMENT, 4); // Force 4-byte alignment
//		glPixelStorei(GL_PACK_ROW_LENGTH, 0);
//		glPixelStorei(GL_PACK_SKIP_ROWS, 0);
//		glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
//		
//		glReadPixels(0, 0, viewportSize.width, viewportSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, byteBuffer);
//		NSLog(@"read error = %d", glGetError());
//	}
//	glPopClientAttrib();
//	
//	
//	//---------- Save to image -------------------------------------------------
//	
//	CGColorSpaceRef         cSpace  = NULL;
//	CGContextRef            bitmap  = NULL;
//	CGImageRef              image   = NULL;
//	CGImageDestinationRef   dest    = NULL;
//	
//	
//	cSpace = CGColorSpaceCreateWithName (kCGColorSpaceGenericRGB);
//	bitmap = CGBitmapContextCreate(byteBuffer, viewportSize.width, viewportSize.height, 8, byteWidth,
//												cSpace,
//												kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);
//	
//	// Make an image out of our bitmap; does a cheap vm_copy of the bitmap
//	image = CGBitmapContextCreateImage(bitmap);
//	NSAssert( image != NULL, @"CGBitmapContextCreate failure");
//	
//	// Save the image to the file
//	dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.tiff"), 1, nil);
//	NSAssert( dest != 0, @"CGImageDestinationCreateWithURL failed");
//	
//	// Set the image in the image destination to be `image' with
//	// optional properties specified in saved properties dict.
//	CGImageDestinationAddImage(dest, image, nil);
//	
//	bool success = CGImageDestinationFinalize(dest);
//	NSAssert( success != 0, @"Image could not be written successfully");
//	
//	CFRelease(cSpace);
//	CFRelease(dest);
//	CGImageRelease(image);
//	CFRelease(bitmap);
//	free(byteBuffer);
	
}//end saveImageToPath:


@end
