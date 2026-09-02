//==============================================================================
//
//  File:       LDrawUtilities.m
//  Package:    LDrawCore
//
//  Purpose:    Convenience routines for managing LDraw directives: their
//              syntax, manipulation, or display.
//
//  Created by Allen Smith on 2/28/06.
//  Copyright 2006. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawUtilities.h>

#import <ImageIO/ImageIO.h>
#import <math.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/LDrawMetaCommand.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawTexture.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawRegex.h>

#import <LDrawCore/LDrawPartLibrary.h>


static BOOL                 ColumnizesOutput    = NO;
static NSString				*defaultAuthor		= @"anonymous";

@implementation LDrawUtilities

#pragma mark -
#pragma mark CONFIGURATION
#pragma mark -

//---------- defaultAuthor -------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)defaultAuthor
{
	return defaultAuthor;
}


#pragma mark -

//---------- setColumnizesOutput: ------------------------------------[static]--
//
// Purpose:		Sets whether certain variable-width fields will be padded to 
//				make them all the same size in outputted files. 
//
// Notes:		Historically, LDraw programs truncate numbers as much as 
//				possible and insert exactly one space in between: 
//					4 16 -40 0 -20 -40 24 -20 40 24 -20 40 0 -20
//					4 16 40 0 20 40 24 20 -40 24 20 -40 0 20
//
//				Bricksmith 1.0 - 2.3 instead formatted the output into columns 
//				for easy readability, like so: 
//					4  16   -40.000000     0.000000   -20.000000   -40.000000    24.000000   -20.000000    40.000000    24.000000   -20.000000    40.000000     0.000000   -20.000000
//					4  16    40.000000     0.000000    20.000000    40.000000    24.000000    20.000000   -40.000000    24.000000    20.000000   -40.000000     0.000000    20.000000
//
//				But LDraw traditionalists hated that.
//
//				This method checks preferences to see which format is specified 
//				and outputs the chosen format. The result may be concatenated 
//				together with exactly one space; the columnizable string will 
//				already contain the necessary padding spaces. 
//
//------------------------------------------------------------------------------
+ (void)setColumnizesOutput:(BOOL)flag
{
	ColumnizesOutput = flag;
}


//---------- setDefaultAuthor: ---------------------------------------[static]--
//
// Purpose:		Sets the default author name used in new models.
//
//------------------------------------------------------------------------------
+ (void)setDefaultAuthor:(NSString *)nameIn
{
    // LLW: If the incoming nameIn is nil, leave this alone.
    if (nameIn != nil)
    {
        defaultAuthor = nameIn;
    }
}


#pragma mark -
#pragma mark PARSING
#pragma mark -

//---------- classForDirectiveBeginningWithLine: ---------------------[static]--
//
// Purpose:		Allows initializing the right kind of class based on the code 
//				found at the beginning of an LDraw line.
//
//------------------------------------------------------------------------------
+ (Class)classForDirectiveBeginningWithLine:(NSString *)line
{
	Class       classForType        = Nil;
	NSString    *commandCodeString  = nil;
	NSInteger   lineType            = 0;
	
	commandCodeString   = [LDrawUtilities readNextField:line remainder:NULL];
	// We may need to check for nil here someday.
	lineType            = [commandCodeString integerValue];
	
	// The linecode (0, 1, 2, 3, 4, 5) identifies the type of command, and is 
	// always the first character in the line. 
	switch (lineType)
	{
        case 0:
            {
                if ([LDrawTexture lineIsTextureBeginning:line])
                    classForType = [LDrawTexture textureClass];
                else if ([LDrawLSynth lineIsLSynthBeginning:line]) {
                    classForType = [LDrawLSynth class];
                }
                else
                    classForType = [LDrawMetaCommand class];
            }
            break;
		case 1:
			classForType = [LDrawPart class];
			break;
		case 2:
			classForType = [LDrawLine class];
			break;
		case 3:
			classForType = [LDrawTriangle class];
			break;
		case 4:
			classForType = [LDrawQuadrilateral class];
			break;
		case 5:
			classForType = [LDrawConditionalLine class];
			break;
		default:
			NSLog(@"unrecognized LDraw line type: %ld", (long)lineType);
	}
	
	return classForType;
	
} // end classForDirectiveBeginningWithLine:


//---------- parseColorFromField: ------------------------------------[static]--
//
// Purpose:		Returns the color code which is represented by the field.
//
// Notes:		This supports a nonstandard but fairly widely-supported 
//				extension which allows arbitrary RGB values to be specified in 
//				place of color codes. (MLCad, L3P, LDView, and others support 
//				this.) 
//
//------------------------------------------------------------------------------
+ (LDrawColor *)parseColorFromField:(NSString *)colorField
{
	NSScanner   *scanner        = [NSScanner scannerWithString:colorField];
	LDrawColorT colorCode       = LDrawColorBogus;
	unsigned	hexBytes        = 0;
	int			customCodeType  = 0;
	float		components[4]   = {};
	LDrawColor	*color			= nil;

	// Custom RGB?
	if ([scanner scanString:@"0x" intoString:nil] == YES)
	{
		// The integer should be of the format:
		// 0x2RRGGBB for opaque colors
		// 0x3RRGGBB for transparent colors
		// 0x4RGBRGB for a dither of two 12-bit RGB colors
		// 0x5RGBxxx as a dither of one 12-bit RGB color with clear (for transparency).

		[scanner scanHexInt:&hexBytes];
		customCodeType = (hexBytes >> 3*8) & 0xFF;
		
		switch (customCodeType)
		{
			// Solid color
			case 2:
				components[0] = (float) ((hexBytes >> 2*8) & 0xFF) / 255; // Red
				components[1] = (float) ((hexBytes >> 1*8) & 0xFF) / 255; // Green
				components[2] = (float) ((hexBytes >> 0*8) & 0xFF) / 255; // Blue
				components[3] = (float) 1.0; // alpha
				break;
			
			// Transparent color
			case 3:
				components[0] = (float) ((hexBytes >> 2*8) & 0xFF) / 255; // Red
				components[1] = (float) ((hexBytes >> 1*8) & 0xFF) / 255; // Green
				components[2] = (float) ((hexBytes >> 0*8) & 0xFF) / 255; // Blue
				components[3] = (float) 0.5; // alpha
				break;
			
			// combined opaque color
			case 4:
				components[0] = (float) (((hexBytes >> 5*4) & 0xF) + ((hexBytes >> 2*4) & 0xF))/2 / 255; // Red
				components[0] = (float) (((hexBytes >> 4*4) & 0xF) + ((hexBytes >> 1*4) & 0xF))/2 / 255; // Green
				components[0] = (float) (((hexBytes >> 3*4) & 0xF) + ((hexBytes >> 0*4) & 0xF))/2 / 255; // Blue
				components[3] = (float) 1.0; // alpha
				break;
				
			// bad-looking transparent color
			case 5:
				components[0] = (float) ((hexBytes >> 5*4) & 0xF) / 15; // Red
				components[0] = (float) ((hexBytes >> 4*4) & 0xF) / 15; // Green
				components[0] = (float) ((hexBytes >> 3*4) & 0xF) / 15; // Blue
				components[3] = (float) 0.5; // alpha
				break;
			
			default:
				break;
		}
		
		color = [[LDrawColor alloc] init];
		[color setColorCode:LDrawColorCustomRGB];
		[color setEdgeColorCode:LDrawBlack];
		[color setColorRGBA:components];
	}
	else
	{
		// Regular, standards-compliant LDraw color code
		colorCode   = [colorField intValue];
		color       = [[LDrawColorLibrary sharedColorLibrary] colorForCode:colorCode];
		
		if (color == nil)
		{
			// This is probably a file-local color. Or a file from the future.
			color = [[LDrawColor alloc] init];
			[color setColorCode:colorCode];
			[color setEdgeColorCode:LDrawBlack];
		}
	}
		
	return color;
	
} // end parseColorFromField:


//---------- readNextField:remainder: --------------------------------[static]--
//
// Purpose:		Given the portion of the LDraw line, read the first available 
//				field. Fields are separated by whitespace of any length.
//
//				If remainder is not NULL, return by indirection the remainder of 
//				partialDirective after the first field has been removed. If 
//				there is no remainder, an empty string will be returned.
//
//				So, given the line
//				1 8 -150 -8 20 0 0 -1 0 1 0 1 0 0 3710.DAT
//
//				remainder will be set to:
//				 8 -150 -8 20 0 0 -1 0 1 0 1 0 0 3710.DAT
//
// Notes:		This method is incapable of reading field strings with spaces 
//				in them!
//
//				A case could be made to replace this method with an NSScanner!
//				They don't seem to be as adept at scanning in unknown string 
//				tags though, which would make them difficult to use to 
//				distinguish between "0 WRITE blah" and "0 COMMENT blah".
//
//------------------------------------------------------------------------------
+ (NSString *)readNextField:(NSString *) partialDirective
				  remainder:(NSString * _Nullable * _Nullable) remainder
{
	NSCharacterSet	*whitespaceCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSRange			 rangeOfNextWhiteSpace;
	NSString		*fieldContents			= nil;
	
	// First, remove any heading whitespace.
	partialDirective		= [partialDirective stringByTrimmingCharactersInSet:whitespaceCharacterSet];
	// Find the beginning of the next field separation
	rangeOfNextWhiteSpace	= [partialDirective rangeOfCharacterFromSet:whitespaceCharacterSet];
	
	// The text between the beginning and the next field separator is the first 
	// field (what we are after).
	if (rangeOfNextWhiteSpace.location != NSNotFound)
	{
		fieldContents = [partialDirective substringToIndex:rangeOfNextWhiteSpace.location];
		// See if they want the rest of the line, sans the field we just parsed.
		if (remainder != NULL)
			*remainder = [partialDirective substringFromIndex:rangeOfNextWhiteSpace.location];
	}
	else
	{
		// There was no subsequent field separator; we must be at the end of the line.
		fieldContents = partialDirective;
		if (remainder != NULL)
			*remainder = [NSString string];
	}
	
	return fieldContents;
} // end readNextField


//---------- scanQuotableToken: --------------------------------------[static]--
//
// Purpose:		Scans a field which allows embedded whitespace if the field is 
//				wrappend in double-quotes. Otherwise, leading whitespace is 
//				trimmed and the field ends at the first whitespace character. 
//
//------------------------------------------------------------------------------
+ (NSString *)scanQuotableToken:(NSScanner *)scanner
{
	NSCharacterSet	*doubleQuote	= [NSCharacterSet characterSetWithCharactersInString:@"\""];
	NSMutableString *token			= [NSMutableString string];
	NSString		*temp			= nil;
	
	if ([scanner scanCharactersFromSet:doubleQuote intoString:NULL] == YES)
	{
		// String is wrapped in double quotes.
		// Watch out for embedded " characters, escaped as \"
		//                    and \ characters, escaped as \\        .
		
		[scanner scanUpToCharactersFromSet:doubleQuote intoString:&temp];
		[scanner scanCharactersFromSet:doubleQuote intoString:NULL];
		[token appendString:temp];
		while ([token hasSuffix:@"\\"] == YES)
		{
			// Un-escape the \"
			[token deleteCharactersInRange:NSMakeRange([token length] - 1, 1)];
			[token appendString:@"\""];
			
			[scanner scanUpToCharactersFromSet:doubleQuote intoString:&temp];
			[scanner scanCharactersFromSet:doubleQuote intoString:NULL];
			[token appendString:temp];
		}
		
		// Un-escape backslashes
		[token replaceOccurrencesOfString:@"\\\\" withString:@"\\" options:NSLiteralSearch range:NSMakeRange(0, [token length])];
	}
	else
	{
		// No leading quote mark
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&temp];
		[token appendString:temp];
	}
	
	return token;
	
} // end scanQuotableToken:


//---------- stringFromFile: -----------------------------------------[static]--
//
// Purpose:		Reads the contents of the file at the given path into a string. 
//
//------------------------------------------------------------------------------
+ (NSString *)stringFromFile:(NSString *)path
{
	NSData      *fileData   = [NSData dataWithContentsOfFile:path];
	NSString    *fileString = [self stringFromFileData:fileData];
	
	return fileString;
	
} // end stringFromFile:


//---------- stringFromFileData: -------------------------------------[static]--
//
// Purpose:		Reads the contents of the file with the given data into a 
//				string. We try a few different encodings. 
//
//------------------------------------------------------------------------------
+ (NSString *)stringFromFileData:(NSData *)fileData
{
	NSString    *fileString = nil;
	
	if (fileData)
	{
		// Try UTF-8 first, because it's so nice.
		fileString = [[NSString alloc] initWithData:fileData
										   encoding:NSUTF8StringEncoding ];
		
		// Uh-oh. Maybe Windows Latin?
		if (fileString == nil)
			fileString = [[NSString alloc] initWithData:fileData
											   encoding:NSISOLatin1StringEncoding ];
		
		// Yikes. Not even Windows. MacRoman will do it, even if it doesn't look 
		// right. 
		if (fileString == nil) 
			fileString = [[NSString alloc] initWithData:fileData
											   encoding:NSMacOSRomanStringEncoding ];
	}

	return fileString;
	
} // end stringFromFileData:


//---------- parseGroup: ---------------------------------------------[static]--
//
// Purpose:        Reads MLCAD group meta command
//
//------------------------------------------------------------------------------
+ (NSString *)parseGroup:(NSString *)line
{
	// 0 MLCAD BTG <GROUP_NAME>
	NSArray *matches = [line captureComponentsMatchedByRegex:GROUP_REGEX_PATTERN];
	if (matches.count == 2) {
		return [NSString stringWithString:matches[1]];
	}
	
	return nil;
} // end parseGroup:


#pragma mark -
#pragma mark WRITING
#pragma mark -

//---------- outputStringForColorCode:RGB: ---------------------------[static]--
//
// Purpose:		Returns the string representing the color code which should be 
//				written out in a file. 
//
// Notes:		This supports the non-standard custom RGB extension.
//
//------------------------------------------------------------------------------
+ (NSString *)outputStringForColor:(LDrawColor *)color
{
	NSString        *outputString   = nil;
	float			components[4]	= {};
	LDrawColorT		colorCode		= LDrawColorBogus;
	
	colorCode = [color colorCode];
	[color getColorRGBA:components];

	if (colorCode == LDrawColorCustomRGB)
	{
		// Opaque?
		if (components[3] == 1.0)
		{
			outputString = [NSString stringWithFormat:@"0x2%02X%02X%02X",
													   (uint8_t)(components[0] * 255),
													   (uint8_t)(components[1] * 255),
													   (uint8_t)(components[2] * 255) ];
		}
		else
		{
			outputString = [NSString stringWithFormat:@"0x3%02X%02X%02X",
													   (uint8_t)(components[0] * 255),
													   (uint8_t)(components[1] * 255),
													   (uint8_t)(components[2] * 255) ];
		}
	}
	else
	{
		if (ColumnizesOutput == YES)
		{
			outputString = [NSString stringWithFormat:@"%3d", (int)colorCode];
		}
		else
		{
			outputString = [NSString stringWithFormat:@"%d", (int)colorCode];
		}

	}
	
	return outputString;

} // end outputStringForColorCode:RGB:


//---------- outputStringForFloat: -----------------------------------[static]--
//
// Purpose:		Returns a formatted floating-point value appropriate for 
//				inserting into an LDraw file. 
//
// Notes:		The argument is a double so that callers holding a double-precision 
//				value do not have to narrow it to float first. Narrowing reintroduces 
//				rounding error at the sixth decimal place -- exactly where %f prints -- 
//				which is how a coordinate like 1024.15 used to be written out as 
//				"1024.150024". 
//
//------------------------------------------------------------------------------
+ (NSString *)outputStringForFloat:(double)number
{
	NSString        *outputString   = nil;
	
	if (ColumnizesOutput == YES)
	{
		// Make a nice wide fixed-width string which will force the numbers into 
		// columns. 
		outputString = [NSString stringWithFormat:@"%12f", number];
	}
	else
	{
		// Remove all trailing zeroes (and the decimal point if an integer).
		
		char    formattedFloat[64]  = "";
		char    *endOfString        = NULL;
		size_t  fullLength          = 0;
		int     requiredLength      = 0;
		
		// First format the number into a string. We could wind up with 
		// something like "50.090000".
		requiredLength = snprintf(formattedFloat, sizeof(formattedFloat), "%f", number);
		
		// A magnitude too large for the buffer would be silently truncated, and the 
		// trailing-zero trim below would then eat digits out of the integer part 
		// (1e20 becoming "1"). Nothing in a real model gets this big, but print it 
		// untrimmed rather than wrong. 
		if (requiredLength < 0 || (size_t)requiredLength >= sizeof(formattedFloat))
		{
			return [NSString stringWithFormat:@"%f", number];
		}
		
		fullLength  = strlen(formattedFloat);
		endOfString = &formattedFloat[fullLength - 1];
		
		// Back up past all the zeroes that may be at the end of the number
		while (*endOfString == '0')
		{
			endOfString--;
		}
		if (*endOfString != '.')
		{
			// We must be pointing at a non-zero digit, so lop off the 
			// subsequent character that is a zero. 
			endOfString++;
		}
		
		*endOfString = '\0';
		outputString = [NSString stringWithUTF8String:formattedFloat];
	}
	
	return outputString;

} // end outputStringForFloat:


#pragma mark -
#pragma mark HIT DETECTION
#pragma mark -

//---------- registerHitForObject:depth:creditObject:hits: -----------[static]--
//
// Purpose:		Adds a hit record to the hits dictionary such that only the 
//				nearest hits per credit object survive. 
//
// Parameters:	hitObject - the exact object whose geometry was hit
//				depth - the distance in the depth of field
//				creditObject - an object to which the hit should be attributed 
//						(instead of the hitObject itself) 
//				hits - the list of hit records to modify
//
//------------------------------------------------------------------------------
+ (void)registerHitForObject:(id)hitObject depth:(float)hitDepth creditObject:(nullable id)creditObject hits:(NSMutableDictionary *)hits
{
	NSNumber    *existingRecord = [hits objectForKey:creditObject];
	float       existingDepth   = 0;
	NSValue     *key            = nil;
	
	// NSDictionary copies its keys (which we don't want to do!), so we'll just 
	// wrap the pointers. 
	if (creditObject == nil)
	{
		key = [NSValue valueWithPointer:(__bridge const void *)(hitObject)];
	}
	else
	{
		key = [NSValue valueWithPointer:(__bridge const void *)(creditObject)];
	}

	existingRecord = [hits objectForKey:key];
	if (existingRecord == nil)
	{
		existingDepth = INFINITY;
	}
	else
	{
		existingDepth = [existingRecord floatValue];
	}
	
	// Found a shallower intersection point? Record the hit.
	if (hitDepth < existingDepth)
	{
		[hits setObject:@(hitDepth) forKey:key];
	}
}

//---------- registerHitForObject:creditObject:hits: -----------------[static]--
//
// Purpose:		Same as above, but it adds its objects to a mutable set, 
//				and ignores depth.
//
// Parameters:	hitObject - the exact object whose geometry was hit
//				creditObject - an object to which the hit should be attributed 
//						(instead of the hitObject itself) 
//				hits - the hit set
//
//------------------------------------------------------------------------------
+ (void)registerHitForObject:(id)hitObject creditObject:(nullable id)creditObject hits:(NSMutableSet *)hits
{
	NSValue     *key            = nil;
	
	// NSDictionary copies its keys (which we don't want to do!), so we'll just 
	// wrap the pointers. 
	if (creditObject == nil)
	{
		key = [NSValue valueWithPointer:(__bridge const void *)(hitObject)];
	}
	else
	{
		key = [NSValue valueWithPointer:(__bridge const void *)(creditObject)];
	}

	[hits addObject:key];

}


#pragma mark -
#pragma mark IMAGES
#pragma mark -

//---------- imageAtPath: --------------------------------------------[static]--
//
// Purpose:		Creates an image from the file at the given path.
//
// Notes:		Uses Core Graphics' `CGImageSource` so this can live in
//				LDrawCore (no AppKit/UIKit) and work on both macOS and iOS.
//				Returns an autoreleased `CGImageRef`; the result is valid
//				until the autorelease pool drains.
//
//------------------------------------------------------------------------------
+ (nullable CGImageRef)imageAtPath:(NSString *)imagePath
{
	if (imagePath == nil) return NULL;
    
	NSURL *url = [NSURL fileURLWithPath:imagePath];
	CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
	if (source == NULL) return NULL;
    
	CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
	CFRelease(source);
	if (image == NULL) return NULL;
    
	return (CGImageRef)CFAutorelease(image);
}


#pragma mark -
#pragma mark MISCELLANEOUS
#pragma mark -
// This is stuff that didn't really go anywhere else.

//---------- angleForViewOrientation: --------------------------------[static]--
//
// Purpose:		Returns the viewing angle in degrees for the given orientation.
//
//------------------------------------------------------------------------------
+ (Tuple3)angleForViewOrientation:(LDrawViewOrientation)orientation
{
	Tuple3 angle	= ZeroPoint3;
	
	switch (orientation)
	{
		case LDrawViewOrientationWalkThrough:
			angle = V3Make(0,0,0);
			break;
	
		case LDrawViewOrientation3D:
			// This is MLCad's default 3-D viewing angle, which is arrived at by 
			// applying these rotations in order: z=0, y=45, x=23. 
			angle = V3Make(16.707, 42.63, 16.039);
			break;
			
		case LDrawViewOrientationFront:
			angle = V3Make(0, 0, 0);
			break;
			
		case LDrawViewOrientationBack:
			angle = V3Make(0, 180, 0);
			break;
			
		case LDrawViewOrientationLeft:
			angle = V3Make(0, -90, 0);
			break;
			
		case LDrawViewOrientationRight:
			angle = V3Make(0, 90, 0);
			break;
			
		case LDrawViewOrientationTop:
			angle = V3Make(90, 0, 0);
			break;
			
		case LDrawViewOrientationBottom:
			angle = V3Make(-90, 0, 0);
			break;
	}
	
	return angle;
	
} // end angleForViewOrientation:


//---------- boundingBox3ForDirectives: ------------------------------[static]--
//
// Purpose:		Returns the minimum and maximum points of the box which 
//				perfectly contains all the given objects. (Only objects which 
//				respond to -boundingBox3 will be tested.)
//
// Notes:		This method used to live in LDrawContainer, which was a very 
//				nice place. But I moved it here so that other interested parties 
//				could do bounds testing on ad-hoc collections of directives.
//
//------------------------------------------------------------------------------
+ (Box3)boundingBox3ForDirectives:(NSArray *)directives
{
	Box3        bounds              = InvalidBox;
	Box3        partBounds          = InvalidBox;
	id          currentDirective    = nil;
	NSUInteger  numberOfDirectives  = [directives count];
	NSUInteger  counter             = 0;
	
	for (counter = 0; counter < numberOfDirectives; counter++)
	{
		currentDirective = [directives objectAtIndex:counter];
//		if ([currentDirective respondsToSelector:@selector(boundingBox3)])
		{
			partBounds	= [currentDirective boundingBox3];
			bounds		= V3UnionBox(bounds, partBounds);
		}
	}
	
	return bounds;
	
} // end boundingBox3ForDirectives


//---------- isLDrawFilenameValid: -----------------------------------[static]--
//
// Purpose:		The LDraw File Specification defines what makes a valid LDraw 
//				file name: http://www.ldraw.org/Article218.html#files 
//
//				Alas, these rules suck in MPD names too, thanks to the wording 
//				on Linetype 1 in the spec. 
//
// Notes:		The spec also has disparaging things to say about whitespace and 
//				special characters in filenames. To the spec I say: join the 
//				1990s. 
//
//------------------------------------------------------------------------------
+ (BOOL)isLDrawFilenameValid:(NSString *)fileName
{
	NSString	*extension	= [fileName pathExtension];
	BOOL		isValid		= NO;
	
	// Make sure it has a valid extension
	if (	extension == nil
	   ||	(	[extension isEqualToString:@"ldr"] == NO
			 &&	[extension isEqualToString:@"dat"] == NO )
	   )
	{
		isValid = NO;
	}
	else
		isValid = YES;
		
	return isValid;
	
} // end isLDrawFilenameValid:


//---------- updateNameForMovedPart: ---------------------------------[static]--
//
// Purpose:		If the specified part has been moved to a new number/name by 
//				LDraw.org, this method will update the part name to point to the 
//				new location.
//
//				Example:
//					193.dat (~Moved to 193a) becomes 193a.dat
//
//------------------------------------------------------------------------------
+ (void)updateNameForMovedPart:(LDrawPart *)movedPart
{
	NSString	*description	= [[LDrawPartLibrary sharedPartLibrary] descriptionForPart:movedPart];

	if ([description hasPrefix:LDRAW_MOVED_DESCRIPTION_PREFIX])
	{
		[movedPart followRedirectionAndUpdate];
	}
	
} // end updateNameForMovedPart:


//---------- updateNamesForMovedParts: -------------------------------[static]--
//
// Purpose:		They want us to update the ~Moved parts.
//
//------------------------------------------------------------------------------
+ (void)updateNamesForMovedParts:(NSArray *)movedParts
{
	NSUInteger counter;
	for (counter = 0; counter < [movedParts count]; counter++)
	{
		[self updateNameForMovedPart:[movedParts objectAtIndex:counter]];
	}
} // end updateNamesForMovedParts:


//---------- viewOrientationForAngle: --------------------------------[static]--
//
// Purpose:		Returns the viewing orientation for the given angle. If the 
//				angle is not a recognized head-on view, LDrawViewOrientation3D will 
//				be returned. 
//
//------------------------------------------------------------------------------
+ (LDrawViewOrientation)viewOrientationForAngle:(Tuple3)rotationAngle
{
	LDrawViewOrientation    viewOrientation = LDrawViewOrientation3D;
	NSUInteger          counter             = 0;
	Tuple3              testAngle           = ZeroPoint3;
	LDrawViewOrientation    testOrientation = LDrawViewOrientation3D;
	
	LDrawViewOrientation    orientations[]  = {	LDrawViewOrientationFront,
		LDrawViewOrientationBack,
		LDrawViewOrientationLeft,
		LDrawViewOrientationRight,
		LDrawViewOrientationTop,
		LDrawViewOrientationBottom
	};
	NSUInteger          orientationCount    = sizeof(orientations)/sizeof(LDrawViewOrientation);
	
	// See if the angle matches any of the head-on orientations.
	for (counter = 0; viewOrientation == LDrawViewOrientation3D && counter < orientationCount; counter++)
	{
		testOrientation	= orientations[counter];
		testAngle		= [LDrawUtilities angleForViewOrientation:testOrientation];
		
		if ( V3PointsWithinTolerance(rotationAngle, testAngle) == YES )
			viewOrientation = testOrientation;
	}
	
	return viewOrientation;
	
} // end viewOrientationForAngle:



//---------- unresolveLibraryParts: ----------------------------------[static]--
//
// Purpose:		This routine walks a directive tree and sends
//				unresolvePartIfPartLibrary to any parts it finds.  This has the
//				result of causing all parts to drop their weak reference to the
//				library.
//
//------------------------------------------------------------------------------
+ (void)unresolveLibraryParts:(LDrawDirective *) directive
{
	if ([directive respondsToSelector:@selector(allEnclosedElements)])
	{
		NSArray * subs = [(LDrawContainer*)directive allEnclosedElements];		
		for (LDrawDirective * d in subs)
		{
			[self unresolveLibraryParts:d];
		}
	}
	
	if ([directive respondsToSelector:@selector(unresolvePartIfPartLibrary)])
		[(LDrawPart*)directive unresolvePartIfPartLibrary];
} // end unresolveLibraryParts


//---------- hoverCoordinateAxisIsQuestionable: ----------------------[static]--
//
// Purpose:		Display the 3D world coordinates of the mouse as it hovers over
//				the model. Confidence 0 means that axis is unknown.
//
//------------------------------------------------------------------------------
+ (BOOL)hoverCoordinateAxisIsQuestionable:(float)confidence
{
	return confidence == 0.0;
}


//---------- dimensionFromLDU:unit:isHeight: -------------------------[static]--
//
// Purpose:		We have the value in LDraw Units; convert to display units.
//				1 stud = 20 LDraw units = 8 mm ≈ 3/8". Studs are different
//				depending on whether they are horizontal or vertical. Brick
//				aspect ratio of width to height is 5:6. Legonian Imperial Feet
//				are a 3:128 scale.
//
//------------------------------------------------------------------------------
+ (double)dimensionFromLDU:(double)ldu
					  unit:(LDrawDimensionUnitT)unit
				  isHeight:(BOOL)isHeight
{
	double studsPerLDU       = 1 / 20.0;    // HORIZONTAL studs!
	double mmPerStud         = 8.0;         // HORIZONTAL studs!
	double inchesPerMM       = 1 / 25.4;
	double brickHeightPerLDU = 1 / 24.;     // brick aspect ratio of width to height is 5:6
	double legoInchPerInch   = 128 / 3.0;   // Legonian Imperial Feet are a 3:128 scale.
	double value             = ldu;

	switch (unit)
	{
		case LDrawDimensionUnitStuds:
			if (isHeight)
				value *= brickHeightPerLDU; //get vertical studs.
			else
				value *= studsPerLDU; //get horizontal studs
			break;
		case LDrawDimensionUnitInches:
			value *= studsPerLDU * mmPerStud * inchesPerMM;
			break;
		case LDrawDimensionUnitCentimeters:
			value *= studsPerLDU * mmPerStud / 10.;
			break;
		case LDrawDimensionUnitLegonianFeet:
			value *= studsPerLDU * mmPerStud * inchesPerMM * legoInchPerInch;
			break;
		case LDrawDimensionUnitLDU:
			value *= 1; // nothing to convert for LDU
			break;
	}
	return value;
}


//---------- dimensionUnitNameKey: -----------------------------------[static]--
//
// Purpose:		Localization key for the unit column label. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)dimensionUnitNameKey:(LDrawDimensionUnitT)unit
{
	switch (unit)
	{
		case LDrawDimensionUnitStuds:         return @"Studs";
		case LDrawDimensionUnitInches:        return @"Inches";
		case LDrawDimensionUnitCentimeters:   return @"Centimeters";
		case LDrawDimensionUnitLegonianFeet:  return @"LegonianFeet";
		case LDrawDimensionUnitLDU:           return @"LDU";
	}
	return nil;
}


//---------- feetAndInchesFormatKey ----------------------------------[static]--
//
// Purpose:		Localization format key for Legonian feet+inches display.
//
//------------------------------------------------------------------------------
+ (NSString *)feetAndInchesFormatKey
{
	return @"FeetAndInchesFormat";
}


//---------- copySuffixLocalizationKey -------------------------------[static]--
//
// Purpose:		Localization key for the "copy" token in duplicate names.
//
//------------------------------------------------------------------------------
+ (NSString *)copySuffixLocalizationKey
{
	return @"CopySuffix";
}


//---------- nextCopyNameForString:copyToken: ------------------------[static]--
//
// Purpose:		Returns the next name (in sequence) for a copy of the given
//				name.
//
// Notes:		This method does not attempt to check for the existence of the
//				copy name it returns; that is the caller's responsibility.
//
// Examples:	Base Name				New Name
//				----------				----------
//				foo						foo copy
//				foo copy				foo copy 2
//				foo copy 3				foo copy 4
//				foo.txt					foo.txt copy		// ignores extensions!
//				foo copy.txt			foo copy.txt copy
//
//------------------------------------------------------------------------------
+ (NSString *)nextCopyNameForString:(NSString *)originalString
						  copyToken:(NSString *)copyToken
{
	NSRange     rangeOfCopyToken    = [originalString rangeOfString:copyToken options:NSBackwardsSearch];
	NSScanner   *copyNumberScanner  = nil;
	NSInteger   currentCopyNumber   = 0;
	BOOL        foundCopyNumber     = NO;
	NSString    *baseName           = nil;
	NSString    *newCopyString      = nil;

	// This string doesn't have the word "copy" in it yet.
	if (rangeOfCopyToken.location == NSNotFound)
	{
		currentCopyNumber = 0;
	}
	// This is already a copy itself; now we need to figure out which copy is
	// next!
	else
	{
		copyNumberScanner	= [NSScanner scannerWithString:originalString];
		[copyNumberScanner setScanLocation:NSMaxRange(rangeOfCopyToken)];

		// Is there a number at the end?
		foundCopyNumber = [copyNumberScanner scanInteger:&currentCopyNumber];

		if ([copyNumberScanner isAtEnd] == NO)
		{
			// The word "copy" in the name was apparently followed by something
			// other than an integer or the empty string. Thus, it is not a
			// valid copy token. So just append the word copy to the end and be
			// done with it.
			currentCopyNumber = 0;
		}
		else if (	[copyNumberScanner isAtEnd] == YES
				&&	foundCopyNumber == NO )
		{
			// The word copy is there, but not followed by a number. So this is
			// the first copy.
			currentCopyNumber = 1;
		}

		// Pathological case: It's a negative number!
		if (currentCopyNumber < 0)
			currentCopyNumber = 0;
	}

	// Build the copy string.
	switch (currentCopyNumber)
	{
		case 0:
			// Just append the word "copy" for the first copy
			newCopyString = [originalString stringByAppendingFormat:@" %@", copyToken];
			break;

		default:
			// Strip the old copy number
			baseName = [originalString substringToIndex:NSMaxRange(rangeOfCopyToken)];

			// Increment the copy number.
			newCopyString = [baseName stringByAppendingFormat:@" %ld", (long)(currentCopyNumber + 1)];
			break;
	}

	return newCopyString;
}


//---------- nextCopyPathForFilePath:copyToken: ----------------------[static]--
//
// Purpose:		Returns the next path or file name (in sequence) for a copy of
//				the given name. Correctly handles file extensions.
//
// Notes:		This method does not attempt to check for the existence of the
//				copy name it returns; that is the caller's responsibility.
//
// Examples:	Base Name				New Name
//				----------				----------
//				foo						foo copy
//				foo copy				foo copy 2
//				foo copy 3				foo copy 4
//				foo.txt					foo copy.txt
//				foo copy.txt			foo copy 2.txt
//
//------------------------------------------------------------------------------
+ (NSString *)nextCopyPathForFilePath:(NSString *)basePath
							copyToken:(NSString *)copyToken
{
	NSString	*fileName				= [basePath lastPathComponent];
	NSString	*enclosingPath			= [basePath stringByDeletingLastPathComponent];
	NSString	*extension				= [basePath pathExtension];
	NSString	*fileNameSansExtension	= [fileName stringByDeletingPathExtension];
	NSString	*copyBaseName			= nil;
	NSString	*copyPath				= nil;

	// Derive the copy name and reconstitute the new path based on it.
	copyBaseName	= [self nextCopyNameForString:fileNameSansExtension copyToken:copyToken];
	copyPath		= [enclosingPath stringByAppendingPathComponent:copyBaseName];
	copyPath		= [copyPath stringByAppendingPathExtension:extension];

	return copyPath;
}


//---------- legonianFeet:inches:fromValue: --------------------------[static]--
//
// Purpose:		Format in feet and inches.
//
//------------------------------------------------------------------------------
+ (void)legonianFeet:(NSInteger *)outFeet
			  inches:(NSInteger *)outInches
		   fromValue:(double)legonianInches
{
	if (outFeet != NULL)
		*outFeet = (NSInteger)floor(legonianInches / 12);
	if (outInches != NULL)
		*outInches = (NSInteger)fmod(legonianInches, 12);
}


//---------- formattedDimensionDisplayFromLDU:unit:isHeight:… --------[static]--
//
// Purpose:		This is downright ugly. Studs are different depending on whether
//				they are horizontal or vertical. Oh yeah, and we want to display
//				integers, floats, and strings in one table. Host localizes the
//				feet+inches format string first.
//
//------------------------------------------------------------------------------
+ (NSString *)formattedDimensionDisplayFromLDU:(double)ldu
										  unit:(LDrawDimensionUnitT)unit
									  isHeight:(BOOL)isHeight
					 feetAndInchesFormatString:(NSString *)localizedFormat
{
	double               value          = [self dimensionFromLDU:ldu unit:unit isHeight:isHeight];
	NSNumberFormatter   *floatFormatter = [NSNumberFormatter new];
	NSNumberFormatter   *studFormatter  = [NSNumberFormatter new];

	[floatFormatter setPositiveFormat:@"0.0"];
	[studFormatter setPositiveFormat:@"0.##"];

	switch (unit)
	{
		case LDrawDimensionUnitStuds:
			return [studFormatter stringForObjectValue:@(value)];

		case LDrawDimensionUnitInches:
		case LDrawDimensionUnitCentimeters:
			return [floatFormatter stringForObjectValue:@(value)];

		case LDrawDimensionUnitLegonianFeet:
		{
			NSInteger feet   = 0;
			NSInteger inches = 0;
			[self legonianFeet:&feet inches:&inches fromValue:value];
			return [NSString stringWithFormat:localizedFormat, (int)feet, (int)inches];
		}

		case LDrawDimensionUnitLDU:
			return [NSString stringWithFormat:@"%ld", (long)ceil(value)];
	}

	return nil;
}

@end
