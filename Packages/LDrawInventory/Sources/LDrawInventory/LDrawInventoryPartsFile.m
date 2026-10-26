//==============================================================================
//
//  File:       LDrawInventoryPartsFile.m
//  Package:    LDrawInventory
//
//  Purpose:    Reads loose parts from a parts list file, for a combined
//              inventory.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawInventoryPartsFile.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawInventory/LDrawInventoryItem.h>

NSString * const LDrawInventoryErrorDomain = @"LDrawInventoryErrorDomain";


//========== PartsFileError ====================================================
//==============================================================================
static NSError *PartsFileError(LDrawInventoryError code, NSString *description)
{
	return [NSError errorWithDomain:LDrawInventoryErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey: description}];
}


//========== PositiveInteger ===================================================
///
/// @abstract	The whole number a field holds, or -1 when it holds anything
/// 			else.
///
//==============================================================================
static NSInteger PositiveInteger(NSString *field)
{
	NSScanner	*scanner	= [NSScanner scannerWithString:field];
	NSInteger	 value		= 0;

	if ([scanner scanInteger:&value] == NO || [scanner isAtEnd] == NO || value < 0)
		return -1;
	return value;
}


//========== CSVFields =========================================================
///
/// @abstract	The fields of one CSV line. A quoted field may hold commas and
/// 			doubled quotes.
///
//==============================================================================
static NSArray<NSString *> *CSVFields(NSString *line)
{
	NSMutableArray	*fields		= [NSMutableArray array];
	NSMutableString	*field		= [NSMutableString string];
	BOOL			 isQuoted	= NO;
	NSUInteger		 length		= [line length];

	for (NSUInteger index = 0; index < length; index++)
	{
		unichar character = [line characterAtIndex:index];

		if (isQuoted)
		{
			if (character != '"')
				[field appendFormat:@"%C", character];
			else if (index + 1 < length && [line characterAtIndex:index + 1] == '"')
			{
				[field appendString:@"\""];
				index++;
			}
			else
				isQuoted = NO;
		}
		else if (character == '"')
			isQuoted = YES;
		else if (character == ',')
		{
			[fields addObject:[field copy]];
			[field setString:@""];
		}
		else
			[field appendFormat:@"%C", character];
	}
	[fields addObject:[field copy]];

	return fields;
}


@implementation LDrawInventoryPartsFile


//---------- itemsFromFileAtURL:error: -------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<LDrawInventoryItem *> *) itemsFromFileAtURL:(NSURL *)url error:(NSError **)error
{
	NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:NULL error:NULL];

	if (text == nil)
		text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];
	if (text == nil)
	{
		if (error != NULL)
			*error = PartsFileError(LDrawInventoryErrorUnreadableFile,
									NSLocalizedString(@"The file could not be read as text.", nil));
		return nil;
	}

	return [self itemsFromString:text error:error];

}//end itemsFromFileAtURL:error:


//---------- itemsFromString:error: ----------------------------------[static]--
///
/// @abstract	Tells the format by the first line: tabs for Bricksmith's
/// 			export, a header with Part, Color and Quantity for Rebrickable.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawInventoryItem *> *) itemsFromString:(NSString *)text error:(NSError **)error
{
	NSMutableArray<NSString *>	*lines	= [NSMutableArray array];
	NSArray						*items	= nil;

	[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([trimmed length] > 0)
			[lines addObject:line];
	}];

	if ([lines count] > 0 && [lines[0] containsString:@"\t"])
		items = [self itemsFromTabbedLines:lines];
	else if ([lines count] > 0)
		items = [self itemsFromCSVLines:lines];

	if (items == nil && error != NULL)
		*error = PartsFileError(LDrawInventoryErrorUnknownFormat,
								NSLocalizedString(@"The file is not a Bricksmith piece count or a Rebrickable "
												  @"parts list.", nil));
	return items;

}//end itemsFromString:error:


//---------- itemsFromTabbedLines: -----------------------------------[static]--
///
/// @abstract	Bricksmith's piece count export. Lines whose quantity is not a
/// 			number, such as the header, are skipped. Nil when none is left.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawInventoryItem *> *) itemsFromTabbedLines:(NSArray<NSString *> *)lines
{
	NSMutableArray		*keys		= [NSMutableArray array];
	NSMutableDictionary	*itemsByKey	= [NSMutableDictionary dictionary];

	for (NSString *line in lines)
	{
		NSArray<NSString *>	*fields		= [line componentsSeparatedByString:@"\t"];
		NSCharacterSet		*spaces		= [NSCharacterSet whitespaceCharacterSet];
		NSInteger			 quantity	= 0;
		NSInteger			 colorCode	= 0;
		NSString			*partName	= nil;
		LDrawInventoryItem	*item		= nil;

		if ([fields count] < 3)
			continue;

		quantity	= PositiveInteger([fields[0] stringByTrimmingCharactersInSet:spaces]);
		colorCode	= PositiveInteger([fields[2] stringByTrimmingCharactersInSet:spaces]);
		partName	= [[fields[1] stringByTrimmingCharactersInSet:spaces] lowercaseString];

		if (quantity <= 0 || colorCode < 0 || [partName length] == 0)
			continue;

		// The export leaves off the extension.
		if ([[partName pathExtension] length] == 0)
			partName = [partName stringByAppendingPathExtension:@"dat"];

		item = [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:nil
													  rebrickableColorID:LDrawRebrickableColorNone
														   ldrawPartName:partName
														  ldrawColorCode:(LDrawColorT)colorCode
																quantity:quantity
														   spareQuantity:0];
		[self addItem:item key:[NSString stringWithFormat:@"%@\n%ld", partName, (long)colorCode]
			   toKeys:keys items:itemsByKey];
	}

	return [keys count] > 0 ? [itemsByKey objectsForKeys:keys notFoundMarker:[NSNull null]] : nil;

}//end itemsFromTabbedLines:


//---------- itemsFromCSVLines: --------------------------------------[static]--
///
/// @abstract	A Rebrickable parts list. Nil without the columns it needs, or
/// 			with no row left.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawInventoryItem *> *) itemsFromCSVLines:(NSArray<NSString *> *)lines
{
	NSMutableArray		*keys			= [NSMutableArray array];
	NSMutableDictionary	*itemsByKey		= [NSMutableDictionary dictionary];
	NSMutableArray		*header			= [NSMutableArray array];
	NSUInteger			 partColumn		= NSNotFound;
	NSUInteger			 colorColumn	= NSNotFound;
	NSUInteger			 countColumn	= NSNotFound;
	NSUInteger			 spareColumn	= NSNotFound;
	NSCharacterSet		*spaces			= [NSCharacterSet whitespaceCharacterSet];

	for (NSString *name in CSVFields(lines[0]))
		[header addObject:[[name stringByTrimmingCharactersInSet:spaces] lowercaseString]];

	partColumn	= [header indexOfObject:@"part"];
	colorColumn	= [header indexOfObject:@"color"];
	countColumn	= [header indexOfObject:@"quantity"];
	spareColumn	= [header indexOfObject:@"is spare"];

	if (partColumn == NSNotFound || colorColumn == NSNotFound || countColumn == NSNotFound)
		return nil;

	for (NSUInteger index = 1; index < [lines count]; index++)
	{
		NSArray<NSString *>	*fields		= CSVFields(lines[index]);
		NSString			*partNumber	= nil;
		NSString			*spareText	= nil;
		NSInteger			 colorID	= 0;
		NSInteger			 quantity	= 0;
		BOOL				 isSpare	= NO;
		LDrawInventoryItem	*item		= nil;

		if ([fields count] <= MAX(partColumn, MAX(colorColumn, countColumn)))
			continue;

		partNumber	= [fields[partColumn] stringByTrimmingCharactersInSet:spaces];
		colorID		= [[fields[colorColumn] stringByTrimmingCharactersInSet:spaces] integerValue];
		quantity	= PositiveInteger([fields[countColumn] stringByTrimmingCharactersInSet:spaces]);

		if (spareColumn != NSNotFound && spareColumn < [fields count])
		{
			spareText	= [[fields[spareColumn] stringByTrimmingCharactersInSet:spaces] lowercaseString];
			isSpare		= [@[@"true", @"yes", @"1"] containsObject:spareText];
		}

		if ([partNumber length] == 0 || quantity <= 0)
			continue;

		item = [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:partNumber
													  rebrickableColorID:colorID
														   ldrawPartName:nil
														  ldrawColorCode:LDrawColorBogus
																quantity:isSpare ? 0 : quantity
														   spareQuantity:isSpare ? quantity : 0];
		[self addItem:item key:[NSString stringWithFormat:@"%@\n%ld", partNumber, (long)colorID]
			   toKeys:keys items:itemsByKey];
	}

	return [keys count] > 0 ? [itemsByKey objectsForKeys:keys notFoundMarker:[NSNull null]] : nil;

}//end itemsFromCSVLines:


//---------- addItem:key:toKeys:items: -------------------------------[static]--
///
/// @abstract	Adds an item, or its counts to the item already listed with the
/// 			same part and color.
///
//------------------------------------------------------------------------------
+ (void) addItem:(LDrawInventoryItem *)item
			 key:(NSString *)key
		  toKeys:(NSMutableArray *)keys
		   items:(NSMutableDictionary *)itemsByKey
{
	LDrawInventoryItem *listed = itemsByKey[key];

	if (listed == nil)
	{
		[keys addObject:key];
		itemsByKey[key] = item;
	}
	else
		itemsByKey[key] = [listed itemByAddingQuantity:item.quantity spareQuantity:item.spareQuantity];

}//end addItem:key:toKeys:items:

@end
