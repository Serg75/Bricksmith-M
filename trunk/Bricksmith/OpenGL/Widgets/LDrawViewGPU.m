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
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import "LDrawViewGPU.h"

#import "FocusRingView.h"
#import "LDrawApplicationGPU.h"
#import "LDrawRendererGPU.h"
#import "OverlayViewCategory.h"

#include OPEN_GL_HEADER


@implementation LDrawView (OpenGL)

- (void)makeCurrentContext
{
	[[self openGLContext] makeCurrentContext];
}

- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block
{
	CGLLockContext([[self openGLContext] CGLContextObj]);
	{
		block();
	}
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== initWithFrame: ====================================================
//
// Purpose:		For programmatically-created GL views.
//
//==============================================================================
- (id) initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat *)format
{
	self = [super initWithFrame:frameRect pixelFormat:format];
	
	[self internalInit];
	
	return self;
	
}//end initWithFrame:


//========== internalInit ======================================================
//
// Purpose:		Set up the beatiful OpenGL view.
//
//==============================================================================
- (void) internalInit
{
	NSOpenGLContext         *context            = nil;
	NSOpenGLPixelFormat     *pixelFormat        = [LDrawApplication openGLPixelFormat];
	NSNotificationCenter    *notificationCenter = [NSNotificationCenter defaultCenter];

	selectionIsMarquee = NO;
	marqueeSelectionMode = SelectionReplace;

	//---------- Load UI -------------------------------------------------------

	// Yes, we have a nib file. Don't laugh. This view has accessories.
	NSArray *nibObjects = nil;
	if ([[NSBundle mainBundle] loadNibNamed:@"LDrawViewAccessories" owner:self topLevelObjects:&nibObjects]) {
		topLevelObjects = nibObjects;
	} else {
		NSLog(@"Couldn't load LDrawViewAccessories.nib");
	}

	self->focusRingView = [[FocusRingView alloc] initWithFrame:[self bounds]];
	[focusRingView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[focusRingView setFocusSource:self];

	[self addOverlayView:focusRingView];


	//---------- Initialize instance variables ---------------------------------

	[self setAcceptsFirstResponder:YES];

	// Set up our OpenGL context. We need to base it on a shared context so that
	// display-list names can be shared globally throughout the application.
	context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat
										 shareContext:[LDrawApplication sharedOpenGLContext]];
	[self setOpenGLContext:context];
//	[context setView:self]; //documentation says to do this, but it generates an error. Weird.
	[[self openGLContext] makeCurrentContext];

	[self setPixelFormat:pixelFormat];

	// Multithreading engine
	// It turned out to be as miserable a failure as my home-spun attempts.
	// Three times longer and display corruption to boot. Bricksmith is
	// apparently allergic to multithreading of any kind, and darn if I know
	// why.
//	CGLEnable(CGLGetCurrentContext(), kCGLCEMPEngine);

	// Prevent "tearing"
	GLint   swapInterval    = 1;
	[[self openGLContext] setValues: &swapInterval
					   forParameter: NSOpenGLCPSwapInterval ];

	// GL surface should be under window to allow Cocoa overtop.
	// Huge FPS hit--over 40%! Don't do it!
//	GLint   surfaceOrder    = -1;
//	[[self openGLContext] setValues: &surfaceOrder
//					   forParameter: NSOpenGLCPSurfaceOrder ];

	renderer = [[LDrawRenderer alloc] initWithBounds:[self bounds].size];
	[renderer setDelegate:self withScroller:self];
	[renderer setLDrawColor:[[ColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor]];
	[renderer prepareOpenGL];

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


//========== prepareOpenGL =====================================================
//
// Purpose:		The context is all set up; this is where we prepare our OpenGL
//				state.
//
//==============================================================================
- (void) prepareOpenGL
{
	[super prepareOpenGL];
	
	[self takeBackgroundColorFromUserDefaults]; //glClearColor()
	
}//end prepareOpenGL


#pragma mark -
#pragma mark DRAWING
#pragma mark -

//========== drawRect: =========================================================
//
// Purpose:        Draw the file into the view.
//
//==============================================================================
- (void) drawRect:(NSRect)rect
{
    [self draw];

}//end drawRect:


//========== draw ==============================================================
//
// Purpose:        Draw the LDraw content of the view.
//
//==============================================================================
- (void) draw
{
	[self lockContextAndExecute:^
	{
		[self makeCurrentContext];
		[self->renderer draw];
	}];
	
}//end draw


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
	NSColor			*rgbColor		= nil;
	
	if(newColor == nil)
		newColor = [NSColor windowBackgroundColor];
	
	// the new color may not be in the RGB colorspace, so we need to convert.
	rgbColor = [newColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];

	CGLLockContext([[self openGLContext] CGLContextObj]);
	{
		//This method can get called from -prepareOpenGL, which is itself called
		// from -makeCurrentContext. That's a recipe for infinite recursion. So,
		// we only makeCurrentContext if we *need* to.
		if([NSOpenGLContext currentContext] != [self openGLContext])
			[[self openGLContext] makeCurrentContext];
			
		[self->renderer setBackgroundColorRed:[rgbColor redComponent]
										green:[rgbColor greenComponent]
										 blue:[rgbColor blueComponent] ];
	}
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
	
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
	CGLLockContext([[self openGLContext] CGLContextObj]);
	{
		//This method can get called from -prepareOpenGL, which is itself called
		// from -makeCurrentContext. That's a recipe for infinite recursion. So,
		// we only makeCurrentContext if we *need* to.
		if([NSOpenGLContext currentContext] != [self openGLContext])
			[[self openGLContext] makeCurrentContext];
		
		[self->renderer setViewingAngle:newAngle];
		
		[self setNeedsDisplay:YES];
	}
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
	
}//end setViewingAngle:


#pragma mark -
#pragma mark RENDERER DELEGATE
#pragma mark -


//========== LDrawRendererNeedsFlush: ========================================
//
// Purpose:		Drawing is complete; do a flush.
//
// Notes:		This is implemented as a callback because flushing might be a
//				time-sensitive operation, and we want to do the framerate
//				calculation (in the renderer) after drawing is done. Otherwise,
//				we'd just do it in -[LDrawOpenGLView draw].
//
//==============================================================================
- (void) LDrawRendererNeedsFlush:(LDrawRenderer*)renderer
{
	[[self openGLContext] flushBuffer];
}


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -


//========== renewGState =======================================================
//
// Purpose:		NSOpenGLViews' content is drawn directly by a hardware surface
//				that, when being moved, is moved before the surrounding regular
//				window content gets drawn and flushed. This causes an annoying
//				flicker, especially with NSSplitViews. Overriding this method
//				gives us a chance to compensate for this problem.
//
//==============================================================================
- (void) renewGState
{
	NSWindow *window = [self window];
	
	// Disabling screen updates should allow the redrawing of the surrounding
	// window to catch up with the new position of the OpenGL hardware surface.
	//
	// Note: In Apple's "GLChildWindow" sample code, Apple put this in
	//		 -splitViewWillResizeSubviews:. But that doesn't actually solve the
	//		 problem. Putting it here *does*.
	//
	[window disableScreenUpdatesUntilFlush];
	
	[super renewGState];
	
}//end renewGState


//========== reshape ===========================================================
//
// Purpose:		Something changed in the viewing department; we need to adjust
//				our projection and viewing area.
//
//==============================================================================
- (void) reshape
{
	[super reshape];

	[self lockContextAndExecute:^
	{
		[self makeCurrentContext];

		NSSize maxVisibleSize = [self visibleRect].size;

		if(maxVisibleSize.width > 0 && maxVisibleSize.height > 0)
		{
			glViewport(0,0, maxVisibleSize.width,maxVisibleSize.height);

			[self->renderer setGraphicsSurfaceSize:V2MakeSize(maxVisibleSize.width, maxVisibleSize.height)];
		}
	}];

}//end reshape


//========== update ============================================================
//
// Purpose:		This method is called by the AppKit whenever our drawable area
//				changes somehow. Ordinarily, we wouldn't be concerned about what
//				happens here. However, calling -update is highly thread-unsafe,
//				so we guard the context with a mutex here so as to avoid truly
//				hideous system crashes.
//
//==============================================================================
- (void) update
{
	[self lockContextAndExecute:^
	{
		[super update];
	}];

}//end update


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
	[[self openGLContext] makeCurrentContext];
	
	GLint   viewport [4]  = {0};
	NSSize  viewportSize    = NSZeroSize;
	size_t  byteWidth       = 0;
	uint8_t *byteBuffer     = NULL;
	
	glGetIntegerv(GL_VIEWPORT, viewport);
	viewportSize    = NSMakeSize(viewport[2], viewport[3]);
	
	byteWidth   = viewportSize.width * 4;	// Assume 4 bytes/pixel for now
	byteWidth   = (byteWidth + 3) & ~3;    // Align to 4 bytes
	
	byteBuffer  = malloc(byteWidth * viewportSize.height);
	
	glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
	{
		glPixelStorei(GL_PACK_ALIGNMENT, 4); // Force 4-byte alignment
		glPixelStorei(GL_PACK_ROW_LENGTH, 0);
		glPixelStorei(GL_PACK_SKIP_ROWS, 0);
		glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
		
		glReadPixels(0, 0, viewportSize.width, viewportSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, byteBuffer);
		NSLog(@"read error = %d", glGetError());
	}
	glPopClientAttrib();
	
	
	//---------- Save to image -------------------------------------------------
	
	CGColorSpaceRef         cSpace  = NULL;
	CGContextRef            bitmap  = NULL;
	CGImageRef              image   = NULL;
	CGImageDestinationRef   dest    = NULL;
	
	
	cSpace = CGColorSpaceCreateWithName (kCGColorSpaceGenericRGB);
	bitmap = CGBitmapContextCreate(byteBuffer, viewportSize.width, viewportSize.height, 8, byteWidth,
												cSpace,
												kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);
	
	// Make an image out of our bitmap; does a cheap vm_copy of the bitmap
	image = CGBitmapContextCreateImage(bitmap);
	NSAssert( image != NULL, @"CGBitmapContextCreate failure");
	
	// Save the image to the file
	dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.tiff"), 1, nil);
	NSAssert( dest != 0, @"CGImageDestinationCreateWithURL failed");
	
	// Set the image in the image destination to be `image' with
	// optional properties specified in saved properties dict.
	CGImageDestinationAddImage(dest, image, nil);
	
	bool success = CGImageDestinationFinalize(dest);
	NSAssert( success != 0, @"Image could not be written successfully");
	
	CFRelease(cSpace);
	CFRelease(dest);
	CGImageRelease(image);
	CFRelease(bitmap);
	free(byteBuffer);
	
}//end saveImageToPath:


@end
