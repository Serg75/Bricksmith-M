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

#import <LDrawInventory/LDrawPartLimit.h>

#import "PreferencesForm.h"

// The sheet on screen. It keeps itself until it closes.
static PartsLimitOptionsController *runningController = nil;


@implementation PartsLimitOptionsController
{
	LDrawMutablePartLimit	*limit;
	NSWindow				*parent;
	NSPanel					*panel;
	void					(^completion)(LDrawPartLimit *limit);

	NSPopUpButton			*yearsPopUp;
	NSSwitch				*pickABrickSwitch;
	NSSwitch				*sparesSwitch;
	NSSwitch				*moldsSwitch;
	NSSwitch				*printsSwitch;
	NSSwitch				*colorsSwitch;
	NSSwitch				*warnsSwitch;
}


//---------- runWithLimit:window:completion: -------------------------[static]--
//------------------------------------------------------------------------------
+ (void) runWithLimit:(LDrawPartLimit *)limit
			   window:(NSWindow *)window
		   completion:(void (^)(LDrawPartLimit *limit))completion
{
	if(runningController != nil)
	{
		[runningController->panel makeKeyAndOrderFront:nil];
		return;
	}

	runningController = [[PartsLimitOptionsController alloc] init];
	runningController->limit		= [limit mutableCopy];
	runningController->parent		= window;
	runningController->completion	= completion;
	[runningController show];

}//end runWithLimit:window:completion:


//========== show ==============================================================
//
// Purpose:		Builds the sheet from the limit and puts it up.
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
	NSString	*warnNote		= NSLocalizedString(@"A color the part does not come in can still be picked. "
													@"The part is marked.", nil);
	NSButton	*okButton		= [NSButton buttonWithTitle:NSLocalizedString(@"OK", nil)
												 target:self
												 action:@selector(ok:)];
	NSButton	*cancelButton	= [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil)
												 target:self
												 action:@selector(cancel:)];
	NSStackView	*buttons		= [NSStackView stackViewWithViews:@[cancelButton, okButton]];
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

	yearsPopUp = [PreferencesForm popUpWithTitles:@[NSLocalizedString(@"This year", nil),
													NSLocalizedString(@"This year and last", nil),
													NSLocalizedString(@"The last 3 years", nil),
													NSLocalizedString(@"The last 5 years", nil),
													NSLocalizedString(@"Any year", nil)]
											 tags:@[@1, @2, @3, @5, @0]
										   target:nil
										   action:NULL];
	pickABrickSwitch	= [PreferencesForm switchWithTarget:nil action:NULL];
	sparesSwitch		= [PreferencesForm switchWithTarget:nil action:NULL];
	moldsSwitch			= [PreferencesForm switchWithTarget:nil action:NULL];
	printsSwitch		= [PreferencesForm switchWithTarget:nil action:NULL];
	colorsSwitch		= [PreferencesForm switchWithTarget:nil action:NULL];
	warnsSwitch			= [PreferencesForm switchWithTarget:nil action:NULL];

	if([yearsPopUp selectItemWithTag:limit.yearsBack] == NO)
		[yearsPopUp selectItemWithTag:2];
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
	warnRow		= [PreferencesForm rowWithTitle:NSLocalizedString(@"Allow any color", nil)
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

	[okButton setKeyEquivalent:@"\r"];
	[cancelButton setKeyEquivalent:@"\e"];

	NSStackView *stack = [NSStackView stackViewWithViews:@[available, inventory, matching, buttons]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeTrailing];
	[stack setSpacing:18];
	[stack setEdgeInsets:NSEdgeInsetsMake(20, 20, 20, 20)];

	panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
									   styleMask:NSWindowStyleMaskTitled
										 backing:NSBackingStoreBuffered
										   defer:YES];
	[panel setTitle:NSLocalizedString(@"Limit Options", nil)];
	[panel setContentView:stack];
	[panel setContentSize:[stack fittingSize]];

	if(parent != nil)
		[parent beginSheet:panel completionHandler:nil];
	else
	{
		[panel center];
		[panel makeKeyAndOrderFront:nil];
	}

}//end show


//========== ok: ===============================================================
//==============================================================================
- (void) ok:(id)sender
{
	limit.yearsBack				= [[yearsPopUp selectedItem] tag];
	limit.countsPickABrickParts	= ([pickABrickSwitch state] == NSControlStateValueOn);
	limit.includesSpares		= ([sparesSwitch state] == NSControlStateValueOn);
	limit.matchesMoldVariants	= ([moldsSwitch state] == NSControlStateValueOn);
	limit.matchesAnyPrint		= ([printsSwitch state] == NSControlStateValueOn);
	limit.matchesAnyColor		= ([colorsSwitch state] == NSControlStateValueOn);
	limit.warnsOnly				= ([warnsSwitch state] == NSControlStateValueOn);

	[self closeWithLimit:[limit copy]];
}


//========== cancel: ===========================================================
//==============================================================================
- (void) cancel:(id)sender
{
	[self closeWithLimit:nil];
}


//========== closeWithLimit: ===================================================
//==============================================================================
- (void) closeWithLimit:(LDrawPartLimit *)result
{
	if(parent != nil)
		[parent endSheet:panel];
	[panel orderOut:nil];

	runningController = nil;
	completion(result);

}//end closeWithLimit:

@end
