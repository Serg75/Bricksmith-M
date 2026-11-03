//==============================================================================
//
// File:		PartReplacementMenu.m
//
// Purpose:		The Replace With menu: the molds, plain part and prints that can
//				take the place of parts, and how each stands against the
//				model's parts limit.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//==============================================================================
#import "PartReplacementMenu.h"

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawFeatures/LDrawPartReplacements.h>

#import "LDrawDocument.h"
#import "PartBrowserLimitViews.h"
#import "PartsLimitController.h"
#import "PartsLimitManager.h"

// The color swatch beside each item.
static const CGFloat PartReplacementSwatchSize = 12.0;

// Keys of an item's represented object.
static NSString * const PartReplacementKey	= @"replacement";
static NSString * const PartReplacedKey		= @"parts";


@implementation PartReplacementMenu
{
	__weak LDrawDocument	*document;
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
		self->document = aDocument;
	return self;
}


//========== replaceWithItem ===================================================
//==============================================================================
- (NSMenuItem *) replaceWithItem
{
	NSMenuItem	*item	= [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Replace With", nil)
													 action:NULL
											  keyEquivalent:@""];
	NSMenu		*menu	= [[NSMenu alloc] initWithTitle:[item title]];

	[menu setDelegate:self];
	[item setSubmenu:menu];
	return item;

}//end replaceWithItem


#pragma mark -
#pragma mark THE MENU
#pragma mark -

//========== fillMenu:forParts: ================================================
//
// Purpose:		Puts each kind under its heading. With nothing to offer, one
//				dimmed item says so. The first time, the identity map is built
//				off the main thread, and the menu fills once it is ready.
//
//==============================================================================
- (void) fillMenu:(NSMenu *)menu forParts:(NSArray<LDrawPart *> *)parts
{
	PartsLimitController	*limits			= [self->document partsLimitController];
	LDrawPartLimitReport	*report			= [limits report];
	LDrawPartLimitSession	*session		= [[PartsLimitManager sharedManager] session];
	LDrawPartIdentity		*identity		= [session preparedIdentity];
	NSArray					*replacements	= nil;
	NSInteger				 kind			= NSNotFound;
	__weak NSMenu			*weakMenu		= menu;

	[menu removeAllItems];

	if(identity == nil)
	{
		[menu addItemWithTitle:NSLocalizedString(@"Finding Molds and Prints…", nil) action:NULL keyEquivalent:@""];
		[session prepareIdentityThen:^{
			NSMenu *waiting = weakMenu;

			if(waiting != nil)
				[self fillMenu:waiting forParts:parts];
		}];
		return;
	}

	replacements = [LDrawPartReplacements replacementsForParts:parts
														report:report
														 usage:(report != nil) ? [limits usage] : nil
													  identity:identity
												libraryHasPart:[PartsLimitManager libraryHasPartTest]];

	if([replacements count] == 0)
		[menu addItemWithTitle:NSLocalizedString(@"No Molds or Prints", nil) action:NULL keyEquivalent:@""];

	for(LDrawPartReplacement *replacement in replacements)
	{
		if(replacement.kind != kind)
		{
			if(kind != NSNotFound)
				[menu addItem:[NSMenuItem separatorItem]];
			kind = replacement.kind;
			[menu addItem:[self headingForKind:replacement.kind]];
		}
		[menu addItem:[self itemForReplacement:replacement parts:parts table:[report table]]];
	}

}//end fillMenu:forParts:


//========== headingForKind: ===================================================
//==============================================================================
- (NSMenuItem *) headingForKind:(LDrawPartReplacementKind)kind
{
	NSString	*title	= nil;
	NSMenuItem	*item	= nil;

	switch(kind)
	{
		case LDrawPartReplacementKindMold:	title = NSLocalizedString(@"Molds and Alternates", nil);	break;
		case LDrawPartReplacementKindPlain:	title = NSLocalizedString(@"Plain Part", nil);				break;
		case LDrawPartReplacementKindPrint:	title = NSLocalizedString(@"Prints", nil);					break;
	}

	if(@available(macOS 14.0, *))
		return [NSMenuItem sectionHeaderWithTitle:title];

	item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
	[item setEnabled:NO];
	return item;

}//end headingForKind:


//========== itemForReplacement:parts:table: ===================================
//
// Purpose:		The part's number and description, a swatch of the color it
//				would have, and below, how it would stand against the limit.
//				An item that sets a color names it. The item keeps the parts it
//				replaces.
//
//==============================================================================
- (NSMenuItem *) itemForReplacement:(LDrawPartReplacement *)replacement
							  parts:(NSArray<LDrawPart *> *)parts
							  table:(LDrawPartLimitTable *)table
{
	NSString	*number		= [replacement.partName stringByDeletingPathExtension];
	NSString	*what		= [[LDrawPartLibrary sharedPartLibrary] descriptionForPartName:replacement.partName];
	NSString	*title		= [NSString stringWithFormat:@"%@  %@", number, what ?: @""];
	NSString	*line		= nil;
	NSString	*colorName	= nil;
	NSMenuItem	*item		= [[NSMenuItem alloc] initWithTitle:title
														 action:@selector(replaceParts:)
												  keyEquivalent:@""];

	if(table != nil)
		line = [LDrawPartLimitPresentation lineForReplacement:replacement
														table:table
														store:[[PartsLimitManager sharedManager] store]];
	if(replacement.setsColor)
	{
		colorName	= [[[LDrawColorLibrary sharedColorLibrary] colorForCode:replacement.colorCode] localizedName];
		line		= (line != nil) ? [NSString stringWithFormat:@"%@ · %@", colorName, line] : colorName;
	}

	if(replacement.colorCode != LDrawColorBogus && replacement.colorCode != LDrawCurrentColor)
		[item setImage:PartBrowserSwatchImage(replacement.colorCode,
											  NSMakeSize(PartReplacementSwatchSize, PartReplacementSwatchSize),
											  NO, NO)];
	if(line != nil)
	{
		if(@available(macOS 14.4, *))
			[item setSubtitle:line];
		else
			[item setTitle:[NSString stringWithFormat:@"%@ — %@", title, line]];
	}

	[item setTarget:self];
	[item setRepresentedObject:@{PartReplacementKey: replacement, PartReplacedKey: parts}];
	return item;

}//end itemForReplacement:parts:table:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== replaceParts: =====================================================
//
// Purpose:		Swaps the parts the chosen item was made for.
//
//==============================================================================
- (void) replaceParts:(NSMenuItem *)sender
{
	NSDictionary			*choice			= [sender representedObject];
	LDrawPartReplacement	*replacement	= choice[PartReplacementKey];
	LDrawColor				*color			= nil;

	if(replacement.setsColor)
		color = [[LDrawColorLibrary sharedColorLibrary] colorForCode:replacement.colorCode];

	[self->document replaceParts:choice[PartReplacedKey] withPartNamed:replacement.partName color:color];

}//end replaceParts:


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//**** NSMenuDelegate ****
//========== menuNeedsUpdate: ==================================================
//
// Purpose:		A contextual Replace With menu is for the selected parts.
//
//==============================================================================
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	NSMutableArray *parts = [NSMutableArray array];

	for(id object in [self->document selectedObjects])
	{
		if([object isKindOfClass:[LDrawPart class]])
			[parts addObject:object];
	}
	[self fillMenu:menu forParts:parts];

}//end menuNeedsUpdate:


@end
