//==============================================================================
//
// File:		DownloadProgressPanel.m
//
// Purpose:		Shows a download's progress in a sheet, or in a panel of its
//				own without a window.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//==============================================================================
#import "DownloadProgressPanel.h"

#import "PreferencesForm.h"

static NSString * const FractionKeyPath		= @"fractionCompleted";
static NSString * const CancellableKeyPath	= @"cancellable";


@implementation DownloadProgressPanel
{
	NSPanel				*panel;
	NSWindow			*parent;
	NSProgress			*progress;
	NSProgressIndicator	*indicator;
	NSTextField			*label;
	NSButton			*cancelButton;
	NSString			*finishingMessage;
}

//========== initWithProgress:window:makeKey:message:finishingMessage: =========
//
// Purpose:		Shows a small panel with a bar, a line of text and Cancel.
//
//==============================================================================
- (instancetype) initWithProgress:(NSProgress *)aProgress
						   window:(NSWindow *)window
						  makeKey:(BOOL)makeKey
						  message:(NSString *)message
				 finishingMessage:(NSString *)aFinishingMessage
{
	self = [super init];
	if (self)
	{
		self->progress			= aProgress;
		self->parent			= window;
		self->finishingMessage	= [aFinishingMessage copy];
		self->panel				= [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 110)
															 styleMask:NSWindowStyleMaskTitled
															   backing:NSBackingStoreBuffered
																 defer:NO];
		self->label				= [NSTextField labelWithString:message];
		self->indicator			= [[NSProgressIndicator alloc] init];
		self->cancelButton		= [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil)
													 target:self
													 action:@selector(cancel:)];

		[self->indicator setIndeterminate:NO];
		[self->indicator setMinValue:0];
		[self->indicator setMaxValue:1];
		[self->cancelButton setKeyEquivalent:@"\e"];

		NSStackView *stack = [NSStackView stackViewWithViews:@[self->label, self->indicator, self->cancelButton]];
		[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[stack setAlignment:NSLayoutAttributeTrailing];
		[[self->indicator widthAnchor] constraintEqualToConstant:340].active = YES;
		[[self->label leadingAnchor] constraintEqualToAnchor:[self->indicator leadingAnchor]].active = YES;

		NSView *content = [PreferencesForm containerForView:stack margins:NSEdgeInsetsMake(20, 20, 20, 20)];
		[self->panel setContentView:content];
		[self->panel setContentSize:[content fittingSize]];

		[self->progress addObserver:self forKeyPath:FractionKeyPath options:0 context:NULL];
		[self->progress addObserver:self forKeyPath:CancellableKeyPath options:0 context:NULL];

		if(window != nil)
			[window beginSheet:self->panel completionHandler:nil];
		else if(makeKey)
		{
			[self->panel center];
			[self->panel makeKeyAndOrderFront:nil];
		}
		else
		{
			[self->panel setFloatingPanel:YES];
			[self->panel center];
			[self->panel orderFront:nil];
		}
	}
	return self;

}//end initWithProgress:window:makeKey:message:finishingMessage:


//========== observeValueForKeyPath:ofObject:change:context: ===================
//
// Purpose:		Moves the bar. The work after the downloads reports no
//				progress, so the bar spins. Cancel is off while the work
//				cannot be stopped.
//
//==============================================================================
- (void) observeValueForKeyPath:(NSString *)keyPath
					   ofObject:(id)object
						 change:(NSDictionary *)change
						context:(void *)context
{
	double	fraction	= [self->progress fractionCompleted];
	BOOL	cancellable	= [self->progress isCancellable];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self->cancelButton setEnabled:cancellable];
		[self->indicator setDoubleValue:fraction];
		if(fraction >= 1.0)
		{
			[self->indicator setIndeterminate:YES];
			[self->indicator startAnimation:nil];
			[self->label setStringValue:self->finishingMessage];
		}
	});
}


//========== cancel: ===========================================================
//==============================================================================
- (void) cancel:(id)sender
{
	[self->progress cancel];
}


//========== close =============================================================
//==============================================================================
- (void) close
{
	[self->progress removeObserver:self forKeyPath:FractionKeyPath];
	[self->progress removeObserver:self forKeyPath:CancellableKeyPath];

	if(self->parent != nil)
		[self->parent endSheet:self->panel];
	[self->panel orderOut:nil];
}

@end
