//==============================================================================
//
// File:		PartReplacementMenu.h
//
// Purpose:		The Replace With menu: the molds, plain part and prints that can
//				take the place of parts, and how each stands against the
//				model's parts limit.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//==============================================================================
#import <Cocoa/Cocoa.h>

@class LDrawDocument;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class PartReplacementMenu
//
////////////////////////////////////////////////////////////////////////////////
@interface PartReplacementMenu : NSObject <NSMenuDelegate>

- (instancetype) initWithDocument:(LDrawDocument *)document;

// A Replace With item for a contextual menu. Its menu fills with the
// document's selected parts as it opens.
- (NSMenuItem *) replaceWithItem;

// Fills the menu with what can replace the parts. Choosing an item replaces
// them, as one undoable edit. The first time, the items may come a moment
// later, while the menu is open.
- (void) fillMenu:(NSMenu *)menu forParts:(NSArray<LDrawPart *> *)parts;

@end

NS_ASSUME_NONNULL_END
