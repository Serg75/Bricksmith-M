//==============================================================================
//
//  File:       LDrawPartUsage.m
//  Package:    LDrawFeatures
//
//  Purpose:    Every part a model uses, in the order it is built.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartUsage.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubPliSubstitute.h>

#import "LDrawLPubRangeTracker.h"
#import "LDrawStepPartListInternal.h"


@interface LDrawPartUsageCopy ()

- (instancetype) initWithPartName:(NSString *)partName
						colorCode:(LDrawColorT)colorCode
							 kind:(LDrawPartUsageKind)kind
							parts:(NSArray<LDrawPart *> *)parts
						isCounted:(BOOL)isCounted;

@end


@implementation LDrawPartUsageCopy

//========== initWithPartName:... ==============================================
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName
						colorCode:(LDrawColorT)colorCode
							 kind:(LDrawPartUsageKind)kind
							parts:(NSArray<LDrawPart *> *)parts
						isCounted:(BOOL)isCounted
{
	self = [super init];
	if (self) {
		self->_partName		= [partName copy];
		self->_colorCode	= colorCode;
		self->_kind			= kind;
		self->_parts		= [parts copy];
		self->_isCounted	= isCounted;
	}
	return self;
}

//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@ color %d kind %ld%@>", [self class], self.partName,
			(int)self.colorCode, (long)self.kind, self.isCounted ? @"" : @" not counted"];
}

@end


@interface LDrawPartUsage ()

@property (nonatomic, readwrite, copy) NSArray<LDrawPartUsageCopy *> *copies;

@end


@implementation LDrawPartUsage
{
	NSMutableArray<LDrawPartUsageCopy *>	*collected;
	NSHashTable<LDrawModel *>				*walkPath;		// models being walked, against a loop
	NSHashTable<LDrawModel *>				*walked;		// models walked at least once
	LDrawPartLibrary						*library;		// nil in a host with no catalog
}


//---------- usageOfFile: --------------------------------------------[static]--
///
/// @abstract	The first model and what it places, then every model nothing
/// 			places.
///
//------------------------------------------------------------------------------
+ (instancetype) usageOfFile:(LDrawFile *)file
{
	LDrawPartUsage *usage = [[self alloc] init];

	usage->collected	= [NSMutableArray array];
	usage->walkPath		= [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	usage->walked		= [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	usage->library		= [LDrawPartLibrary sharedPartLibraryIfRegistered];

	LDrawModel *first = ([[file submodels] count] > 0) ? [file firstModel] : nil;

	if (first != nil)
		[usage walkModel:first inheritingColor:nil counted:YES];

	for (LDrawModel *model in [file submodels])
	{
		if ([usage->walked containsObject:model] == NO)
			[usage walkModel:model inheritingColor:nil counted:NO];
	}

	usage.copies = usage->collected;
	return usage;

}//end usageOfFile:


//========== walkModel:inheritingColor:counted: ================================
///
/// @abstract	Every step of a model, with its parts in the main color taking
/// 			`inheritedColor`. A model already being walked further up is
/// 			skipped, so a file that places a model inside itself ends.
///
//==============================================================================
- (void) walkModel:(LDrawModel *)model inheritingColor:(LDrawColor *)inheritedColor counted:(BOOL)counted
{
	if ([self->walkPath containsObject:model])
		return;

	[self->walkPath addObject:model];
	[self->walked addObject:model];

	for (LDrawStep *step in [model steps])
		[self walkStep:step inheritingColor:inheritedColor counted:counted];

	[self->walkPath removeObject:model];

}//end walkModel:inheritingColor:counted:


//========== walkStep:inheritingColor:counted: =================================
//==============================================================================
- (void) walkStep:(LDrawStep *)step inheritingColor:(LDrawColor *)inheritedColor counted:(BOOL)counted
{
	LDrawLPubRangeTracker *ranges = [[LDrawLPubRangeTracker alloc] init];

	for (LDrawDirective *directive in [LDrawStepPartList flattenedDirectives:[step subdirectives]])
	{
		LDrawLPubRange *closed = nil;

		if ([ranges readBracket:directive closedRange:&closed])
		{
			if (closed != nil)
				[self addSubstituteOfRange:closed counted:counted];
			continue;
		}

		if ([directive isKindOfClass:[LDrawPart class]])
		{
			LDrawPart *part = (LDrawPart *)directive;
			[ranges notePart:part color:[LDrawStepPartList colorOfPart:part inheriting:inheritedColor]];
		}

		if (ranges.isInsideRange)
			continue;

		if ([directive isKindOfClass:[LDrawLSynth class]])
		{
			LDrawLSynth	*synthesized	= (LDrawLSynth *)directive;
			LDrawColor	*color			= [synthesized LDrawColor];

			if (inheritedColor != nil && [color colorCode] == LDrawCurrentColor)
				color = inheritedColor;

			[self addCopyNamed:[[synthesized lsynthType] lowercaseString] ?: @""
						 color:[color colorCode]
						  kind:LDrawPartUsageKindSynthesized
						 parts:@[]
					   counted:counted];
		}
		else if ([directive isKindOfClass:[LDrawPart class]])
		{
			[self walkPart:(LDrawPart *)directive inheritingColor:inheritedColor counted:counted];
		}
	}

	for (LDrawLPubRange *range in ranges.openRanges)
		[self addSubstituteOfRange:range counted:counted];

}//end walkStep:inheritingColor:counted:


//========== walkPart:inheritingColor:counted: =================================
///
/// @abstract	A part is a copy; a part that places an assembly is walked into.
///
//==============================================================================
- (void) walkPart:(LDrawPart *)part inheritingColor:(LDrawColor *)inheritedColor counted:(BOOL)counted
{
	LDrawColor	*color		= [LDrawStepPartList colorOfPart:part inheriting:inheritedColor];
	LDrawModel	*submodel	= [LDrawStepPartList submodelForPart:part library:self->library];
	NSString	*name		= [part referenceName];

	if (submodel != nil && [LDrawStepPartList isPartLikeModel:submodel] == NO)
	{
		[self walkModel:submodel inheritingColor:color counted:counted];
		return;
	}

	if ([name length] == 0 || [LDrawStepPartList isPrimitiveOrSubpartName:name library:self->library])
		return;

	// Asking whether a part is missing resolves it, which needs a catalog.
	BOOL isMissing = (submodel == nil && self->library != nil && [part partIsMissing]);

	[self addCopyNamed:name
				 color:(color != nil) ? [color colorCode] : LDrawCurrentColor
				  kind:isMissing ? LDrawPartUsageKindMissing : LDrawPartUsageKindPart
				 parts:@[part]
			   counted:counted];

}//end walkPart:inheritingColor:counted:


//========== addSubstituteOfRange:counted: =====================================
///
/// @abstract	What a SUB range lists, standing for the parts inside it. An IGN
/// 			range, and a SUB inside a range that lists nothing, add nothing.
///
//==============================================================================
- (void) addSubstituteOfRange:(LDrawLPubRange *)range counted:(BOOL)counted
{
	LPubPliSubstitute	*substitute	= range.substitute;
	NSString			*name		= [substitute.partName lowercaseString];
	NSString			*extension	= [name pathExtension];
	LDrawColorT			 colorCode	= (LDrawColorT)substitute.partColorCode;

	if (substitute == nil || range.suppressed || [name length] == 0)
		return;

	// LPub3D takes "2429c01.ldr" for the library's "2429c01.dat".
	if ([extension isEqualToString:@"ldr"] || [extension isEqualToString:@"mpd"])
		name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:@"dat"];

	if (colorCode == LDrawColorBogus)
		colorCode = (range.firstColor != nil) ? [range.firstColor colorCode] : LDrawCurrentColor;

	[self addCopyNamed:name
				 color:colorCode
				  kind:LDrawPartUsageKindSubstitute
				 parts:range.enclosedParts
			   counted:counted];

}//end addSubstituteOfRange:counted:


//========== addCopyNamed:color:kind:parts:counted: ============================
//==============================================================================
- (void) addCopyNamed:(NSString *)name
				color:(LDrawColorT)colorCode
				 kind:(LDrawPartUsageKind)kind
				parts:(NSArray<LDrawPart *> *)parts
			  counted:(BOOL)counted
{
	[self->collected addObject:[[LDrawPartUsageCopy alloc] initWithPartName:name
																	colorCode:colorCode
																		 kind:kind
																		parts:parts
																	isCounted:counted]];
}

@end
