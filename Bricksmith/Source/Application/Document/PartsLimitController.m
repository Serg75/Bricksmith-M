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

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawFeatures/LDrawPartUsage.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

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

// The statuses the popover lists, worst first.
static const LDrawPartLimitStatus PartsLimitListedStatuses[] = {
	LDrawPartLimitStatusNotAvailable,
	LDrawPartLimitStatusNotInColor,
	LDrawPartLimitStatusTooMany,
	LDrawPartLimitStatusNoData,
};


@implementation PartsLimitController
{
	__weak LDrawDocument	*document;
	__weak NSView			*modelMenu;
	__weak NSView			*stepControls;

	NSPopUpButton			*limitPopUp;
	NSButton				*problemButton;
	NSPopover				*popover;

	BOOL					 isHidden;
	BOOL					 hasMarks;		// some part may hold a status from an earlier limit
	LDrawPartUsage			*usage;			// nil after an edit until asked for
	NSMapTable				*missingCounts;	// container → parts not in the library, until the next edit
}


//========== initWithDocument: =================================================
//==============================================================================
- (instancetype) initWithDocument:(LDrawDocument *)aDocument
{
	self = [super init];
	if (self)
	{
		self->document		= aDocument;
		self->missingCounts	= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
															   | NSPointerFunctionsObjectPointerPersonality
													valueOptions:NSPointerFunctionsStrongMemory];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(limitDidChange:)
													 name:LDrawPartLimitDidChangeNotification
												   object:[[PartsLimitManager sharedManager] session]];
	}
	return self;

}//end initWithDocument:


//========== dealloc ===========================================================
//==============================================================================
- (void) dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


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


//========== layout ============================================================
//
// Purpose:		Puts the button against the step controls and the menu before
//				it, as wide as its title. The model menu ends before them.
//
// Notes:		The model menu also resizes with the bar, so this runs after
//				every change of the bar's size.
//
//==============================================================================
- (void) layout
{
	NSView			*model		= self->modelMenu;
	NSRect			 modelFrame	= [model frame];
	NSRect			 popUp		= [self->limitPopUp frame];
	NSRect			 button		= [self->problemButton frame];
	CGFloat			 right		= NSMinX([self->stepControls frame]) - PartsLimitGroupGap;

	if(model == nil)
		return;

	if([self->problemButton isHidden] == NO)
	{
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

	// The model menu keeps its left edge and shrinks to make room for the
	// limit's controls.
	modelFrame.size.width = MAX(NSMinX(popUp) - PartsLimitGroupGap - NSMinX(modelFrame), PartsLimitModelMinWidth);
	[model setFrame:modelFrame];

}//end layout


//========== updateControls ====================================================
//
// Purpose:		Shows the limit's name, and the problem count when there are
//				problems. With none, the button counts in gray the parts with
//				no data or not in the part library, once the limit has its
//				data.
//
//==============================================================================
- (void) updateControls
{
	PartsLimitManager		*manager	= [PartsLimitManager sharedManager];
	LDrawPartLimit			*limit		= [[manager session] limit];
	NSString				*title		= [manager titleForLimit:limit]
										  ?: NSLocalizedString(@"Missing Inventory", nil);
	LDrawPartLimitReport	*report		= self.report;
	NSUInteger				 problems	= 0;
	NSUInteger				 noted		= 0;
	LDrawPartLimitStatus	 worst		= LDrawPartLimitStatusAllowed;
	NSColor					*color		= nil;
	NSString				*symbol		= @"exclamationmark.triangle.fill";
	NSString				*toolTip	= NSLocalizedString(@"Parts that break the parts limit", nil);
	NSImage					*image		= nil;

	if(report != nil && [[report table] limit].isRestricting)
	{
		LDrawFile *file = [self->document documentContents];

		problems	= [report problemCountInContainer:file];
		worst		= [report worstStatusInContainer:file];
		noted		= (problems == 0 && [[report table] hasData]) ? [self notedPartCount] : 0;
	}

	[[self->limitPopUp itemAtIndex:0] setTitle:title];
	[self->limitPopUp setHidden:self->isHidden];

	// The icon takes the color of the worst problem: orange for too many, else red.
	color = (worst == LDrawPartLimitStatusTooMany) ? [NSColor systemOrangeColor] : [NSColor systemRedColor];
	if(problems == 0)
	{
		color	= [NSColor secondaryLabelColor];
		symbol	= @"questionmark.circle";
		toolTip	= NSLocalizedString(@"Parts with no data, or not in the part library", nil);
	}
	image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
			 imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];

	[self->problemButton setImage:image];
	[self->problemButton setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)MAX(problems, noted)]];
	[self->problemButton setContentTintColor:color];
	[self->problemButton setToolTip:toolTip];
	[self->problemButton setHidden:(self->isHidden || (problems == 0 && noted == 0))];

	[self layout];

}//end updateControls


//========== notedPartCount ====================================================
//
// Purpose:		How many parts have no data or are not in the part library.
//
//==============================================================================
- (NSUInteger) notedPartCount
{
	NSHashTable *parts = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];

	for(LDrawPart *part in [self.report partsWithStatus:LDrawPartLimitStatusNoData])
		[parts addObject:part];
	for(LDrawPart *part in [self.report missingParts])
		[parts addObject:part];
	return [parts count];

}//end notedPartCount


#pragma mark -
#pragma mark CHECKING
#pragma mark -

//========== setNeedsCheck =====================================================
//==============================================================================
- (void) setNeedsCheck
{
	self->usage = nil;
	[self->missingCounts removeAllObjects];
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
// Purpose:		Puts the model against the limit, marks every part with its
//				status, and redraws when a mark changed.
//
// Notes:		With no limit the walk is skipped, once the marks of an earlier
//				limit are cleared.
//
//==============================================================================
- (void) check
{
	LDrawFile			*file		= [self->document documentContents];
	LDrawPartLimitTable	*table		= [[[PartsLimitManager sharedManager] session] table];
	BOOL				 restricts	= [table limit].isRestricting;
	NSArray				*changed	= nil;

	if(file == nil)
		return;

	if(restricts == NO && self->hasMarks == NO)
	{
		self->_report = nil;
		[self updateControls];
		[self postCheck];
		return;
	}

	self->_report	= [LDrawPartLimitCheck reportForUsage:[self usage] table:table];
	changed			= [LDrawPartLimitCheck applyReport:self->_report toFile:file];
	self->hasMarks	= restricts;

	if([changed count] > 0)
		[self redrawMarks];

	[self updateControls];
	if([self->popover isShown])
		[self fillPopover];
	[self postCheck];

}//end check


//========== usage =============================================================
//
// Purpose:		What the model uses. The walk is kept until the next edit.
//
//==============================================================================
- (LDrawPartUsage *) usage
{
	LDrawFile *file = [self->document documentContents];

	if(self->usage == nil && file != nil)
		self->usage = [LDrawPartUsage usageOfFile:file];
	return self->usage;

}//end usage


//========== postCheck =========================================================
//==============================================================================
- (void) postCheck
{
	[[NSNotificationCenter defaultCenter] postNotificationName:PartsLimitDidCheckNotification
														object:self->document];
}


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
	NSString				*title		= [manager titleForLimit:[[manager session] limit]] ?: @"";
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

	for(size_t index = 0; index < sizeof(PartsLimitListedStatuses) / sizeof(PartsLimitListedStatuses[0]); index++)
	{
		LDrawPartLimitStatus	 status	= PartsLimitListedStatuses[index];
		NSUInteger				 count	= [[report partsWithStatus:status] count];
		NSString				*format	= [self formatForStatus:status];
		NSArray					*row	= nil;

		if(count == 0)
			continue;

		row = [self popoverRowWithText:[NSString stringWithFormat:format, (unsigned long)count]
							   toolTip:[self explanationForStatus:status]
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


//========== formatForStatus: ==================================================
//==============================================================================
- (NSString *) formatForStatus:(LDrawPartLimitStatus)status
{
	switch(status)
	{
		case LDrawPartLimitStatusNotAvailable:	return NSLocalizedString(@"%lu not available", nil);
		case LDrawPartLimitStatusNotInColor:	return NSLocalizedString(@"%lu not made in their color", nil);
		case LDrawPartLimitStatusTooMany:		return NSLocalizedString(@"%lu more than the inventory holds", nil);
		case LDrawPartLimitStatusNoData:		return NSLocalizedString(@"%lu with no data", nil);
		case LDrawPartLimitStatusAllowed:		return @"%lu";
	}
	return @"%lu";
}


//========== explanationForStatus: =============================================
//==============================================================================
- (NSString *) explanationForStatus:(LDrawPartLimitStatus)status
{
	switch(status)
	{
		case LDrawPartLimitStatusNotAvailable:
			return NSLocalizedString(@"The limit does not allow these parts in any color.", nil);
		case LDrawPartLimitStatusNotInColor:
			return NSLocalizedString(@"The limit allows these parts, but not in the color they have.", nil);
		case LDrawPartLimitStatusTooMany:
			return NSLocalizedString(@"Copies past what the inventory holds, counted in build order.", nil);
		case LDrawPartLimitStatusNoData:
			return NSLocalizedString(@"Rebrickable knows nothing of these parts or colors, so they are not "
									 @"checked.", nil);
		case LDrawPartLimitStatusAllowed:
			return @"";
	}
	return @"";
}


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
	LDrawFile		*file		= [owner documentContents];
	NSArray			*models		= [file submodels];
	NSMutableArray	*selected	= [NSMutableArray array];
	NSHashTable		*holders	= [NSHashTable weakObjectsHashTable];	// models with a selected part
	LDrawMPDModel	*shown		= nil;

	for(LDrawPart *part in parts)
	{
		LDrawModel *model = [part enclosingModel];

		if([models containsObject:model] == NO)
			continue;
		[selected addObject:part];
		[holders addObject:model];
	}
	if([selected count] == 0)
		return NO;

	shown = [file activeModel];
	if([holders containsObject:shown] == NO)
	{
		for(LDrawMPDModel *model in models)
		{
			if([holders containsObject:model])
			{
				shown = model;
				break;
			}
		}
	}

	[owner selectDirectives:selected];
	[owner setActiveModel:shown];
	return YES;

}//end selectParts:


//========== useNearestAllowedColor: ===========================================
//
// Purpose:		Recolors every part not made in its color to the nearest color
//				it is made in, by red, green and blue, as one undoable edit.
//
// Notes:		A part in color 16 takes the color of what places it, so it is
//				left alone.
//
//==============================================================================
- (IBAction) useNearestAllowedColor:(id)sender
{
	LDrawDocument		*owner		= self->document;
	LDrawPartLimitTable	*table		= [self.report table];
	LDrawColorLibrary	*library	= [LDrawColorLibrary sharedColorLibrary];
	NSUndoManager		*undo		= [owner undoManager];
	NSUInteger			 changed	= 0;

	[self->popover close];
	[undo beginUndoGrouping];

	for(LDrawPart *part in [self.report partsWithStatus:LDrawPartLimitStatusNotInColor])
	{
		LDrawColor		*color		= [part LDrawColor];
		NSMutableArray	*choices	= [NSMutableArray array];
		LDrawColor		*nearest	= nil;

		if([color colorCode] == LDrawCurrentColor)
			continue;

		for(NSNumber *code in [table colorCodesForPartNamed:[part displayName]])
		{
			LDrawColor *choice = [library colorForCode:(LDrawColorT)[code intValue]];
			if(choice != nil)
				[choices addObject:choice];
		}

		// A part inside a SUB range takes the substitute's status, and may
		// already be in its nearest color.
		nearest = [LDrawPartLimitPresentation nearestColorTo:color amongColors:choices];
		if(nearest == nil || [nearest colorCode] == [color colorCode])
			continue;

		[owner setObject:part toColor:nearest];
		changed++;
	}

	[undo setActionName:NSLocalizedString(@"Use Nearest Allowed Color", nil)];
	[undo endUndoGrouping];

	if(changed == 0)
		NSBeep();
	[[owner documentContents] noteNeedsDisplay];

}//end useNearestAllowedColor:


#pragma mark -
#pragma mark FILE CONTENTS
#pragma mark -

//========== showsMarks ========================================================
//
// Purpose:		Whether the model's problems are shown: a limit is on, the
//				check ran, and the marks are on.
//
//==============================================================================
- (BOOL) showsMarks
{
	return		self.report != nil
			&&	[[self.report table] limit].isRestricting
			&&	[LDrawPart limitMarkStyle] != LDrawRenderMarkNone;
}


//========== configureBadgeOfCell:forItem: =====================================
//
// Purpose:		A part's badge says how it breaks the limit. A step or model
//				says how many of its parts do, in the color of the worst.
//
// Notes:		Parts the part library does not have get a gray badge of their
//				own, with or without a limit, unless they break it.
//
//==============================================================================
- (void) configureBadgeOfCell:(IconTextCell *)cell forItem:(id)item
{
	LDrawPartLimitStatus	status	= LDrawPartLimitStatusAllowed;
	NSUInteger				count	= 0;
	NSUInteger				missing	= 0;
	NSColor					*color	= nil;
	NSString				*symbol	= nil;

	if([self showsMarks])
	{
		if([item isKindOfClass:[LDrawPart class]])
			status = [(LDrawPart *)item limitStatus];
		else if([item isKindOfClass:[LDrawContainer class]])
		{
			count	= [self.report problemCountInContainer:item];
			status	= (count > 0) ? [self.report worstStatusInContainer:item] : LDrawPartLimitStatusAllowed;
		}
	}

	symbol	= [LDrawPartLimitPresentation badgeSymbolNameForStatus:status];
	color	= [self colorForBadgeTint:[LDrawPartLimitPresentation badgeTintForStatus:status]];

	if(LDrawPartLimitStatusIsProblem(status) == NO)
		missing = [self missingPartCountInItem:item];
	if(missing > 0)
	{
		symbol	= @"questionmark.square.dashed";
		color	= [NSColor secondaryLabelColor];
		count	= [item isKindOfClass:[LDrawPart class]] ? 0 : missing;
	}

	[cell setBadgeColor:color];
	[cell setBadgeText:(count > 0) ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil];
	[cell setBadgeImage:(symbol != nil) ? [self badgeImageNamed:symbol color:color] : nil];

}//end configureBadgeOfCell:forItem:


//========== colorForBadgeTint: ================================================
//
// Purpose:		The marks' colors from Settings, or gray for no data.
//
//==============================================================================
- (NSColor *) colorForBadgeTint:(LDrawPartLimitBadgeTint)tint
{
	NSString *key = nil;

	if(tint == LDrawPartLimitBadgeTintNotAvailable)
		key = PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY;
	else if(tint == LDrawPartLimitBadgeTintTooMany)
		key = PARTS_LIMIT_TOO_MANY_COLOR_KEY;
	else
		return [NSColor secondaryLabelColor];

	return [PartsLimitManager markColorForKey:key] ?: [NSColor systemRedColor];

}//end colorForBadgeTint:


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


//========== missingPartCountInItem: ===========================================
//
// Purpose:		How many parts the part library does not have: 1 or 0 for a
//				part, and the parts inside a step or model.
//
// Notes:		A container's count is kept until the next edit, since every
//				row asks each time File Contents draws.
//
//==============================================================================
- (NSUInteger) missingPartCountInItem:(id)item
{
	__block NSUInteger	 count	= 0;
	NSNumber			*known	= nil;

	if([item isKindOfClass:[LDrawPart class]])
		return [(LDrawPart *)item partIsMissing] ? 1 : 0;
	if([item isKindOfClass:[LDrawContainer class]] == NO)
		return 0;

	known = [self->missingCounts objectForKey:item];
	if(known != nil)
		return [known unsignedIntegerValue];

	[(LDrawContainer *)item applyToAllParts:^(LDrawPart *part) {
		if([part partIsMissing])
			count += 1;
	}];
	[self->missingCounts setObject:@(count) forKey:item];
	return count;

}//end missingPartCountInItem:


//========== toolTipForItem: ===================================================
//
// Purpose:		Why a part's badge is there, or how many of a step's or model's
//				parts break the limit or are not in the part library.
//
//==============================================================================
- (NSString *) toolTipForItem:(id)item
{
	NSUInteger	 count		= 0;
	NSUInteger	 missing	= [self missingPartCountInItem:item];
	NSString	*line		= nil;

	if([item isKindOfClass:[LDrawPart class]])
	{
		NSString *note = NSLocalizedString(@"The part library does not have this part.", nil);

		line = [self showsMarks] ? [self describePart:item fully:YES] : nil;
		if(missing == 0)
			return line;
		return (line != nil) ? [NSString stringWithFormat:@"%@ %@", note, line] : note;
	}

	if([self showsMarks] && [item isKindOfClass:[LDrawContainer class]])
		count = [self.report problemCountInContainer:item];

	if(count == 1)
		return NSLocalizedString(@"1 part breaks the parts limit.", nil);
	if(count > 1)
		return [NSString localizedStringWithFormat:NSLocalizedString(@"%lu parts break the parts limit.", nil),
				(unsigned long)count];
	if(missing == 1)
		return NSLocalizedString(@"1 part is not in the part library.", nil);
	if(missing > 1)
		return [NSString localizedStringWithFormat:NSLocalizedString(@"%lu parts are not in the part library.", nil),
				(unsigned long)missing];
	return nil;

}//end toolTipForItem:


//========== limitLineForPart: =================================================
//
// Purpose:		The inspector's line about a part, or nil when it is within the
//				limit.
//
//==============================================================================
- (NSString *) limitLineForPart:(LDrawPart *)part
{
	if([self showsMarks] == NO)
		return nil;
	return [self describePart:part fully:NO];

}//end limitLineForPart:


//========== describePart:fully: ===============================================
//
// Purpose:		How a part breaks the limit, in a short line, or fully for a
//				tooltip. Nil for a part within it.
//
//==============================================================================
- (NSString *) describePart:(LDrawPart *)part fully:(BOOL)fully
{
	LDrawPartLimitTable	*table		= [self.report table];
	LDrawPartLimit		*limit		= [table limit];
	BOOL				 isNow		= (limit.kind == LDrawPartLimitKindAvailableNow);
	NSString			*inventory	= [[PartsLimitManager sharedManager] titleForLimit:limit] ?: @"";
	NSString			*partName	= [part displayName];
	LDrawColor			*color		= [part LDrawColor];
	LDrawColorT			 checked	= [self.report colorCodeForPart:part];
	NSString			*colorName	= nil;
	NSString			*line		= nil;

	// A part in color 16 is checked in the color of what places it.
	if(checked != LDrawColorBogus && checked != [color colorCode])
		color = [[LDrawColorLibrary sharedColorLibrary] colorForCode:checked] ?: color;
	colorName = [color localizedName];

	switch([part limitStatus])
	{
		case LDrawPartLimitStatusAllowed:
			return nil;

		case LDrawPartLimitStatusNoData:
			// In a color with no match, every part has no data.
			if([table hasData] && [table matchesColorCode:[color colorCode]] == NO)
			{
				NSString *format = fully ? NSLocalizedString(@"Bricksmith cannot match %@ to a LEGO color.", nil)
										 : NSLocalizedString(@"No LEGO color matches %@", nil);
				return [NSString stringWithFormat:format, colorName];
			}
			return fully ? NSLocalizedString(@"Bricksmith cannot match this part to a LEGO part.", nil)
						 : NSLocalizedString(@"No LEGO part matches it", nil);

		case LDrawPartLimitStatusNotAvailable:
			line = isNow ? NSLocalizedString(@"Not made now in any color", nil)
						 : [NSString stringWithFormat:NSLocalizedString(@"Not in %@", nil), inventory];
			return fully ? [line stringByAppendingString:@"."] : line;

		case LDrawPartLimitStatusNotInColor:
			line = isNow ? [NSString stringWithFormat:NSLocalizedString(@"Not made in %@ now", nil), colorName]
						 : [NSString stringWithFormat:NSLocalizedString(@"Not in %@ in %@", nil), inventory, colorName];
			if(fully == NO)
				return line;
			return [NSString stringWithFormat:isNow ? NSLocalizedString(@"%@. Made in %@.", nil)
													: NSLocalizedString(@"%@. It has %@.", nil),
					line, [self listOfColorCodes:[table colorCodesForPartNamed:partName]]];

		case LDrawPartLimitStatusTooMany:
		{
			NSUInteger	used	= [self.report usedCountForPartNamed:partName colorCode:[color colorCode]];
			NSUInteger	owned	= [table ownedCountForPartNamed:partName colorCode:[color colorCode]];
			NSString	*what	= [[LDrawPartLibrary sharedPartLibrary] descriptionForPartName:partName] ?: partName;

			if(fully == NO)
				return [NSString stringWithFormat:NSLocalizedString(@"Uses %lu of %lu in %@", nil),
						(unsigned long)used, (unsigned long)owned, inventory];
			return [NSString stringWithFormat:NSLocalizedString(@"The model uses %lu %@ %@; %@ holds %lu.", nil),
					(unsigned long)used, colorName, what, inventory, (unsigned long)owned];
		}
	}
	return nil;

}//end describePart:fully:


//========== listOfColorCodes: =================================================
//
// Purpose:		"Black, Red, Light Bluish Gray and 11 more".
//
//==============================================================================
- (NSString *) listOfColorCodes:(NSArray<NSNumber *> *)codes
{
	LDrawColorLibrary	*library	= [LDrawColorLibrary sharedColorLibrary];
	NSMutableArray		*names		= [NSMutableArray array];
	NSUInteger			 shown		= MIN([codes count], (NSUInteger)3);

	for(NSUInteger index = 0; index < shown; index++)
		[names addObject:[[library colorForCode:(LDrawColorT)[codes[index] intValue]] localizedName] ?: @"?"];

	if([codes count] > shown)
		return [NSString stringWithFormat:NSLocalizedString(@"%@ and %lu more", nil),
				[names componentsJoinedByString:@", "], (unsigned long)([codes count] - shown)];
	if([names count] > 1)
		return [NSString stringWithFormat:NSLocalizedString(@"%@ and %@", nil),
				[[names subarrayWithRange:NSMakeRange(0, [names count] - 1)] componentsJoinedByString:@", "],
				[names lastObject]];
	return [names firstObject] ?: @"";

}//end listOfColorCodes:


//========== showPieceCount: ===================================================
//==============================================================================
- (void) showPieceCount:(id)sender
{
	[self->popover close];
	[self->document showPieceCount:sender];
}


#pragma mark -
#pragma mark MENU
#pragma mark -

//========== menuNeedsUpdate: ==================================================
//
// Purpose:		The app's limit menu, after the pull-down's title item, with
//				Limit Options. Sets are imported in the Inventories window.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	[[PartsLimitManager sharedManager] populatePullDownLimitMenu:menu commands:PartsLimitMenuLimitOptions];

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
	[self layout];
}

@end
