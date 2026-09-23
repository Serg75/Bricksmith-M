//==============================================================================
//
//  File:       LDrawConnectorLibrary.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Finds the connectors of library parts and caches them by part
//              name.
//
//  Notes:      Each file's connectors are cached in its own coordinates, so a
//              shared primitive is read once.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <LDrawConnectivity/LDrawConnectorLibrary.h>

#import "LDrawConnectivityMath.h"
#import "LDrawShadowFile.h"
#import "LDrawSubfileReader.h"

// Rounding for duplicate keys: three decimals, well below the 20 / 8 LDU grid.
static const double DuplicateScale = 1000.0;


/// The fields that make two records the same connector, rounded to ignore
/// float noise.
typedef struct
{
	int64_t	position[3];
	int64_t	axis[3];
	int64_t	reference[3];
	int64_t	stepX[3];
	int64_t	stepZ[3];
	uint8_t	countX;
	uint8_t	countZ;
	uint8_t	centeredX;
	uint8_t	centeredZ;
	uint8_t	kind;
	uint8_t	gender;
	uint8_t	caps;
	uint8_t	centered;
	uint8_t	slide;

} LDrawRecordFingerprint;


//---------- RoundedVector ---------------------------------------------[static]--
//------------------------------------------------------------------------------
static void RoundedVector(Vector3 vector, int64_t *into)
{
	into[0] = llround(vector.x * DuplicateScale);
	into[1] = llround(vector.y * DuplicateScale);
	into[2] = llround(vector.z * DuplicateScale);
}


//---------- MaleStudPrimitives ---------------------------------------[static]--
//
// Purpose:		Primitives that are each one male stud, rising from Y = 0 to
//				Y = -4. Used only when the primitive has no shadow file.
//
//------------------------------------------------------------------------------
static NSSet<NSString *> *MaleStudPrimitives(void)
{
	static NSSet<NSString *>	*names	= nil;
	static dispatch_once_t		once;

	dispatch_once(&once, ^{
		NSMutableSet<NSString *> *all = [NSMutableSet setWithArray:@[
			@"stud.dat", @"studa.dat", @"stud2.dat", @"stud2a.dat",
			@"stud6.dat", @"stud6a.dat", @"stud17a.dat", @"studp01.dat",
			@"stud10.dat", @"stud13.dat", @"stud15.dat", @"stud23.dat", @"stud24.dat",
			@"stud25.dat", @"stud26.dat", @"stud27.dat", @"stud27a.dat", @"stud28.dat",
			@"stud28a.dat", @"studel.dat", @"studh.dat", @"studhl.dat", @"studhr.dat",
			@"stud9.dat", @"stud11.dat", @"stud14.dat", @"stud19.dat",
		]];
		for (NSString *suffix in @[@"", @"2", @"3", @"4", @"5"])
		{
			[all addObject:[NSString stringWithFormat:@"stud-logo%@.dat", suffix]];
			[all addObject:[NSString stringWithFormat:@"stud2-logo%@.dat", suffix]];
		}
		names = [all copy];
	});
	return names;
}


//---------- ProvenanceRank --------------------------------------------[static]--
//
// Purpose:		How much a source is trusted; higher is better. The enum values
//				are not in this order.
//
//------------------------------------------------------------------------------
static NSUInteger ProvenanceRank(LDrawConnectorProvenance provenance)
{
	switch (provenance)
	{
		case LDrawConnectorProvenanceOverride:	return 4;
		case LDrawConnectorProvenanceShadow:	return 3;
		case LDrawConnectorProvenanceInherited:	return 2;
		case LDrawConnectorProvenancePrimitive:	return 1;
		case LDrawConnectorProvenanceLattice:	return 0;
	}
	return 0;
}


#pragma mark -

//==============================================================================
//
// One connector while a part is being resolved. It also keeps the id that
// SNAP_CLEAR uses and the rule for scaled references.
//
//==============================================================================
@interface LDrawConnectorRecord : NSObject

@property (nonatomic) LDrawConnector						connector;
@property (nonatomic, copy) NSData							*sections;
@property (nonatomic, copy, nullable) NSString				*identifier;
@property (nonatomic) LDrawConnectorScaleRule				scaleRule;

- (LDrawConnectorRecord *)recordByTransforming:(Matrix4)transform;
- (NSData *)duplicateKey;

@end


@implementation LDrawConnectorRecord

//========== recordByTransforming: =============================================
//
// Purpose:		The connector moved into the coordinates of the file that
//				references it, and marked as inherited.
//
// Notes:		A negative scale flips the axis. Sections are scaled only when
//				the scale rule allows it.
//
//==============================================================================
- (LDrawConnectorRecord *)recordByTransforming:(Matrix4)transform
{
	LDrawConnectorRecord	*moved			= [[LDrawConnectorRecord alloc] init];
	LDrawConnector			connector		= self.connector;
	Vector3					across			= V3Cross(connector.axis, connector.reference);
	Vector3					turnedAxis		= LDrawDirectionByMatrix(connector.axis, transform);
	Vector3					turnedReference	= LDrawDirectionByMatrix(connector.reference, transform);
	double					lengthScale		= V3Length(turnedAxis);
	double					radiusScale		= (V3Length(turnedReference)
											   + V3Length(LDrawDirectionByMatrix(across, transform))) / 2.0;

	connector.position		= V3MulPointByProjMatrix(connector.position, transform);
	connector.axis			= V3Normalize(turnedAxis);
	connector.reference		= V3Normalize(turnedReference);
	connector.grid.stepX	= LDrawDirectionByMatrix(connector.grid.stepX, transform);
	connector.grid.stepZ	= LDrawDirectionByMatrix(connector.grid.stepZ, transform);

	if (connector.provenance == LDrawConnectorProvenanceShadow)
	{
		connector.provenance = LDrawConnectorProvenanceInherited;
	}

	moved.connector		= connector;
	moved.identifier	= self.identifier;
	moved.scaleRule		= self.scaleRule;
	moved.sections		= [self sectionsScaledByLength:lengthScale radius:radiusScale];

	return moved;
}


//========== sectionsScaledByLength:radius: ====================================
//==============================================================================
- (NSData *)sectionsScaledByLength:(double)lengthScale radius:(double)radiusScale
{
	BOOL			scalesLength	= (self.scaleRule == LDrawConnectorScaleRuleLength
									   || self.scaleRule == LDrawConnectorScaleRuleBoth);
	BOOL			scalesRadius	= (self.scaleRule == LDrawConnectorScaleRuleRadius
									   || self.scaleRule == LDrawConnectorScaleRuleBoth);
	NSMutableData	*scaled			= nil;

	if (scalesLength == NO && scalesRadius == NO)
	{
		return self.sections;
	}
	scaled = [self.sections mutableCopy];

	LDrawConnectorSection	*sections	= scaled.mutableBytes;
	NSUInteger				count		= scaled.length / sizeof(LDrawConnectorSection);

	for (NSUInteger index = 0; index < count; index++)
	{
		if (scalesLength)
		{
			sections[index].length *= lengthScale;
		}
		if (scalesRadius)
		{
			sections[index].radius *= radiusScale;
		}
	}
	return scaled;
}


//========== duplicateKey ======================================================
//
// Purpose:		Records with the same key are the same connector, and only one
//				is kept. A part that references a subpart and also includes its
//				shadow file finds each connector twice.
//
//==============================================================================
- (NSData *)duplicateKey
{
	LDrawConnector				connector	= self.connector;
	const LDrawConnectorSection	*sections	= self.sections.bytes;
	NSUInteger					count		= self.sections.length / sizeof(LDrawConnectorSection);
	LDrawRecordFingerprint		print;
	NSMutableData				*key		= nil;

	// The key is compared byte by byte, so clear the padding.
	memset(&print, 0, sizeof(print));

	RoundedVector(connector.position, print.position);
	RoundedVector(connector.axis, print.axis);
	RoundedVector(connector.reference, print.reference);
	RoundedVector(connector.grid.stepX, print.stepX);
	RoundedVector(connector.grid.stepZ, print.stepZ);

	print.countX	= connector.grid.countX;
	print.countZ	= connector.grid.countZ;
	print.centeredX	= connector.grid.centeredX;
	print.centeredZ	= connector.grid.centeredZ;
	print.kind		= connector.kind;
	print.gender	= connector.gender;
	print.caps		= connector.caps;
	print.centered	= connector.centered;
	print.slide		= connector.slide;

	key = [NSMutableData dataWithBytes:&print length:sizeof(print)];

	for (NSUInteger index = 0; index < count; index++)
	{
		int64_t profile[3] = { sections[index].shape,
							   llround(sections[index].radius * DuplicateScale),
							   llround(sections[index].length * DuplicateScale) };

		[key appendBytes:profile length:sizeof(profile)];
	}
	return key;
}

@end


#pragma mark -

@implementation LDrawConnectorLibrary
{
	NSMutableDictionary<NSString *, LDrawConnectorSet *>	*_sets;		// under _setsLock
	NSMutableDictionary<NSString *, id>						*_records;	// name -> records, or NSNull if missing
	NSMutableSet<NSString *>								*_resolving;
	LDrawSubfileReader										*_reader;
	NSObject												*_setsLock;
	NSObject												*_buildLock;	// one builder at a time
}

// Both accessors are custom, so the ivar must be synthesized by hand.
@synthesize shadowLibraryPath = _shadowLibraryPath;


//========== initWithShadowLibraryPath: ========================================
//==============================================================================
- (instancetype)initWithShadowLibraryPath:(nullable NSString *)shadowLibraryPath
{
	return [self initWithPaths:nil shadowLibraryPath:shadowLibraryPath];
}


//========== initWithPaths:shadowLibraryPath: ==================================
//==============================================================================
- (instancetype)initWithPaths:(nullable LDrawPaths *)paths
			shadowLibraryPath:(nullable NSString *)shadowLibraryPath
{
	self = [super init];
	if (self != nil)
	{
		_shadowLibraryPath	= [shadowLibraryPath copy];
		_sets				= [NSMutableDictionary dictionary];
		_records			= [NSMutableDictionary dictionary];
		_resolving			= [NSMutableSet set];
		_reader				= [[LDrawSubfileReader alloc] initWithPaths:paths];
		_setsLock			= [[NSObject alloc] init];
		_buildLock			= [[NSObject alloc] init];
	}
	return self;
}


//========== init ==============================================================
//==============================================================================
- (instancetype)init
{
	return [self initWithShadowLibraryPath:nil];
}


//========== setShadowLibraryPath: =============================================
//==============================================================================
- (void)setShadowLibraryPath:(nullable NSString *)shadowLibraryPath
{
	@synchronized (_setsLock)
	{
		_shadowLibraryPath = [shadowLibraryPath copy];
	}
	[self removeAllConnectorSets];
}


//========== shadowLibraryPath =================================================
//==============================================================================
- (nullable NSString *)shadowLibraryPath
{
	@synchronized (_setsLock)
	{
		return _shadowLibraryPath;
	}
}


#pragma mark - Lookup

//========== connectorSetForPartNamed: =========================================
//
// Purpose:		Returns the cached set, building it the first time.
//
//==============================================================================
- (nullable LDrawConnectorSet *)connectorSetForPartNamed:(NSString *)partName
{
	NSString			*key	= [LDrawSubfileReader normalizedName:partName];
	LDrawConnectorSet	*set	= nil;

	@synchronized (_setsLock)
	{
		set = _sets[key];
	}
	if (set != nil)
	{
		return set;
	}

	// Building reads files, so it uses its own lock. Readers of cached sets
	// do not wait for it.
	@synchronized (_buildLock)
	{
		@synchronized (_setsLock)
		{
			set = _sets[key];
		}
		if (set != nil)
		{
			return set;			// built by another thread while this one waited
		}
		set = [self buildConnectorSetForPartNamed:key];

		if (set != nil)
		{
			@synchronized (_setsLock)
			{
				_sets[key] = set;
			}
		}
	}
	return set;
}


//========== removeAllConnectorSets ============================================
//==============================================================================
- (void)removeAllConnectorSets
{
	@synchronized (_buildLock)
	{
		@synchronized (_setsLock)
		{
			[_sets removeAllObjects];
		}
		[_records removeAllObjects];
		[_reader removeAllReferences];
	}
}


#pragma mark - Building

//========== buildConnectorSetForPartNamed: ====================================
//
// Purpose:		Packs the part's records into a set, with all sections in one
//				shared list.
//
//==============================================================================
- (nullable LDrawConnectorSet *)buildConnectorSetForPartNamed:(NSString *)partName
{
	NSArray<LDrawConnectorRecord *>	*records	= [self recordsForFileNamed:partName];
	NSMutableData					*connectors	= [NSMutableData data];
	NSMutableData					*sections	= [NSMutableData data];

	if (records == nil)
	{
		return nil;
	}
	for (LDrawConnectorRecord *record in records)
	{
		LDrawConnector	connector	= record.connector;
		NSUInteger		count		= record.sections.length / sizeof(LDrawConnectorSection);

		connector.sectionOffset	= (uint16_t)(sections.length / sizeof(LDrawConnectorSection));
		connector.sectionCount	= (uint8_t)MIN(count, (NSUInteger)UINT8_MAX);

		[sections appendData:record.sections];
		[connectors appendBytes:&connector length:sizeof(connector)];
	}

	return [[LDrawConnectorSet alloc] initWithConnectors:connectors.bytes
										  connectorCount:connectors.length / sizeof(LDrawConnector)
												sections:sections.bytes
											sectionCount:sections.length / sizeof(LDrawConnectorSection)];
}


//========== recordsForFileNamed: ==============================================
//
// Purpose:		Every connector of one library file, in its own coordinates:
//				first from its references, then from its shadow file.
//
// Returns:		Nil when there is no such file; an empty array when the file
//				has no connectors.
//
//==============================================================================
- (nullable NSArray<LDrawConnectorRecord *> *)recordsForFileNamed:(NSString *)name
{
	NSString						*key		= [LDrawSubfileReader normalizedName:name];
	id								cached		= _records[key];
	NSArray<LDrawSubfileReference *>	*references	= nil;
	NSMutableArray<LDrawConnectorRecord *>	*records	= nil;

	if (cached != nil)
	{
		return (cached == [NSNull null]) ? nil : cached;
	}
	if ([_resolving containsObject:key])
	{
		// A reference cycle. Stop here.
		return @[];
	}
	references = [_reader referencesInFileNamed:key];
	if (references == nil)
	{
		_records[key] = [NSNull null];
		return nil;
	}

	[_resolving addObject:key];
	records = [NSMutableArray array];
	[self addInheritedRecordsOfReferences:references into:records];
	[self applyShadowFileForName:key to:records];
	[_resolving removeObject:key];

	records = [[self recordsWithoutDuplicates:records] mutableCopy];
	_records[key] = records;

	return records;
}


//========== addInheritedRecordsOfReferences:into: =============================
//
// Purpose:		Adds the connectors of each referenced file. A stud primitive
//				with no connectors adds one male stud.
//
//==============================================================================
- (void)addInheritedRecordsOfReferences:(NSArray<LDrawSubfileReference *> *)references
								   into:(NSMutableArray<LDrawConnectorRecord *> *)records
{
	for (LDrawSubfileReference *reference in references)
	{
		NSArray<LDrawConnectorRecord *> *inherited = [self recordsForFileNamed:reference.name];

		if (inherited.count == 0 && [MaleStudPrimitives() containsObject:reference.name.lastPathComponent])
		{
			inherited = @[[self primitiveStudRecord]];
		}
		for (LDrawConnectorRecord *record in inherited)
		{
			[records addObject:[record recordByTransforming:reference.transform]];
		}
	}
}


//========== applyShadowFileForName:to: ========================================
//
// Purpose:		Applies the file's shadow metas in order. SNAP_CLEAR removes
//				records, SNAP_INCL adds another file's, and SNAP_CYL adds one.
//
//==============================================================================
- (void)applyShadowFileForName:(NSString *)name to:(NSMutableArray<LDrawConnectorRecord *> *)records
{
	LDrawShadowFile *shadow = [self shadowFileForName:name];

	for (LDrawShadowMeta *meta in shadow.metas)
	{
		switch (meta.kind)
		{
			case LDrawShadowMetaKindClear:
				[self clearRecords:records named:meta.identifier];
				break;

			case LDrawShadowMetaKindInclude:
				[self addIncludedRecordsOfMeta:meta into:records];
				break;

			case LDrawShadowMetaKindCylinder:
				[records addObject:[self recordForCylinderMeta:meta]];
				break;
		}
	}
}


//========== clearRecords:named: ===============================================
//
// Purpose:		SNAP_CLEAR removes the inherited records. With an id, it removes
//				only the records with that id.
//
//==============================================================================
- (void)clearRecords:(NSMutableArray<LDrawConnectorRecord *> *)records named:(nullable NSString *)identifier
{
	NSIndexSet *doomed = [records indexesOfObjectsPassingTest:^BOOL(LDrawConnectorRecord *record, NSUInteger index, BOOL *stop) {
		if (identifier == nil)
		{
			return YES;
		}
		return (record.identifier != nil)
			&& ([record.identifier caseInsensitiveCompare:identifier] == NSOrderedSame);
	}];

	[records removeObjectsAtIndexes:doomed];
}


//========== addIncludedRecordsOfMeta:into: ====================================
//
// Purpose:		SNAP_INCL adds another file's connectors, placed by the meta's
//				frame and repeated over its grid.
//
//==============================================================================
- (void)addIncludedRecordsOfMeta:(LDrawShadowMeta *)meta into:(NSMutableArray<LDrawConnectorRecord *> *)records
{
	NSArray<LDrawConnectorRecord *>	*included	= nil;
	LDrawConnector					steps		= { .position = V3Make(0, 0, 0), .grid = meta.grid };

	if (meta.reference == nil)
	{
		return;
	}
	included = [self recordsForFileNamed:meta.reference];

	for (NSUInteger index = 0; index < LDrawConnectorPointCount(steps); index++)
	{
		Point3	offset	= LDrawConnectorPointAtIndex(steps, index);
		Matrix4	frame	= meta.frame;

		frame.element[3][0] += offset.x;
		frame.element[3][1] += offset.y;
		frame.element[3][2] += offset.z;

		for (LDrawConnectorRecord *record in included)
		{
			[records addObject:[record recordByTransforming:frame]];
		}
	}
}


//========== recordForCylinderMeta: ============================================
//
// Purpose:		A SNAP_CYL meta as a connector. The cylinder runs along the
//				frame's -Y, like a stud.
//
//==============================================================================
- (LDrawConnectorRecord *)recordForCylinderMeta:(LDrawShadowMeta *)meta
{
	LDrawConnectorRecord	*record	= [[LDrawConnectorRecord alloc] init];
	Matrix4					frame	= meta.frame;
	LDrawConnector			connector = {
		.position	= V3Make(frame.element[3][0], frame.element[3][1], frame.element[3][2]),
		.axis		= V3Normalize(V3Make(-frame.element[1][0], -frame.element[1][1], -frame.element[1][2])),
		.reference	= V3Normalize(V3Make(frame.element[0][0], frame.element[0][1], frame.element[0][2])),
		.grid		= meta.grid,
		.kind		= LDrawConnectorKindCylinder,
		.gender		= meta.gender,
		.caps		= meta.caps,
		.provenance	= LDrawConnectorProvenanceShadow,
		.centered	= meta.centered,
		.slide		= meta.slide,
	};

	record.connector	= connector;
	record.sections		= meta.sections;
	record.identifier	= meta.identifier;
	record.scaleRule	= meta.scaleRule;

	return record;
}


//========== primitiveStudRecord ===============================================
//
// Purpose:		The male stud of a stud primitive, in the primitive's own
//				coordinates.
//
//==============================================================================
- (LDrawConnectorRecord *)primitiveStudRecord
{
	LDrawConnectorRecord	*record		= [[LDrawConnectorRecord alloc] init];
	LDrawConnectorSection	section		= { .radius = 6, .length = 4, .shape = LDrawSectionShapeRound };
	LDrawConnector			connector	= {
		.position	= V3Make(0, 0, 0),
		.axis		= V3Make(0, -1, 0),
		.reference	= V3Make(1, 0, 0),
		.grid		= { .countX = 1, .countZ = 1 },
		.kind		= LDrawConnectorKindCylinder,
		.gender		= LDrawConnectorGenderMale,
		.caps		= LDrawConnectorCapsOne,
		.provenance	= LDrawConnectorProvenancePrimitive,
	};

	record.connector	= connector;
	record.sections		= [NSData dataWithBytes:&section length:sizeof(section)];
	record.scaleRule	= LDrawConnectorScaleRuleNone;

	return record;
}


//========== recordsWithoutDuplicates: =========================================
//
// Purpose:		Keeps one record per connector, from the best source.
//
//==============================================================================
- (NSArray<LDrawConnectorRecord *> *)recordsWithoutDuplicates:(NSArray<LDrawConnectorRecord *> *)records
{
	NSMutableArray<LDrawConnectorRecord *>		*unique	= [NSMutableArray arrayWithCapacity:records.count];
	NSMutableDictionary<NSData *, NSNumber *>	*seen	= [NSMutableDictionary dictionary];

	for (LDrawConnectorRecord *record in records)
	{
		NSData		*key	= [record duplicateKey];
		NSNumber	*known	= seen[key];

		if (known == nil)
		{
			seen[key] = @(unique.count);
			[unique addObject:record];
			continue;
		}

		LDrawConnectorRecord *kept = unique[known.unsignedIntegerValue];

		if (ProvenanceRank(record.connector.provenance) > ProvenanceRank(kept.connector.provenance))
		{
			unique[known.unsignedIntegerValue] = record;
		}
	}
	return unique;
}


#pragma mark - Shadow files

//========== shadowFileForName: ================================================
//
// Purpose:		The shadow file for a library file, if there is one. The shadow
//				library uses the same relative paths as the LDraw library.
//
//==============================================================================
- (nullable LDrawShadowFile *)shadowFileForName:(NSString *)name
{
	NSString		*root		= self.shadowLibraryPath;
	NSString		*relative	= (root != nil) ? [_reader relativePathForFileNamed:name] : nil;
	LDrawShadowFile	*shadow		= nil;

	if (relative == nil)
	{
		return nil;
	}
	shadow = [LDrawShadowFile shadowFileWithContentsOfFile:[root stringByAppendingPathComponent:relative]];

	if (shadow == nil && [relative.pathComponents.firstObject caseInsensitiveCompare:@"unofficial"] == NSOrderedSame)
	{
		// The shadow library may have no "Unofficial" folder, so also look
		// for the file without that prefix.
		NSString *inOneTree = [NSString pathWithComponents:
							   [relative.pathComponents subarrayWithRange:
								NSMakeRange(1, relative.pathComponents.count - 1)]];

		shadow = [LDrawShadowFile shadowFileWithContentsOfFile:
				  [root stringByAppendingPathComponent:inOneTree]];
	}
	return shadow;
}

@end
