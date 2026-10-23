//==============================================================================
//
//  File:       LDrawStepOverlayRenderer.m
//  Package:    LDrawStepRendering
//
//  Purpose:    Draws what a step shows over the model.
//
//  Notes:      Rectangles come from the layout, colors and sizes from the
//              policy and the file. This class only fills, strokes and draws
//              text.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepRendering/LDrawStepOverlayRenderer.h>

#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepCalloutStyle.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>
#import <LDrawStepRendering/LDrawStepCalloutPictureStore.h>

#import "LDrawStepDrawing.h"


/// An arrow's shaft is as thick as the frame's border, but no thinner than
/// this. Its head is sized in multiples of the shaft.
static const CGFloat ARROW_MINIMUM_SHAFT_WIDTH	= 1.5;
static const CGFloat ARROW_HEAD_LENGTH_FACTOR	= 6.0;
static const CGFloat ARROW_HEAD_WIDTH_FACTOR	= 4.5;

/// On the page an arrow's head is as long and as wide as LPub3D prints it, in
/// page inches. Its shaft is as thick as the box's outline, or this thick for
/// a box with none.
static const CGFloat PAGE_ARROW_HEAD_LENGTH		= 5.0 / 16.0;
static const CGFloat PAGE_ARROW_HEAD_WIDTH		= 1.0 / 8.0;
static const CGFloat PAGE_ARROW_SHAFT_WIDTH		= 1.0 / 32.0;

/// A dash is four widths of the line, a dot is one, and a gap is two, as Qt
/// draws them. Each line style is the first few of these.
#define DASH_PATTERN_COUNT 6
static const CGFloat DASH_PATTERN[DASH_PATTERN_COUNT] = { 4.0, 2.0, 1.0, 2.0, 1.0, 2.0 };

/// Blank points around the text of a callout's steps badge.
static const CGFloat STEPS_BADGE_PADDING_X = 5.0;
static const CGFloat STEPS_BADGE_PADDING_Y = 1.0;

/// Blank points around the text of the button that leads back.
static const CGFloat RETURN_BUTTON_PADDING_X = 9.0;
static const CGFloat RETURN_BUTTON_PADDING_Y = 4.0;

/// The strip of a turned view: how far its buttons are from its edge, how far
/// its text is from its left end, and the gaps after the text and between the
/// buttons, in points.
static const CGFloat TURNED_STRIP_INSET			= 4.0;
static const CGFloat TURNED_STRIP_TEXT_INSET	= 12.0;
static const CGFloat TURNED_STRIP_TEXT_GAP		= 10.0;
static const CGFloat TURNED_STRIP_BUTTON_GAP	= 6.0;

/// The line around a badge, a button and a missing part's box.
static const CGFloat HAIRLINE_WIDTH = 1.0;

/// The dashed line around a step being arranged: its width, and its dash and
/// gap, in points.
static const CGFloat ARRANGE_FRAME_WIDTH	= 1.5;
static const CGFloat ARRANGE_FRAME_DASH		= 6.0;
static const CGFloat ARRANGE_FRAME_GAP		= 4.0;

/// The line around the page while a step is arranged, and a guide on the
/// page, in points.
static const CGFloat ARRANGE_EDGE_WIDTH		= 3.0;
static const CGFloat GUIDE_WIDTH			= 1.0;

/// How strongly the previous step's picture shows through.
static const CGFloat GHOST_IMAGE_ALPHA		= 0.35;

/// The outline of the item the arrow keys move: its width, and how far out
/// from the item's frame it runs, in points.
static const CGFloat SELECTION_WIDTH		= 2.0;
static const CGFloat SELECTION_OUTSET		= 2.0;

/// How closely a curve is followed, in pixels. AppKit draws its paths with
/// this value, so a round corner comes out the same in every host.
static const CGFloat CURVE_FLATNESS = 0.6;


//========== StrokeDashedPath ==================================================
///
/// @abstract	Strokes the context's path in one of LPub3D's line styles.
///
//==============================================================================
static void StrokeDashedPath(CGContextRef context, LPubLineStyle lineStyle, CGFloat lineWidth)
{
	CGFloat	lengths[DASH_PATTERN_COUNT]	= { 0.0 };
	size_t	first						= 0;
	size_t	count						= 0;

	switch (lineStyle) {
		case LPubLineStyleDash:
			count = 2;
			break;
		case LPubLineStyleDot:
			first = 2;
			count = 2;
			break;
		case LPubLineStyleDashDot:
			count = 4;
			break;
		case LPubLineStyleDashDotDot:
			count = 6;
			break;
		default:
			break;
	}

	for (size_t index = 0; index < count; index++) {
		lengths[index] = DASH_PATTERN[first + index] * lineWidth;
	}

	if (count > 0) {
		CGContextSetLineDash(context, 0.0, lengths, count);
	}

	CGContextSetLineWidth(context, lineWidth);
	CGContextStrokePath(context);

}//end StrokeDashedPath


//========== DrawFrame =========================================================
///
/// @abstract	Draws a frame: its fill, then its outline in one of LPub3D's
///				line styles. A NULL fill or a line of no width draws nothing for
///				that part.
///
/// @discussion	Inset by half the line, so the outline is drawn inside the
///				frame.
///
//==============================================================================
static void DrawFrame(CGContextRef context, CGRect frameRect, CGColorRef _Nullable fill, const double *borderRGBA,
					  CGFloat lineWidth, CGFloat radius, LPubLineStyle lineStyle)
{
	CGRect inset = CGRectInset(frameRect, lineWidth / 2.0, lineWidth / 2.0);

	if (fill != NULL) {
		LDrawStepSetColor(context, fill);
		LDrawStepAddRoundedRect(context, inset, radius);
		CGContextFillPath(context);
	}

	if (lineWidth <= 0.0 || lineStyle == LPubLineStyleNone) {
		return;
	}

	CGContextSaveGState(context);

	LDrawStepSetRGBA(context, borderRGBA);
	LDrawStepAddRoundedRect(context, inset, radius);
	StrokeDashedPath(context, lineStyle, lineWidth);

	CGContextRestoreGState(context);

}//end DrawFrame


//========== FontCreateForText =================================================
///
/// @abstract	The font a file names for some text, at a size in points.
///
//==============================================================================
static LDrawStepFont FontCreateForText(LDrawStepCalloutText *text, CGFloat size)
{
	return LDrawStepFontCreateOfFamily(text.fontFamily, text.isBold, text.isItalic, size);

}//end FontCreateForText


//========== DrawStyledText ====================================================
///
/// @abstract	Draws one line in the font and color a file names, in the middle
///				of a rect. The font's size is in page inches.
///
//==============================================================================
static void DrawStyledText(CGContextRef context, NSString *string, CGRect rect, LDrawStepCalloutText *text,
						   double pointsPerPageInch)
{
	LDrawStepFont	font	= FontCreateForText(text, text.fontSize * pointsPerPageInch);
	double			rgba[4];

	LPubColorComponentsGetRGBA(text.color, rgba);

	LDrawStepDrawTextCentered(context, string, rect, font, rgba);
	LDrawStepFontRelease(font);

}//end DrawStyledText


//========== DrawPill ==========================================================
///
/// @abstract	Draws an outlined pill with one line of text in its middle. The
///				badges and the button that leads back are drawn this way.
///				With no fill, only the outline and the text are drawn.
///
//==============================================================================
static void DrawPill(CGContextRef context, CGRect rect, NSString *text, LDrawStepFont font,
					 CGColorRef _Nullable fill, const double *borderRGBA, const double *textRGBA)
{
	// Stroked on the half-point, so a one-point outline is crisp.
	CGRect	inset	= CGRectInset(rect, HAIRLINE_WIDTH / 2.0, HAIRLINE_WIDTH / 2.0);
	CGFloat	radius	= CGRectGetHeight(rect) / 2.0;

	if (fill != NULL) {
		LDrawStepSetColor(context, fill);
		LDrawStepAddRoundedRect(context, inset, radius);
		CGContextFillPath(context);
	}

	LDrawStepSetRGBA(context, borderRGBA);
	LDrawStepAddRoundedRect(context, inset, radius);
	CGContextSetLineWidth(context, HAIRLINE_WIDTH);
	CGContextStrokePath(context);

	LDrawStepDrawTextCentered(context, text, rect, font, textRGBA);

}//end DrawPill


//========== DrawBadge =========================================================
///
/// @abstract	Draws a pill with text in the colors of a badge style.
///
//==============================================================================
static void DrawBadge(CGContextRef context, CGRect rect, NSString *text, LDrawStepFont font,
					  LDrawStepPartListBadgeStyle style)
{
	CGColorRef fill = LDrawStepColorCreateRGBA(style.fillRGBA);

	DrawPill(context, rect, text, font, fill, style.borderRGBA, style.textRGBA);
	CGColorRelease(fill);

}//end DrawBadge


//========== ReturnButtonFontCreate ============================================
///
/// @abstract	The font of the button that leads back. The button is part of
///				the window, not of the page, so it has one size at any zoom.
///
//==============================================================================
static LDrawStepFont ReturnButtonFontCreate(void)
{
	LDrawStepPartListChrome chrome = [LDrawStepPartListPolicy defaultChrome];

	return LDrawStepFontCreateSystem(chrome.labelPointSize, LDrawStepFontWeightMedium);

}//end ReturnButtonFontCreate


/// Where the parts of the turned view's strip go, in the view.
typedef struct TurnedViewStripLayout {
	CGRect	strip;
	CGRect	text;
	CGRect	useAngle;
	CGRect	stepAngle;
} TurnedViewStripLayout;


@implementation LDrawStepOverlayRenderer


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_overflowFormat	= @"+%lu";
		self->_stepCountFormat	= @"%lu";
	}
	return self;

}//end init


//========== dealloc ===========================================================
- (void) dealloc
{
	CGColorRelease(self->_listBackgroundColor);
	CGColorRelease(self->_pinColor);
	CGColorRelease(self->_arrangeFrameColor);
	CGColorRelease(self->_guideColor);
	CGColorRelease(self->_ghostColor);
	CGColorRelease(self->_selectionColor);
	CGImageRelease(self->_ghostImage);

}//end dealloc


// MARK: - ACCESSORS -


//========== setListBackgroundColor: ===========================================
- (void) setListBackgroundColor:(nullable CGColorRef)color
{
	CGColorRetain(color);
	CGColorRelease(self->_listBackgroundColor);
	self->_listBackgroundColor = color;

}//end setListBackgroundColor:


//========== setPinColor: ======================================================
- (void) setPinColor:(nullable CGColorRef)color
{
	CGColorRetain(color);
	CGColorRelease(self->_pinColor);
	self->_pinColor = color;

}//end setPinColor:


//========== setArrangeFrameColor: =============================================
- (void) setArrangeFrameColor:(nullable CGColorRef)color
{
	CGColorRetain(color);
	CGColorRelease(self->_arrangeFrameColor);
	self->_arrangeFrameColor = color;

}//end setArrangeFrameColor:


//========== setGuideColor: ====================================================
- (void) setGuideColor:(nullable CGColorRef)color
{
	CGColorRetain(color);
	CGColorRelease(self->_guideColor);
	self->_guideColor = color;

}//end setGuideColor:


//========== setGhostColor: ====================================================
- (void) setGhostColor:(nullable CGColorRef)color
{
	CGColorRetain(color);
	CGColorRelease(self->_ghostColor);
	self->_ghostColor = color;

}//end setGhostColor:


//========== setGhostImage: ====================================================
- (void) setGhostImage:(nullable CGImageRef)image
{
	CGImageRetain(image);
	CGImageRelease(self->_ghostImage);
	self->_ghostImage = image;

}//end setGhostImage:


//========== setSelectionColor: ================================================
- (void) setSelectionColor:(nullable CGColorRef)color
{
	CGColorRetain(color);
	CGColorRelease(self->_selectionColor);
	self->_selectionColor = color;

}//end setSelectionColor:


//========== chrome ============================================================
- (LDrawStepPartListChrome) chrome
{
	return (self.presentation != nil) ? self.presentation.chrome : [LDrawStepPartListPolicy defaultChrome];

}//end chrome


//========== calloutChrome =====================================================
- (LDrawStepPartListChrome) calloutChrome
{
	return (self.presentation != nil) ? self.presentation.calloutChrome : [LDrawStepPartListPolicy defaultChrome];

}//end calloutChrome


// MARK: - THE PAGE AND THE FRAME -


//========== drawPageAndFrameInContext:viewSize: ===============================
- (void) drawPageAndFrameInContext:(CGContextRef)context viewSize:(Size2)viewSize
{
	CGContextSaveGState(context);
	CGContextSetFlatness(context, CURVE_FLATNESS);

	[self drawPageSurroundInContext:context viewSize:viewSize];
	[self drawGhostInContext:context];
	[self drawPageNumberInContext:context];
	[self drawListFrameInContext:context];

	CGContextRestoreGState(context);

}//end drawPageAndFrameInContext:viewSize:


//========== drawPageSurroundInContext:viewSize: ===============================
///
/// @abstract	Dims what falls outside the page LPub3D would print this step
///				on, which shows where the paper ends.
///
//==============================================================================
- (void) drawPageSurroundInContext:(CGContextRef)context viewSize:(Size2)viewSize
{
	CGRect					pageRect	= LDrawStepRectFromBox(self.presentation.pageRect);
	LDrawStepPartListChrome	chrome		= [self chrome];

	if (CGRectIsEmpty(pageRect)) {
		return;
	}

	// The whole view with the page cut out of it, which is what the even-odd
	// rule does with two nested rectangles.
	LDrawStepSetRGBA(context, chrome.pageSurroundRGBA);
	CGContextAddRect(context, CGRectMake(0.0, 0.0, viewSize.width, viewSize.height));
	CGContextAddRect(context, pageRect);
	CGContextEOFillPath(context);

}//end drawPageSurroundInContext:viewSize:


//========== drawGhostInContext: ===============================================
///
/// @abstract	Shows where the previous step's assembly sat, so the step can be
///				lined up with it: its picture, faintly, or else its outline
///				filled.
///
//==============================================================================
- (void) drawGhostInContext:(CGContextRef)context
{
	const Point2	*point	= self.ghostOutline.bytes;
	NSUInteger		 count	= self.ghostOutline.length / sizeof(Point2);
	CGRect			 rect	= LDrawStepRectFromBox(self.ghostRect);

	if (self.ghostImage != NULL && CGRectIsEmpty(rect) == NO) {
		CGContextSaveGState(context);
		CGContextSetAlpha(context, GHOST_IMAGE_ALPHA);
		LDrawStepDrawImage(context, self.ghostImage, rect);
		CGContextRestoreGState(context);
		return;
	}

	if (count < 3 || self.ghostColor == NULL) {
		return;
	}

	CGContextSaveGState(context);

	CGContextMoveToPoint(context, point[0].x, point[0].y);
	for (NSUInteger index = 1; index < count; index++) {
		CGContextAddLineToPoint(context, point[index].x, point[index].y);
	}
	CGContextClosePath(context);

	LDrawStepSetColor(context, self.ghostColor);
	CGContextFillPath(context);

	CGContextRestoreGState(context);

}//end drawGhostInContext:


//========== drawPageNumberInContext: ==========================================
///
/// @abstract	Writes the page's number in the file's font and color, in the
///				middle of the room the presentation keeps for it.
///
//==============================================================================
- (void) drawPageNumberInContext:(CGContextRef)context
{
	LDrawStepPartListPresentation *presentation = self.presentation;

	if (presentation.pageNumber == nil) {
		return;
	}

	DrawStyledText(context, presentation.pageNumber, LDrawStepRectFromBox(presentation.pageNumberRect),
				   presentation.pageNumberText, presentation.pointsPerPageInch);

}//end drawPageNumberInContext:


//========== drawListFrameInContext: ===========================================
///
/// @abstract	Draws the parts list's background, border and pins, as the
///				chrome says. On the page these are the file's.
///
/// @discussion	The host's icons cover the icon area and are drawn on the same
///				color, so this fill only shows in the padding.
///
//==============================================================================
- (void) drawListFrameInContext:(CGContextRef)context
{
	CGRect frameRect = LDrawStepRectFromBox(self.presentation.frameRect);

	if (CGRectIsEmpty(frameRect)) {
		return;
	}

	LDrawStepPartListChrome	chrome	= [self chrome];
	CGColorRef				fill	= NULL;

	if (chrome.fill == LDrawStepPartListFillHost) {
		fill = CGColorRetain(self.listBackgroundColor);
	}
	else if (chrome.fill == LDrawStepPartListFillColor) {
		fill = LDrawStepColorCreateRGBA(chrome.fillRGBA);
	}

	DrawFrame(context, frameRect, fill, chrome.borderRGBA, chrome.borderWidth, chrome.cornerRadius,
			  chrome.borderLineStyle);
	CGColorRelease(fill);

	[self drawPinForAxis:LPubPliAxisWidth inContext:context];
	[self drawPinForAxis:LPubPliAxisHeight inContext:context];

	if (self.presentation.placementPinned) {
		[self drawPin:self.presentation.placementPinRect inContext:context];
	}

}//end drawListFrameInContext:


//========== drawPlainFrame:inContext: =========================================
///
/// @abstract	Draws a callout's box off the page the way the list's frame is
///				drawn there: the list's background inside the chrome's border.
///
//==============================================================================
- (void) drawPlainFrame:(CGRect)frameRect inContext:(CGContextRef)context
{
	LDrawStepPartListChrome chrome = [self calloutChrome];

	DrawFrame(context, frameRect, self.listBackgroundColor, chrome.borderRGBA, chrome.borderWidth,
			  chrome.cornerRadius, LPubLineStyleSolid);

}//end drawPlainFrame:inContext:


//========== drawPinForAxis:inContext: =========================================
///
/// @abstract	Draws the pin that marks an axis whose size this step sets
///				itself.
///
//==============================================================================
- (void) drawPinForAxis:(LPubPliAxis)axis inContext:(CGContextRef)context
{
	LDrawStepPartListPresentation	*presentation	= self.presentation;
	BOOL							 isPinned		= (axis == LPubPliAxisWidth) ? presentation.widthPinned
																				 : presentation.heightPinned;

	if (isPinned) {
		[self drawPin:[presentation pinRectForAxis:axis] inContext:context];
	}

}//end drawPinForAxis:inContext:


//========== drawPin:inContext: ================================================
- (void) drawPin:(Box2)pin inContext:(CGContextRef)context
{
	if (self.pinColor == NULL) {
		return;
	}

	LDrawStepSetColor(context, self.pinColor);
	LDrawStepAddOval(context, CGRectInset(LDrawStepRectFromBox(pin), 1.0, 1.0));
	CGContextFillPath(context);

}//end drawPin:inContext:


// MARK: - A LIST'S LABELS -


//---------- drawLabelsOfLayout:chrome:contentWidth:overflowFormat:inContext: --
+ (void) drawLabelsOfLayout:(LDrawStepPartListLayout *)layout
					 chrome:(LDrawStepPartListChrome)chrome
			   contentWidth:(double)contentWidth
			 overflowFormat:(NSString *)overflowFormat
				  inContext:(CGContextRef)context
{
	[self drawLabelsOfLayout:layout
					  chrome:chrome
				   countText:nil
			  annotationText:nil
				contentWidth:contentWidth
			  overflowFormat:overflowFormat
				   inContext:context];

}//end drawLabelsOfLayout:chrome:contentWidth:overflowFormat:inContext:


//---------- drawLabelsOfLayout:chrome:countText:... -----------------[static]--
+ (void) drawLabelsOfLayout:(LDrawStepPartListLayout *)layout
					 chrome:(LDrawStepPartListChrome)chrome
				  countText:(nullable LDrawStepCalloutText *)countText
			 annotationText:(nullable LDrawStepCalloutText *)annotationText
			   contentWidth:(double)contentWidth
			 overflowFormat:(NSString *)overflowFormat
				  inContext:(CGContextRef)context
{
	CGContextSaveGState(context);
	CGContextSetFlatness(context, CURVE_FLATNESS);

	// Every count and badge of a list is written the same, so each font is
	// made once.
	CGFloat			size		= chrome.labelPointSize;
	LDrawStepFont	countFont	= (countText != nil) ? FontCreateForText(countText, size)
												 : LDrawStepFontCreateSystem(size, LDrawStepFontWeightBold);
	LDrawStepFont	badgeFont	= (annotationText != nil)
									? FontCreateForText(annotationText, chrome.annotationPointSize)
									: LDrawStepFontCreateSystem(size, LDrawStepFontWeightMedium);

	for (LDrawStepPartListPlacement *placement in layout.placements) {

		if ([LDrawStepPartListModelBuilder isDrawablePlacement:placement] == NO) {
			[self drawPlaceholderInRect:LDrawStepRectFromBox(placement.iconFrame) chrome:chrome inContext:context];
		}

		[self drawAnnotationForPlacement:placement chrome:chrome font:badgeFont inContext:context];

		if (placement.showsCount == NO) {
			continue;
		}

		// The file's font is not cut short, as LPub3D does not cut it.
		NSString	*text	= [LDrawStepPartListLayout quantityTextForQuantity:placement.entry.quantity];
		CGRect		 rect	= LDrawStepRectFromBox(placement.labelFrame);

		if (countText != nil) {
			LDrawStepDrawTextCentered(context, text, rect, countFont, chrome.labelRGBA);
		}
		else {
			LDrawStepDrawTextInRect(context, text, rect, countFont, chrome.labelRGBA);
		}
	}

	LDrawStepFontRelease(countFont);
	LDrawStepFontRelease(badgeFont);

	// The notice goes along the top, where the dropped rows would have been.
	if (layout.overflowCount > 0) {
		NSString		*text	= [NSString stringWithFormat:overflowFormat, (unsigned long)layout.overflowCount];
		LDrawStepFont	 font	= LDrawStepFontCreateSystem(chrome.labelPointSize, LDrawStepFontWeightRegular);
		Box2			 box	= [LDrawStepPartListPolicy overflowNoticeRectForContentWidth:contentWidth
																			   chrome:chrome];

		LDrawStepDrawTextInRect(context, text, LDrawStepRectFromBox(box), font, chrome.labelRGBA);
		LDrawStepFontRelease(font);
	}

	CGContextRestoreGState(context);

}//end drawLabelsOfLayout:chrome:countText:annotationText:contentWidth:overflowFormat:inContext:


//---------- drawPlaceholderInRect:chrome:inContext: -----------------[static]--
///
/// @abstract	Draws a dashed box in place of a part that could not be found.
///				It shows that a part belongs there.
///
//------------------------------------------------------------------------------
+ (void) drawPlaceholderInRect:(CGRect)rect chrome:(LDrawStepPartListChrome)chrome inContext:(CGContextRef)context
{
	if (CGRectIsEmpty(rect)) {
		return;
	}

	CGFloat pattern[2] = { chrome.placeholderDashLength, chrome.placeholderGapLength };

	CGContextSaveGState(context);

	LDrawStepSetRGBA(context, chrome.borderRGBA);
	CGContextAddRect(context, CGRectInset(rect, 1.0, 1.0));
	CGContextSetLineWidth(context, HAIRLINE_WIDTH);
	CGContextSetLineDash(context, 0.0, pattern, 2);
	CGContextStrokePath(context);

	CGContextRestoreGState(context);

}//end drawPlaceholderInRect:chrome:inContext:


//---------- drawAnnotationForPlacement:chrome:font:inContext: -------[static]--
///
/// @abstract	Draws the part's size in studs as a badge, in `font`.
///
/// @discussion	Long thin parts look alike, so the size tells them apart. A
///				part drawn at reduced scale gets the marker color.
///
//------------------------------------------------------------------------------
+ (void) drawAnnotationForPlacement:(LDrawStepPartListPlacement *)placement
							 chrome:(LDrawStepPartListChrome)chrome
							   font:(LDrawStepFont)font
						  inContext:(CGContextRef)context
{
	NSString *text = placement.annotationText;

	if (text == nil || CGRectIsEmpty(LDrawStepRectFromBox(placement.annotationFrame))) {
		return;
	}

	LDrawStepPartListBadgeStyle	style	= [LDrawStepPartListPolicy badgeStyleForScaledDownPart:placement.isScaledDown
																						chrome:chrome];

	CGSize	textSize	= LDrawStepTextSize(text, font);
	Box2	badgeBox	= [LDrawStepPartListLayout badgeRectForTextSize:V2MakeSize(textSize.width, textSize.height)
															 inSlot:placement.annotationFrame];

	DrawBadge(context, LDrawStepRectFromBox(badgeBox), text, font, style);

}//end drawAnnotationForPlacement:chrome:font:inContext:


// MARK: - CALLOUTS -


//========== drawCalloutsInContext:viewSize: ===================================
///
/// @abstract	Draws each callout's arrows, then its box, then the button that
///				leads back.
///
/// @discussion	Every arrow first, so a box covers the place its arrows leave
///				from, and no arrow crosses another box.
///
//==============================================================================
- (void) drawCalloutsInContext:(CGContextRef)context viewSize:(Size2)viewSize
{
	NSArray<LDrawStepCalloutBox *>	*boxes	= self.presentation.calloutBoxes;
	NSArray<NSData *>				*arrows	= self.calloutArrows;

	CGContextSaveGState(context);
	CGContextSetFlatness(context, CURVE_FLATNESS);

	for (NSUInteger index = 0; index < boxes.count && index < arrows.count; index++) {
		const LDrawStepCalloutArrow	*ofBox	= arrows[index].bytes;
		NSUInteger					 count	= arrows[index].length / sizeof(LDrawStepCalloutArrow);

		for (NSUInteger arrowIndex = 0; arrowIndex < count; arrowIndex++) {
			[self drawArrow:ofBox[arrowIndex] ofBox:boxes[index] inContext:context];
		}
	}

	for (LDrawStepCalloutBox *box in boxes) {
		[self drawCalloutBox:box inContext:context];
	}

	[self drawSelectionInContext:context];
	[self drawGuidesInContext:context];
	[self drawArrangeFrameInContext:context];
	[self drawArrangeEdgeInContext:context viewSize:viewSize];
	[self drawReturnButtonInContext:context viewSize:viewSize];
	[self drawTurnedViewStripInContext:context viewSize:viewSize];

	CGContextRestoreGState(context);

}//end drawCalloutsInContext:viewSize:


//========== drawSelectionInContext: ===========================================
///
/// @abstract	Outlines the item the arrow keys move, just outside its frame.
///
//==============================================================================
- (void) drawSelectionInContext:(CGContextRef)context
{
	CGRect rect = LDrawStepRectFromBox(self.selectionRect);

	if (self.selectionColor == NULL || CGRectIsEmpty(rect)) {
		return;
	}

	CGContextSaveGState(context);

	LDrawStepSetColor(context, self.selectionColor);
	CGContextSetLineWidth(context, SELECTION_WIDTH);
	CGContextStrokeRect(context, CGRectInset(rect, -SELECTION_OUTSET, -SELECTION_OUTSET));

	CGContextRestoreGState(context);

}//end drawSelectionInContext:


//========== drawArrangeFrameInContext: ========================================
///
/// @abstract	Draws a dashed line a little outside the step while it is
///				arranged, so it is plain that a move of the camera moves the
///				step. Its corners that move as the step grows get a handle:
///				a white square, edged in the frame's color.
///
//==============================================================================
- (void) drawArrangeFrameInContext:(CGContextRef)context
{
	LDrawStepPartListPresentation	*presentation	= self.presentation;
	CGRect							 frameRect		= LDrawStepRectFromBox(presentation.arrangeFrameRect);
	CGFloat							 pattern[2]		= { ARRANGE_FRAME_DASH, ARRANGE_FRAME_GAP };

	if (self.arrangeFrameColor == NULL || CGRectIsEmpty(frameRect)) {
		return;
	}

	CGContextSaveGState(context);

	LDrawStepSetColor(context, self.arrangeFrameColor);
	CGContextAddRect(context, frameRect);
	CGContextSetLineWidth(context, ARRANGE_FRAME_WIDTH);
	CGContextSetLineDash(context, 0.0, pattern, 2);
	CGContextStrokePath(context);

	CGContextSetLineDash(context, 0.0, NULL, 0);
	CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);

	for (LDrawStepArrangeHandle handle = LDrawStepArrangeHandleTopLeft;
		 handle <= LDrawStepArrangeHandleBottomLeft;
		 handle++) {
		CGRect handleRect = LDrawStepRectFromBox([presentation rectOfArrangeHandle:handle]);

		if (CGRectIsEmpty(handleRect) == NO) {
			CGContextAddRect(context, handleRect);
		}
	}

	CGContextDrawPath(context, kCGPathFillStroke);

	CGContextRestoreGState(context);

}//end drawArrangeFrameInContext:


//========== drawGuidesInContext: ==============================================
///
/// @abstract	Draws the guides on the page, such as the middle lines and
///				margins the arranged step or a dragged list meets, as thin
///				lines.
///
//==============================================================================
- (void) drawGuidesInContext:(CGContextRef)context
{
	const Box2	*lines	= self.guides.bytes;
	NSUInteger	 count	= self.guides.length / sizeof(Box2);

	if (self.guideColor == NULL || count == 0) {
		return;
	}

	CGContextSaveGState(context);

	LDrawStepSetColor(context, self.guideColor);
	CGContextSetLineWidth(context, GUIDE_WIDTH);

	for (NSUInteger index = 0; index < count; index++) {
		Box2 line = lines[index];

		CGContextMoveToPoint(context, line.origin.x, line.origin.y);
		CGContextAddLineToPoint(context, V2BoxMaxX(line), V2BoxMaxY(line));
	}

	CGContextStrokePath(context);
	CGContextRestoreGState(context);

}//end drawGuidesInContext:


//========== drawArrangeEdgeInContext:viewSize: ================================
///
/// @abstract	Draws a line just outside the page while a step is arranged, so
///				the page says the camera moves the step on it.
///
/// @discussion	Where the page runs past the view, the line runs along the
///				inside of the part the scroll bars leave instead.
///
//==============================================================================
- (void) drawArrangeEdgeInContext:(CGContextRef)context viewSize:(Size2)viewSize
{
	CGFloat	half	= ARRANGE_EDGE_WIDTH / 2.0;
	CGRect	shown	= LDrawStepRectFromBox(self.unobscuredRect);
	CGRect	page	= LDrawStepRectFromBox(self.presentation.pageRect);

	if (CGRectIsEmpty(shown)) {
		shown = CGRectMake(0.0, 0.0, viewSize.width, viewSize.height);
	}

	CGRect	edge	= CGRectIntersection(CGRectInset(page, -half, -half), CGRectInset(shown, half, half));

	if (self.arrangeFrameColor == NULL || CGRectIsEmpty(page) || CGRectIsEmpty(edge)) {
		return;
	}

	CGContextSaveGState(context);

	LDrawStepSetColor(context, self.arrangeFrameColor);
	CGContextSetLineWidth(context, ARRANGE_EDGE_WIDTH);
	CGContextStrokeRect(context, edge);

	CGContextRestoreGState(context);

}//end drawArrangeEdgeInContext:viewSize:


//========== drawArrow:ofBox:inContext: ========================================
///
/// @abstract	Draws one arrow of a box.
///
//==============================================================================
- (void) drawArrow:(LDrawStepCalloutArrow)arrow ofBox:(LDrawStepCalloutBox *)box inContext:(CGContextRef)context
{
	LDrawStepPartListChrome	 chrome		= [self calloutChrome];
	LDrawStepCalloutStyle	*style		= box.style;
	CGFloat					 shaftWidth	= MAX(ARROW_MINIMUM_SHAFT_WIDTH, chrome.borderWidth);
	CGFloat					 headLength	= shaftWidth * ARROW_HEAD_LENGTH_FACTOR;
	CGFloat					 headWidth	= shaftWidth * ARROW_HEAD_WIDTH_FACTOR;
	CGFloat					 dx			= arrow.tip.x - arrow.start.x;
	CGFloat					 dy			= arrow.tip.y - arrow.start.y;
	CGFloat					 length		= hypot(dx, dy);

	if (length <= 0.0) {
		return;
	}

	// The round end of the shaft is for this arrow alone.
	CGContextSaveGState(context);

	// On the page an arrow is drawn in the color of its box's outline.
	if (style != nil) {
		CGFloat scale		= self.presentation.pointsPerPageInch;
		CGFloat thickness	= (style.borderThickness > 0.0) ? style.borderThickness : PAGE_ARROW_SHAFT_WIDTH;

		shaftWidth	= thickness * scale;
		headLength	= style.hidesArrowTips ? 0.0 : PAGE_ARROW_HEAD_LENGTH * scale;
		headWidth	= PAGE_ARROW_HEAD_WIDTH * scale;

		LDrawStepSetColorComponents(context, style.borderColor);
	}
	else {
		LDrawStepSetRGBA(context, chrome.borderRGBA);
	}

	// A short arrow gets a head as long as itself, in the same shape.
	if (headLength > length) {
		headWidth	*= length / headLength;
		headLength	= length;
	}

	// One step along the arrow, and one across it.
	CGFloat	alongX	= dx / length;
	CGFloat	alongY	= dy / length;
	CGPoint	neck	= CGPointMake(arrow.tip.x - alongX * headLength, arrow.tip.y - alongY * headLength);

	CGContextMoveToPoint(context, arrow.start.x, arrow.start.y);
	CGContextAddLineToPoint(context, neck.x, neck.y);
	CGContextSetLineWidth(context, shaftWidth);
	CGContextSetLineCap(context, kCGLineCapRound);
	CGContextStrokePath(context);

	if (headLength > 0.0) {
		CGContextMoveToPoint(context, arrow.tip.x, arrow.tip.y);
		CGContextAddLineToPoint(context, neck.x - alongY * headWidth / 2.0, neck.y + alongX * headWidth / 2.0);
		CGContextAddLineToPoint(context, neck.x + alongY * headWidth / 2.0, neck.y - alongX * headWidth / 2.0);
		CGContextClosePath(context);
		CGContextFillPath(context);
	}

	CGContextRestoreGState(context);

}//end drawArrow:ofBox:inContext:


//========== drawCalloutBox:inContext: =========================================
///
/// @abstract	Draws one callout: its box, the lines between groups of steps,
///				its pictures, and the counts and parts that go over them.
///
//==============================================================================
- (void) drawCalloutBox:(LDrawStepCalloutBox *)box inContext:(CGContextRef)context
{
	LDrawStepCalloutStyle *style = box.style;

	if (style != nil) {
		[self drawFrameOfCalloutBox:box style:style inContext:context];
		LDrawStepSetColorComponents(context, style.separatorColor);
	}
	else {
		[self drawPlainFrame:LDrawStepRectFromBox(box.frameRect) inContext:context];
		LDrawStepSetRGBA(context, [self calloutChrome].borderRGBA);
	}

	for (NSUInteger index = 0; index < box.dividerCount; index++) {
		CGContextFillRect(context, LDrawStepRectFromBox([box dividerRectAtIndex:index]));
	}

	for (LDrawStepCalloutPicture *picture in box.pictures) {
		[self drawPicture:picture ofBox:box inContext:context];
	}

	for (LDrawStepCalloutLabel *label in box.labels) {
		LDrawStepCalloutText *text = label.isStepNumber ? style.stepNumberText : style.countText;

		[self drawLabel:label withText:text inContext:context];
	}

	[self drawStepsBadgeForBox:box inContext:context];

}//end drawCalloutBox:inContext:


//========== drawFrameOfCalloutBox:style:inContext: ============================
///
/// @abstract	Draws a box the way its file says: its fill, and its outline in
///				the file's color, thickness, corners and dashes.
///
//==============================================================================
- (void) drawFrameOfCalloutBox:(LDrawStepCalloutBox *)box
						 style:(LDrawStepCalloutStyle *)style
					 inContext:(CGContextRef)context
{
	CGFloat		scale			= self.presentation.pointsPerPageInch;
	double		fillRGBA[4];
	double		borderRGBA[4];
	CGColorRef	fill			= NULL;

	LPubColorComponentsGetRGBA(style.fillColor, fillRGBA);
	LPubColorComponentsGetRGBA(style.borderColor, borderRGBA);

	if (style.hasFill) {
		fill = LDrawStepColorCreateRGBA(fillRGBA);
	}

	DrawFrame(context, LDrawStepRectFromBox(box.frameRect), fill, borderRGBA, style.borderThickness * scale,
			  style.cornerRadius * scale, style.borderLineStyle);
	CGColorRelease(fill);

}//end drawFrameOfCalloutBox:style:inContext:


//========== drawLabel:withText:inContext: =====================================
///
/// @abstract	Draws a step's number or a count. `text` says how the file wants
///				it drawn, or is nil for the parts list's own lettering.
///
//==============================================================================
- (void) drawLabel:(LDrawStepCalloutLabel *)label
		  withText:(nullable LDrawStepCalloutText *)text
		 inContext:(CGContextRef)context
{
	LDrawStepPartListChrome	chrome	= [self calloutChrome];
	CGRect					rect	= LDrawStepRectFromBox(label.rect);

	if (text == nil) {
		LDrawStepFont font = LDrawStepFontCreateSystem(chrome.labelPointSize, LDrawStepFontWeightBold);

		LDrawStepDrawTextInRect(context, label.text, rect, font, chrome.labelRGBA);
		LDrawStepFontRelease(font);
		return;
	}

	DrawStyledText(context, label.text, rect, text, self.presentation.pointsPerPageInch);

}//end drawLabel:withText:inContext:


//========== drawPicture:ofBox:inContext: ======================================
///
/// @abstract	Draws one picture of a box, then what goes over it: the labels
///				of a parts list, or the counts of submodels shown finished.
///
//==============================================================================
- (void) drawPicture:(LDrawStepCalloutPicture *)picture
			   ofBox:(LDrawStepCalloutBox *)box
		   inContext:(CGContextRef)context
{
	LDrawStepPartListChrome	chrome	= [self calloutChrome];
	CGRect					rect	= LDrawStepRectFromBox(picture.rect);
	CGImageRef				image	= [self.pictureStore imageForPicture:picture];

	if (image != NULL) {
		LDrawStepDrawImage(context, image, rect);
	}
	else if (picture.isPartsList == NO) {
		// No picture can be drawn off screen, so the box names its submodel.
		NSString		*title	= box.callout.entries.firstObject.displayTitle;
		LDrawStepFont	 font	= LDrawStepFontCreateSystem(chrome.annotationPointSize, LDrawStepFontWeightRegular);

		if (title != nil) {
			LDrawStepDrawTextInRect(context, title, rect, font, chrome.labelRGBA);
		}
		LDrawStepFontRelease(font);
	}

	LDrawStepPartListLayout *layout = picture.layout;

	if (layout == nil) {
		return;
	}

	if (picture.isPartsList) {
		// The cells are measured from the picture's corner.
		CGContextSaveGState(context);
		CGContextTranslateCTM(context, CGRectGetMinX(rect), CGRectGetMinY(rect));

		[LDrawStepOverlayRenderer drawLabelsOfLayout:layout
											  chrome:chrome
										contentWidth:CGRectGetWidth(rect)
									  overflowFormat:self.overflowFormat
										   inContext:context];
		CGContextRestoreGState(context);
		return;
	}

	LDrawStepFont font = LDrawStepFontCreateSystem(chrome.labelPointSize, LDrawStepFontWeightBold);

	for (LDrawStepPartListPlacement *placement in layout.placements) {
		if ([picture drawsCountOfPlacement:placement] == NO) {
			continue;
		}

		NSString	*text		= [LDrawStepPartListLayout quantityTextForQuantity:placement.entry.quantity];
		CGRect		 labelRect	= LDrawStepRectFromBox(placement.labelFrame);

		LDrawStepDrawTextInRect(context, text, CGRectOffset(labelRect, CGRectGetMinX(rect), CGRectGetMinY(rect)),
								font, chrome.labelRGBA);
	}

	LDrawStepFontRelease(font);

}//end drawPicture:ofBox:inContext:


//========== drawStepsBadgeForBox:inContext: ===================================
///
/// @abstract	Draws the badge on a box's top edge that says how many steps
///				build its submodels. Nothing for a box that shows the steps
///				itself.
///
//==============================================================================
- (void) drawStepsBadgeForBox:(LDrawStepCalloutBox *)box inContext:(CGContextRef)context
{
	NSUInteger stepCount = box.summarizedStepCount;

	if (stepCount == 0) {
		return;
	}

	LDrawStepPartListChrome		chrome	= [self calloutChrome];
	LDrawStepPartListBadgeStyle	style	= [LDrawStepPartListPolicy badgeStyleForScaledDownPart:NO chrome:chrome];
	NSString					*text	= [NSString stringWithFormat:self.stepCountFormat, (unsigned long)stepCount];

	LDrawStepFont	font		= LDrawStepFontCreateSystem(chrome.annotationPointSize, LDrawStepFontWeightMedium);
	CGSize			textSize	= LDrawStepTextSize(text, font);
	CGRect			frame		= LDrawStepRectFromBox(box.frameRect);
	CGSize			badgeSize	= CGSizeMake(ceil(textSize.width) + 2.0 * STEPS_BADGE_PADDING_X,
											 ceil(textSize.height) + 2.0 * STEPS_BADGE_PADDING_Y);

	// Across the top edge, clear of the corner.
	CGRect			badge		= CGRectMake(round(CGRectGetMaxX(frame) - chrome.cornerRadius - badgeSize.width),
											 round(CGRectGetMinY(frame) - badgeSize.height / 2.0),
											 badgeSize.width, badgeSize.height);

	DrawBadge(context, badge, text, font, style);
	LDrawStepFontRelease(font);

}//end drawStepsBadgeForBox:inContext:


// MARK: - THE WAY BACK -


//========== returnButtonRectForViewSize: ======================================
///
/// @abstract	Where the button sits: in the view's bottom left corner, sized
///				to its title.
///
//==============================================================================
- (Box2) returnButtonRectForViewSize:(Size2)viewSize
{
	if (self.returnTitle.length == 0) {
		return ZeroBox2;
	}

	LDrawStepFont	font		= ReturnButtonFontCreate();
	CGSize			textSize	= LDrawStepTextSize(self.returnTitle, font);
	double			margin		= [LDrawStepPartListPolicy frameInsetForPointsPerPageInch:0.0];
	double			width		= ceil(textSize.width) + 2.0 * RETURN_BUTTON_PADDING_X;
	double			height		= ceil(textSize.height) + 2.0 * RETURN_BUTTON_PADDING_Y;

	LDrawStepFontRelease(font);

	return V2MakeBox(margin, viewSize.height - margin - height, width, height);

}//end returnButtonRectForViewSize:


//========== drawReturnButtonInContext:viewSize: ===============================
///
/// @abstract	Draws the button that leads back to the step that called this
///				model out.
///
//==============================================================================
- (void) drawReturnButtonInContext:(CGContextRef)context viewSize:(Size2)viewSize
{
	CGRect button = LDrawStepRectFromBox([self returnButtonRectForViewSize:viewSize]);

	if (CGRectIsEmpty(button)) {
		return;
	}

	LDrawStepPartListChrome	chrome	= [LDrawStepPartListPolicy defaultChrome];
	LDrawStepFont			font	= ReturnButtonFontCreate();

	DrawPill(context, button, self.returnTitle, font, self.listBackgroundColor, chrome.borderRGBA, chrome.labelRGBA);
	LDrawStepFontRelease(font);

}//end drawReturnButtonInContext:viewSize:


// MARK: - THE TURNED VIEW -


//========== turnedViewStripLayoutForViewSize: =================================
///
/// @abstract	Lays the strip out across the middle of the view's top: its
///				text, then its two buttons, each the size of the button that
///				leads back.
///
//==============================================================================
- (TurnedViewStripLayout) turnedViewStripLayoutForViewSize:(Size2)viewSize
{
	TurnedViewStripLayout layout = { CGRectZero, CGRectZero, CGRectZero, CGRectZero };

	if (self.turnedViewText.length == 0) {
		return layout;
	}

	LDrawStepFont	font		= ReturnButtonFontCreate();
	CGSize			textSize	= LDrawStepTextSize(self.turnedViewText, font);
	CGSize			useSize		= LDrawStepTextSize(self.useAngleTitle ?: @"", font);
	CGSize			stepSize	= LDrawStepTextSize(self.stepAngleTitle ?: @"", font);

	LDrawStepFontRelease(font);

	CGFloat	buttonHeight	= ceil(MAX(textSize.height, MAX(useSize.height, stepSize.height)))
							+ 2.0 * RETURN_BUTTON_PADDING_Y;
	CGFloat	textWidth		= ceil(textSize.width);
	CGFloat	useWidth		= ceil(useSize.width) + 2.0 * RETURN_BUTTON_PADDING_X;
	CGFloat	stepWidth		= ceil(stepSize.width) + 2.0 * RETURN_BUTTON_PADDING_X;
	CGFloat	width			= TURNED_STRIP_TEXT_INSET + textWidth + TURNED_STRIP_TEXT_GAP
							+ useWidth + TURNED_STRIP_BUTTON_GAP + stepWidth + TURNED_STRIP_INSET;
	CGFloat	height			= buttonHeight + 2.0 * TURNED_STRIP_INSET;
	CGFloat	left			= floor((viewSize.width - width) / 2.0);
	CGFloat	top				= [LDrawStepPartListPolicy frameInsetForPointsPerPageInch:0.0];
	CGFloat	buttonTop		= top + TURNED_STRIP_INSET;

	layout.strip		= CGRectMake(left, top, width, height);
	layout.text			= CGRectMake(left + TURNED_STRIP_TEXT_INSET, buttonTop, textWidth, buttonHeight);
	layout.useAngle		= CGRectMake(CGRectGetMaxX(layout.text) + TURNED_STRIP_TEXT_GAP, buttonTop,
									 useWidth, buttonHeight);
	layout.stepAngle	= CGRectMake(CGRectGetMaxX(layout.useAngle) + TURNED_STRIP_BUTTON_GAP, buttonTop,
									 stepWidth, buttonHeight);

	return layout;

}//end turnedViewStripLayoutForViewSize:


//========== turnedViewStripRectForViewSize: ===================================
- (Box2) turnedViewStripRectForViewSize:(Size2)viewSize
{
	return LDrawStepBoxFromRect([self turnedViewStripLayoutForViewSize:viewSize].strip);

}//end turnedViewStripRectForViewSize:


//========== rectOfTurnedViewButton:forViewSize: ===============================
- (Box2) rectOfTurnedViewButton:(LDrawStepTurnedViewButton)button forViewSize:(Size2)viewSize
{
	TurnedViewStripLayout layout = [self turnedViewStripLayoutForViewSize:viewSize];

	return LDrawStepBoxFromRect((button == LDrawStepTurnedViewButtonUseAngle) ? layout.useAngle : layout.stepAngle);

}//end rectOfTurnedViewButton:forViewSize:


//========== drawTurnedViewStripInContext:viewSize: ============================
///
/// @abstract	Draws the strip that says the view is turned away from the
///				step's angle, in the colors of the button that leads back.
///
//==============================================================================
- (void) drawTurnedViewStripInContext:(CGContextRef)context viewSize:(Size2)viewSize
{
	TurnedViewStripLayout layout = [self turnedViewStripLayoutForViewSize:viewSize];

	if (CGRectIsEmpty(layout.strip)) {
		return;
	}

	LDrawStepPartListChrome	chrome	= [LDrawStepPartListPolicy defaultChrome];
	LDrawStepFont			font	= ReturnButtonFontCreate();

	DrawPill(context, layout.strip, @"", font, self.listBackgroundColor, chrome.borderRGBA, chrome.labelRGBA);
	LDrawStepDrawTextCentered(context, self.turnedViewText, layout.text, font, chrome.labelRGBA);
	DrawPill(context, layout.useAngle, self.useAngleTitle ?: @"", font, NULL, chrome.borderRGBA, chrome.labelRGBA);
	DrawPill(context, layout.stepAngle, self.stepAngleTitle ?: @"", font, NULL, chrome.borderRGBA, chrome.labelRGBA);

	LDrawStepFontRelease(font);

}//end drawTurnedViewStripInContext:viewSize:

@end
