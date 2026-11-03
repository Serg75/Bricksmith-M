//==============================================================================
//
// File:		PartsLimitOptionsController.m
//
// Purpose:		A sheet with the options of the parts limit: how far back
//				Available Now looks, spares, and how parts and colors match.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "PartsLimitOptionsController.h"

#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawPartLimit.h>

#import "PartsLimitManager.h"
#import "PreferencesForm.h"

// The sheet on screen. It keeps itself until it closes.
static PartsLimitOptionsController *runningController = nil;


@interface PartsLimitOptionsController () <NSWindowDelegate>
@end


////////////////////////////////////////////////////////////////////////////////
//
// class PartsLimitOptionsPanel
//
////////////////////////////////////////////////////////////////////////////////
@interface PartsLimitOptionsPanel : NSPanel
@end


@implementation PartsLimitOptionsPanel

//========== keyDown: ==========================================================
//
// Purpose:		Sends Escape to the delegate as cancelOperation:. The panel has
//				no text field, so nothing else turns Escape into one.
//
//==============================================================================
- (void) keyDown:(NSEvent *)event
{
	id		delegate	= [self delegate];
	BOOL	isEscape	= [[event charactersIgnoringModifiers] isEqualToString:@"\e"];

	if(isEscape && [delegate respondsToSelector:@selector(cancelOperation:)])
		[delegate cancelOperation:self];
	else
		[super keyDown:event];

}//end keyDown:

@end


@implementation PartsLimitOptionsController
{
	NSWindow				*parent;
	NSPanel					*panel;

	NSPopUpButton			*yearsPopUp;
	NSSwitch				*pickABrickSwitch;
	NSSwitch				*sparesSwitch;
	NSSwitch				*moldsSwitch;
	NSSwitch				*printsSwitch;
	NSSwitch				*colorsSwitch;
	NSSwitch				*warnsSwitch;
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- showWithWindow: -----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (void) showWithWindow:(NSWindow *)window
{
	if(runningController != nil)
	{
		[runningController->panel makeKeyAndOrderFront:nil];
		return;
	}

	runningController = [[PartsLimitOptionsController alloc] init];
	runningController->parent = window;
	[runningController show];

}//end showWithWindow:


//========== show ==============================================================
//
// Purpose:		Builds the sheet from the app's limit and puts it up.
//
//==============================================================================
- (void) show
{
	NSString	*yearsNote		= NSLocalizedString(@"A part is available when a set of these years has it in "
													@"that color.", nil);
	NSString	*pickNote		= NSLocalizedString(@"Parts sold loose, as on Pick a Brick, though no set of "
													@"these years has them.", nil);
	NSString	*moldNote		= NSLocalizedString(@"Another mold or an alternate of a part counts as the "
													@"part.", nil);
	NSString	*printNote		= NSLocalizedString(@"A printed part counts as the plain part, and the plain "
													@"part as any of its prints.", nil);
	NSString	*warnNote		= NSLocalizedString(@"You can pick a color the part is not made in. The part "
													@"then gets a mark.", nil);
	NSButton	*doneButton		= [NSButton buttonWithTitle:NSLocalizedString(@"Done", nil)
													 target:self
													 action:@selector(done:)];
	NSStackView	*buttons		= [[NSStackView alloc] init];
	NSView		*yearsRow		= nil;
	NSView		*looseRow		= nil;
	NSView		*sparesRow		= nil;
	NSView		*moldRow		= nil;
	NSView		*printRow		= nil;
	NSView		*colorRow		= nil;
	NSView		*warnRow		= nil;
	NSView		*available		= nil;
	NSView		*inventory		= nil;
	NSView		*matching		= nil;

	yearsPopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"The last 3 years", nil),
													NSLocalizedString(@"The last 5 years", nil),
													NSLocalizedString(@"The last 10 years", nil),
													NSLocalizedString(@"Any year", nil)]
											 tags:@[@3, @5, @10, @0]
										   target:self
										   action:@selector(optionDidChange:)];
	pickABrickSwitch	= [PreferencesForm switchWithTarget:self action:@selector(optionDidChange:)];
	sparesSwitch		= [PreferencesForm switchWithTarget:self action:@selector(optionDidChange:)];
	moldsSwitch			= [PreferencesForm switchWithTarget:self action:@selector(optionDidChange:)];
	printsSwitch		= [PreferencesForm switchWithTarget:self action:@selector(optionDidChange:)];
	colorsSwitch		= [PreferencesForm switchWithTarget:self action:@selector(optionDidChange:)];
	warnsSwitch			= [PreferencesForm switchWithTarget:self action:@selector(optionDidChange:)];

	LDrawPartLimit *limit = [[[PartsLimitManager sharedManager] session] limit];

	// A value the menu lacks, from an older choice, shows as the next longer one.
	if([yearsPopUp selectItemWithTag:limit.yearsBack] == NO)
	{
		NSInteger years = limit.yearsBack;

		[yearsPopUp selectItemWithTag:(years <= 3) ? 3 : (years <= 5) ? 5 : (years <= 10) ? 10 : 0];
	}
	[pickABrickSwitch	setState:limit.countsPickABrickParts];
	[sparesSwitch		setState:limit.includesSpares];
	[moldsSwitch		setState:limit.matchesMoldVariants];
	[printsSwitch		setState:limit.matchesAnyPrint];
	[colorsSwitch		setState:limit.matchesAnyColor];
	[warnsSwitch		setState:limit.warnsOnly];

	yearsRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Sets from", nil)
										   note:yearsNote
										control:yearsPopUp
									  noteField:NULL];
	looseRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Count loose parts", nil)
										   note:pickNote
										control:pickABrickSwitch
									  noteField:NULL];
	sparesRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Count spare parts", nil)
										control:sparesSwitch];
	moldRow		= [PreferencesForm rowWithTitle:NSLocalizedString(@"Any mold", nil)
										   note:moldNote
										control:moldsSwitch
									  noteField:NULL];
	printRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Any print", nil)
										   note:printNote
										control:printsSwitch
									  noteField:NULL];
	colorRow	= [PreferencesForm rowWithTitle:NSLocalizedString(@"Ignore colors", nil)
										control:colorsSwitch];
	warnRow		= [PreferencesForm rowWithTitle:NSLocalizedString(@"Pick any color", nil)
										   note:warnNote
										control:warnsSwitch
									  noteField:NULL];

	available	= [PreferencesForm sectionWithTitle:NSLocalizedString(@"Available Now", nil)
											   rows:@[yearsRow, looseRow]
											 footer:nil];
	inventory	= [PreferencesForm sectionWithTitle:NSLocalizedString(@"Sets and Inventories", nil)
											   rows:@[sparesRow]
											 footer:nil];
	matching	= [PreferencesForm sectionWithTitle:NSLocalizedString(@"Matching", nil)
											   rows:@[moldRow, printRow, colorRow, warnRow]
											 footer:nil];

	// Return and Escape both close it, since every change is already made.
	[doneButton setKeyEquivalent:@"\r"];
	[buttons addView:doneButton inGravity:NSStackViewGravityTrailing];

	NSStackView *stack = [NSStackView stackViewWithViews:@[available, inventory, matching, buttons]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:18];
	[[[buttons widthAnchor] constraintEqualToAnchor:[stack widthAnchor]] setActive:YES];

	NSView *content = [PreferencesForm containerForView:stack margins:NSEdgeInsetsMake(20, 20, 20, 20)];

	panel = [[PartsLimitOptionsPanel alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
													  styleMask:NSWindowStyleMaskTitled
														backing:NSBackingStoreBuffered
														  defer:YES];
	[panel setTitle:NSLocalizedString(@"Limit Options", nil)];
	[panel setDelegate:self];
	[panel setContentView:content];
	[panel setContentSize:[content fittingSize]];

	if(parent != nil)
		[parent beginSheet:panel completionHandler:nil];
	else
	{
		[panel center];
		[panel makeKeyAndOrderFront:nil];
	}

}//end show


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== optionDidChange: ==================================================
//
// Purpose:		Puts the options into the app's limit. Its kind is read again,
//				since a menu may pick another limit while the sheet is up.
//
//==============================================================================
- (void) optionDidChange:(id)sender
{
	PartsLimitManager		*manager	= [PartsLimitManager sharedManager];
	LDrawMutablePartLimit	*limit		= [[[manager session] limit] mutableCopy];

	limit.yearsBack				= [[yearsPopUp selectedItem] tag];
	limit.countsPickABrickParts	= ([pickABrickSwitch state] == NSControlStateValueOn);
	limit.includesSpares		= ([sparesSwitch state] == NSControlStateValueOn);
	limit.matchesMoldVariants	= ([moldsSwitch state] == NSControlStateValueOn);
	limit.matchesAnyPrint		= ([printsSwitch state] == NSControlStateValueOn);
	limit.matchesAnyColor		= ([colorsSwitch state] == NSControlStateValueOn);
	limit.warnsOnly				= ([warnsSwitch state] == NSControlStateValueOn);

	[manager setLimit:[limit copy] window:parent];

}//end optionDidChange:


//========== done: =============================================================
//==============================================================================
- (void) done:(id)sender
{
	if(parent != nil)
		[parent endSheet:panel];
	[panel orderOut:nil];

	// The last strong reference may go here, so nothing of self is read after.
	runningController = nil;

}//end done:


//========== cancelOperation: ==================================================
//
// Purpose:		Escape closes the sheet, like Done.
//
//==============================================================================
- (void) cancelOperation:(id)sender
{
	[self done:sender];
}

@end
