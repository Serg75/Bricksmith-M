//==============================================================================
//
//  File:       LDrawRebrickableSetImporter.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Gets the parts of one set, from the downloads or from the API.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableSetImporter.h>

#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawInventoryJSON.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableClient.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>

#import "LDrawRebrickableInventoryIndex.h"

static NSString * const SourceDownloads	= @"rebrickable-downloads";
static NSString * const SourceAPI		= @"rebrickable-api";

/// Sets inside sets go only a few levels deep; a loop must not hang.
static const NSUInteger MaximumNesting = 6;


/// Adds up quantities and spares by part and color, and makes the items.
@interface LDrawRebrickableItemTally : NSObject
- (void) addPartNumber:(NSString *)partNumber
			   colorID:(NSInteger)colorID
		 ldrawPartName:(NSString *)ldrawPartName
		ldrawColorCode:(LDrawColorT)ldrawColorCode
			  quantity:(NSUInteger)quantity
			   isSpare:(BOOL)isSpare;
- (NSArray<LDrawInventoryItem *> *) items;
@end


@implementation LDrawRebrickableItemTally
{
	NSMutableDictionary<NSString *, LDrawInventoryItem *> *itemsByKey;
}

//========== init ==============================================================
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->itemsByKey = [NSMutableDictionary dictionary];
	}
	return self;
}

//========== addPartNumber:... =================================================
//==============================================================================
- (void) addPartNumber:(NSString *)partNumber
			   colorID:(NSInteger)colorID
		 ldrawPartName:(NSString *)ldrawPartName
		ldrawColorCode:(LDrawColorT)ldrawColorCode
			  quantity:(NSUInteger)quantity
			   isSpare:(BOOL)isSpare
{
	NSString			*key		= [NSString stringWithFormat:@"%@\n%ld", partNumber, (long)colorID];
	NSUInteger			 regular	= isSpare ? 0 : quantity;
	NSUInteger			 spares		= isSpare ? quantity : 0;
	LDrawInventoryItem	*item		= self->itemsByKey[key];

	if (item == nil)
		item = [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:partNumber
													  rebrickableColorID:colorID
														   ldrawPartName:ldrawPartName
														  ldrawColorCode:ldrawColorCode
																quantity:regular
														   spareQuantity:spares];
	else
		item = [item itemByAddingQuantity:regular spareQuantity:spares];

	self->itemsByKey[key] = item;
}

//========== items =============================================================
///
/// @abstract	By part number in natural order, then color.
///
//==============================================================================
- (NSArray<LDrawInventoryItem *> *) items
{
	return [[self->itemsByKey allValues] sortedArrayUsingComparator:^NSComparisonResult(LDrawInventoryItem *a,
																						LDrawInventoryItem *b) {
		NSComparisonResult order = [a.rebrickablePartNumber localizedStandardCompare:b.rebrickablePartNumber];
		if (order != NSOrderedSame)
			return order;
		return [@(a.rebrickableColorID) compare:@(b.rebrickableColorID)];
	}];
}

@end


@implementation LDrawRebrickableSetImporter


// MARK: - FROM THE DOWNLOADS -


//---------- setInventoryForNumber:fromDownloads:setList:error: ------[static]--
///
/// @abstract	The set's parts from the downloads.
///
//------------------------------------------------------------------------------
+ (LDrawSetInventory *) setInventoryForNumber:(NSString *)setNumber
								fromDownloads:(LDrawRebrickableDownloads *)downloads
									  setList:(LDrawRebrickableSetList *)setList
										error:(NSError **)error
{
	LDrawRebrickableSet				*set			= [setList setForNumber:setNumber];
	LDrawRebrickableInventoryIndex	*index			= nil;
	NSMutableDictionary				*multipliers	= [NSMutableDictionary dictionary];	// inventory id → count
	LDrawRebrickableItemTally		*tally			= [[LDrawRebrickableItemTally alloc] init];

	if (set == nil)
	{
		NSString *reason = [NSString stringWithFormat:@"Rebrickable has no set %@.", setNumber];

		if (error != NULL)
			*error = [NSError errorWithDomain:LDrawRebrickableErrorDomain
										 code:LDrawRebrickableErrorNotFound
									 userInfo:@{ NSLocalizedDescriptionKey : reason }];
		return nil;
	}

	index = [LDrawRebrickableInventoryIndex indexFromDownloads:downloads error:error];
	if (index == nil)
		return nil;

	[self addInventoryOfNumber:set.setNumber count:1 index:index multipliers:multipliers depth:0];

	BOOL didRead = [index enumeratePartsUsingBlock:^(NSString *inventoryID, NSString *partNumber, NSInteger colorID,
													 NSUInteger quantity, BOOL isSpare, BOOL *stop) {
		NSUInteger count = [multipliers[inventoryID] unsignedIntegerValue];

		if (count > 0)
			[tally addPartNumber:partNumber colorID:colorID ldrawPartName:nil ldrawColorCode:LDrawColorBogus
						quantity:quantity * count isSpare:isSpare];
	} error:error];

	if (didRead == NO)
		return nil;

	return [[LDrawSetInventory alloc] initWithSetNumber:set.setNumber
												   name:set.name
												   year:set.year
											  themeName:set.themeName
											   imageURL:set.imageURL
												  items:[tally items]
											  fetchDate:[NSDate date]
												 source:SourceDownloads];

}//end setInventoryForNumber:fromDownloads:setList:error:


//---------- addInventoryOfNumber:count:index:multipliers:depth: -----[static]--
///
/// @abstract	Counts a set's or minifigure's newest inventory, and what it
/// 			holds, as many times as it comes.
///
//------------------------------------------------------------------------------
+ (void) addInventoryOfNumber:(NSString *)number
						count:(NSUInteger)count
						index:(LDrawRebrickableInventoryIndex *)index
				  multipliers:(NSMutableDictionary *)multipliers
						depth:(NSUInteger)depth
{
	NSString *inventoryID = [index latestInventoryIDForNumber:number];

	if (inventoryID == nil || depth > MaximumNesting)
		return;

	multipliers[inventoryID] = @([multipliers[inventoryID] unsignedIntegerValue] + count);

	for (NSArray *child in [index childrenOfInventoryID:inventoryID])
	{
		[self addInventoryOfNumber:child[0]
							 count:count * [child[1] unsignedIntegerValue]
							 index:index
					   multipliers:multipliers
							 depth:depth + 1];
	}

}//end addInventoryOfNumber:count:index:multipliers:depth:


// MARK: - FROM THE API -


//---------- fetchSetInventoryForNumber:client:setList:completion: ---[static]--
///
/// @abstract	The set, then its parts with minifigure parts and part details.
///
//------------------------------------------------------------------------------
+ (void) fetchSetInventoryForNumber:(NSString *)setNumber
							 client:(LDrawRebrickableClient *)client
							setList:(LDrawRebrickableSetList *)setList
						 completion:(void (^)(LDrawSetInventory *, NSDictionary<NSString *, NSString *> *,
											  NSError *))completion
{
	NSString *number	= [LDrawSetInventory normalizedSetNumber:setNumber] ?: @"";
	NSString *escaped	= [number stringByAddingPercentEncodingWithAllowedCharacters:
						   [NSCharacterSet URLPathAllowedCharacterSet]];
	NSString *setPath	= [NSString stringWithFormat:@"lego/sets/%@/", escaped];

	[client fetchObjectAtPath:setPath parameters:nil completion:^(NSDictionary *setObject, NSError *error) {
		if (setObject == nil)
		{
			completion(nil, @{}, error);
			return;
		}

		NSDictionary *parameters = @{ @"inc_minifig_parts" : @"1", @"inc_part_details" : @"1" };
		[client fetchAllResultsAtPath:[setPath stringByAppendingString:@"parts/"]
						   parameters:parameters
						   completion:^(NSArray<NSDictionary *> *rows, NSError *partsError) {
			NSDictionary		*links	= nil;
			LDrawSetInventory	*set	= nil;

			if (rows == nil)
			{
				completion(nil, @{}, partsError);
				return;
			}
			set = [self setInventoryFromSetObject:setObject partRows:rows setList:setList partLinks:&links];
			completion(set, links, nil);
		}];
	}];

}//end fetchSetInventoryForNumber:client:setList:completion:


//---------- setInventoryFromSetObject:partRows:setList:partLinks: ---[static]--
///
/// @abstract	The set inventory in the API's answers. Each part keeps the
/// 			first LDraw id Rebrickable gives it; every LDraw id it gives
/// 			becomes a link.
///
//------------------------------------------------------------------------------
+ (LDrawSetInventory *) setInventoryFromSetObject:(NSDictionary *)setObject
										 partRows:(NSArray<NSDictionary *> *)partRows
										  setList:(LDrawRebrickableSetList *)setList
										partLinks:(NSDictionary **)partLinks
{
	LDrawRebrickableItemTally	*tally		= [[LDrawRebrickableItemTally alloc] init];
	NSMutableDictionary			*links		= [NSMutableDictionary dictionary];
	NSString					*number		= [LDrawSetInventory normalizedSetNumber:
											   LDrawJSONString(setObject[@"set_num"])] ?: @"";

	for (NSDictionary *row in partRows)
	{
		NSDictionary	*part			= LDrawJSONDictionary(row[@"part"]);
		NSDictionary	*color			= LDrawJSONDictionary(row[@"color"]);
		NSString		*partNumber		= LDrawJSONString(part[@"part_num"]);
		NSInteger		 colorID		= LDrawJSONInteger(color[@"id"], LDrawRebrickableColorNone);
		NSInteger		 quantity		= LDrawJSONInteger(row[@"quantity"], 0);
		NSArray			*ldrawParts		= LDrawJSONArray(LDrawJSONDictionary(part[@"external_ids"])[@"LDraw"]);
		NSDictionary	*ldrawColors	= LDrawJSONDictionary(LDrawJSONDictionary(color[@"external_ids"])[@"LDraw"]);
		NSArray			*colorCodes		= LDrawJSONArray(ldrawColors[@"ext_ids"]);
		NSString		*ldrawPartName	= nil;
		NSInteger		 ldrawColor		= ([colorCodes count] > 0) ? LDrawJSONInteger(colorCodes[0], LDrawColorBogus)
																   : LDrawColorBogus;

		if (partNumber == nil || quantity <= 0)
			continue;

		for (id ldrawID in ldrawParts)
		{
			NSString *name = LDrawJSONString(ldrawID);
			if (name == nil)
				continue;

			name = [[name lowercaseString] stringByAppendingString:@".dat"];
			links[name] = partNumber;
			if (ldrawPartName == nil)
				ldrawPartName = name;
		}

		[tally addPartNumber:partNumber
					 colorID:colorID
			   ldrawPartName:ldrawPartName
			  ldrawColorCode:(LDrawColorT)ldrawColor
					quantity:(NSUInteger)quantity
					 isSpare:LDrawJSONBool(row[@"is_spare"], NO)];
	}

	if (partLinks != NULL)
		*partLinks = links;

	return [[LDrawSetInventory alloc] initWithSetNumber:number
												   name:LDrawJSONString(setObject[@"name"]) ?: number
												   year:LDrawJSONInteger(setObject[@"year"], 0)
											  themeName:[setList setForNumber:number].themeName
											   imageURL:LDrawJSONString(setObject[@"set_img_url"])
												  items:[tally items]
											  fetchDate:[NSDate date]
												 source:SourceAPI];

}//end setInventoryFromSetObject:partRows:setList:partLinks:

@end
