//==============================================================================
//
// File:		PartsLimitController.m
//
// Purpose:		A document's side of the parts limit: the Parts menu and the
//				problem button in the scope bar, and the check of the model.
//
// Notes:		The model is checked once per edit, after the document's own
//				change notice, and whenever the app's limit changes.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "PartsLimitController.h"

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawEditing/LDrawSelection.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartLimitChecker.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>

#import "IconTextCell.h"
#import "LDrawDocument.h"
#import "PartsLimitManager.h"
#import "PreferencesForm.h"

NSString * const PartsLimitDidCheckNotification = @"PartsLimitDidCheckNotification";

// Sizes in the scope bar. The gaps match the arranging controls.
static const CGFloat	PartsLimitGroupGap		= 10.0;
static const CGFloat	PartsLimitButtonGap		= 4.0;
static const CGFloat	PartsLimitPopUpMaxWidth	= 200.0;
static const CGFloat	PartsLimitModelMinWidth	= 80.0;


@implementation PartsLimitController
{
	__weak LDrawDocument	*document;
	__weak NSView			*modelMenu;
	__weak NSView			*stepControls;

	NSPopUpButton			*limitPopUp;
	NSButton				*problemButton;
	NSPopover				*popover;

	BOOL					 isHidden;
	LDrawPartLimitChecker	*checker;		// for the document's file; use -checker
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== initWithDocument: =================================================
//==============================================================================
- (instancetype) initWithDocument:(LDrawDocument *)aDocument
{
	self = [super init];
	if (self)
	{
		self->document = aDocument;

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(limitDidChange:)
													 name:LDrawPartLimitDidChangeNotification
												   object:[[PartsLimitManager sharedManager] session]];
	}
	return self;

}//end initWithDocument:


#pragma mark -
#pragma mark CONTROLS
#pragma mark -

//========== installAfterView:beforeView: ======================================
//
// Purpose:		Makes the Parts menu and the problem button, small like the
//				rest of the scope bar.
//
//==============================================================================
- (void) installAfterView:(NSView *)aModelMenu beforeView:(NSView *)aStepControls
{
	NSView		*bar		= [aModelMenu superview];
	NSRect		 model		= [aModelMenu frame];
	NSImage		*image		= [NSImage imageWithSystemSymbolName:@"shippingbox" accessibilityDescription:nil];
	NSFont		*font		= [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];

	self->modelMenu		= aModelMenu;
	self->stepControls	= aStepControls;

	self->limitPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, NSMinY(model), 100, NSHeight(model))
												  pullsDown:YES];
	[self->limitPopUp setBezelStyle:NSBezelStyleRoundRect];
	[self->limitPopUp setControlSize:NSControlSizeSmall];
	[self->limitPopUp setFont:font];
	[[self->limitPopUp cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[[self->limitPopUp cell] setImagePosition:NSImageLeft];
	[[self->limitPopUp cell] setUsesItemFromMenu:YES];
	[self->limitPopUp addItemWithTitle:@""];
	[[self->limitPopUp itemAtIndex:0] setImage:image];
	[[self->limitPopUp menu] setDelegate:self];
	[self->limitPopUp setToolTip:NSLocalizedString(@"Which parts the model may use. Every window shares it.", nil)];
	[self->limitPopUp setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];

	self->problemButton = [NSButton buttonWithTitle:@""
											  image:[NSImage new]
											 target:self
											 action:@selector(showProblems:)];
	[self->problemButton setBezelStyle:NSBezelStyleRecessed];
	[self->problemButton setShowsBorderOnlyWhileMouseInside:YES];
	[self->problemButton setControlSize:NSControlSizeSmall];
	[self->problemButton setFont:font];
	[self->problemButton setImagePosition:NSImageLeading];
	[self->problemButton setToolTip:NSLocalizedString(@"Parts that break the parts limit", nil)];
	[self->problemButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
	[self->problemButton setHidden:YES];

	[bar addSubview:self->limitPopUp];
	[bar addSubview:self->problemButton];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(barDidResize:)
												 name:NSViewFrameDidChangeNotification
											   object:bar];
	[self updateControls];

}//end installAfterView:beforeView:


//========== setHidden: ========================================================
//
// Purpose:		Hidden while a step is arranged, whose fields take the room.
//
//==============================================================================
- (void) setHidden:(BOOL)hidden
{
	self->isHidden = hidden;
	[self updateControls];
}


//========== updateControls ====================================================
//
// Purpose:		Shows the limit's name, and the problem count when there are
//				problems or parts worth a note.
//
//==============================================================================
- (void) updateControls
{
	PartsLimitManager		*manager	= [PartsLimitManager sharedManager];
	LDrawPartLimitChecker	*check		= [self checker];
	LDrawPartLimitBadge		*badge		= [check summaryBadge];
	NSColor					*color		= [PartsLimitManager colorForBadgeTint:[badge tint]];
	NSImage					*image		= nil;

	[[self->limitPopUp itemAtIndex:0] setTitle:[manager titleForLimit:[[manager session] limit]]];
	[self->limitPopUp setHidden:self->isHidden];

	image = [[NSImage imageWithSystemSymbolName:[badge symbolName] accessibilityDescription:nil]
			 imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];

	[self->problemButton setImage:image];
	[self->problemButton setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)[badge count]]];
	[self->problemButton setContentTintColor:color];
	[self->problemButton setToolTip:[check summaryToolTip]];
	[self->problemButton setHidden:(self->isHidden || [badge count] == 0)];

	[self layoutControls];

}//end updateControls


//========== layoutControls ====================================================
//
// Purpose:		Puts the button against the step controls and the menu before
//				it, as wide as its title. The model menu ends before them.
//
// Notes:		The model menu also resizes with the bar, so this runs after
//				every change of the bar's size.
//
//==============================================================================
- (void) layoutControls
{
	NSView		*model		= self->modelMenu;
	NSRect		 modelFrame	= [model frame];
	NSRect		 popUp		= [self->limitPopUp frame];
	CGFloat		 right		= NSMinX([self->stepControls frame]) - PartsLimitGroupGap;

	if(model == nil)
		return;

	if([self->problemButton isHidden] == NO)
	{
		NSRect button = NSZeroRect;

		[self->problemButton sizeToFit];
		button			= [self->problemButton frame];
		button.origin.x	= right - NSWidth(button);
		button.origin.y	= NSMidY(modelFrame) - NSHeight(button) / 2;
		[self->problemButton setFrame:button];
		right = NSMinX(button) - PartsLimitButtonGap;
	}

	popUp.size.width	= MIN(ceil([[self->limitPopUp cell] cellSize].width), PartsLimitPopUpMaxWidth);
	popUp.origin.x		= right - NSWidth(popUp);
	popUp.origin.y		= NSMidY(modelFrame) - NSHeight(popUp) / 2;
	[self->limitPopUp setFrame:popUp];

	// The model menu keeps its left edge and shrinks to make room.
	modelFrame.size.width = MAX(NSMinX(popUp) - PartsLimitGroupGap - NSMinX(modelFrame), PartsLimitModelMinWidth);
	[model setFrame:modelFrame];

}//end layoutControls


#pragma mark -
#pragma mark CHECKING
#pragma mark -

//========== checker ===========================================================
//
// Purpose:		The check of the document's file, made again when the file is
//				replaced.
//
//==============================================================================
- (LDrawPartLimitChecker *) checker
{
	LDrawFile *file = [self->document documentContents];

	if(file != nil && [self->checker file] != file)
		self->checker = [[LDrawPartLimitChecker alloc] initWithFile:file];
	return self->checker;

}//end checker


//========== report ============================================================
//==============================================================================
- (LDrawPartLimitReport *) report
{
	return [[self checker] report];
}


//========== usage =============================================================
//==============================================================================
- (LDrawPartUsage *) usage
{
	return [[self checker] usage];
}


//========== setNeedsCheck =====================================================
//==============================================================================
- (void) setNeedsCheck
{
	[[self checker] modelDidChange];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(check) object:nil];
	[self performSelector:@selector(check) withObject:nil afterDelay:0];
}


//========== redrawMarks =======================================================
//==============================================================================
- (void) redrawMarks
{
	[[self->document documentContents] noteNeedsDisplay];
}


//========== check =============================================================
//
// Purpose:		Puts the model against the limit, redraws when a mark changed,
//				and tells the part browsers and the inspector.
//
//==============================================================================
- (void) check
{
	LDrawPartLimitTable *table = [[[PartsLimitManager sharedManager] session] table];

	if([[self checker] checkAgainstTable:table])
		[self redrawMarks];

	[self updateControls];
	if([self->popover isShown])
		[self fillPopover];

	[[NSNotificationCenter defaultCenter] postNotificationName:PartsLimitDidCheckNotification
														object:self->document];

}//end check


#pragma mark -
#pragma mark PROBLEMS
#pragma mark -

//========== showProblems: =====================================================
//
// Purpose:		A popover with how many parts have each problem, and a button
//				to select them.
//
//==============================================================================
- (void) showProblems:(id)sender
{
	if(self->popover == nil)
	{
		self->popover = [[NSPopover alloc] init];
		[self->popover setBehavior:NSPopoverBehaviorTransient];
		[self->popover setContentViewController:[[NSViewController alloc] init]];
	}

	[self fillPopover];
	[self->popover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSRectEdgeMinY];

}//end showProblems:


//========== fillPopover =======================================================
//
// Purpose:		Fills the popover from the last report: one row per status the
//				model has, the parts not in the part library, then Show Piece
//				Count.
//
//==============================================================================
- (void) fillPopover
{
	NSViewController		*content	= [self->popover contentViewController];
	LDrawPartLimitReport	*report		= self.report;
	PartsLimitManager		*manager	= [PartsLimitManager sharedManager];
	NSString				*title		= [manager titleForLimit:[[manager session] limit]];
	NSUInteger				 missing	= [[report missingParts] count];
	NSTextField				*heading	= nil;
	NSGridView				*grid		= nil;
	NSButton				*pieceCount	= nil;

	if(content == nil)
		return;

	heading		= [NSTextField labelWithString:title];
	grid		= [NSGridView gridViewWithViews:@[]];
	pieceCount	= [NSButton buttonWithTitle:NSLocalizedString(@"Show Piece Count…", nil)
									 target:self
									 action:@selector(showPieceCount:)];

	[heading setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	[grid setColumnSpacing:12];
	[grid setRowSpacing:6];
	[grid setRowAlignment:NSGridRowAlignmentFirstBaseline];

	for(NSNumber *number in [[self checker] summaryStatuses])
	{
		LDrawPartLimitStatus	 status	= [number integerValue];
		NSUInteger				 count	= [[report partsWithStatus:status] count];
		NSArray					*row	= nil;

		row = [self popoverRowWithText:[LDrawPartLimitPresentation summaryForStatus:status count:count]
							   toolTip:[LDrawPartLimitPresentation explanationForStatus:status]
								action:@selector(selectPartsWithStatus:)
								   tag:status];

		if(status == LDrawPartLimitStatusNotInColor)
		{
			NSButton *nearest = [NSButton buttonWithTitle:NSLocalizedString(@"Use Nearest Color", nil)
												   target:self
												   action:@selector(useNearestAllowedColor:)];
			[nearest setControlSize:NSControlSizeSmall];
			[nearest setToolTip:NSLocalizedString(@"Gives each of them the nearest color it is made in.", nil)];
			row = [row arrayByAddingObject:nearest];
		}
		[grid addRowWithViews:row];
	}

	if(missing > 0)
	{
		NSString *text		= [NSString stringWithFormat:NSLocalizedString(@"%lu not in the part library", nil),
							   (unsigned long)missing];
		NSString *toolTip	= NSLocalizedString(@"The part library does not have these parts. Each is still "
												@"checked when Bricksmith can match it to a LEGO part.", nil);

		[grid addRowWithViews:[self popoverRowWithText:text
											   toolTip:toolTip
												action:@selector(selectMissingParts:)
												   tag:0]];
	}

	if([grid numberOfRows] == 0)
	{
		NSString *none = NSLocalizedString(@"Every part is within the limit.", nil);
		[grid addRowWithViews:@[[NSTextField labelWithString:none]]];
	}

	NSStackView *stack = [NSStackView stackViewWithViews:@[heading, grid, pieceCount]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:10];

	// Measured before it goes in, where the popover's old size would hold it.
	NSView *view = [PreferencesForm containerForView:stack margins:NSEdgeInsetsMake(14, 16, 14, 16)];
	NSSize	size = [view fittingSize];

	[content setView:view];
	[content setPreferredContentSize:size];
	[self->popover setContentSize:size];

}//end fillPopover


//========== popoverRowWithText:toolTip:action:tag: ============================
//
// Purpose:		A popover row: a line of text and a Select button.
//
//==============================================================================
- (NSArray<NSView *> *) popoverRowWithText:(NSString *)text
								   toolTip:(NSString *)toolTip
									action:(SEL)action
									   tag:(NSInteger)tag
{
	NSTextField	*label	= [NSTextField labelWithString:text];
	NSButton	*select	= [NSButton buttonWithTitle:NSLocalizedString(@"Select", nil) target:self action:action];

	[label setToolTip:toolTip];
	[select setTag:tag];
	[select setControlSize:NSControlSizeSmall];
	return @[label, select];

}//end popoverRowWithText:toolTip:action:tag:


//========== selectPartsWithStatus: ============================================
//
// Purpose:		Selects the parts with the button's status, in every model.
//
//==============================================================================
- (void) selectPartsWithStatus:(id)sender
{
	[self->popover close];
	[self selectParts:[self.report partsWithStatus:[sender tag]]];

}//end selectPartsWithStatus:


//========== selectMissingParts: ===============================================
//
// Purpose:		Selects the parts the part library does not have.
//
//==============================================================================
- (void) selectMissingParts:(id)sender
{
	[self->popover close];
	[self selectParts:[self.report missingParts]];

}//end selectMissingParts:


//========== selectProblemParts ================================================
//
// Purpose:		Selects every part that breaks the limit. NO when there is none.
//
//==============================================================================
- (BOOL) selectProblemParts
{
	return [self selectParts:[self.report problemParts] ?: @[]];
}


//========== selectParts: ======================================================
//
// Purpose:		Selects the parts in every model of the file, and shows the
//				model being edited when it has some, else the first model that
//				does. NO when there are none.
//
// Notes:		Selecting rows in File Contents shows the last row's model, so
//				the model to show is set after the selection.
//
//==============================================================================
- (BOOL) selectParts:(NSArray<LDrawPart *> *)parts
{
	LDrawDocument	*owner		= self->document;
	NSArray			*found		= nil;
	LDrawMPDModel	*shown		= [LDrawSelection modelShowingParts:parts
															 inFile:[owner documentContents]
														 foundParts:&found];

	if(shown == nil)
		return NO;

	[owner selectDirectives:found];
	[owner setActiveModel:shown];
	return YES;

}//end selectParts:


//========== useNearestAllowedColor: ===========================================
//
// Purpose:		Recolors every part not made in its color to the nearest color
//				it is made in, as one undoable edit.
//
//==============================================================================
- (IBAction) useNearestAllowedColor:(id)sender
{
	LDrawDocument	*owner	= self->document;
	NSUndoManager	*undo	= [owner undoManager];
	NSMapTable		*colors	= [[self checker] nearestAllowedColors];

	[self->popover close];
	[undo beginUndoGrouping];

	for(LDrawPart *part in colors)
		[owner setObject:part toColor:[colors objectForKey:part]];

	[undo setActionName:NSLocalizedString(@"Use Nearest Allowed Color", nil)];
	[undo endUndoGrouping];

	if([colors count] == 0)
		NSBeep();
	[[owner documentContents] noteNeedsDisplay];

}//end useNearestAllowedColor:


//========== showPieceCount: ===================================================
//==============================================================================
- (void) showPieceCount:(id)sender
{
	[self->popover close];
	[self->document showPieceCount:sender];
}


#pragma mark -
#pragma mark FILE CONTENTS AND INSPECTOR
#pragma mark -

//========== configureBadgeOfCell:forItem: =====================================
//
// Purpose:		Gives a File Contents row the badge the check chose.
//
//==============================================================================
- (void) configureBadgeOfCell:(IconTextCell *)cell forItem:(id)item
{
	LDrawPartLimitBadge	*badge	= [[self checker] badgeForItem:item];
	NSColor				*color	= [PartsLimitManager colorForBadgeTint:[badge tint]];
	NSUInteger			 count	= [badge count];

	[cell setBadgeColor:color];
	[cell setBadgeText:(count > 0) ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil];
	[cell setBadgeImage:([badge symbolName] != nil) ? [self badgeImageNamed:[badge symbolName] color:color] : nil];

}//end configureBadgeOfCell:forItem:


//========== badgeImageNamed:color: ============================================
//
// Purpose:		A small symbol in the color. Kept, since every row asks.
//
//==============================================================================
- (NSImage *) badgeImageNamed:(NSString *)symbol color:(NSColor *)color
{
	static NSMutableDictionary	*images	= nil;
	NSString					*key	= [NSString stringWithFormat:@"%@ %@", symbol, color];
	NSImage						*image	= images[key];

	if(image == nil)
	{
		NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:11
																						   weight:NSFontWeightRegular];
		NSImageSymbolConfiguration *tinted = [size configurationByApplyingConfiguration:
											  [NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];

		image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
				 imageWithSymbolConfiguration:tinted];
		if(images == nil)
			images = [NSMutableDictionary dictionary];
		if(image != nil)
			images[key] = image;
	}
	return image;

}//end badgeImageNamed:color:


//========== toolTipForItem: ===================================================
//==============================================================================
- (NSString *) toolTipForItem:(id)item
{
	return [[self checker] toolTipForItem:item store:[[PartsLimitManager sharedManager] store]];
}


//========== limitLineForPart: =================================================
//==============================================================================
- (NSString *) limitLineForPart:(LDrawPart *)part
{
	return [[self checker] lineForPart:part store:[[PartsLimitManager sharedManager] store]];
}


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//**** NSMenuDelegate ****
//========== menuNeedsUpdate: ==================================================
//
// Purpose:		Fills the Parts menu with the app's limits as it opens.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	[[PartsLimitManager sharedManager] populatePullDownLimitMenu:menu];

}//end menuNeedsUpdate:


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== limitDidChange: ===================================================
//==============================================================================
- (void) limitDidChange:(NSNotification *)notification
{
	[self updateControls];
	[self setNeedsCheck];
}


//========== barDidResize: =====================================================
//==============================================================================
- (void) barDidResize:(NSNotification *)notification
{
	[self layoutControls];
}


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//==============================================================================
- (void) dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
