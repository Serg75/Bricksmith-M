//==============================================================================
//
//	LDrawViewMTL.m
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

#import "LDrawViewMTL.h"

#import "FocusRingView.h"
#import "LDrawApplicationMTL.h"
#import "LDrawRendererMTL.h"
#import "MetalGPU.h"
#import "OverlayViewCategory.h"


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
	self.sampleCount = MSAASampleCount;

	self.paused = YES;
	self.enableSetNeedsDisplay = YES;

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

	renderer = [[LDrawRenderer alloc] initWithBounds:[self bounds].size];
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
	NSColor			*rgbColor		= nil;

	if(newColor == nil)
		newColor = [NSColor windowBackgroundColor];

	// the new color may not be in the RGB colorspace, so we need to convert.
	rgbColor = [newColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];

	[self->renderer setBackgroundColorRed:[rgbColor redComponent]
									green:[rgbColor greenComponent]
									 blue:[rgbColor blueComponent] ];
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
	[self->renderer setViewingAngle:newAngle];
	[self setNeedsDisplay:YES];
	
}//end setViewingAngle:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== saveImage =========================================================
//
// Purpose:		Dumps the current drawable to the given file. Debugging aid.
//
//==============================================================================
- (void) saveImageToPath:(NSString *)path
{
	// Not using, not implemented
    
}//end saveImageToPath:


@end
