//==============================================================================
//
//  File:       LDrawShadowFile.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Reads the SNAP metas of one LDCad shadow file.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import "LDrawShadowFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawShadowMeta ()
- (nullable instancetype)initWithLine:(NSString *)line;
@end


@interface LDrawShadowFile ()
- (instancetype)initWithText:(NSString *)text;
@end


//---------- AttributeIs -----------------------------------------------[static]--
//
// Purpose:		Whether an attribute is present and equals the expected value,
//				ignoring case.
//
// Notes:		Checks for nil, because a compare sent to nil returns
//				NSOrderedSame.
//
//------------------------------------------------------------------------------
static BOOL AttributeIs(NSString * _Nullable value, NSString *expected)
{
	return (value != nil) && ([value caseInsensitiveCompare:expected] == NSOrderedSame);
}


//---------- Tokens ----------------------------------------------------[static]--
//
// Purpose:		The words of a line, split on whitespace.
//
//------------------------------------------------------------------------------
static NSArray<NSString *> *Tokens(NSString *text)
{
	NSArray<NSString *> *all = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

	return [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
}


//---------- Attributes ------------------------------------------------[static]--
//
// Purpose:		The "[name=value]" pairs of a meta line, keyed by lowercase
//				name. A value may contain spaces.
//
//------------------------------------------------------------------------------
static NSDictionary<NSString *, NSString *> *Attributes(NSString *line)
{
	NSMutableDictionary<NSString *, NSString *>	*attributes	= [NSMutableDictionary dictionary];
	NSScanner									*scanner	= [NSScanner scannerWithString:line];

	scanner.charactersToBeSkipped = nil;

	while ([scanner isAtEnd] == NO)
	{
		NSString *body = nil;

		if ([scanner scanUpToString:@"[" intoString:NULL] == NO && [scanner isAtEnd])
		{
			break;
		}
		if ([scanner scanString:@"[" intoString:NULL] == NO)
		{
			break;
		}
		if ([scanner scanUpToString:@"]" intoString:&body] == NO)
		{
			break;
		}
		[scanner scanString:@"]" intoString:NULL];

		NSRange separator = [body rangeOfString:@"="];
		if (separator.location != NSNotFound)
		{
			NSString *name	= [[body substringToIndex:separator.location] lowercaseString];
			NSString *value	= [body substringFromIndex:NSMaxRange(separator)];

			attributes[[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]] = value;
		}
	}
	return attributes;
}


//---------- SectionShape ----------------------------------------------[static]--
//------------------------------------------------------------------------------
static LDrawSectionShape SectionShape(NSString *token)
{
	NSString *shape = token.uppercaseString;

	if ([shape isEqualToString:@"A"])	{ return LDrawSectionShapeAxle; }
	if ([shape isEqualToString:@"S"])	{ return LDrawSectionShapeSquare; }
	if ([shape isEqualToString:@"_L"])	{ return LDrawSectionShapeFlexToPrevious; }
	if ([shape isEqualToString:@"L_"])	{ return LDrawSectionShapeFlexToNext; }

	return LDrawSectionShapeRound;
}


//---------- Caps ------------------------------------------------------[static]--
//------------------------------------------------------------------------------
static LDrawConnectorCaps Caps(NSString * _Nullable token)
{
	NSString *caps = token.lowercaseString;

	if ([caps isEqualToString:@"one"])	{ return LDrawConnectorCapsOne; }
	if ([caps isEqualToString:@"two"])	{ return LDrawConnectorCapsTwo; }
	if ([caps isEqualToString:@"a"])	{ return LDrawConnectorCapsA; }
	if ([caps isEqualToString:@"b"])	{ return LDrawConnectorCapsB; }

	return LDrawConnectorCapsNone;
}


//---------- ScaleRule -------------------------------------------------[static]--
//------------------------------------------------------------------------------
static LDrawConnectorScaleRule ScaleRule(NSString * _Nullable token)
{
	NSString *rule = token.lowercaseString;

	if ([rule isEqualToString:@"yonly"])	{ return LDrawConnectorScaleRuleLength; }
	if ([rule isEqualToString:@"ronly"])	{ return LDrawConnectorScaleRuleRadius; }
	if ([rule isEqualToString:@"yandr"])	{ return LDrawConnectorScaleRuleBoth; }

	return LDrawConnectorScaleRuleNone;
}


//---------- FrameFromAttributes ---------------------------------------[static]--
//
// Purpose:		The meta's placement, as a matrix on row vectors.
//
// Notes:		"ori" is written like the matrix of an LDraw type 1 line, so it
//				is transposed, with "pos" as the last row.
//
//------------------------------------------------------------------------------
static Matrix4 FrameFromAttributes(NSDictionary<NSString *, NSString *> *attributes)
{
	NSArray<NSString *>	*position	= Tokens(attributes[@"pos"] ?: @"");
	NSArray<NSString *>	*orientation= Tokens(attributes[@"ori"] ?: @"");
	Matrix4				frame		= IdentityMatrix4;

	if (orientation.count >= 9)
	{
		for (NSUInteger row = 0; row < 3; row++)
		{
			for (NSUInteger column = 0; column < 3; column++)
			{
				frame.element[row][column] = orientation[column * 3 + row].doubleValue;
			}
		}
	}
	if (position.count >= 3)
	{
		frame.element[3][0] = position[0].doubleValue;
		frame.element[3][1] = position[1].doubleValue;
		frame.element[3][2] = position[2].doubleValue;
	}
	return frame;
}


//---------- GridFromAttributes ----------------------------------------[static]--
//
// Purpose:		Reads "grid=C 4 C 2 20 20": 4 by 2 connectors, 20 LDU apart,
//				centered both ways. Without "C", the grid starts at the
//				position.
//
//------------------------------------------------------------------------------
static LDrawConnectorGrid GridFromAttributes(NSDictionary<NSString *, NSString *> *attributes, Matrix4 frame)
{
	NSArray<NSString *>	*tokens	= Tokens(attributes[@"grid"] ?: @"");
	LDrawConnectorGrid	grid	= { .countX = 1, .countZ = 1 };
	NSUInteger			index	= 0;
	uint8_t				counts[2]	= { 1, 1 };
	bool				centered[2]	= { false, false };
	double				steps[2]	= { 0.0, 0.0 };
	Vector3				alongX		= V3Normalize(V3Make(frame.element[0][0], frame.element[0][1], frame.element[0][2]));
	Vector3				alongZ		= V3Normalize(V3Make(frame.element[2][0], frame.element[2][1], frame.element[2][2]));

	for (NSUInteger axis = 0; axis < 2 && index < tokens.count; axis++)
	{
		if ([tokens[index] caseInsensitiveCompare:@"C"] == NSOrderedSame)
		{
			centered[axis] = true;
			index++;
		}
		if (index < tokens.count)
		{
			counts[axis] = (uint8_t)MAX(1, MIN(255, tokens[index].integerValue));
			index++;
		}
	}
	for (NSUInteger axis = 0; axis < 2 && index < tokens.count; axis++, index++)
	{
		steps[axis] = tokens[index].doubleValue;
	}

	grid.countX		= counts[0];
	grid.countZ		= counts[1];
	grid.centeredX	= centered[0];
	grid.centeredZ	= centered[1];
	grid.stepX		= V3MulScalar(alongX, steps[0]);
	grid.stepZ		= V3MulScalar(alongZ, steps[1]);

	return grid;
}


//---------- SectionsFromAttributes ------------------------------------[static]--
//
// Purpose:		Reads "secs=R 6 20 R 4 8" as sections of shape, radius and
//				length.
//
//------------------------------------------------------------------------------
static NSData *SectionsFromAttributes(NSDictionary<NSString *, NSString *> *attributes)
{
	NSArray<NSString *>	*tokens		= Tokens(attributes[@"secs"] ?: @"");
	NSMutableData		*sections	= [NSMutableData data];

	for (NSUInteger index = 0; index + 2 < tokens.count; index += 3)
	{
		LDrawConnectorSection section = {
			.shape	= SectionShape(tokens[index]),
			.radius	= tokens[index + 1].doubleValue,
			.length	= tokens[index + 2].doubleValue,
		};
		[sections appendBytes:&section length:sizeof(section)];
	}
	return sections;
}


@implementation LDrawShadowMeta

//========== initWithLine: =====================================================
//
// Purpose:		Reads one meta, or returns nil when the line is not a meta
//				this package reads.
//
// Notes:		SNAP_CLP, SNAP_FGR and SNAP_GEN are skipped for now.
//
//==============================================================================
- (nullable instancetype)initWithLine:(NSString *)line
{
	NSArray<NSString *>	*tokens	= Tokens(line);
	NSString			*name	= nil;

	if (tokens.count < 3 || [tokens[0] isEqualToString:@"0"] == NO)
	{
		return nil;
	}
	if ([tokens[1] caseInsensitiveCompare:@"!LDCAD"] != NSOrderedSame)
	{
		return nil;
	}
	name = tokens[2].uppercaseString;

	self = [super init];
	if (self == nil)
	{
		return nil;
	}

	if ([name isEqualToString:@"SNAP_CYL"])
	{
		_kind = LDrawShadowMetaKindCylinder;
	}
	else if ([name isEqualToString:@"SNAP_CLEAR"])
	{
		_kind = LDrawShadowMetaKindClear;
	}
	else if ([name isEqualToString:@"SNAP_INCL"])
	{
		_kind = LDrawShadowMetaKindInclude;
	}
	else
	{
		return nil;
	}

	NSDictionary<NSString *, NSString *> *attributes = Attributes(line);

	_identifier	= [attributes[@"id"] copy];
	_reference	= [attributes[@"ref"] copy];
	_frame		= FrameFromAttributes(attributes);
	_grid		= GridFromAttributes(attributes, _frame);
	_sections	= [SectionsFromAttributes(attributes) copy];
	_gender		= AttributeIs(attributes[@"gender"], @"F")
					? LDrawConnectorGenderFemale : LDrawConnectorGenderMale;
	_caps		= Caps(attributes[@"caps"]);
	_scaleRule	= ScaleRule(attributes[@"scale"]);
	_centered	= AttributeIs(attributes[@"center"], @"true");
	_slide		= AttributeIs(attributes[@"slide"], @"true");

	return self;
}

@end


@implementation LDrawShadowFile

//---------- shadowFileWithContentsOfFile: -----------------------------[static]--
//------------------------------------------------------------------------------
+ (nullable instancetype)shadowFileWithContentsOfFile:(NSString *)path
{
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];

	if (text == nil)
	{
		// Older library files are Latin-1.
		text = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:NULL];
	}
	if (text == nil)
	{
		return nil;
	}
	return [[self alloc] initWithText:text];
}


//========== initWithText: =====================================================
//==============================================================================
- (instancetype)initWithText:(NSString *)text
{
	self = [super init];
	if (self != nil)
	{
		NSMutableArray<LDrawShadowMeta *> *metas = [NSMutableArray array];

		[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
			LDrawShadowMeta *meta = [[LDrawShadowMeta alloc] initWithLine:line];

			if (meta != nil)
			{
				[metas addObject:meta];
			}
		}];
		_metas = [metas copy];
	}
	return self;
}

@end

NS_ASSUME_NONNULL_END
