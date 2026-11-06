//==============================================================================
//
// File:		PartLibraryController.h
//
// Purpose:		UI layerings on top of LDrawPartLibrary.
//
// Modified:	01/28/2009 Allen Smith. Creation Date.
//
//==============================================================================
#import "PartLibraryController.h"

#import <AMSProgressBar/AMSProgressBar.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawModelManager.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPartOverride.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawEditing/LDrawEditorStrings.h>
#import <LDrawFeatures/LDrawHostKeys.h>
#import <LDrawFeatures/LDrawPartOverridePresentation.h>
#ifdef METAL
#import <LDrawRenderMetal/LDrawRendererMTL.h>
#endif

#import "LDrawDocument.h"

// How long parts are loaded between updates of the progress panel, in seconds.
static const NSTimeInterval ReloadStepDuration = 0.04;

// The most lines of outdated overrides the launch alert shows before it
// scrolls.
static const NSUInteger OutdatedAlertVisibleLines = 10;


@interface PartLibraryController ()
{
	// Set while changed parts are read. A change to the paths meanwhile, or
	// a catalog reload, sets changedPartsPending, and they are checked again
	// before the documents are told.
	BOOL		reloadingChangedParts;
	BOOL		changedPartsPending;

	// Catalog reloads under way. Changed parts are read after them.
	NSUInteger	catalogLoads;

	// Set when the overrides folder was turned on or off, so the Part Browser
	// lists change. They are told with the documents.
	BOOL		catalogListsChanged;
}

- (void) setUsesPartOverrides:(BOOL)flag;
- (void) setPartResolution:(LDrawResolution)newResolution;
- (void) reloadChangedParts;
- (void) finishReloadingChangedParts;

@end


@implementation PartLibraryController

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== init ==============================================================
//
// Purpose:		Initialize a controller for a part library (also initialize the 
//				library itself). 
//
//==============================================================================
- (id) init
{
	self = [super init];
	
	// Create the part library
	LDrawPartLibrary *library = [LDrawPartLibrary sharedPartLibrary];
	[library setCatalogVersion:[LDrawPartLibrary catalogVersionInBundle:[NSBundle mainBundle]]];
	[library setDelegate:self];
	
	return self;

}//end init


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== loadPartCatalog ===================================================
//
// Purpose:		Reads the part catalog out of the LDraw folder. Returns YES upon 
//				success.
//
//==============================================================================
- (void) loadPartCatalog:(void (^)(BOOL success))completionHandler
{
	LDrawPartLibrary *library    = [LDrawPartLibrary sharedPartLibrary];
	NSArray          *favorites  = [[NSUserDefaults standardUserDefaults] objectForKey:FAVORITE_PARTS_KEY];
	BOOL             success     = NO;
	
	// Try loading an existing library first.
	[library setFavorites:favorites];
	success = [library load];
	
	if(success == NO)
	{
		// loading failed; try reloading (generates a new part list)
		[self reloadPartCatalog:completionHandler];
	}
	else if(completionHandler != nil)
	{
		completionHandler(success);
	}
	
}//end loadPartCatalog


//========== reloadPartCatalog =================================================
//
// Purpose:		Scans the contents of the LDraw/ folder and produces a 
//				Mac-friendly index of parts, displaying a progress bar. Then
//				reads again the loaded parts whose files changed.
//
//==============================================================================
- (void) reloadPartCatalog:(void (^)(BOOL success))completionHandler
{
	AMSProgressPanel* progressPanel	= [AMSProgressPanel progressPanel];
	
	self->catalogLoads++;
	[progressPanel setMessage:@"Loading Parts"];
	[progressPanel showProgressPanel];
	
	[[LDrawPartLibrary sharedPartLibrary] reloadPartsWithMaxLoadCountHandler:
	 ^(NSUInteger maxPartCount)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[progressPanel setMaxValue:maxPartCount];
		});
	}
											   progressIncrementHandler:
	 ^{
		dispatch_async(dispatch_get_main_queue(), ^{
			[progressPanel increment];
		});
	}
													  completionHandler:
	 ^(BOOL success)
	 {
		dispatch_async(dispatch_get_main_queue(), ^{
			[progressPanel close];
			self->catalogLoads--;
			if(completionHandler)
			{
				completionHandler(success);
			}
			// After the catalog, so one progress panel shows at a time.
			[self reloadChangedParts];
		});
	}];
	
	// To print out a list of all categories. For debugging !CATEGORY coverage.
//	NSArray *categories = [[[LDrawPartLibrary sharedPartLibrary] categories] sortedArrayUsingSelector:@selector(compare:)];
//	NSMutableString* list = [NSMutableString string];
//	for(NSString* name in categories)
//	{
//		[list appendString:name];
//		[list appendString:@"\n"];
//	}
//	NSLog(@"%@", list);
	
}//end reloadPartCatalog


//========== validateLDrawFolderWithMessage: ===================================
//
// Purpose:		Checks to see that the folder at path is indeed a valid LDraw 
//				folder and contains the vital Parts and P directories.
//
//==============================================================================
- (BOOL) validateLDrawFolderWithMessage:(NSString *) folderPath
{
	BOOL folderIsValid = [[LDrawPaths sharedPaths] validateLDrawFolder:folderPath];
	
	if(folderIsValid == NO)
	{
		NSAlert *error = [[NSAlert alloc] init];
		[error setAlertStyle:NSAlertStyleCritical];
		[error addButtonWithTitle:NSLocalizedString([LDrawEditorStrings okButtonNameKey], nil)];
		
		
		[error setMessageText:NSLocalizedString([LDrawPaths ldrawFolderChooserErrorMessageKey], nil)];
		[error setInformativeText:NSLocalizedString([LDrawPaths ldrawFolderChooserErrorInformativeKey], nil)];
		
		[error runModal];
	}
	
	return folderIsValid;
	
}//end validateLDrawFolder


#pragma mark -
#pragma mark OVERRIDES
#pragma mark -

//========== reportOutdatedPartOverrides =======================================
//
// Purpose:		Warns when the library has a newer version of a part in the
//				overrides folder. Each part is reported once.
//
//==============================================================================
- (void) reportOutdatedPartOverrides
{
	if ([[LDrawPaths sharedPaths] overridesPath] == nil)
		return;

	[LDrawPartOverride readOverridesWithPaths:[LDrawPaths sharedPaths]
							completionHandler:^(NSArray<LDrawPartOverride *> *overrides) {
		NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

		if ([LDrawPartOverridePresentation recordOutdatedOverrides:overrides inDefaults:userDefaults])
			[self showOutdatedPartOverrides:[LDrawPartOverridePresentation outdatedOverrides:overrides]];
	}];

}//end reportOutdatedPartOverrides


//========== showOutdatedPartOverrides: ========================================
//
// Purpose:		Lists every override the library has a newer version of, in a
//				box that scrolls when the list is long.
//
//==============================================================================
- (void) showOutdatedPartOverrides:(NSArray<LDrawPartOverride *> *)outdated
{
	NSAlert		*alert	= [[NSAlert alloc] init];
	NSString	*list	= [LDrawPartOverridePresentation listOfOutdatedOverrides:outdated limit:[outdated count]];

	[alert setMessageText:NSLocalizedString(@"The LDraw library has changed parts you override.", nil)];
	[alert setInformativeText:NSLocalizedString(@"Bricksmith still uses your files. Compare them with the "
												@"library's, then update or remove them.", nil)];
	[alert setAccessoryView:[self listViewWithText:list lineCount:[outdated count]]];
	[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings okButtonNameKey], nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Show Folder", nil)];

	if ([alert runModal] == NSAlertSecondButtonReturn)
		[self showPartOverridesFolder:self];

}//end showOutdatedPartOverrides:


//========== listViewWithText:lineCount: =======================================
//
// Purpose:		A text box an alert can hold. It is as tall as the text, up to
//				OutdatedAlertVisibleLines lines, and scrolls past that.
//
//==============================================================================
- (NSScrollView *) listViewWithText:(NSString *)text lineCount:(NSUInteger)lineCount
{
	NSFont			*font		= [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	NSLayoutManager	*layout		= [[NSLayoutManager alloc] init];
	NSUInteger		 shown		= MIN(MAX(lineCount, 1), OutdatedAlertVisibleLines);
	CGFloat			 height		= ceil(shown * [layout defaultLineHeightForFont:font]) + 8;
	NSScrollView	*scrollView	= [NSTextView scrollableTextView];
	NSTextView		*textView	= [scrollView documentView];

	[scrollView setFrame:NSMakeRect(0, 0, 340, height)];
	[scrollView setBorderType:NSNoBorder];
	[scrollView setDrawsBackground:NO];
	[scrollView setAutohidesScrollers:YES];

	[textView setString:text];
	[textView setFont:font];
	[textView setEditable:NO];
	[textView setDrawsBackground:NO];
	[textView setTextContainerInset:NSMakeSize(0, 4)];

	return scrollView;

}//end listViewWithText:lineCount:


//========== showPartOverridesFolder: ==========================================
//
// Purpose:		Opens the overrides folder in the Finder.
//
//==============================================================================
- (IBAction) showPartOverridesFolder:(id)sender
{
	NSString *folder = [[LDrawPaths sharedPaths] overridesPath];

	if (folder != nil)
		[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:folder isDirectory:YES]];

}//end showPartOverridesFolder:


//========== changePartOverridesFolderPath: ====================================
//
// Purpose:		Uses a new overrides folder, or none for nil. The open models
//				redraw with the parts it changes.
//
//==============================================================================
- (void) changePartOverridesFolderPath:(NSString *)folderPath
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

	if (folderPath != nil)
		[userDefaults setObject:folderPath forKey:PART_OVERRIDES_PATH_KEY];
	else
		[userDefaults removeObjectForKey:PART_OVERRIDES_PATH_KEY];

	[[LDrawPaths sharedPaths] setOverridesPath:folderPath];

	// It lists the parts only the folder has, and reads the changed parts.
	[self reloadPartCatalog:nil];

}//end changePartOverridesFolderPath:


//========== setUsesPartOverrides: =============================================
//
// Purpose:		Turns the overrides folder on or off. The open models redraw
//				with the parts it changes.
//
//==============================================================================
- (void) setUsesPartOverrides:(BOOL)flag
{
	LDrawPaths *paths = [LDrawPaths sharedPaths];

	if (flag == [paths overridesEnabled])
		return;

	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PART_OVERRIDES_ENABLED_KEY];
	[paths setOverridesEnabled:flag];

	// The Part Browser leaves out the parts only the folder has while it is off.
	self->catalogListsChanged = YES;
	[self reloadChangedParts];

}//end setUsesPartOverrides:


//========== toggleUsesPartOverrides: ==========================================
//
// Purpose:		View > Use Part Overrides.
//
//==============================================================================
- (IBAction) toggleUsesPartOverrides:(id)sender
{
	[self setUsesPartOverrides:([[LDrawPaths sharedPaths] overridesEnabled] == NO)];

}//end toggleUsesPartOverrides:


#pragma mark -
#pragma mark RESOLUTION
#pragma mark -

//========== setPartResolution: ================================================
//
// Purpose:		Draws the high, normal or low version of each part that has
//				one. The open models redraw with the parts it changes.
//
//==============================================================================
- (void) setPartResolution:(LDrawResolution)newResolution
{
	LDrawPaths *paths = [LDrawPaths sharedPaths];

	if (newResolution == [paths resolution])
		return;

	[[NSUserDefaults standardUserDefaults] setInteger:newResolution forKey:PART_RESOLUTION_KEY];
	[paths setResolution:newResolution];
	[self reloadChangedParts];

}//end setPartResolution:


//========== chooseResolution: =================================================
//
// Purpose:		View > Resolution. The item's tag is the resolution.
//
//==============================================================================
- (IBAction) chooseResolution:(id)sender
{
	[self setPartResolution:[sender tag]];

}//end chooseResolution:


#pragma mark -
#pragma mark RELOADING PARTS
#pragma mark -

//========== reloadChangedParts ================================================
//
// Purpose:		After a change to the paths, reads again the library parts the
//				open models use that now come from other files, with a progress
//				panel. Then the documents switch to them.
//
// Notes:		The documents are told last. Told first, their next draw reads
//				every part at once and stops the app with no sign of why. Until
//				then they draw the parts they had, which the library keeps.
//
//==============================================================================
- (void) reloadChangedParts
{
	if (self->reloadingChangedParts || self->catalogLoads > 0)
	{
		self->changedPartsPending = YES;
		return;
	}
	self->reloadingChangedParts	= YES;
	self->changedPartsPending	= NO;

	[[LDrawPartLibrary sharedPartLibrary] markPartsWhoseFilesChangedWithCompletionHandler:
	 ^(NSSet<NSString *> *marked)
	{
		NSArray<NSString *>	*partNames	= [self partNamesToReloadFromMarked:marked];
		AMSProgressPanel	*panel		= nil;

		if ([partNames count] == 0)
		{
			[self finishReloadingChangedParts];
			return;
		}

		panel = [AMSProgressPanel progressPanel];
		[panel setMessage:NSLocalizedString(@"Loading Parts", nil)];
		[panel setMaxValue:[partNames count]];
		[panel showProgressPanel];

		[self reloadPartNames:partNames fromIndex:0 panel:panel];
	}];

}//end reloadChangedParts


//========== partNamesToReloadFromMarked: ======================================
//
// Purpose:		The library parts the open models and their peer files use that
//				are marked as changed, or that are not loaded but have a file
//				now, such as a part only a new overrides folder has.
//
//==============================================================================
- (NSArray<NSString *> *) partNamesToReloadFromMarked:(NSSet<NSString *> *)marked
{
	LDrawPartLibrary			*library	= [LDrawPartLibrary sharedPartLibrary];
	LDrawPaths					*paths		= [LDrawPaths sharedPaths];
	NSMutableSet<NSString *>	*used		= [NSMutableSet set];
	NSMutableArray<NSString *>	*partNames	= [NSMutableArray array];

	for (LDrawFile *file in [self openFiles])
		[used unionSet:[LDrawUtilities libraryPartNamesInDirective:file]];

	for (NSString *name in used)
	{
		if (	[marked containsObject:name]
			||	([library modelForNameThreadSafe:name] == nil && [paths pathForPartName:name] != nil) )
		{
			[partNames addObject:name];
		}
	}

	return partNames;

}//end partNamesToReloadFromMarked:


//========== openFiles =========================================================
//
// Purpose:		The open models, and the files they use from beside them.
//
//==============================================================================
- (NSArray<LDrawFile *> *) openFiles
{
	NSMutableArray<LDrawFile *> *files = [NSMutableArray array];

	for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
	{
		if ([document isKindOfClass:[LDrawDocument class]])
			[files addObject:[(LDrawDocument *)document documentContents]];
	}
	[files addObjectsFromArray:[[LDrawModelManager sharedModelManager] peerFiles]];

	return files;

}//end openFiles


//========== reloadPartNames:fromIndex:panel: ==================================
//
// Purpose:		Reads parts and builds what they draw with for a short while,
//				then comes back for the rest after the panel has redrawn.
//
//==============================================================================
- (void) reloadPartNames:(NSArray<NSString *> *)partNames
			   fromIndex:(NSUInteger)start
				   panel:(AMSProgressPanel *)panel
{
	LDrawPartLibrary	*library	= [LDrawPartLibrary sharedPartLibrary];
	NSTimeInterval		 stopTime	= [[NSProcessInfo processInfo] systemUptime] + ReloadStepDuration;
	NSUInteger			 index		= start;

	while (index < [partNames count] && (index == start || [[NSProcessInfo processInfo] systemUptime] < stopTime))
	{
		@autoreleasepool {
			LDrawModel *model = [library freshModelForName:partNames[index]];

#ifdef METAL
			// Builds the smoothed mesh now. OpenGL has no way to draw off
			// screen, so there the views build it when they draw.
			if (model != nil)
				[LDrawRenderer prepareDrawingOfDirective:model];
#else
			(void)model;
#endif
			[panel increment];
		}
		index++;
	}

	if (index >= [partNames count])
	{
		[panel close];
		[self finishReloadingChangedParts];
		return;
	}

	// Async, so the panel redraws before the next step.
	dispatch_async(dispatch_get_main_queue(), ^{
		[self reloadPartNames:partNames fromIndex:index panel:panel];
	});

}//end reloadPartNames:fromIndex:panel:


//========== finishReloadingChangedParts =======================================
//
// Purpose:		Checks again when the paths changed during the reload.
//				Otherwise drops the changed parts no model uses, and tells the
//				documents.
//
//==============================================================================
- (void) finishReloadingChangedParts
{
	self->reloadingChangedParts = NO;

	if (self->changedPartsPending)
	{
		[self reloadChangedParts];
		return;
	}

	[[LDrawPartLibrary sharedPartLibrary] dropStaleParts];
	[self notifyPartsReloaded];

}//end finishReloadingChangedParts


//========== notifyPartsReloaded ===============================================
//
// Purpose:		Has the documents look their library parts up again and redraw.
//				The peer files have no document, so their parts are done here.
//
//==============================================================================
- (void) notifyPartsReloaded
{
	LDrawPartLibrary *library = [LDrawPartLibrary sharedPartLibrary];

	for (LDrawFile *file in [[LDrawModelManager sharedModelManager] peerFiles])
		[LDrawUtilities unresolveLibraryParts:file];

	// Told only now, so the step pictures are not drawn once more with the
	// old parts.
	if (self->catalogListsChanged)
	{
		self->catalogListsChanged = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName:LDrawPartLibraryDidChangeNotification
															object:library];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawPartLibraryReloaded
														object:library];

}//end notifyPartsReloaded


#pragma mark -
#pragma mark MENUS
#pragma mark -

//========== validateMenuItem: =================================================
//
// Purpose:		Checks Use Part Overrides while it is on. It needs a folder.
//				Checks the resolution in use.
//
//==============================================================================
- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	LDrawPaths *paths = [LDrawPaths sharedPaths];

	if ([menuItem action] == @selector(toggleUsesPartOverrides:))
	{
		[menuItem setState:([paths overridesEnabled] ? NSControlStateValueOn : NSControlStateValueOff)];
		return ([paths overridesPath] != nil);
	}

	if ([menuItem action] == @selector(chooseResolution:))
		[menuItem setState:([menuItem tag] == [paths resolution]) ? NSControlStateValueOn : NSControlStateValueOff];

	return YES;

}//end validateMenuItem:


#pragma mark -
#pragma mark PART LIBRARY DELEGATE
#pragma mark -

//========== partLibrary:didChangeFavorites: ===================================
//
// Purpose:		Save new favorites into preferences.
//
//==============================================================================
- (void) partLibrary:(LDrawPartLibrary *)partLibrary didChangeFavorites:(NSArray *)newFavorites
{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	[userDefaults setObject:newFavorites forKey:FAVORITE_PARTS_KEY];
}


@end
