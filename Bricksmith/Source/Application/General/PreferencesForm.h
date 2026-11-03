//==============================================================================
//
// File:		PreferencesForm.h
//
// Purpose:		Builds the panes of the preferences window: titled sections of
//				rows in rounded boxes, with a label on the left of each row and
//				its controls on the right.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Width of a pane. The window is this wide plus the sidebar.
extern const CGFloat PreferencesFormPaneWidth;


////////////////////////////////////////////////////////////////////////////////
//
// class PreferencesForm
//
////////////////////////////////////////////////////////////////////////////////
@interface PreferencesForm : NSObject

// Layout
+ (NSScrollView *) paneWithSections:(NSArray<NSView *> *)sections;
+ (NSView *) sectionWithTitle:(nullable NSString *)title
						 rows:(NSArray<NSView *> *)rows
					   footer:(nullable NSString *)footer;
+ (NSView *) rowWithTitle:(NSString *)title
				  control:(nullable NSView *)control;
+ (NSView *) rowWithTitle:(NSString *)title
					 note:(nullable NSString *)note
				  control:(nullable NSView *)control
				noteField:(NSTextField * _Nullable * _Nullable)noteField;
+ (NSView *) rowWithContent:(NSView *)content;
+ (NSStackView *) controlGroup:(NSArray<NSView *> *)views;

// A view that holds another with margins around it, for a window or popover
// sized to fit. Use it instead of a stack view's edge insets: once the stack
// holds two or more views, its fitting size leaves out the side insets.
+ (NSView *) containerForView:(NSView *)view margins:(NSEdgeInsets)margins;

// Controls
+ (NSSwitch *) switchWithTarget:(id)target action:(SEL)action;
+ (NSPopUpButton *) popUpWithTitles:(NSArray<NSString *> *)titles
							   tags:(NSArray<NSNumber *> *)tags
							 target:(id)target
							 action:(SEL)action;
+ (NSTextField *) numberFieldWithWidth:(CGFloat)width
								target:(id)target
								action:(SEL)action;
+ (NSTextField *) pathFieldWithPlaceholder:(nullable NSString *)placeholder;
+ (NSButton *) buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
+ (NSSlider *) sliderWithMinValue:(double)minValue
						 maxValue:(double)maxValue
						   target:(id)target
						   action:(SEL)action;
+ (NSColorWell *) colorWellWithTarget:(id)target action:(SEL)action;
+ (NSTextField *) unitLabelWithString:(NSString *)text;
+ (NSView *) chooserAccessoryViewWithText:(NSString *)text;

// Tables
// A table cell holding the field, centered from top to bottom. A table
// stretches a bare field to the row's height, which puts its text at the top.
+ (NSTableCellView *) tableCellWithField:(NSTextField *)field;

@end

NS_ASSUME_NONNULL_END
