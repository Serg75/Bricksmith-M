//==============================================================================
//
//  File:       LPubColor.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @struct     LPubColorComponents
///
/// @abstract   A color an LPub line names, as sRGB numbers from 0 to 1.
///
//------------------------------------------------------------------------------
typedef struct LPubColorComponents
{
	double	red;
	double	green;
	double	blue;
	double	alpha;

} LPubColorComponents;

/// Opaque black, which LPub3D draws for a color it cannot read.
extern const LPubColorComponents LPubColorBlack;

/// Reads a color the way LPub3D does: `#rgb`, `#rrggbb`, `#aarrggbb`, or a
/// name such as `Black` or `lightgray`, in any case, with or without quotes
/// around it. NO for anything else.
extern BOOL LPubColorComponentsFromString(NSString *string, LPubColorComponents *outColor);

/// Writes the color as four numbers: red, green, blue and alpha.
extern void LPubColorComponentsGetRGBA(LPubColorComponents color, double *outRGBA);

NS_ASSUME_NONNULL_END
