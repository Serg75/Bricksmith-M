//==============================================================================
//
//  File:       LPubCalloutFont.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutMargins.h>
#import <LDrawCore/LPubColor.h>
#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubCalloutFont
///
/// @abstract   The font or the color of the text in a callout's box, of the
///             counts and annotations in a parts list, or of the page's
///             number:
///             0 !LPUB CALLOUT (STEP_NUMBER | INSTANCE_COUNT) FONT
///                 [GLOBAL|LOCAL] "<font>"
///             0 !LPUB CALLOUT (STEP_NUMBER | INSTANCE_COUNT) FONT_COLOR
///                 [GLOBAL|LOCAL] <color>
///             0 !LPUB PLI (INSTANCE_COUNT | ANNOTATE)
///                 (FONT "<font>" | FONT_COLOR <color>)
///             0 !LPUB PAGE NUMBER (FONT "<font>" | FONT_COLOR <color>)
///                 with the same optional scope.
///
/// @discussion A font is written the way Qt describes one: the family, the
///             size, and numbers for the weight and the slant, with commas
///             between them.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutFont : LPubCommand <LPubStyleLine>

@property (nonatomic, readonly) LPubStyleBranch		branch;
@property (nonatomic, readonly) LPubMetaScope		scope;

/// The text the line is for: a step's number, how many times the box is
/// built or a part is used, or the text on a part in a parts list.
@property (nonatomic, readonly) LPubCalloutPart		part;

/// YES for a FONT_COLOR line, which gives `color` and nothing else. NO for a
/// FONT line, which gives everything but `color`.
@property (nonatomic, readonly) BOOL				isColor;

@property (nonatomic, readonly, copy, nullable) NSString *family;

/// The size as written. LPub3D draws it as that many dots at the file's
/// resolution.
@property (nonatomic, readonly) double				size;
@property (nonatomic, readonly) BOOL				isBold;
@property (nonatomic, readonly) BOOL				isItalic;

/// Black for a color that cannot be read.
@property (nonatomic, readonly) LPubColorComponents	color;

@end

NS_ASSUME_NONNULL_END
