//==============================================================================
//
//  File:       LDrawSetInventory.m
//  Package:    LDrawInventory
//
//  Purpose:    The parts of one LEGO set, as an import fetched them.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawSetInventory.h>

#import <LDrawInventory/LDrawInventoryItem.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

static NSString * const SetVersionKey	= @"version";
static NSString * const SetNumberKey	= @"setNumber";
static NSString * const SetNameKey		= @"name";
static NSString * const SetYearKey		= @"year";
static NSString * const SetThemeKey		= @"theme";
static NSString * const SetImageKey		= @"image";
static NSString * const SetItemsKey		= @"items";
static NSString * const SetFetchedKey	= @"fetched";
static NSString * const SetSourceKey	= @"source";


@implementation LDrawSetInventory


// MARK: - INITIALIZATION -


//========== initWithSetNumber:... =============================================
///
/// @abstract	Designated initializer.
///
//==============================================================================
- (instancetype) initWithSetNumber:(NSString *)setNumber
							  name:(NSString *)name
							  year:(NSInteger)year
						 themeName:(NSString *)themeName
						  imageURL:(NSString *)imageURL
							 items:(NSArray<LDrawInventoryItem *> *)items
						 fetchDate:(NSDate *)fetchDate
							source:(NSString *)source
{
	self = [super init];
	if (self) {
		self->_setNumber	= [setNumber copy];
		self->_name			= [name copy];
		self->_year			= year;
		self->_themeName	= [themeName copy];
		self->_imageURL		= [imageURL copy];
		self->_items		= [items copy];
		self->_fetchDate	= [fetchDate copy];
		self->_source		= [source copy];
	}
	return self;

}//end initWithSetNumber:...


//---------- setInventoryWithDictionary: -----------------------------[static]--
///
/// @abstract	A set read back from what the store wrote.
///
//------------------------------------------------------------------------------
+ (instancetype) setInventoryWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	NSString		*setNumber	= nil;
	NSMutableArray	*items		= [NSMutableArray array];

	if (LDrawJSONDictionary(dictionary) == nil)
		return nil;

	setNumber = [self normalizedSetNumber:LDrawJSONString(dictionary[SetNumberKey])];
	if (setNumber == nil)
		return nil;

	for (id itemDictionary in LDrawJSONArray(dictionary[SetItemsKey]))
	{
		LDrawInventoryItem *item = [LDrawInventoryItem itemWithDictionary:itemDictionary];
		if (item != nil)
			[items addObject:item];
	}

	return [[self alloc] initWithSetNumber:setNumber
									  name:LDrawJSONString(dictionary[SetNameKey]) ?: setNumber
									  year:LDrawJSONInteger(dictionary[SetYearKey], 0)
								 themeName:LDrawJSONString(dictionary[SetThemeKey])
								  imageURL:LDrawJSONString(dictionary[SetImageKey])
									 items:items
								 fetchDate:LDrawJSONDate(dictionary[SetFetchedKey])
									source:LDrawJSONString(dictionary[SetSourceKey])];

}//end setInventoryWithDictionary:


// MARK: - ACCESSORS -


//========== partCount =========================================================
//==============================================================================
- (NSUInteger) partCount
{
	NSUInteger count = 0;

	for (LDrawInventoryItem *item in self.items)
		count += item.quantity;
	return count;
}


//========== spareCount ========================================================
//==============================================================================
- (NSUInteger) spareCount
{
	NSUInteger count = 0;

	for (LDrawInventoryItem *item in self.items)
		count += item.spareQuantity;
	return count;
}


//---------- normalizedSetNumber: ------------------------------------[static]--
///
/// @abstract	A set number as Rebrickable writes it.
///
/// @discussion	Rebrickable ends every set number with a version: "42115-1".
/// 			A number typed without one means the first version. A minifigure
/// 			number like "fig-000123" already ends in digits after a hyphen,
/// 			so it is left alone.
///
//------------------------------------------------------------------------------
+ (NSString *) normalizedSetNumber:(NSString *)setNumber
{
	NSCharacterSet	*whitespace	= [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSCharacterSet	*nonDigits	= [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
	NSString		*trimmed	= [[setNumber stringByTrimmingCharactersInSet:whitespace] lowercaseString];
	NSRange			 hyphen		= NSMakeRange(NSNotFound, 0);
	NSString		*suffix		= nil;

	if ([trimmed length] == 0)
		return nil;

	hyphen = [trimmed rangeOfString:@"-" options:NSBackwardsSearch];
	if (hyphen.location != NSNotFound)
	{
		suffix = [trimmed substringFromIndex:NSMaxRange(hyphen)];
		if ([suffix length] > 0 && [suffix rangeOfCharacterFromSet:nonDigits].location == NSNotFound)
			return trimmed;
	}
	return [trimmed stringByAppendingString:@"-1"];

}//end normalizedSetNumber:


// MARK: - ARCHIVING -


//========== dictionaryRepresentation ==========================================
//==============================================================================
- (NSDictionary<NSString *, id> *) dictionaryRepresentation
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

	dictionary[SetVersionKey]	= @(LDrawInventoryFileVersion);
	dictionary[SetNumberKey]	= self.setNumber;
	dictionary[SetNameKey]		= self.name;
	dictionary[SetItemsKey]		= [self.items valueForKey:@"dictionaryRepresentation"];

	if (self.year != 0)
		dictionary[SetYearKey] = @(self.year);
	if (self.themeName != nil)
		dictionary[SetThemeKey] = self.themeName;
	if (self.imageURL != nil)
		dictionary[SetImageKey] = self.imageURL;
	if (self.fetchDate != nil)
		dictionary[SetFetchedKey] = LDrawJSONStringFromDate(self.fetchDate);
	if (self.source != nil)
		dictionary[SetSourceKey] = self.source;

	return dictionary;

}//end dictionaryRepresentation


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@ \"%@\" %lu items>",
			[self class], self.setNumber, self.name, (unsigned long)[self.items count]];
}

@end
