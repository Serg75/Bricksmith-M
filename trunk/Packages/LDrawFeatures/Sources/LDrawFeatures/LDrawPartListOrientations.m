//==============================================================================
//
//  File:       LDrawPartListOrientations.m
//  Package:    LDrawFeatures
//
//  Purpose:    The base orientation LPub3D gives each part in a parts list.
//
//  Created by Sergey Slobodenyuk on 2026-09-14.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartListOrientations.h>


/// The tokens of a type-1 line: code, color, x y z, a b c d e f g h i, name.
static const NSUInteger PART_LINE_TOKENS = 15;


@interface LDrawPartListOrientations ()

/// Part name, lower-case, to its 3×3 matrix as nine NSNumbers in LDraw order.
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSNumber *> *> *matrices;

@end


@implementation LDrawPartListOrientations


// MARK: - INITIALIZATION -


//---------- orientationsWithContentsOfFile:error: -------------------[static]--
+ (nullable instancetype) orientationsWithContentsOfFile:(NSString *)path
												   error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];

	if (data == nil) {
		return nil;
	}

	// Latin-1 as a fallback, because it cannot fail: one odd byte in a
	// comment must not lose the whole file.
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
				   ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];

	return [[self alloc] initWithString:text];

}//end orientationsWithContentsOfFile:error:


//========== initWithString: ===================================================
///
/// @abstract	Reads the matrix from every part line in the text.
///
//==============================================================================
- (instancetype) initWithString:(NSString *)text
{
	self = [super init];
	if (self) {
		NSMutableDictionary<NSString *, NSArray<NSNumber *> *>
						*matrices	= [NSMutableDictionary dictionary];
		NSCharacterSet	*spaces		= [NSCharacterSet whitespaceCharacterSet];

		[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {

			NSMutableArray<NSString *> *tokens = [NSMutableArray array];

			for (NSString *token in [line componentsSeparatedByCharactersInSet:spaces]) {
				if (token.length > 0) {
					[tokens addObject:token];
				}
			}

			if (tokens.count != PART_LINE_TOKENS || [tokens[0] isEqualToString:@"1"] == NO) {
				return;
			}

			NSString *name = [tokens[14] lowercaseString];

			// Keep the first line for a part, as LPub3D does.
			if (matrices[name] != nil) {
				return;
			}

			NSMutableArray<NSNumber *> *matrix = [NSMutableArray arrayWithCapacity:9];

			for (NSUInteger index = 5; index < 14; index++) {
				[matrix addObject:@([tokens[index] doubleValue])];
			}

			matrices[name] = matrix;
		}];

		self->_matrices = [matrices copy];
	}
	return self;

}//end initWithString:


// MARK: - ACCESSORS -


- (NSUInteger) count
{
	return self.matrices.count;
}


//========== orientationForPartName: ===========================================
///
/// @abstract	The part's base orientation, as Bricksmith multiplies points.
///
/// @discussion	An LDraw line turns a point as matrix times point. Bricksmith
/// 			puts the point on the left, so the same turn is the transpose.
///
//==============================================================================
- (Matrix4) orientationForPartName:(NSString *)partName
{
	NSArray<NSNumber *> *values = self.matrices[[partName lowercaseString]];
	Matrix4				 matrix	= IdentityMatrix4;

	if (values == nil) {
		return matrix;
	}

	for (int row = 0; row < 3; row++) {
		for (int column = 0; column < 3; column++) {
			matrix.element[row][column] = values[column * 3 + row].doubleValue;
		}
	}

	return matrix;

}//end orientationForPartName:


//---------- lpubDefaultFilePath -------------------------------------[static]--
///
/// @abstract	LPub3D's control file on this Mac, if it is there.
///
/// @discussion	LPub3D keeps the file in
/// 			`~/Library/Application Support/<organization>/LPub3D/extras`.
/// 			Both file names are tried, because LPub3D falls back to the
/// 			library name when `pli.mpd` is missing. Both spellings of the
/// 			organization are tried too.
///
//------------------------------------------------------------------------------
+ (nullable NSString *) lpubDefaultFilePath
{
	NSArray<NSString *>	*paths		= NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
																		  NSUserDomainMask,
																		  YES);
	NSString			*support	= [paths firstObject];

	if (support == nil) {
		return nil;
	}

	NSFileManager *fileManager = [NSFileManager defaultManager];

	for (NSString *organization in @[@"LPub3D Software", @"LPub3D Software Maint"]) {
		for (NSString *name in @[@"pli.mpd", @"LEGOPliControl.ldr"]) {
			NSString *path = [[[support stringByAppendingPathComponent:organization]
										stringByAppendingPathComponent:@"LPub3D/extras"]
										stringByAppendingPathComponent:name];

			if ([fileManager isReadableFileAtPath:path]) {
				return path;
			}
		}
	}

	return nil;

}//end lpubDefaultFilePath


@end
