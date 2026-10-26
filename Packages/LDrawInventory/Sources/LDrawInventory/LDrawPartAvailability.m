//==============================================================================
//
//  File:       LDrawPartAvailability.m
//  Package:    LDrawInventory
//
//  Purpose:    For each part and color, when and how often it came in sets.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawPartAvailability.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

static NSString * const AvailabilityVersionKey	= @"version";
static NSString * const AvailabilityDateKey		= @"date";
static NSString * const AvailabilityPartsKey	= @"parts";

/// One record as it is kept in memory, many to a part's data.
typedef struct PackedRecord
{
	int32_t		colorID;
	int16_t		firstYear;
	int16_t		lastYear;
	uint32_t	setCount;
	uint8_t		onlyInDatabaseSets;

} PackedRecord;

/// What the builder keeps for one part and color: the real sets and the
/// Database Sets apart, so the real ones can win at the end.
typedef struct BuilderRecord
{
	int32_t		colorID;
	int16_t		firstYear;
	int16_t		lastYear;
	uint32_t	setCount;
	int16_t		databaseFirstYear;
	int16_t		databaseLastYear;
	uint32_t	databaseSetCount;

} BuilderRecord;


//========== UnpackedRecord ====================================================
//==============================================================================
static LDrawPartAvailabilityRecord UnpackedRecord(PackedRecord packed)
{
	LDrawPartAvailabilityRecord record;

	record.colorID				= packed.colorID;
	record.firstYear			= packed.firstYear;
	record.lastYear				= packed.lastYear;
	record.setCount				= packed.setCount;
	record.onlyInDatabaseSets	= (packed.onlyInDatabaseSets != 0);

	return record;
}


@interface LDrawPartAvailability ()

- (instancetype) initWithDate:(NSDate *)date packedParts:(NSDictionary<NSString *, NSData *> *)packedParts;

@end


@implementation LDrawPartAvailability
{
	NSDictionary<NSString *, NSData *>	*packedParts;	// part number → PackedRecord array
}


// MARK: - INITIALIZATION -


//========== initWithDate:packedParts: =========================================
//==============================================================================
- (instancetype) initWithDate:(NSDate *)date packedParts:(NSDictionary<NSString *, NSData *> *)parts
{
	self = [super init];
	if (self) {
		self->_date			= [date copy];
		self->packedParts	= [parts copy];
	}
	return self;
}


//---------- availabilityWithDictionary: -----------------------------[static]--
///
/// @abstract	A catalog read back from what the store wrote: each part maps
/// 			to rows of color, first year, last year, set count, and 1 when
/// 			only Database Sets hold it.
///
//------------------------------------------------------------------------------
+ (instancetype) availabilityWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	NSDictionary		*parts	= LDrawJSONDictionary(LDrawJSONDictionary(dictionary)[AvailabilityPartsKey]);
	NSMutableDictionary	*packed	= nil;

	if (parts == nil)
		return nil;

	packed = [NSMutableDictionary dictionaryWithCapacity:[parts count]];
	for (id partNumber in parts)
	{
		NSArray			*rows	= LDrawJSONArray(parts[partNumber]);
		NSMutableData	*data	= [NSMutableData data];

		if (LDrawJSONString(partNumber) == nil)
			continue;

		for (id row in rows)
		{
			NSArray			*fields	= LDrawJSONArray(row);
			PackedRecord	 record	= {0};

			if ([fields count] < 4)
				continue;

			record.colorID				= (int32_t)LDrawJSONInteger(fields[0], 0);
			record.firstYear			= (int16_t)LDrawJSONInteger(fields[1], 0);
			record.lastYear				= (int16_t)LDrawJSONInteger(fields[2], 0);
			record.setCount				= (uint32_t)MAX(LDrawJSONInteger(fields[3], 0), 0);
			record.onlyInDatabaseSets	= ([fields count] > 4 && LDrawJSONInteger(fields[4], 0) != 0);

			[data appendBytes:&record length:sizeof(record)];
		}
		if ([data length] > 0)
			packed[partNumber] = data;
	}

	return [[self alloc] initWithDate:LDrawJSONDate(dictionary[AvailabilityDateKey]) packedParts:packed];

}//end availabilityWithDictionary:


// MARK: - ACCESSORS -


//========== partCount =========================================================
//==============================================================================
- (NSUInteger) partCount
{
	return [self->packedParts count];
}


//========== partNumbers =======================================================
//==============================================================================
- (NSArray<NSString *> *) partNumbers
{
	return [self->packedParts allKeys];
}


//========== getRecord:forPartNumber:colorID: ==================================
///
/// @abstract	Fills the record and returns YES when the part came in the
/// 			color.
///
//==============================================================================
- (BOOL) getRecord:(LDrawPartAvailabilityRecord *)record
	 forPartNumber:(NSString *)partNumber
		   colorID:(NSInteger)colorID
{
	NSData				*data		= self->packedParts[partNumber];
	const PackedRecord	*records	= [data bytes];
	NSUInteger			 count		= [data length] / sizeof(PackedRecord);

	for (NSUInteger index = 0; index < count; index++)
	{
		if (records[index].colorID == colorID)
		{
			if (record != NULL)
				*record = UnpackedRecord(records[index]);
			return YES;
		}
	}
	return NO;

}//end getRecord:forPartNumber:colorID:


//========== enumerateRecordsForPartNumber:usingBlock: =========================
//==============================================================================
- (void) enumerateRecordsForPartNumber:(NSString *)partNumber
							usingBlock:(void (NS_NOESCAPE ^)(LDrawPartAvailabilityRecord record))block
{
	NSData				*data		= self->packedParts[partNumber];
	const PackedRecord	*records	= [data bytes];
	NSUInteger			 count		= [data length] / sizeof(PackedRecord);

	for (NSUInteger index = 0; index < count; index++)
		block(UnpackedRecord(records[index]));

}//end enumerateRecordsForPartNumber:usingBlock:


// MARK: - ARCHIVING -


//========== dictionaryRepresentation ==========================================
//==============================================================================
- (NSDictionary<NSString *, id> *) dictionaryRepresentation
{
	NSMutableDictionary	*parts		= [NSMutableDictionary dictionaryWithCapacity:[self->packedParts count]];
	NSMutableDictionary	*dictionary	= [NSMutableDictionary dictionary];

	for (NSString *partNumber in self->packedParts)
	{
		NSMutableArray *rows = [NSMutableArray array];

		[self enumerateRecordsForPartNumber:partNumber usingBlock:^(LDrawPartAvailabilityRecord record) {
			[rows addObject:@[@(record.colorID), @(record.firstYear), @(record.lastYear),
							  @(record.setCount), @(record.onlyInDatabaseSets ? 1 : 0)]];
		}];
		parts[partNumber] = rows;
	}

	dictionary[AvailabilityVersionKey]	= @(LDrawInventoryFileVersion);
	dictionary[AvailabilityPartsKey]	= parts;
	if (self.date != nil)
		dictionary[AvailabilityDateKey] = LDrawJSONStringFromDate(self.date);

	return dictionary;

}//end dictionaryRepresentation

@end


@implementation LDrawPartAvailabilityBuilder
{
	NSMutableDictionary<NSString *, NSMutableData *>	*builderParts;	// part number → BuilderRecord array
}


//========== init ==============================================================
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->builderParts = [NSMutableDictionary dictionary];
	}
	return self;
}


//========== notePartNumber:colorID:year:inDatabaseSet: ========================
///
/// @abstract	Counts one more set from this year that holds the part in this
/// 			color.
///
//==============================================================================
- (void) notePartNumber:(NSString *)partNumber
				colorID:(NSInteger)colorID
				   year:(NSInteger)year
		  inDatabaseSet:(BOOL)isDatabaseSet
{
	NSMutableData	*data		= self->builderParts[partNumber];
	BuilderRecord	*records	= NULL;
	BuilderRecord	*record		= NULL;
	NSUInteger		 count		= 0;

	if (data == nil)
	{
		data = [NSMutableData data];
		self->builderParts[partNumber] = data;
	}

	records	= [data mutableBytes];
	count	= [data length] / sizeof(BuilderRecord);
	for (NSUInteger index = 0; index < count && record == NULL; index++)
	{
		if (records[index].colorID == colorID)
			record = &records[index];
	}

	if (record == NULL)
	{
		BuilderRecord fresh = {0};
		fresh.colorID = (int32_t)colorID;
		[data appendBytes:&fresh length:sizeof(fresh)];
		record = (BuilderRecord *)[data mutableBytes] + count;
	}

	if (isDatabaseSet)
	{
		if (record->databaseSetCount == 0 || year < record->databaseFirstYear)
			record->databaseFirstYear = (int16_t)year;
		record->databaseLastYear	= MAX(record->databaseLastYear, (int16_t)year);
		record->databaseSetCount	+= 1;
	}
	else
	{
		if (record->setCount == 0 || year < record->firstYear)
			record->firstYear = (int16_t)year;
		record->lastYear	= MAX(record->lastYear, (int16_t)year);
		record->setCount	+= 1;
	}

}//end notePartNumber:colorID:year:inDatabaseSet:


//========== availabilityWithDate: =============================================
///
/// @abstract	The catalog of everything noted so far.
///
//==============================================================================
- (LDrawPartAvailability *) availabilityWithDate:(NSDate *)date
{
	NSMutableDictionary *packed = [NSMutableDictionary dictionaryWithCapacity:[self->builderParts count]];

	for (NSString *partNumber in self->builderParts)
	{
		NSData				*data		= self->builderParts[partNumber];
		const BuilderRecord	*records	= [data bytes];
		NSUInteger			 count		= [data length] / sizeof(BuilderRecord);
		NSMutableData		*out		= [NSMutableData dataWithCapacity:count * sizeof(PackedRecord)];

		for (NSUInteger index = 0; index < count; index++)
		{
			BuilderRecord	from	= records[index];
			PackedRecord	to		= {0};
			BOOL			isReal	= (from.setCount > 0);

			to.colorID				= from.colorID;
			to.firstYear			= isReal ? from.firstYear : from.databaseFirstYear;
			to.lastYear				= isReal ? from.lastYear : from.databaseLastYear;
			to.setCount				= isReal ? from.setCount : from.databaseSetCount;
			to.onlyInDatabaseSets	= (isReal == NO);

			[out appendBytes:&to length:sizeof(to)];
		}
		packed[partNumber] = out;
	}

	return [[LDrawPartAvailability alloc] initWithDate:date packedParts:packed];

}//end availabilityWithDate:

@end
