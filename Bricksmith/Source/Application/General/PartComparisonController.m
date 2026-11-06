//==============================================================================
//
// File:		PartComparisonController.m
//
// Purpose:		A window that shows a part from the overrides folder next to
//				the library's, with the two views turning together.
//
//==============================================================================
#import "PartComparisonController.h"

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawPartComparison.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawFeatures/LDrawPartOverridePresentation.h>

#import "LDrawApplication.h"
#import "LDrawView.h"
#import "LDrawViewerContainer.h"


@implementation PartComparisonController
{
	NSStackView				*overrideColumn;
	NSStackView				*libraryColumn;
	LDrawViewerContainer	*overrideViewer;
	LDrawViewerContainer	*libraryViewer;
	NSTextField				*overrideNote;
	NSTextField				*libraryNote;
	NSTextField				*changedNote;

	Box3					 sharedBounds;	// both sides together, which both cameras stand back from
	BOOL					 linking;		// set while one camera is copied to the other
	LDrawView				*pendingSource;	// the view whose camera is waiting to be copied

	NSString				*shownPartName;	// the part shown, built again when library parts change
	LDrawColor				*shownColor;

	// Set when library parts changed while the window was minimized.
	BOOL					 reloadWhenRestored;
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- sharedController ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (PartComparisonController *) sharedController
{
	static PartComparisonController	*sharedController	= nil;
	static dispatch_once_t			 onceToken;

	dispatch_once(&onceToken, ^{
		sharedController = [[PartComparisonController alloc] init];
	});
	return sharedController;

}//end sharedController


//========== init ==============================================================
//
// Purpose:		Builds the window: the two sides, each under its title, and the
//				parts that differ along the bottom.
//
//==============================================================================
- (instancetype) init
{
	NSWindowStyleMask	 style	= (	NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
								  | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable);
	NSWindow			*window	= [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 540)
															  styleMask:style
																backing:NSBackingStoreBuffered
																  defer:YES];

	self = [super initWithWindow:window];
	if(self)
	{
		[window setReleasedWhenClosed:NO];
		[window setMinSize:NSMakeSize(480, 300)];
		[window center];
		[window setFrameAutosaveName:@"PartComparisonWindow"];

		self->sharedBounds = InvalidBox;
		[self buildContent];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(partLibraryReloaded:)
													 name:LDrawPartLibraryReloaded
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(windowWillClose:)
													 name:NSWindowWillCloseNotification
												   object:window];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(windowDidDeminiaturize:)
													 name:NSWindowDidDeminiaturizeNotification
												   object:window];
	}
	return self;

}//end init


#pragma mark -
#pragma mark CONTENT
#pragma mark -

//========== buildContent ======================================================
//==============================================================================
- (void) buildContent
{
	NSView		*content		= [[self window] contentView];
	NSStackView	*sides			= nil;
	NSStackView	*stack			= nil;

	overrideNote	= [self noteField];
	libraryNote		= [self noteField];
	changedNote		= [self noteField];
	[changedNote setLineBreakMode:NSLineBreakByWordWrapping];
	[changedNote setPreferredMaxLayoutWidth:900];

	overrideColumn	= [self columnWithViews:@[[self titleField:NSLocalizedString(@"Overrides Folder", nil)],
											  overrideNote]];
	libraryColumn	= [self columnWithViews:@[[self titleField:NSLocalizedString(@"LDraw Library", nil)],
											  libraryNote]];

	sides = [NSStackView stackViewWithViews:@[overrideColumn, libraryColumn]];
	[sides setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[sides setDistribution:NSStackViewDistributionFillEqually];
	[sides setAlignment:NSLayoutAttributeTop];
	[sides setSpacing:12];

	stack = [NSStackView stackViewWithViews:@[sides, changedNote]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:8];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:stack];

	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:12],
		[[stack trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-12],
		[[stack topAnchor] constraintEqualToAnchor:[content topAnchor] constant:12],
		[[stack bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-12],
		[[sides widthAnchor] constraintEqualToAnchor:[stack widthAnchor]],
	]];

}//end buildContent


//========== titleField: =======================================================
//==============================================================================
- (NSTextField *) titleField:(NSString *)title
{
	NSTextField *label = [NSTextField labelWithString:title];

	[label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	return label;

}//end titleField:


//========== newViewerInColumn:replacing: ======================================
//
// Purpose:		Puts a new 3D view at the bottom of the column, in place of the
//				old one. It can be turned and zoomed, but not edited.
//
// Notes:		Each part gets new views. A Metal view that is given a second
//				file can stop being redrawn by AppKit, and keep showing the
//				first part.
//
//==============================================================================
- (LDrawViewerContainer *) newViewerInColumn:(NSStackView *)column replacing:(LDrawViewerContainer *)oldViewer
{
	LDrawViewerContainer *viewer = [[LDrawViewerContainer alloc] initWithFrame:NSMakeRect(0, 0, 440, 440)];

	if(oldViewer != nil)
	{
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:LDrawViewCameraDidChangeNotification
													  object:[oldViewer glView]];
		[column removeArrangedSubview:oldViewer];
		[oldViewer removeFromSuperview];
	}

	[viewer setShowsScrollbars:NO];
	[viewer setTranslatesAutoresizingMaskIntoConstraints:NO];
	[viewer setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
					   forOrientation:NSLayoutConstraintOrientationVertical];
	[[viewer glView] setLocksParts:YES];
	[[viewer glView] setFocusRingVisible:NO];

	[column addArrangedSubview:viewer];
	[[[viewer widthAnchor] constraintEqualToAnchor:[column widthAnchor]] setActive:YES];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(cameraDidChange:)
												 name:LDrawViewCameraDidChangeNotification
											   object:[viewer glView]];
	return viewer;

}//end newViewerInColumn:replacing:


//========== noteField =========================================================
//==============================================================================
- (NSTextField *) noteField
{
	NSTextField *note = [NSTextField labelWithString:@""];

	[note setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[note setTextColor:[NSColor secondaryLabelColor]];
	[note setLineBreakMode:NSLineBreakByTruncatingMiddle];
	[note setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
								   forOrientation:NSLayoutConstraintOrientationHorizontal];
	return note;

}//end noteField


//========== columnWithViews: ==================================================
//
// Purpose:		A title and a note, one under the other. The viewer goes under
//				them and takes the height that is left.
//
//==============================================================================
- (NSStackView *) columnWithViews:(NSArray<NSView *> *)views
{
	NSStackView *column = [NSStackView stackViewWithViews:views];

	[column setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[column setAlignment:NSLayoutAttributeLeading];
	[column setSpacing:4];
	[column setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
					   forOrientation:NSLayoutConstraintOrientationVertical];

	return column;

}//end columnWithViews:


#pragma mark -
#pragma mark SHOWING A PART
#pragma mark -

//========== showPartNamed:color: ==============================================
//
// Purpose:		Puts each side in its view and brings the window forward.
//
//==============================================================================
- (BOOL) showPartNamed:(NSString *)partName color:(LDrawColor *)color
{
	if([self loadPartNamed:partName color:color keepingCamera:NO] == NO)
		return NO;

	[self showWindow:nil];
	return YES;

}//end showPartNamed:color:


//========== loadPartNamed:color:keepingCamera: ================================
//
// Purpose:		Puts each side in its view, both framed the same way: fitted, or
//				as the views had it. NO, with the views unchanged, when the two
//				sides are the same.
//
//==============================================================================
- (BOOL) loadPartNamed:(NSString *)partName color:(LDrawColor *)color keepingCamera:(BOOL)keepCamera
{
	LDrawPartComparison	*comparison		= [[LDrawPartComparison alloc] initWithPartName:partName
																				  paths:[LDrawPaths sharedPaths]];
	LDrawView			*oldView		= keepCamera ? [overrideViewer glView] : nil;
	LDrawFile			*overrideFile	= nil;
	LDrawFile			*libraryFile	= nil;
	NSString			*changedLine	= nil;

	if([[comparison changedPartNames] count] == 0)
		return NO;

	self->shownPartName	= [partName copy];
	self->shownColor	= color;

	overrideFile	= [comparison fileUsingOverrides:YES];
	libraryFile		= [comparison fileUsingOverrides:NO];

	[[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Compare %@", nil),
							 [comparison partName]]];
	[overrideNote setStringValue:[LDrawPartOverridePresentation noteForFileAtPath:[comparison overridePath]]];
	[overrideNote setToolTip:[comparison overridePath]];
	[libraryNote setStringValue:[LDrawPartOverridePresentation noteForFileAtPath:[comparison libraryPath]]];
	[libraryNote setToolTip:[comparison libraryPath]];
	changedLine = [LDrawPartOverridePresentation lineForChangedPartNames:[comparison changedPartNames]];
	[changedNote setStringValue:changedLine];

	self->sharedBounds = V3UnionBox([overrideFile boundingBox3], [libraryFile boundingBox3]);

	overrideViewer	= [self newViewerInColumn:overrideColumn replacing:overrideViewer];
	libraryViewer	= [self newViewerInColumn:libraryColumn replacing:libraryViewer];

	[LDrawApplication makeCurrentSharedContext];
	[self showFile:overrideFile color:color inViewer:overrideViewer];
	[self showFile:libraryFile color:color inViewer:libraryViewer];

	// Frame one side, then the other the same way. Waits for the window's
	// layout, since the fit needs the view's size.
	dispatch_async(dispatch_get_main_queue(), ^{
		if(oldView != nil)
			[self copyCameraFrom:oldView to:[self->overrideViewer glView]];
		else
			[[self->overrideViewer glView] zoomToFit:nil];
		[self copyCameraFrom:[self->overrideViewer glView] to:[self->libraryViewer glView]];
	});

	return YES;

}//end loadPartNamed:color:keepingCamera:


//========== partLibraryReloaded: ==============================================
//
// Purpose:		Library parts now come from other files, or at another
//				resolution. Builds the shown part again. A minimized window
//				waits until it is restored, since its views are not laid out.
//
//==============================================================================
- (void) partLibraryReloaded:(NSNotification *)notification
{
	if(self->shownPartName == nil)
		return;

	if([[self window] isMiniaturized])
		self->reloadWhenRestored = YES;
	else
		[self reloadShownPart];

}//end partLibraryReloaded:


//========== windowDidDeminiaturize: ===========================================
//
// Purpose:		Builds the part again when library parts changed meanwhile.
//
//==============================================================================
- (void) windowDidDeminiaturize:(NSNotification *)notification
{
	if(self->reloadWhenRestored)
	{
		self->reloadWhenRestored = NO;
		[self reloadShownPart];
	}

}//end windowDidDeminiaturize:


//========== windowWillClose: ==================================================
//
// Purpose:		A closed window shows no part, so it is not built again.
//
//==============================================================================
- (void) windowWillClose:(NSNotification *)notification
{
	self->shownPartName			= nil;
	self->shownColor			= nil;
	self->reloadWhenRestored	= NO;

}//end windowWillClose:


//========== reloadShownPart ===================================================
//
// Purpose:		Builds the shown part again with the views' camera, or closes
//				the window when its two sides are now the same.
//
//==============================================================================
- (void) reloadShownPart
{
	if([self loadPartNamed:self->shownPartName color:self->shownColor keepingCamera:YES] == NO)
		[self close];

}//end reloadShownPart


//========== showFile:color:inViewer: ==========================================
//==============================================================================
- (void) showFile:(LDrawFile *)file color:(LDrawColor *)color inViewer:(LDrawViewerContainer *)viewer
{
	LDrawView *view = [viewer glView];

	[view setLDrawDirective:file];
	if(color != nil)
		[view setLDrawColor:color];
	[view setCameraBounds:self->sharedBounds];
	[view setViewOrientation:LDrawViewOrientation3D];

}//end showFile:color:inViewer:


#pragma mark -
#pragma mark LINKED CAMERAS
#pragma mark -

//========== cameraDidChange: ==================================================
//
// Purpose:		One view turned, zoomed or scrolled; the other follows.
//
// Notes:		The copy waits until the camera update that posted this is done.
//
//==============================================================================
- (void) cameraDidChange:(NSNotification *)notification
{
	BOOL wasPending = (self->pendingSource != nil);

	if(self->linking)
		return;

	self->pendingSource = [notification object];
	if(wasPending)
		return;

	dispatch_async(dispatch_get_main_queue(), ^{
		LDrawView *source = self->pendingSource;
		LDrawView *target = (source == [self->overrideViewer glView]) ? [self->libraryViewer glView]
																	  : [self->overrideViewer glView];

		self->pendingSource = nil;

		// The view may have been replaced by one for another part meanwhile.
		if(source == [self->overrideViewer glView] || source == [self->libraryViewer glView])
			[self copyCameraFrom:source to:target];
	});

}//end cameraDidChange:


//========== copyCameraFrom:to: ================================================
//
// Purpose:		Gives the target the source's angle, zoom and center. Both
//				stand back from the same box, so the parts line up.
//
//==============================================================================
- (void) copyCameraFrom:(LDrawView *)source to:(LDrawView *)target
{
	NSRect	bounds	= [source bounds];
	Point3	depth	= V3CenterOfBox(self->sharedBounds);
	Point3	center	= [source modelPointForViewPoint:NSMakePoint(NSMidX(bounds), NSMidY(bounds))
								 depthReferencePoint:depth];

	self->linking = YES;

	if([target projectionMode] != [source projectionMode])
		[target setProjectionMode:[source projectionMode]];
	[target setViewingAngle:[source viewingAngle]];
	[target setZoomPercentage:[source zoomPercentage]];
	[target scrollCenterToModelPoint:center];
	[target setNeedsDisplay:YES];

	self->linking = NO;

}//end copyCameraFrom:to:

@end
