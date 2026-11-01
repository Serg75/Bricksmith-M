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

NSString * const PartsLimitDidCheckNotification = @"PartsLimitDidCheckNotification";

// Gaps in the scope bar, as the arranging controls use.
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
	BOOL					 isRedrawing;	// the redraw reaches the document as an edit
	LDrawPartUsage			*usage;			// nil after an edit until asked for
}


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

	// The model menu keeps where it starts, and gives up what the limit needs.
	modelFrame.size.width = MAX(NSMinX(popUp) - PartsLimitGroupGap - NSMinX(modelFrame), PartsLimitModelMinWidth);
	[model setFrame:modelFrame];

}//end layout


//========== updateControls ====================================================
//
// Purpose:		Shows the limit's name, and the problem count when there are
//				problems.
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
	LDrawPartLimitStatus	 worst		= LDrawPartLimitStatusAllowed;
	NSColor					*color		= nil;
	NSImage					*warning	= nil;

	if(report != nil && [[report table] limit].isRestricting)
	{
		LDrawFile *file = [self->document documentContents];

		problems	= [report problemCountInContainer:file];
		worst		= [report worstStatusInContainer:file];
	}

	[[self->limitPopUp itemAtIndex:0] setTitle:title];
	[self->limitPopUp setHidden:self->isHidden];

	// The icon takes the color of the worst problem: orange for too many, else red.
	color	= (worst == LDrawPartLimitStatusTooMany) ? [NSColor systemOrangeColor] : [NSColor systemRedColor];
	warning	= [[NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill" accessibilityDescription:nil]
			   imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];

	[self->problemButton setImage:warning];
	[self->problemButton setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)problems]];
	[self->problemButton setContentTintColor:color];
	[self->problemButton setHidden:(self->isHidden || problems == 0)];

	[self layout];

}//end updateControls


#pragma mark -
#pragma mark CHECKING
#pragma mark -

//========== setNeedsCheck =====================================================
//==============================================================================
- (void) setNeedsCheck
{
	if(self->isRedrawing)
		return;

	self->usage = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(check) object:nil];
	[self performSelector:@selector(check) withObject:nil afterDelay:0];
}


//========== redrawMarks =======================================================
//
// Purpose:		Redraws the model. The document takes the redraw for an edit,
//				which would walk the model again for nothing.
//
//==============================================================================
- (void) redrawMarks
{
	self->isRedrawing = YES;
	[[self->document documentContents] noteNeedsDisplay];
	self->isRedrawing = NO;
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
	[self updatePopover];
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

	[self updatePopover];
	[self->popover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSRectEdgeMinY];

}//end showProblems:


//========== updatePopover =====================================================
//
// Purpose:		Fills the popover from the last report: one row per status the
//				model has, then Show Piece Count.
//
//==============================================================================
- (void) updatePopover
{
	NSViewController		*content	= [self->popover contentViewController];
	LDrawPartLimitReport	*report		= self.report;
	PartsLimitManager		*manager	= [PartsLimitManager sharedManager];
	NSString				*title		= [manager titleForLimit:[[manager session] limit]] ?: @"";
	NSTextField				*heading	= [NSTextField labelWithString:title];
	NSGridView				*grid		= [NSGridView gridViewWithViews:@[]];
	NSButton				*pieceCount	= [NSButton buttonWithTitle:NSLocalizedString(@"Show Piece Count…", nil)
														  target:self
														  action:@selector(showPieceCount:)];

	if(content == nil)
		return;

	[heading setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	[grid setColumnSpacing:12];
	[grid setRowSpacing:6];

	for(size_t index = 0; index < sizeof(PartsLimitListedStatuses) / sizeof(PartsLimitListedStatuses[0]); index++)
	{
		LDrawPartLimitStatus	 status	= PartsLimitListedStatuses[index];
		NSUInteger				 count	= [[report partsWithStatus:status] count];
		NSTextField				*label	= nil;
		NSButton				*select	= nil;

		if(count == 0)
			continue;

		label	= [NSTextField labelWithString:[NSString stringWithFormat:[self formatForStatus:status],
												(unsigned long)count]];
		select	= [NSButton buttonWithTitle:NSLocalizedString(@"Select", nil)
									target:self
									action:@selector(selectPartsWithStatus:)];
		[select setTag:status];
		[select setControlSize:NSControlSizeSmall];
		[label setToolTip:[self explanationForStatus:status]];

		if(status == LDrawPartLimitStatusNotInColor)
		{
			NSButton *nearest = [NSButton buttonWithTitle:NSLocalizedString(@"Use Nearest Color", nil)
												   target:self
												   action:@selector(useNearestAllowedColor:)];
			[nearest setControlSize:NSControlSizeSmall];
			[nearest setToolTip:NSLocalizedString(@"Gives each of them the nearest color it is made in.", nil)];
			[grid addRowWithViews:@[label, select, nearest]];
		}
		else
			[grid addRowWithViews:@[label, select]];
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
	[stack setEdgeInsets:NSEdgeInsetsMake(14, 16, 14, 16)];
	[content setView:stack];
	[content setPreferredContentSize:[stack fittingSize]];

}//end updatePopover


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
// Purpose:		Selects the parts with the button's status: in the model being
//				edited when it has some, else in the first model that does.
//
//==============================================================================
- (void) selectPartsWithStatus:(id)sender
{
	[self->popover close];
	[self selectParts:[self.report partsWithStatus:[sender tag]]];

}//end selectPartsWithStatus:


//========== selectProblemParts ================================================
//
// Purpose:		Selects every part that breaks the limit, as -selectParts:
//				does. NO when there is none.
//
//==============================================================================
- (BOOL) selectProblemParts
{
	NSMutableArray *parts = [NSMutableArray array];

	for(LDrawPartLimitStatus status = LDrawPartLimitStatusTooMany; status <= LDrawPartLimitStatusNotAvailable; status++)
		[parts addObjectsFromArray:[self.report partsWithStatus:status] ?: @[]];

	return [self selectParts:parts];

}//end selectProblemParts


//========== selectParts: ======================================================
//
// Purpose:		Selects the parts in the model being edited when it has some,
//				else in the first model that does. NO when there are none.
//
//==============================================================================
- (BOOL) selectParts:(NSArray<LDrawPart *> *)parts
{
	LDrawDocument			*owner		= self->document;
	LDrawFile				*file		= [owner documentContents];
	NSMutableDictionary		*byModel	= [NSMutableDictionary dictionary];
	LDrawMPDModel			*chosen		= nil;

	for(LDrawPart *part in parts)
	{
		LDrawModel		*model	= [part enclosingModel];
		NSValue			*key	= [NSValue valueWithNonretainedObject:model];
		NSMutableArray	*list	= byModel[key];

		if(model == nil)
			continue;
		if(list == nil)
			byModel[key] = list = [NSMutableArray array];
		[list addObject:part];
	}

	if(byModel[[NSValue valueWithNonretainedObject:[file activeModel]]] != nil)
		chosen = [file activeModel];
	else
	{
		for(LDrawMPDModel *model in [file submodels])
		{
			if(byModel[[NSValue valueWithNonretainedObject:model]] != nil)
			{
				chosen = model;
				break;
			}
		}
	}

	if(chosen == nil)
		return NO;

	if(chosen != [file activeModel])
		[owner setActiveModel:chosen];
	[owner selectDirectives:byModel[[NSValue valueWithNonretainedObject:chosen]]];
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
			&&	[[NSUserDefaults standardUserDefaults] boolForKey:PARTS_LIMIT_MARKS_KEY];
}


//========== configureBadgeOfCell:forItem: =====================================
//
// Purpose:		A part's badge says how it breaks the limit. A step or model
//				says how many of its parts do, in the color of the worst.
//
//==============================================================================
- (void) configureBadgeOfCell:(IconTextCell *)cell forItem:(id)item
{
	LDrawPartLimitStatus	status	= LDrawPartLimitStatusAllowed;
	NSUInteger				count	= 0;
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
	NSString	*key		= nil;
	NSArray		*components	= nil;

	if(tint == LDrawPartLimitBadgeTintNotAvailable)
		key = PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY;
	else if(tint == LDrawPartLimitBadgeTintTooMany)
		key = PARTS_LIMIT_TOO_MANY_COLOR_KEY;
	else
		return [NSColor secondaryLabelColor];

	components = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
	if([components count] != 3)
		return [NSColor systemRedColor];

	return [NSColor colorWithSRGBRed:[components[0] doubleValue]
							   green:[components[1] doubleValue]
								blue:[components[2] doubleValue]
							   alpha:1.0];

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
		NSImageSymbolConfiguration *size	= [NSImageSymbolConfiguration configurationWithPointSize:11
																						 weight:NSFontWeightRegular];
		NSImageSymbolConfiguration *tinted	= [size configurationByApplyingConfiguration:
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
//
// Purpose:		Why a part's badge is there, or how many of a step's or model's
//				parts break the limit.
//
//==============================================================================
- (NSString *) toolTipForItem:(id)item
{
	NSUInteger count = 0;

	if([self showsMarks] == NO)
		return nil;

	if([item isKindOfClass:[LDrawPart class]])
		return [self describePart:item fully:YES];

	if([item isKindOfClass:[LDrawContainer class]])
		count = [self.report problemCountInContainer:item];

	if(count == 0)
		return nil;
	return [NSString localizedStringWithFormat:NSLocalizedString(@"%lu parts break the parts limit.", nil),
			(unsigned long)count];

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
// Purpose:		The app's limit menu, after the pull-down's title item.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	NSMenuItem *titleItem = [menu itemAtIndex:0];

	[[PartsLimitManager sharedManager] populateLimitMenu:menu];
	[menu insertItem:titleItem atIndex:0];

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
