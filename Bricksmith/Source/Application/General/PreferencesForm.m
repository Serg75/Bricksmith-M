//==============================================================================
//
// File:		PreferencesForm.m
//
// Purpose:		Builds the panes of the preferences window: titled sections of
//				rows in rounded boxes, with a label on the left of each row and
//				its controls on the right.
//
// Notes:		The pane width is fixed, so every wrapping label is given the
//				width it wraps at when it is made.
//
//==============================================================================
#import "PreferencesForm.h"

const CGFloat PreferencesFormPaneWidth = 540;

// The pane width less the side insets, and that less the row insets.
#define kSectionWidth					(540 - 2 * 20)
#define kRowInnerWidth					(kSectionWidth - 2 * 12)

static const CGFloat kPaneInsetX		= 20;
static const CGFloat kPaneInsetY		= 20;
static const CGFloat kSectionSpacing	= 22;
static const CGFloat kHeaderSpacing		= 6;
static const CGFloat kRowInsetX			= 12;
static const CGFloat kRowInsetY			= 9;
static const CGFloat kRowMinHeight		= 22;
static const CGFloat kRowSpacing		= 16;
static const CGFloat kControlSpacing	= 8;
static const CGFloat kBoxRadius			= 8;
static const CGFloat kAccessoryWidth	= 400;


//========== IsDarkAppearance ==================================================
//
// Purpose:		Says whether an appearance is a dark one.
//
//==============================================================================
static BOOL IsDarkAppearance(NSAppearance *appearance)
{
	NSArray<NSAppearanceName>	*names	= @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua];

	return [[appearance bestMatchFromAppearancesWithNames:names] isEqualToString:NSAppearanceNameDarkAqua];

}//end IsDarkAppearance


//========== NoteLabel =========================================================
//
// Purpose:		A small gray label that wraps at the given width.
//
//==============================================================================
static NSTextField *NoteLabel(NSString *text, CGFloat width)
{
	NSTextField *label = [NSTextField wrappingLabelWithString:text];

	[label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[label setTextColor:[NSColor secondaryLabelColor]];
	[label setSelectable:NO];
	[label setPreferredMaxLayoutWidth:width];
	[label setTranslatesAutoresizingMaskIntoConstraints:NO];

	return label;

}//end NoteLabel


//========== InsetView =========================================================
//
// Purpose:		Wraps a view so it lines up with the text inside the rows.
//
//==============================================================================
static NSView *InsetView(NSView *view)
{
	NSView *container = [[NSView alloc] init];

	[container setTranslatesAutoresizingMaskIntoConstraints:NO];
	[view setTranslatesAutoresizingMaskIntoConstraints:NO];
	[container addSubview:view];

	[NSLayoutConstraint activateConstraints:@[
		[[view leadingAnchor] constraintEqualToAnchor:[container leadingAnchor] constant:kRowInsetX],
		[[view trailingAnchor] constraintLessThanOrEqualToAnchor:[container trailingAnchor] constant:-kRowInsetX],
		[[view topAnchor] constraintEqualToAnchor:[container topAnchor]],
		[[view bottomAnchor] constraintEqualToAnchor:[container bottomAnchor]],
		[[container widthAnchor] constraintEqualToConstant:kSectionWidth],
	]];

	return container;

}//end InsetView


////////////////////////////////////////////////////////////////////////////////
//
// class PreferencesFormBox
//
// Purpose:		The rounded box behind a section's rows, with a thin line
//				between rows.
//
////////////////////////////////////////////////////////////////////////////////
@interface PreferencesFormBox : NSView
{
	NSArray<NSView *> *rows;
}
- (instancetype) initWithRows:(NSArray<NSView *> *)rowsIn;
@end


@implementation PreferencesFormBox

//========== initWithRows: =====================================================
//
// Purpose:		Stacks the rows top to bottom inside the box.
//
//==============================================================================
- (instancetype) initWithRows:(NSArray<NSView *> *)rowsIn
{
	self = [super initWithFrame:NSZeroRect];

	NSLayoutYAxisAnchor *top = [self topAnchor];

	rows = [rowsIn copy];
	[self setTranslatesAutoresizingMaskIntoConstraints:NO];

	for(NSView *row in rows)
	{
		[self addSubview:row];
		[NSLayoutConstraint activateConstraints:@[
			[[row leadingAnchor] constraintEqualToAnchor:[self leadingAnchor]],
			[[row trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]],
			[[row topAnchor] constraintEqualToAnchor:top],
		]];
		top = [row bottomAnchor];
	}
	[[top constraintEqualToAnchor:[self bottomAnchor]] setActive:YES];

	return self;

}//end initWithRows:


//========== isFlipped =========================================================
//
// Purpose:		Rows are measured from the top.
//
//==============================================================================
- (BOOL) isFlipped
{
	return YES;

}//end isFlipped


//========== layout ============================================================
//
// Purpose:		Redraws the row lines after the rows move.
//
//==============================================================================
- (void) layout
{
	[super layout];
	[self setNeedsDisplay:YES];

}//end layout


//========== drawRect: =========================================================
//
// Purpose:		Draws the box and the lines between rows.
//
//==============================================================================
- (void) drawRect:(NSRect)dirtyRect
{
	BOOL			 dark		= IsDarkAppearance([NSAppearance currentDrawingAppearance]);
	CGFloat			 scale		= [[self window] backingScaleFactor] ?: 1;
	CGFloat			 lineWidth	= 1 / scale;
	NSRect			 boxRect	= NSInsetRect([self bounds], lineWidth / 2, lineWidth / 2);
	NSBezierPath	*box		= [NSBezierPath bezierPathWithRoundedRect:boxRect
															   xRadius:kBoxRadius
															   yRadius:kBoxRadius];
	NSColor			*fill		= dark ? [NSColor colorWithWhite:1 alpha:0.05] : [NSColor colorWithWhite:0 alpha:0.03];
	NSColor			*border		= dark ? [NSColor colorWithWhite:1 alpha:0.09] : [NSColor colorWithWhite:0 alpha:0.08];

	[fill setFill];
	[box fill];
	[border setStroke];
	[box setLineWidth:lineWidth];
	[box stroke];

	[[NSColor separatorColor] setFill];
	for(NSUInteger index = 0; index + 1 < [rows count]; index++)
	{
		NSRect lineRect = NSMakeRect(kRowInsetX, NSMaxY([rows[index] frame]) - lineWidth,
									 NSWidth([self bounds]) - 2 * kRowInsetX, lineWidth);

		NSRectFillUsingOperation(lineRect, NSCompositingOperationSourceOver);
	}

}//end drawRect:

@end


////////////////////////////////////////////////////////////////////////////////
//
// class PreferencesFormDocument
//
// Purpose:		The scrolling content of a pane. Flipped so it starts at the
//				top.
//
////////////////////////////////////////////////////////////////////////////////
@interface PreferencesFormDocument : NSView
@end

@implementation PreferencesFormDocument

//========== isFlipped =========================================================
//
// Purpose:		Sections are stacked from the top.
//
//==============================================================================
- (BOOL) isFlipped
{
	return YES;

}//end isFlipped

@end


@implementation PreferencesForm

#pragma mark -
#pragma mark LAYOUT
#pragma mark -

//---------- paneWithSections: ---------------------------------------[static]--
//
// Purpose:		A scrolling pane with the sections stacked top to bottom.
//
//------------------------------------------------------------------------------
+ (NSScrollView *) paneWithSections:(NSArray<NSView *> *)sections
{
	NSStackView				*stack		= [NSStackView stackViewWithViews:sections];
	PreferencesFormDocument	*document	= [[PreferencesFormDocument alloc] init];
	NSScrollView			*scrollView	= [[NSScrollView alloc] init];
	NSClipView				*clipView	= nil;

	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:kSectionSpacing];
	[stack setEdgeInsets:NSEdgeInsetsMake(kPaneInsetY, kPaneInsetX, kPaneInsetY, kPaneInsetX)];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];

	[document setTranslatesAutoresizingMaskIntoConstraints:NO];
	[document addSubview:stack];

	[scrollView setHasVerticalScroller:YES];
	[scrollView setAutohidesScrollers:YES];
	[scrollView setDrawsBackground:NO];
	[scrollView setDocumentView:document];
	[scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
	clipView = [scrollView contentView];

	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[document leadingAnchor]],
		[[stack trailingAnchor] constraintEqualToAnchor:[document trailingAnchor]],
		[[stack topAnchor] constraintEqualToAnchor:[document topAnchor]],
		[[stack bottomAnchor] constraintEqualToAnchor:[document bottomAnchor]],
		[[document leadingAnchor] constraintEqualToAnchor:[clipView leadingAnchor]],
		[[document trailingAnchor] constraintEqualToAnchor:[clipView trailingAnchor]],
		[[document topAnchor] constraintEqualToAnchor:[clipView topAnchor]],
	]];

	return scrollView;

}//end paneWithSections:


//---------- sectionWithTitle:rows:footer: ---------------------------[static]--
//
// Purpose:		A bold title, a box of rows, and a note under the box. The
//				title and the note may be nil.
//
//------------------------------------------------------------------------------
+ (NSView *) sectionWithTitle:(NSString *)title
						 rows:(NSArray<NSView *> *)rows
					   footer:(NSString *)footer
{
	NSStackView			*section	= [[NSStackView alloc] init];
	PreferencesFormBox	*box		= [[PreferencesFormBox alloc] initWithRows:rows];

	[section setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[section setAlignment:NSLayoutAttributeLeading];
	[section setSpacing:kHeaderSpacing];
	[section setTranslatesAutoresizingMaskIntoConstraints:NO];

	if(title != nil)
	{
		NSTextField *header = [NSTextField labelWithString:title];

		[header setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
		[section addArrangedSubview:InsetView(header)];
	}

	[section addArrangedSubview:box];
	[[[box widthAnchor] constraintEqualToConstant:kSectionWidth] setActive:YES];

	if(footer != nil)
		[section addArrangedSubview:InsetView(NoteLabel(footer, kRowInnerWidth))];

	return section;

}//end sectionWithTitle:rows:footer:


//---------- rowWithTitle:control: -----------------------------------[static]--
//
// Purpose:		A row with a label on the left and a control on the right.
//
//------------------------------------------------------------------------------
+ (NSView *) rowWithTitle:(NSString *)title
				  control:(NSView *)control
{
	return [self rowWithTitle:title note:nil control:control noteField:NULL];

}//end rowWithTitle:control:


//---------- rowWithTitle:note:control:noteField: --------------------[static]--
//
// Purpose:		A row with a label on the left, a gray note under the label,
//				and a control on the right.
//
// Notes:		noteField gets the note label, so its text can change later. A
//				note is made, empty, whenever noteField is asked for.
//
//------------------------------------------------------------------------------
+ (NSView *) rowWithTitle:(NSString *)title
					 note:(NSString *)note
				  control:(NSView *)control
				noteField:(NSTextField **)noteField
{
	NSView		*row			= [[NSView alloc] init];
	NSStackView	*texts			= [[NSStackView alloc] init];
	NSTextField	*titleLabel		= [NSTextField labelWithString:title];
	CGFloat		 textWidth		= kRowInnerWidth;

	if(control != nil)
	{
		[control setTranslatesAutoresizingMaskIntoConstraints:NO];
		textWidth -= [control fittingSize].width + kRowSpacing;
	}

	[texts setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[texts setAlignment:NSLayoutAttributeLeading];
	[texts setSpacing:2];
	[texts setTranslatesAutoresizingMaskIntoConstraints:NO];
	[texts addArrangedSubview:titleLabel];

	if(note != nil || noteField != NULL)
	{
		NSTextField *noteLabel = NoteLabel(note ?: @"", textWidth);

		[texts addArrangedSubview:noteLabel];
		if(noteField != NULL)
			*noteField = noteLabel;
	}

	[row setTranslatesAutoresizingMaskIntoConstraints:NO];
	[row addSubview:texts];
	[self pinView:texts inRow:row];
	[[[texts leadingAnchor] constraintEqualToAnchor:[row leadingAnchor] constant:kRowInsetX] setActive:YES];

	if(control != nil)
	{
		[row addSubview:control];
		[self pinView:control inRow:row];
		[NSLayoutConstraint activateConstraints:@[
			[[control trailingAnchor] constraintEqualToAnchor:[row trailingAnchor] constant:-kRowInsetX],
			[[texts trailingAnchor] constraintLessThanOrEqualToAnchor:[control leadingAnchor] constant:-kRowSpacing],
		]];
	}
	else
	{
		[[[texts trailingAnchor] constraintLessThanOrEqualToAnchor:[row trailingAnchor]
														  constant:-kRowInsetX] setActive:YES];
	}

	return row;

}//end rowWithTitle:note:control:noteField:


//---------- rowWithContent: -----------------------------------------[static]--
//
// Purpose:		A row filled by one view, such as a path field and its buttons.
//
//------------------------------------------------------------------------------
+ (NSView *) rowWithContent:(NSView *)content
{
	NSView *row = [[NSView alloc] init];

	[row setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content setTranslatesAutoresizingMaskIntoConstraints:NO];
	[row addSubview:content];
	[self pinView:content inRow:row];
	[NSLayoutConstraint activateConstraints:@[
		[[content leadingAnchor] constraintEqualToAnchor:[row leadingAnchor] constant:kRowInsetX],
		[[content trailingAnchor] constraintEqualToAnchor:[row trailingAnchor] constant:-kRowInsetX],
	]];

	return row;

}//end rowWithContent:


//---------- pinView:inRow: ------------------------------------------[static]--
//
// Purpose:		Centers a view in a row's height and makes the row tall enough
//				for it.
//
// Notes:		The low priority height pulls the row down to its tallest view.
//
//------------------------------------------------------------------------------
+ (void) pinView:(NSView *)view inRow:(NSView *)row
{
	NSLayoutConstraint *shrink = [[row heightAnchor] constraintEqualToConstant:0];

	[shrink setPriority:NSLayoutPriorityFittingSizeCompression];

	[NSLayoutConstraint activateConstraints:@[
		[[view centerYAnchor] constraintEqualToAnchor:[row centerYAnchor]],
		[[view topAnchor] constraintGreaterThanOrEqualToAnchor:[row topAnchor] constant:kRowInsetY],
		[[view bottomAnchor] constraintLessThanOrEqualToAnchor:[row bottomAnchor] constant:-kRowInsetY],
		[[row heightAnchor] constraintGreaterThanOrEqualToConstant:kRowMinHeight + 2 * kRowInsetY],
		shrink,
	]];

}//end pinView:inRow:


//---------- controlGroup: -------------------------------------------[static]--
//
// Purpose:		Lines up controls side by side, centered on one line.
//
//------------------------------------------------------------------------------
+ (NSStackView *) controlGroup:(NSArray<NSView *> *)views
{
	NSStackView *group = [NSStackView stackViewWithViews:views];

	[group setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[group setAlignment:NSLayoutAttributeCenterY];
	[group setSpacing:kControlSpacing];
	[group setTranslatesAutoresizingMaskIntoConstraints:NO];

	return group;

}//end controlGroup:


#pragma mark -
#pragma mark CONTROLS
#pragma mark -

//---------- switchWithTarget:action: --------------------------------[static]--
//
// Purpose:		An on/off switch.
//
//------------------------------------------------------------------------------
+ (NSSwitch *) switchWithTarget:(id)target action:(SEL)action
{
	NSSwitch *toggle = [[NSSwitch alloc] init];

	[toggle setControlSize:NSControlSizeSmall];
	[toggle setTarget:target];
	[toggle setAction:action];

	return toggle;

}//end switchWithTarget:action:


//---------- popUpWithTitles:tags:target:action: ---------------------[static]--
//
// Purpose:		A pop-up menu. Each item carries the tag stored in preferences.
//
//------------------------------------------------------------------------------
+ (NSPopUpButton *) popUpWithTitles:(NSArray<NSString *> *)titles
							   tags:(NSArray<NSNumber *> *)tags
							 target:(id)target
							 action:(SEL)action
{
	NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];

	for(NSUInteger index = 0; index < [titles count]; index++)
	{
		[popUp addItemWithTitle:titles[index]];
		[[popUp lastItem] setTag:[tags[index] integerValue]];
	}
	[popUp setTarget:target];
	[popUp setAction:action];

	return popUp;

}//end popUpWithTitles:tags:target:action:


//---------- numberFieldWithWidth:target:action: ---------------------[static]--
//
// Purpose:		A short field for a number. It acts when editing ends.
//
//------------------------------------------------------------------------------
+ (NSTextField *) numberFieldWithWidth:(CGFloat)width
								target:(id)target
								action:(SEL)action
{
	NSTextField *field = [NSTextField textFieldWithString:@""];

	[field setAlignment:NSTextAlignmentRight];
	[[field cell] setSendsActionOnEndEditing:YES];
	[field setTarget:target];
	[field setAction:action];
	[field setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[[field widthAnchor] constraintEqualToConstant:width] setActive:YES];

	return field;

}//end numberFieldWithWidth:target:action:


//---------- pathFieldWithPlaceholder: -------------------------------[static]--
//
// Purpose:		A field for a file path that stretches to fill its row.
//
//------------------------------------------------------------------------------
+ (NSTextField *) pathFieldWithPlaceholder:(NSString *)placeholder
{
	NSTextField *field = [NSTextField textFieldWithString:@""];

	[field setPlaceholderString:placeholder];
	[[field cell] setScrollable:YES];
	[[field cell] setLineBreakMode:NSLineBreakByClipping];
	[field setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
					  forOrientation:NSLayoutConstraintOrientationHorizontal];
	[field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1
									forOrientation:NSLayoutConstraintOrientationHorizontal];

	return field;

}//end pathFieldWithPlaceholder:


//---------- buttonWithTitle:target:action: --------------------------[static]--
//
// Purpose:		A push button.
//
//------------------------------------------------------------------------------
+ (NSButton *) buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
	return [NSButton buttonWithTitle:title target:target action:action];

}//end buttonWithTitle:target:action:


//---------- sliderWithMinValue:maxValue:target:action: --------------[static]--
//
// Purpose:		A slider of fixed width.
//
//------------------------------------------------------------------------------
+ (NSSlider *) sliderWithMinValue:(double)minValue
						 maxValue:(double)maxValue
						   target:(id)target
						   action:(SEL)action
{
	NSSlider *slider = [NSSlider sliderWithValue:minValue
										minValue:minValue
										maxValue:maxValue
										  target:target
										  action:action];

	[slider setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[[slider widthAnchor] constraintEqualToConstant:160] setActive:YES];

	return slider;

}//end sliderWithMinValue:maxValue:target:action:


//---------- colorWellWithTarget:action: -----------------------------[static]--
//
// Purpose:		A color well.
//
//------------------------------------------------------------------------------
+ (NSColorWell *) colorWellWithTarget:(id)target action:(SEL)action
{
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];

	if(@available(macOS 13.0, *))
		[well setColorWellStyle:NSColorWellStyleMinimal];

	[well setTarget:target];
	[well setAction:action];
	[well setTranslatesAutoresizingMaskIntoConstraints:NO];
	[NSLayoutConstraint activateConstraints:@[
		[[well widthAnchor] constraintEqualToConstant:44],
		[[well heightAnchor] constraintEqualToConstant:24],
	]];

	return well;

}//end colorWellWithTarget:action:


//---------- unitLabelWithString: ------------------------------------[static]--
//
// Purpose:		A gray label for the unit after a number field.
//
//------------------------------------------------------------------------------
+ (NSTextField *) unitLabelWithString:(NSString *)text
{
	NSTextField *label = [NSTextField labelWithString:text];

	[label setTextColor:[NSColor secondaryLabelColor]];

	return label;

}//end unitLabelWithString:


//---------- chooserAccessoryViewWithText: ---------------------------[static]--
//
// Purpose:		A note shown at the bottom of an open panel.
//
// Notes:		Open panels place accessory views by frame, so the view is
//				sized here.
//
//------------------------------------------------------------------------------
+ (NSView *) chooserAccessoryViewWithText:(NSString *)text
{
	NSView		*container	= [[NSView alloc] init];
	NSTextField	*label		= NoteLabel(text, kAccessoryWidth);

	[label setAlignment:NSTextAlignmentCenter];
	[container addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[[label leadingAnchor] constraintEqualToAnchor:[container leadingAnchor] constant:kRowInsetX],
		[[label trailingAnchor] constraintEqualToAnchor:[container trailingAnchor] constant:-kRowInsetX],
		[[label topAnchor] constraintEqualToAnchor:[container topAnchor] constant:kRowInsetY],
		[[label bottomAnchor] constraintEqualToAnchor:[container bottomAnchor] constant:-kRowInsetY],
		[[label widthAnchor] constraintEqualToConstant:kAccessoryWidth],
	]];
	[container setFrameSize:[container fittingSize]];

	return container;

}//end chooserAccessoryViewWithText:

@end
