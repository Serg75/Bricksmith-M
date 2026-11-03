//==============================================================================
//
//  File:       LDrawPartLimit.m
//  Package:    LDrawInventory
//
//  Purpose:    Which parts the editor lets a model use, and how strictly.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawPartLimit.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

#import <sys/xattr.h>

NSString * const LDrawPartLimitFileAttributeName = @"com.AllenSmith.Bricksmith.PartsLimit";

static NSString * const LimitKindKey					= @"kind";
static NSString * const LimitYearsBackKey				= @"yearsBack";
static NSString * const LimitCountsPickABrickKey		= @"countsPickABrickParts";
static NSString * const LimitInventoryKey				= @"inventory";
static NSString * const LimitIncludesSparesKey			= @"includesSpares";
static NSString * const LimitMatchesMoldVariantsKey		= @"matchesMoldVariants";
static NSString * const LimitMatchesAnyPrintKey			= @"matchesAnyPrint";
static NSString * const LimitMatchesAnyColorKey			= @"matchesAnyColor";
static NSString * const LimitWarnsOnlyKey				= @"warnsOnly";

static NSString * const LimitKindNone			= @"none";
static NSString * const LimitKindAvailableNow	= @"availableNow";
static NSString * const LimitKindInventory		= @"inventory";

static const NSInteger DefaultYearsBack = 5;


// The ivars are declared here, so the mutable subclass can set them.
@interface LDrawPartLimit ()
{
	@protected
	LDrawPartLimitKind	_kind;
	NSInteger			_yearsBack;
	BOOL				_countsPickABrickParts;
	NSString			*_inventoryIdentifier;
	BOOL				_includesSpares;
	BOOL				_matchesMoldVariants;
	BOOL				_matchesAnyPrint;
	BOOL				_matchesAnyColor;
	BOOL				_warnsOnly;
}

- (void) takeValuesFromLimit:(LDrawPartLimit *)limit;

@end


@implementation LDrawPartLimit


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	No limit, with the default options.
///
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_kind					= LDrawPartLimitKindNone;
		self->_yearsBack			= DefaultYearsBack;
		self->_includesSpares		= YES;
		self->_matchesMoldVariants	= YES;
	}
	return self;
}


//---------- noLimit -------------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (LDrawPartLimit *) noLimit
{
	return [[LDrawPartLimit alloc] init];
}


//---------- availableNowLimit ---------------------------------------[static]--
//------------------------------------------------------------------------------
+ (LDrawPartLimit *) availableNowLimit
{
	return [[LDrawPartLimit noLimit] limitWithKind:LDrawPartLimitKindAvailableNow inventoryIdentifier:nil];
}


//---------- limitWithInventoryIdentifier: ---------------------------[static]--
//------------------------------------------------------------------------------
+ (LDrawPartLimit *) limitWithInventoryIdentifier:(NSString *)identifier
{
	return [[LDrawPartLimit noLimit] limitWithKind:LDrawPartLimitKindInventory inventoryIdentifier:identifier];
}


//========== limitWithKind:inventoryIdentifier: ================================
//==============================================================================
- (LDrawPartLimit *) limitWithKind:(LDrawPartLimitKind)kind inventoryIdentifier:(NSString *)identifier
{
	LDrawMutablePartLimit *limit = [self mutableCopy];

	limit.kind					= kind;
	limit.inventoryIdentifier	= (kind == LDrawPartLimitKindInventory) ? identifier : nil;
	if (kind == LDrawPartLimitKindInventory && [identifier length] == 0)
		limit.kind = LDrawPartLimitKindNone;

	return [limit copy];

}//end limitWithKind:inventoryIdentifier:


//========== takeValuesFromLimit: ==============================================
//==============================================================================
- (void) takeValuesFromLimit:(LDrawPartLimit *)limit
{
	self->_kind						= limit.kind;
	self->_yearsBack				= limit.yearsBack;
	self->_countsPickABrickParts	= limit.countsPickABrickParts;
	self->_inventoryIdentifier		= [limit.inventoryIdentifier copy];
	self->_includesSpares			= limit.includesSpares;
	self->_matchesMoldVariants		= limit.matchesMoldVariants;
	self->_matchesAnyPrint			= limit.matchesAnyPrint;
	self->_matchesAnyColor			= limit.matchesAnyColor;
	self->_warnsOnly				= limit.warnsOnly;
}


// MARK: - ACCESSORS -


//========== isRestricting =====================================================
//==============================================================================
- (BOOL) isRestricting
{
	return self.kind != LDrawPartLimitKindNone;
}


//========== firstYearForCurrentYear: ==========================================
//==============================================================================
- (NSInteger) firstYearForCurrentYear:(NSInteger)currentYear
{
	if (self.yearsBack <= 0)
		return NSIntegerMin;
	return currentYear - self.yearsBack + 1;
}


// MARK: - ARCHIVING -


//========== dictionaryRepresentation ==========================================
//==============================================================================
- (NSDictionary<NSString *, id> *) dictionaryRepresentation
{
	NSMutableDictionary	*dictionary	= [NSMutableDictionary dictionary];
	NSString			*kind		= LimitKindNone;

	if (self.kind == LDrawPartLimitKindAvailableNow)
		kind = LimitKindAvailableNow;
	else if (self.kind == LDrawPartLimitKindInventory)
		kind = LimitKindInventory;

	dictionary[LimitKindKey]				= kind;
	dictionary[LimitYearsBackKey]			= @(self.yearsBack);
	dictionary[LimitCountsPickABrickKey]	= @(self.countsPickABrickParts);
	dictionary[LimitIncludesSparesKey]		= @(self.includesSpares);
	dictionary[LimitMatchesMoldVariantsKey]	= @(self.matchesMoldVariants);
	dictionary[LimitMatchesAnyPrintKey]		= @(self.matchesAnyPrint);
	dictionary[LimitMatchesAnyColorKey]		= @(self.matchesAnyColor);
	dictionary[LimitWarnsOnlyKey]			= @(self.warnsOnly);
	if (self.inventoryIdentifier != nil)
		dictionary[LimitInventoryKey] = self.inventoryIdentifier;

	return dictionary;

}//end dictionaryRepresentation


//---------- limitWithDictionary: ------------------------------------[static]--
///
/// @abstract	The limit read back from the host's defaults.
///
//------------------------------------------------------------------------------
+ (LDrawPartLimit *) limitWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	NSDictionary			*values	= LDrawJSONDictionary(dictionary);
	NSString				*kind	= LDrawJSONString(values[LimitKindKey]);
	LDrawMutablePartLimit	*limit	= [[LDrawMutablePartLimit alloc] init];

	if ([kind isEqualToString:LimitKindAvailableNow])
		limit.kind = LDrawPartLimitKindAvailableNow;
	else if ([kind isEqualToString:LimitKindInventory])
		limit.kind = LDrawPartLimitKindInventory;

	limit.yearsBack				= MAX(LDrawJSONInteger(values[LimitYearsBackKey], DefaultYearsBack), 0);
	limit.countsPickABrickParts	= LDrawJSONBool(values[LimitCountsPickABrickKey], NO);
	limit.inventoryIdentifier	= LDrawJSONString(values[LimitInventoryKey]);
	limit.includesSpares		= LDrawJSONBool(values[LimitIncludesSparesKey], YES);
	limit.matchesMoldVariants	= LDrawJSONBool(values[LimitMatchesMoldVariantsKey], YES);
	limit.matchesAnyPrint		= LDrawJSONBool(values[LimitMatchesAnyPrintKey], NO);
	limit.matchesAnyColor		= LDrawJSONBool(values[LimitMatchesAnyColorKey], NO);
	limit.warnsOnly				= LDrawJSONBool(values[LimitWarnsOnlyKey], NO);

	// An inventory with no identifier reads as no limit.
	return [limit limitWithKind:limit.kind inventoryIdentifier:limit.inventoryIdentifier];

}//end limitWithDictionary:


//---------- supportsSecureCoding ------------------------------------[static]--
//------------------------------------------------------------------------------
+ (BOOL) supportsSecureCoding
{
	return YES;
}


//========== initWithCoder: ====================================================
///
/// @abstract	Reads the same dictionary the defaults keep.
///
//==============================================================================
- (instancetype) initWithCoder:(NSCoder *)coder
{
	NSSet			*classes	= [NSSet setWithObjects:[NSDictionary class], [NSString class], [NSNumber class], nil];
	NSDictionary	*dictionary	= [coder decodeObjectOfClasses:classes forKey:@"limit"];

	self = [super init];
	if (self) {
		[self takeValuesFromLimit:[LDrawPartLimit limitWithDictionary:dictionary]];
	}
	return self;
}


//========== encodeWithCoder: ==================================================
//==============================================================================
- (void) encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:[self dictionaryRepresentation] forKey:@"limit"];
}


// MARK: - KEPT WITH A MODEL FILE -


//---------- limitOfFileAtURL: ---------------------------------------[static]--
///
/// @abstract	The attribute holds the limit's dictionary as JSON. One that does
/// 			not read as a dictionary is no limit.
///
//------------------------------------------------------------------------------
+ (LDrawPartLimit *) limitOfFileAtURL:(NSURL *)fileURL
{
	const char		*path	= [fileURL fileSystemRepresentation];
	const char		*name	= [LDrawPartLimitFileAttributeName UTF8String];
	ssize_t			 size	= getxattr(path, name, NULL, 0, 0, 0);
	NSMutableData	*data	= nil;
	id				 object	= nil;

	if (size <= 0)
		return nil;

	data = [NSMutableData dataWithLength:(NSUInteger)size];
	if (getxattr(path, name, [data mutableBytes], (size_t)size, 0, 0) != size)
		return nil;

	object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (LDrawJSONDictionary(object) == nil)
		return nil;
	return [self limitWithDictionary:object];
}


//========== writeToFileAtURL:error: ===========================================
//==============================================================================
- (BOOL) writeToFileAtURL:(NSURL *)fileURL error:(NSError **)error
{
	NSData *data = [NSJSONSerialization dataWithJSONObject:[self dictionaryRepresentation]
												   options:NSJSONWritingSortedKeys
													 error:error];

	if (data == nil)
		return NO;

	if (setxattr([fileURL fileSystemRepresentation], [LDrawPartLimitFileAttributeName UTF8String],
				 [data bytes], [data length], 0, 0) != 0)
	{
		if (error != NULL)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain
										 code:errno
									 userInfo:@{NSURLErrorKey: fileURL}];
		return NO;
	}
	return YES;
}


// MARK: - NSObject -


//========== copyWithZone: =====================================================
///
/// @abstract	An immutable limit is its own copy; a mutable one copies into
/// 			an immutable one.
///
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	LDrawPartLimit *copy = nil;

	if ([self class] == [LDrawPartLimit class])
		return self;

	copy = [[LDrawPartLimit alloc] init];
	[copy takeValuesFromLimit:self];
	return copy;
}


//========== mutableCopyWithZone: ==============================================
//==============================================================================
- (id) mutableCopyWithZone:(NSZone *)zone
{
	LDrawMutablePartLimit *copy = [[LDrawMutablePartLimit alloc] init];

	[copy takeValuesFromLimit:self];
	return copy;
}


//========== isEqual: ==========================================================
///
/// @abstract	Same kind and same options, mutable or not.
///
//==============================================================================
- (BOOL) isEqual:(id)object
{
	if (object == self)
		return YES;
	if ([object isKindOfClass:[LDrawPartLimit class]] == NO)
		return NO;

	return [[self dictionaryRepresentation] isEqualToDictionary:[object dictionaryRepresentation]];
}


//========== hash ==============================================================
//==============================================================================
- (NSUInteger) hash
{
	return (NSUInteger)self.kind ^ [self.inventoryIdentifier hash];
}


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@>", [self class], [self dictionaryRepresentation]];
}

@end


@implementation LDrawMutablePartLimit

@dynamic kind, yearsBack, countsPickABrickParts, inventoryIdentifier, includesSpares;
@dynamic matchesMoldVariants, matchesAnyPrint, matchesAnyColor, warnsOnly;


//========== Setters ===========================================================
///
/// @abstract	Each sets the ivar its getter in LDrawPartLimit reads.
///
//==============================================================================
- (void) setKind:(LDrawPartLimitKind)kind					{ self->_kind = kind; }
- (void) setYearsBack:(NSInteger)yearsBack					{ self->_yearsBack = yearsBack; }
- (void) setCountsPickABrickParts:(BOOL)flag				{ self->_countsPickABrickParts = flag; }
- (void) setInventoryIdentifier:(NSString *)identifier		{ self->_inventoryIdentifier = [identifier copy]; }
- (void) setIncludesSpares:(BOOL)flag						{ self->_includesSpares = flag; }
- (void) setMatchesMoldVariants:(BOOL)flag					{ self->_matchesMoldVariants = flag; }
- (void) setMatchesAnyPrint:(BOOL)flag						{ self->_matchesAnyPrint = flag; }
- (void) setMatchesAnyColor:(BOOL)flag						{ self->_matchesAnyColor = flag; }
- (void) setWarnsOnly:(BOOL)flag							{ self->_warnsOnly = flag; }

@end
