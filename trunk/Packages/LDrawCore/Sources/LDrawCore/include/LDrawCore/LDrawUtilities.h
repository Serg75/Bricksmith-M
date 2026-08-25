//==============================================================================
//
//  File:       LDrawUtilities.h
//  Package:    LDrawCore
//
//  Purpose:    Convenience routines for managing LDraw directives: their
//              syntax, manipulation, or display.
//
//  Created by Allen Smith on 2/28/06.
//  Copyright 2006. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawDirective;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

static NSString * const		GROUP_WRITE_PATTERN		= @"0 MLCAD BTG %@%@";
static NSString * const		GROUP_REGEX_PATTERN		= @"0\\s+MLCAD\\s+BTG\\s+(\\S+)";

// Viewing Angle
typedef enum
{
	ViewOrientation3D			= 0,
	ViewOrientationFront		= 1,
	ViewOrientationBack			= 2,
	ViewOrientationLeft			= 3,
	ViewOrientationRight		= 4,
	ViewOrientationTop			= 5,
	ViewOrientationBottom		= 6,
	ViewOrientationWalkThrough	= 7

} ViewOrientationT;

/// Dimension-panel unit rows. Height uses vertical studs (1/24 LDU);
/// other axes use horizontal studs (1/20 LDU).
typedef NS_ENUM(NSInteger, LDrawDimensionUnitT) {
	LDrawDimensionUnitStuds        = 0,
	LDrawDimensionUnitInches       = 1,
	LDrawDimensionUnitCentimeters  = 2,
	LDrawDimensionUnitLegonianFeet = 3,
	LDrawDimensionUnitLDU          = 4
};

enum {
	LDrawDimensionUnitCount = 5
};


//------------------------------------------------------------------------------
///
/// @class      LDrawUtilities
///
/// @abstract   Convenience routines for managing LDraw directives: their
///             syntax, manipulation, or display.
///
//------------------------------------------------------------------------------
@interface LDrawUtilities : NSObject

// Configuration
+ (NSString *)defaultAuthor;

+ (void)setColumnizesOutput:(BOOL)flag;
+ (void)setDefaultAuthor:(NSString *)nameIn;

// Parsing
+ (Class)classForDirectiveBeginningWithLine:(NSString *)line;
+ (LDrawColor *)parseColorFromField:(NSString *)colorField;
+ (NSString *)readNextField:(NSString *) partialDirective
				  remainder:(NSString * _Nullable * _Nullable) remainder;
+ (NSString *)scanQuotableToken:(NSScanner *)scanner;
+ (NSString *)stringFromFile:(NSString *)path;
+ (NSString *)stringFromFileData:(NSData *)fileData;
+ (NSString *)parseGroup:(NSString *)line;

// Writing
+ (NSString *)outputStringForColor:(LDrawColor *)color;
+ (NSString *)outputStringForFloat:(float)number;

// Hit Detection
+ (void)registerHitForObject:(id)hitObject
                       depth:(float)depth
                creditObject:(nullable id)creditObject
                        hits:(NSMutableDictionary *)hits;

+ (void)registerHitForObject:(id)hitObject
                creditObject:(nullable id)creditObject
                        hits:(NSMutableSet *)hits;

// Images
+ (nullable CGImageRef)imageAtPath:(NSString *)imagePath CF_RETURNS_NOT_RETAINED;

// Miscellaneous
+ (Tuple3)angleForViewOrientation:(ViewOrientationT)orientation;
+ (Box3)boundingBox3ForDirectives:(NSArray *)directives;
+ (BOOL)isLDrawFilenameValid:(NSString *)fileName;
+ (void)updateNameForMovedPart:(LDrawPart *)movedPart;
+ (void)updateNamesForMovedParts:(NSArray *)movedParts;
+ (ViewOrientationT)viewOrientationForAngle:(Tuple3)rotationAngle;
+ (void)unresolveLibraryParts:(LDrawDirective *)directive;

/// Hover-coordinate axis: confidence 0 means the axis is unknown /
/// questionable. The host still maps that to NSColor.
+ (BOOL)hoverCoordinateAxisIsQuestionable:(float)confidence;

/// Converts an LDU length to the display unit. Height uses vertical studs.
/// The host still formats and localizes.
+ (double)dimensionFromLDU:(double)ldu
					  unit:(LDrawDimensionUnitT)unit
				  isHeight:(BOOL)isHeight;

/// Localization key for the unit column label (Studs, Inches, …).
+ (nullable NSString *)dimensionUnitNameKey:(LDrawDimensionUnitT)unit;

/// Localization format key for Legonian feet+inches display.
+ (NSString *)feetAndInchesFormatKey;

/// Legonian Imperial: 12 of those inches to the foot.
+ (void)legonianFeet:(NSInteger * _Nonnull)outFeet
			  inches:(NSInteger * _Nonnull)outInches
		   fromValue:(double)legonianInches;

/// Formats a bounds length (LDU) for the dimensions table. Host localizes the
/// feet+inches format string first. Returns nil only for an unknown unit.
+ (nullable NSString *)formattedDimensionDisplayFromLDU:(double)ldu
												   unit:(LDrawDimensionUnitT)unit
											   isHeight:(BOOL)isHeight
							  feetAndInchesFormatString:(NSString *)localizedFormat;

/// Localization key for the "copy" token in duplicate names.
+ (NSString *)copySuffixLocalizationKey;

/// Next name in sequence for a copy. Host localizes the copy token first.
/// Does not check existence — that is the caller's responsibility.
+ (NSString *)nextCopyNameForString:(NSString *)originalString
						  copyToken:(NSString *)copyToken;

/// Next path/file name in sequence; handles extensions. Host localizes the
/// copy token first.
+ (NSString *)nextCopyPathForFilePath:(NSString *)basePath
							copyToken:(NSString *)copyToken;

@end

NS_ASSUME_NONNULL_END
