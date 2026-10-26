//==============================================================================
//
// File:		PartBrowserLimitViews.h
//
// Purpose:		The Part Browser's views for the parts limit: the bar over the
//				list, the color strip under the preview, and color swatches.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawCore/LDrawColor.h>

@class LDrawPartBrowserColorChip;

NS_ASSUME_NONNULL_BEGIN

// A color's swatch: a rounded square, with a ring around it or a line
// through it.
NSImage *PartBrowserSwatchImage(LDrawColorT colorCode, NSSize size, BOOL ringed, BOOL struck);


////////////////////////////////////////////////////////////////////////////////
//
// class PartBrowserLimitBar
//
// A line of text over the parts list, and a button at its end.
//
////////////////////////////////////////////////////////////////////////////////
@interface PartBrowserLimitBar : NSView

@property (nonatomic, readonly) NSButton *button;

- (void) setText:(NSString *)text buttonTitle:(nullable NSString *)buttonTitle;

@end


////////////////////////////////////////////////////////////////////////////////
//
// class PartColorStripView
//
// The colors of the selected part, under the preview. A chip that does not
// fit in two rows goes into the menu of a last "+N" chip.
//
////////////////////////////////////////////////////////////////////////////////
@interface PartColorStripView : NSView

@property (nonatomic, weak, nullable) id target;
@property (nonatomic, assign, nullable) SEL action;

// The chip clicked last, for the action.
@property (nonatomic, readonly, nullable) LDrawPartBrowserColorChip *clickedChip;

// Shows the chips. The current color gets a ring; a struck color comes first,
// crossed out, with its tooltip. The strip hides itself when there is nothing
// to show, and sets its own height.
- (void) setChips:(NSArray<LDrawPartBrowserColorChip *> *)chips
	 currentColor:(LDrawColorT)currentColor
	  struckColor:(nullable NSNumber *)struckColor
	struckTooltip:(nullable NSString *)struckTooltip;

@end

NS_ASSUME_NONNULL_END
