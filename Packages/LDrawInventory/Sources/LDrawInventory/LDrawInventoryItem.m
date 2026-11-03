//==============================================================================
//
//  File:       LDrawInventoryItem.m
//  Package:    LDrawInventory
//
//  Purpose:    One part in one color, and how many of it an inventory holds.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawInventoryItem.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

const NSInteger LDrawRebrickableColorAny		= 9999;
const NSInteger LDrawRebrickableColorUnknown	= -1;
const NSInteger LDrawRebrickableColorNone		= NSNotFound;

static NSString * const ItemPartKey			= @"part";
static NSString * const ItemColorKey		= @"color";
static NSString * const ItemLDrawPartKey	= @"ldrawPart";
static NSString * const ItemLDrawColorKey	= @"ldrawColor";
static NSString * const ItemQuantityKey		= @"quantity";
static NSString * const ItemSparesKey		= @"spares";


@implementation LDrawInventoryItem


// MARK: - INITIALIZATION -


//========== initWithRebrickablePartNumber:... =================================
///
/// @abstract	Designated initializer.
///
//==============================================================================
- (instancetype) initWithRebrickablePartNumber:(NSString *)partNumber
							rebrickableColorID:(NSInteger)colorID
								 ldrawPartName:(NSString *)ldrawPartName
								ldrawColorCode:(LDrawColorT)ldrawColorCode
									  quantity:(NSUInteger)quantity
								 spareQuantity:(NSUInteger)spareQuantity
{
	self = [super init];
	if (self) {
		self->_rebrickablePartNumber	= [partNumber copy];
		self->_rebrickableColorID		= colorID;
		self->_ldrawPartName			= [ldrawPartName copy];
		self->_ldrawColorCode			= ldrawColorCode;
		self->_quantity					= quantity;
		self->_spareQuantity			= spareQuantity;
	}
	return self;

}//end initWithRebrickablePartNumber:...


//---------- itemWithDictionary: -------------------------------------[static]--
///
/// @abstract	An item read back from what the store wrote.
///
//------------------------------------------------------------------------------
+ (instancetype) itemWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	if (LDrawJSONDictionary(dictionary) == nil)
		return nil;

	NSString	*partNumber		= LDrawJSONString(dictionary[ItemPartKey]);
	NSString	*ldrawPartName	= LDrawJSONString(dictionary[ItemLDrawPartKey]);
	NSInteger	 colorID		= LDrawJSONInteger(dictionary[ItemColorKey], LDrawRebrickableColorNone);
	NSInteger	 ldrawColor		= LDrawJSONInteger(dictionary[ItemLDrawColorKey], LDrawColorBogus);
	NSInteger	 quantity		= LDrawJSONInteger(dictionary[ItemQuantityKey], 0);
	NSInteger	 spares			= LDrawJSONInteger(dictionary[ItemSparesKey], 0);

	if (partNumber == nil && ldrawPartName == nil)
		return nil;
	if (quantity < 0 || spares < 0 || quantity + spares == 0)
		return nil;

	return [[self alloc] initWithRebrickablePartNumber:partNumber
									rebrickableColorID:colorID
										 ldrawPartName:ldrawPartName
										ldrawColorCode:(LDrawColorT)ldrawColor
											  quantity:(NSUInteger)quantity
										 spareQuantity:(NSUInteger)spares];

}//end itemWithDictionary:


// MARK: - DERIVED ITEMS -


//========== itemByAddingQuantity:spareQuantity: ===============================
//==============================================================================
- (LDrawInventoryItem *) itemByAddingQuantity:(NSUInteger)quantity
								spareQuantity:(NSUInteger)spareQuantity
{
	return [self itemWithQuantity:self.quantity + quantity spareQuantity:self.spareQuantity + spareQuantity];
}


//========== itemMultipliedBy: =================================================
//==============================================================================
- (LDrawInventoryItem *) itemMultipliedBy:(NSUInteger)factor
{
	return [self itemWithQuantity:self.quantity * factor spareQuantity:self.spareQuantity * factor];
}


//========== itemWithQuantity:spareQuantity: ===================================
///
/// @abstract	The same part and color with these counts.
///
//==============================================================================
- (LDrawInventoryItem *) itemWithQuantity:(NSUInteger)quantity spareQuantity:(NSUInteger)spareQuantity
{
	return [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:self.rebrickablePartNumber
												  rebrickableColorID:self.rebrickableColorID
													   ldrawPartName:self.ldrawPartName
													  ldrawColorCode:self.ldrawColorCode
															quantity:quantity
													   spareQuantity:spareQuantity];

}//end itemWithQuantity:spareQuantity:


// MARK: - ARCHIVING -


//========== dictionaryRepresentation ==========================================
///
/// @abstract	What the store writes. Ids the source did not give are left out.
///
//==============================================================================
- (NSDictionary<NSString *, id> *) dictionaryRepresentation
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

	if (self.rebrickablePartNumber != nil)
		dictionary[ItemPartKey] = self.rebrickablePartNumber;
	if (self.rebrickableColorID != LDrawRebrickableColorNone)
		dictionary[ItemColorKey] = @(self.rebrickableColorID);
	if (self.ldrawPartName != nil)
		dictionary[ItemLDrawPartKey] = self.ldrawPartName;
	if (self.ldrawColorCode != LDrawColorBogus)
		dictionary[ItemLDrawColorKey] = @(self.ldrawColorCode);

	dictionary[ItemQuantityKey] = @(self.quantity);
	if (self.spareQuantity > 0)
		dictionary[ItemSparesKey] = @(self.spareQuantity);

	return dictionary;

}//end dictionaryRepresentation


// MARK: - NSObject -


//========== copyWithZone: =====================================================
///
/// @abstract	Immutable, so a copy is the item itself.
///
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	return self;
}


//========== isEqual: ==========================================================
///
/// @abstract	Same ids and same counts.
///
//==============================================================================
- (BOOL) isEqual:(id)object
{
	if (object == self)
		return YES;
	if ([object isKindOfClass:[LDrawInventoryItem class]] == NO)
		return NO;

	LDrawInventoryItem *other = object;

	return	(self.rebrickablePartNumber == other.rebrickablePartNumber
			 || [self.rebrickablePartNumber isEqualToString:other.rebrickablePartNumber])
		&&	(self.ldrawPartName == other.ldrawPartName
			 || [self.ldrawPartName isEqualToString:other.ldrawPartName])
		&&	self.rebrickableColorID	== other.rebrickableColorID
		&&	self.ldrawColorCode		== other.ldrawColorCode
		&&	self.quantity			== other.quantity
		&&	self.spareQuantity		== other.spareQuantity;

}//end isEqual:


//========== hash ==============================================================
//==============================================================================
- (NSUInteger) hash
{
	return [self.rebrickablePartNumber hash] ^ [self.ldrawPartName hash] ^ (NSUInteger)self.rebrickableColorID;
}


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@/%@ color %ld/%d ×%lu+%lu>",
			[self class], self.rebrickablePartNumber, self.ldrawPartName,
			(long)self.rebrickableColorID, (int)self.ldrawColorCode,
			(unsigned long)self.quantity, (unsigned long)self.spareQuantity];
}

@end
