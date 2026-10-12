//==============================================================================
//
//  File:       LPubColor.m
//  Package:    LDrawCore
//
//  Purpose:    Reads the colors LPub lines name.
//
//  Notes:      LPub3D hands the text to Qt, which takes hex digits after a #
//              and the color names of SVG.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubColor.h>


const LPubColorComponents LPubColorBlack = { 0.0, 0.0, 0.0, 1.0 };

/// The color names of SVG, each followed by its red, green and blue as hex.
static NSString * const NAMED_COLORS =
	@"aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff "
	@"beige f5f5dc bisque ffe4c4 black 000000 blanchedalmond ffebcd blue 0000ff "
	@"blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00 "
	@"chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c "
	@"cyan 00ffff darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 "
	@"darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b darkmagenta 8b008b "
	@"darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 "
	@"darksalmon e9967a darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f "
	@"darkslategrey 2f4f4f darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493 "
	@"deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222 "
	@"floralwhite fffaf0 forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc "
	@"ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 grey 808080 green 008000 "
	@"greenyellow adff2f honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082 "
	@"ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 lawngreen 7cfc00 "
	@"lemonchiffon fffacd lightblue add8e6 lightcoral f08080 lightcyan e0ffff "
	@"lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 "
	@"lightpink ffb6c1 lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa "
	@"lightslategray 778899 lightslategrey 778899 lightsteelblue b0c4de lightyellow ffffe0 "
	@"lime 00ff00 limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 "
	@"mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db "
	@"mediumseagreen 3cb371 mediumslateblue 7b68ee mediumspringgreen 00fa9a "
	@"mediumturquoise 48d1cc mediumvioletred c71585 midnightblue 191970 mintcream f5fffa "
	@"mistyrose ffe4e1 moccasin ffe4b5 navajowhite ffdead navy 000080 oldlace fdf5e6 "
	@"olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 "
	@"palegoldenrod eee8aa palegreen 98fb98 paleturquoise afeeee palevioletred db7093 "
	@"papayawhip ffefd5 peachpuff ffdab9 peru cd853f pink ffc0cb plum dda0dd "
	@"powderblue b0e0e6 purple 800080 red ff0000 rosybrown bc8f8f royalblue 4169e1 "
	@"saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee "
	@"sienna a0522d silver c0c0c0 skyblue 87ceeb slateblue 6a5acd slategray 708090 "
	@"slategrey 708090 snow fffafa springgreen 00ff7f steelblue 4682b4 tan d2b48c "
	@"teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 violet ee82ee "
	@"wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32";


//========== NamedColors() =====================================================
///
/// @abstract	The hex digits of each named color, by its name in lower case.
///
//==============================================================================
static NSDictionary<NSString *, NSString *> *NamedColors(void)
{
	static NSDictionary<NSString *, NSString *>	*colors = nil;
	static dispatch_once_t						 onceToken;

	dispatch_once(&onceToken, ^{
		NSArray<NSString *>	*words	= [NAMED_COLORS componentsSeparatedByString:@" "];
		NSMutableDictionary	*table	= [NSMutableDictionary dictionaryWithCapacity:words.count / 2];

		for (NSUInteger index = 0; index + 1 < words.count; index += 2) {
			table[words[index]] = words[index + 1];
		}
		colors = [table copy];
	});

	return colors;

}//end NamedColors


//========== ReadHexDigits() ===================================================
///
/// @abstract	Reads hex digits as red, green and blue, with alpha first when
/// 			there are eight. NO when a digit is not hex, or for a count Qt
/// 			does not take.
///
//==============================================================================
static BOOL ReadHexDigits(NSString *digits, LPubColorComponents *outColor)
{
	NSUInteger	length		= digits.length;
	unsigned	values[8]	= { 0 };

	if (length != 3 && length != 6 && length != 8) {
		return NO;
	}

	for (NSUInteger index = 0; index < length; index++) {
		unichar character = [digits characterAtIndex:index];

		if (character >= '0' && character <= '9') {
			values[index] = character - '0';
		}
		else if (character >= 'a' && character <= 'f') {
			values[index] = character - 'a' + 10;
		}
		else {
			return NO;
		}
	}

	// One digit for each color stands for the same digit twice.
	if (length == 3) {
		*outColor = (LPubColorComponents){ values[0] / 15.0, values[1] / 15.0, values[2] / 15.0, 1.0 };
		return YES;
	}

	NSUInteger	first	= length - 6;
	double		alpha	= (length == 8) ? (values[0] * 16 + values[1]) / 255.0 : 1.0;

	*outColor = (LPubColorComponents){ (values[first] * 16 + values[first + 1]) / 255.0,
									   (values[first + 2] * 16 + values[first + 3]) / 255.0,
									   (values[first + 4] * 16 + values[first + 5]) / 255.0,
									   alpha };
	return YES;

}//end ReadHexDigits


//========== LPubColorComponentsFromString() ===================================
///
/// @abstract	Reads a color the way LPub3D does.
///
//==============================================================================
BOOL LPubColorComponentsFromString(NSString *string, LPubColorComponents *outColor)
{
	// LPub3D writes a name inside quotes, and Qt reads one with spaces in it.
	NSCharacterSet		*ignored	= [NSCharacterSet characterSetWithCharactersInString:@"\" "];
	NSArray<NSString *>	*pieces		= [[string lowercaseString] componentsSeparatedByCharactersInSet:ignored];
	NSString			*text		= [pieces componentsJoinedByString:@""];

	if ([text hasPrefix:@"#"]) {
		return ReadHexDigits([text substringFromIndex:1], outColor);
	}

	if ([text isEqualToString:@"transparent"]) {
		*outColor = (LPubColorComponents){ 0.0, 0.0, 0.0, 0.0 };
		return YES;
	}

	NSString *digits = NamedColors()[text];

	return digits != nil && ReadHexDigits(digits, outColor);

}//end LPubColorComponentsFromString
