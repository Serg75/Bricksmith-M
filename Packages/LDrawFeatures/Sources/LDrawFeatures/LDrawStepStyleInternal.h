//==============================================================================
//
//  File:       LDrawStepStyleInternal.h
//  Package:    LDrawFeatures
//
//  Purpose:    How a callout's style and a parts list's style read the file's
//              styling lines. The two read the same lines under another first
//              word.
//
//  Created by Sergey Slobodenyuk on 2026-10-15.
//
//==============================================================================

#import <LDrawCore/LPubCalloutBorder.h>
#import <LDrawCore/LPubCalloutMargins.h>
#import <LDrawFeatures/LDrawStepCalloutStyle.h>

@class LDrawDirective;
@class LPubCalloutBackground;

NS_ASSUME_NONNULL_BEGIN

/// Finds the line in force that a block matches: for one callout, or for the
/// visible step.
typedef id _Nullable (^LDrawStepStyleLookup)(BOOL (NS_NOESCAPE ^matching)(LDrawDirective *directive));


//------------------------------------------------------------------------------
///
/// @struct     LDrawStepBorderStyle
///
/// @abstract   A box's outline as the BORDER lines in force describe it, in
///             page inches.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepBorderStyle {
	LPubBorderShape		shape;
	LPubLineStyle		lineStyle;
	LPubColorComponents	color;
	/// 0 for NONE.
	double				thickness;
	/// 0 unless the outline is round.
	double				cornerRadius;
	/// The room between the outline and what is inside.
	Size2				margins;
	BOOL				hidesArrowTips;
} LDrawStepBorderStyle;


/// The outline from the BORDER lines of one branch in force. LPub3D keeps the
/// margins it had when a line gives none, so they come from the last line in
/// force that has them. `unit` and `dotInches` are inches per file unit and
/// per dot.
extern LDrawStepBorderStyle LDrawStepReadBorder(LDrawStepStyleLookup lookup, LPubStyleBranch branch,
												double unit, double dotInches);

/// The MARGINS of one branch and part in force, in inches, or LPub3D's 0.05.
extern Size2 LDrawStepReadMargins(LDrawStepStyleLookup lookup, LPubStyleBranch branch, LPubCalloutPart part,
								  double unit);

/// The BACKGROUND line of one branch in force, or nil.
extern LPubCalloutBackground * _Nullable LDrawStepReadBackground(LDrawStepStyleLookup lookup,
																 LPubStyleBranch branch);

/// The text the FONT and FONT_COLOR lines of one branch and part describe.
/// `defaultSize` is LPub3D's size in dots for a file with no FONT line, and
/// such text is bold.
extern LDrawStepCalloutText *LDrawStepReadText(LDrawStepStyleLookup lookup, LPubStyleBranch branch,
											   LPubCalloutPart part, double defaultSize, double dotInches);

NS_ASSUME_NONNULL_END
