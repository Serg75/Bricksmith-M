//==============================================================================
//
//  File:       LDrawStepPartList.m
//  Package:    LDrawFeatures
//
//  Purpose:    Collects the parts a single step consumes, grouped by design and
//              color.
//
//  Notes:      This walks the step's directives in order, because the IGN and
//              SUB ranges only make sense in the order they are written.
//              Entries are grouped by part design and color code.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartList.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawGroupable.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawCore/LPubPliIgnore.h>
#import <LDrawCore/LPubPliShow.h>
#import <LDrawCore/LPubPliSubstitute.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawFeatures/LDrawPartListOrientations.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>


/// The range a frame width may be set to. Below the minimum a stud is a few
/// pixels across; above the maximum the frame is the size of a page.
static const double STEP_PART_LIST_MINIMUM_WIDTH_INCHES = 0.75;
static const double STEP_PART_LIST_MAXIMUM_WIDTH_INCHES = 6.0;

/// A height may be set smaller than a width, because LPub3D files pin heights
/// well under an inch. The maximum is the width's.
static const double STEP_PART_LIST_MINIMUM_HEIGHT_INCHES = 0.25;

static BOOL		StepPartList_enabled				= NO;
static BOOL		StepPartList_includesSubmodels		= NO;
static BOOL		StepPartList_followsStepRotation	= YES;
static BOOL		StepPartList_usesLPubScale			= NO;
static LDrawPartListOrientations *StepPartList_partOrientations = nil;


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListRange
///
/// @abstract   One open `PLI BEGIN IGN` or `PLI BEGIN SUB` range, while the
///             step's directives are walked.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListRange : NSObject

/// The substitute this range lists in its place, or nil for an IGN range.
@property (nonatomic, strong, nullable) LPubPliSubstitute *substitute;

/// This range sits inside one that lists nothing, so its substitute is not
/// listed either.
@property (nonatomic) BOOL suppressed;

/// The color of the first part inside, for a substitute that names none.
@property (nonatomic, strong, nullable) LDrawColor *firstColor;

@end

@implementation LDrawStepPartListRange
@end


//------------------------------------------------------------------------------
///
/// @enum       LDrawStepPartListPartness
///
/// @abstract   What judging a model's contents said about it.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepPartListPartness) {
	/// Nothing either way: a model already being judged further up.
	LDrawStepPartListPartnessUnknown	= 0,
	/// Built of nothing but what parts are built of.
	LDrawStepPartListPartnessPartLike	= 1,
	/// Holds at least one part, or nothing at all.
	LDrawStepPartListPartnessAssembly	= 2
};


@implementation LDrawStepPartList


// MARK: - COLLECTING -


//---------- entriesForStep: -----------------------------------------[static]--
///
/// @abstract	Entries for the given step, in display order.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListEntry *> *) entriesForStep:(LDrawStep *)step
{
	LDrawModel *model = [step enclosingModel];

	// A part has no parts list, so its insides are never listed.
	if (step == nil || [self isPartLikeModel:model]) {
		return @[];
	}

	NSHashTable *path = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];

	// The model being listed counts as open, so a submodel placing it back is
	// not walked into again.
	if (model != nil) {
		[path addObject:model];
	}

	return [self entriesForStep:step path:path shouldMeasure:YES];

}//end entriesForStep:


//---------- entriesForStep:path:shouldMeasure: ----------------------[static]--
///
/// @abstract	Entries for the given step, in display order.
///
/// @discussion	`path` holds the submodels already being walked, so a submodel
/// 			that places one of them is not walked into again. Without
/// 			`shouldMeasure`, submodel rows get no outline and the walk stops at
/// 			the first entry. That is enough to check a submodel for anything
/// 			to list.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListEntry *> *) entriesForStep:(LDrawStep *)step
												  path:(NSHashTable *)path
										 shouldMeasure:(BOOL)shouldMeasure
{
	// Keys in the order the step places them. The sort keeps this order for ties.
	NSMutableArray<NSString *>	*keyOrder		= [NSMutableArray array];
	NSMutableDictionary<NSString *, LDrawStepPartListEntry *>
								*entriesByKey	= [NSMutableDictionary dictionary];

	// `PLI BEGIN IGN` and `PLI BEGIN SUB` share one END, so a `PLI END` closes
	// whichever opened last. They nest, so they are a stack, and an END with
	// nothing open does nothing. `PART BEGIN IGN` has its own END and depth.
	NSMutableArray<LDrawStepPartListRange *>	*pliRanges			= [NSMutableArray array];
	NSInteger									 partIgnoreDepth	= 0;

	for (LDrawDirective *directive in [self flattenedDirectives:[step subdirectives]]) {

		if (shouldMeasure == NO && keyOrder.count > 0) {
			break;
		}

		if ([directive isKindOfClass:[LPubPliSubstitute class]]) {
			LDrawStepPartListRange *range = [LDrawStepPartListRange new];

			range.substitute	= (LPubPliSubstitute *)directive;
			range.suppressed	= (pliRanges.count > 0 || partIgnoreDepth > 0);
			[pliRanges addObject:range];
			continue;
		}

		if ([directive isKindOfClass:[LPubPliIgnore class]]) {
			LPubPliIgnore *bracket = (LPubPliIgnore *)directive;

			if (bracket.branch == LPubPliIgnoreBranchPart) {
				if (bracket.beginsRange) {
					partIgnoreDepth += 1;
				}
				else if (partIgnoreDepth > 0) {
					partIgnoreDepth -= 1;
				}
			}
			else if (bracket.beginsRange) {
				[pliRanges addObject:[LDrawStepPartListRange new]];
			}
			else if (pliRanges.count > 0) {
				LDrawStepPartListRange *closed = pliRanges.lastObject;

				[pliRanges removeLastObject];
				[self addSubstituteOfRange:closed toGroups:entriesByKey order:keyOrder];
			}
			continue;
		}

		// A substitute with no color of its own takes the first part's.
		for (LDrawStepPartListRange *range in pliRanges) {
			if (range.firstColor == nil && [directive isKindOfClass:[LDrawPart class]]) {
				range.firstColor = [(LDrawPart *)directive LDrawColor];
			}
		}

		if (pliRanges.count > 0 || partIgnoreDepth > 0) {
			continue;
		}

		LDrawStepPartListEntry *entry = [self entryForDirective:directive path:path];

		if (entry == nil) {
			continue;
		}

		// Once per row, not once per instance: every instance of a submodel is
		// the same submodel.
		if (shouldMeasure && entry.isSubmodel && entriesByKey[entry.groupKey] == nil
			&& [directive isKindOfClass:[LDrawPart class]]) {
			LDrawModel *submodel = [self submodelForPart:(LDrawPart *)directive
												 library:[LDrawPartLibrary sharedPartLibraryIfRegistered]];

			entry = [entry entryWithOutlinePoints:[self outlinePointsOfModel:submodel]];
		}

		[self addEntry:entry toGroups:entriesByKey order:keyOrder];
	}

	// A range that never closes still stands in for the rest of the step.
	for (LDrawStepPartListRange *range in pliRanges) {
		[self addSubstituteOfRange:range toGroups:entriesByKey order:keyOrder];
	}

	NSMutableArray<LDrawStepPartListEntry *> *entries = [NSMutableArray arrayWithCapacity:keyOrder.count];

	// Only when the icons do not follow the step's rotation. Following the
	// step, they line up with the assembly instead.
	LDrawPartListOrientations *orientations = [self followsStepRotation] ? nil : [self partOrientations];

	for (NSString *key in keyOrder) {
		LDrawStepPartListEntry *entry = entriesByKey[key];

		if (orientations != nil) {
			entry = [entry entryWithListOrientation:[orientations orientationForPartName:entry.partName]];
		}
		[entries addObject:entry];
	}

	return [self sortedEntries:entries];

}//end entriesForStep:path:shouldMeasure:


//---------- addSubstituteOfRange:toGroups:order: --------------------[static]--
///
/// @abstract	Lists a closed range's substitute, grouped like any other part.
///
/// @discussion	Nothing for an IGN range, or for a substitute inside a range
/// 			that lists nothing of its own.
///
//------------------------------------------------------------------------------
+ (void) addSubstituteOfRange:(LDrawStepPartListRange *)range
					 toGroups:(NSMutableDictionary<NSString *, LDrawStepPartListEntry *> *)entriesByKey
						order:(NSMutableArray<NSString *> *)keyOrder
{
	if (range.substitute == nil || range.suppressed) {
		return;
	}

	LDrawStepPartListEntry *entry = [self entryForSubstitute:range.substitute fallbackColor:range.firstColor];

	if (entry != nil) {
		[self addEntry:entry toGroups:entriesByKey order:keyOrder];
	}

}//end addSubstituteOfRange:toGroups:order:


//---------- addEntry:toGroups:order: --------------------------------[static]--
///
/// @abstract	Adds a one-instance entry to its group, or starts the group.
///
//------------------------------------------------------------------------------
+ (void) addEntry:(LDrawStepPartListEntry *)entry
		 toGroups:(NSMutableDictionary<NSString *, LDrawStepPartListEntry *> *)entriesByKey
			order:(NSMutableArray<NSString *> *)keyOrder
{
	NSString				*key		= entry.groupKey;
	LDrawStepPartListEntry	*existing	= entriesByKey[key];

	if (existing == nil) {
		[keyOrder addObject:key];
		entriesByKey[key] = entry;
	}
	else {
		entriesByKey[key] = [existing entryByAddingInstance];
	}

}//end addEntry:toGroups:order:


//---------- entryForSubstitute:fallbackColor: -----------------------[static]--
///
/// @abstract	A one-instance entry for the part a `PLI BEGIN SUB` lists.
///
/// @discussion	A submodel of that name in the file wins, and is listed as one
/// 			part whatever the submodel preference says. Otherwise the name
/// 			goes through the same path as a placed part, and an unknown
/// 			`.ldr` or `.mpd` name is tried again as `.dat`.
///
//------------------------------------------------------------------------------
+ (nullable LDrawStepPartListEntry *) entryForSubstitute:(LPubPliSubstitute *)substitute
										   fallbackColor:(nullable LDrawColor *)fallbackColor
{
	if (substitute.partName.length == 0) {
		return nil;
	}

	LDrawPartLibrary	*library	= [LDrawPartLibrary sharedPartLibraryIfRegistered];
	NSString			*name		= [substitute.partName lowercaseString];
	NSString			*extension	= [name pathExtension];
	LDrawColor			*color		= fallbackColor;

	// Parsed like a part line's color, so an unknown code still gets one.
	if (substitute.partColorCode != LDrawColorBogus) {
		color = [LDrawUtilities parseColorFromField:[@(substitute.partColorCode) stringValue]];
	}

	LDrawModel *submodel = [[substitute enclosingFile] modelWithName:name];

	if (submodel != nil) {
		Box3 bounds = (library != nil) ? [submodel boundingBox3] : InvalidBox;

		NSString				*title = [self titleForSubmodel:submodel named:name];
		LDrawStepPartListEntry	*entry = [[LDrawStepPartListEntry alloc] initWithPartName:name
																			 displayTitle:title
																					color:color
																				 quantity:1
																			  modelBounds:bounds
																				isMissing:NO
																			   isSubmodel:YES];

		return [entry entryWithOutlinePoints:[self outlinePointsOfModel:submodel]];
	}

	if (library != nil
		&& [library modelForName:name] == nil
		&& ([extension isEqualToString:@"ldr"] || [extension isEqualToString:@"mpd"])) {

		NSString *asPart = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:@"dat"];

		if ([library modelForName:asPart] != nil) {
			name = asPart;
		}
	}

	LDrawPart *standInPart = [[LDrawPart alloc] init];

	[standInPart setDisplayName:name parse:NO inGroup:NULL];
	if (color != nil) {
		[standInPart setLDrawColor:color];
	}

	// A stand-in has no file, so it never resolves to a submodel and needs no path.
	return [self entryForPart:standInPart path:nil];

}//end entryForSubstitute:fallbackColor:


//---------- entriesForVisibleStepOfModel: ---------------------------[static]--
///
/// @abstract	Entries for the step the model currently has on display.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListEntry *> *) entriesForVisibleStepOfModel:(LDrawModel *)model
{
	if (model == nil) {
		return @[];
	}

	// Which parts a REMOVE GROUP drops depends on the step on display, so the
	// flags are brought up to date first.
	[model updateGroupSuppressionIfNeeded];

	return [self entriesForStep:[model visibleStep]];

}//end entriesForVisibleStepOfModel:


//---------- isShownForVisibleStepOfModel: ---------------------------[static]--
///
/// @abstract	Whether a list should be shown for the model's visible step.
///
//------------------------------------------------------------------------------
+ (BOOL) isShownForVisibleStepOfModel:(LDrawModel *)model
{
	if ([self isEnabled] == NO || model == nil) {
		return NO;
	}

	LPubPliShow *showDirective = [LDrawStepPartListPolicy directiveInForceForStep:[model visibleStep]
																		excluding:nil
																		 matching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPliShow class]];
	}];

	return (showDirective != nil) ? showDirective.isShown : YES;

}//end isShownForVisibleStepOfModel:


// MARK: - ACCESSORS -


+ (BOOL) isEnabled
{
	return StepPartList_enabled;
}

+ (void) setEnabled:(BOOL)flag
{
	StepPartList_enabled = flag;
}

+ (BOOL) includesSubmodels
{
	return StepPartList_includesSubmodels;
}

+ (void) setIncludesSubmodels:(BOOL)flag
{
	StepPartList_includesSubmodels = flag;
}

+ (nullable LDrawPartListOrientations *) partOrientations
{
	return StepPartList_partOrientations;
}
+ (void) setPartOrientations:(nullable LDrawPartListOrientations *)orientations
{
	StepPartList_partOrientations = orientations;
}
+ (BOOL) usesLPubScale
{
	return StepPartList_usesLPubScale;
}

+ (void) setUsesLPubScale:(BOOL)flag
{
	StepPartList_usesLPubScale = flag;
}


+ (BOOL) followsStepRotation
{
	return StepPartList_followsStepRotation;
}

+ (void) setFollowsStepRotation:(BOOL)flag
{
	StepPartList_followsStepRotation = flag;
}

+ (double) minimumWidthInInches
{
	return STEP_PART_LIST_MINIMUM_WIDTH_INCHES;
}

+ (double) maximumWidthInInches
{
	return STEP_PART_LIST_MAXIMUM_WIDTH_INCHES;
}

+ (double) minimumHeightInInches
{
	return STEP_PART_LIST_MINIMUM_HEIGHT_INCHES;
}


// MARK: - UTILITIES -


//---------- flattenedDirectives: ------------------------------------[static]--
///
/// @abstract	The directives in order, with every container opened in place
/// 			except a hose or band, which is listed as one part.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawDirective *> *) flattenedDirectives:(NSArray<LDrawDirective *> *)directives
{
	NSMutableArray<LDrawDirective *> *flattened = [NSMutableArray arrayWithCapacity:directives.count];

	for (LDrawDirective *directive in directives) {
		if ([directive isKindOfClass:[LDrawContainer class]] && [directive isKindOfClass:[LDrawLSynth class]] == NO) {
			[flattened addObjectsFromArray:[self flattenedDirectives:[(LDrawContainer *)directive subdirectives]]];
		}
		else {
			[flattened addObject:directive];
		}
	}

	return flattened;

}//end flattenedDirectives:


//---------- entryForDirective: --------------------------------------[static]--
///
/// @abstract	A one-instance entry for a directive the list should carry, or
/// 			nil for one it should not.
///
//------------------------------------------------------------------------------
+ (nullable LDrawStepPartListEntry *) entryForDirective:(LDrawDirective *)directive
													 path:(NSHashTable *)path
{
	if ([directive conformsToProtocol:@protocol(LDrawGroupable)]) {
		// A REMOVE GROUP in force says this is not built here. A ghost counts
		// as removed too: it shows something already taken out.
		if ([(id<LDrawGroupable>)directive groupVisibility] != LDrawGroupVisibilityVisible) {
			return nil;
		}
	}

	if ([directive isKindOfClass:[LDrawPart class]]) {
		return [self entryForPart:(LDrawPart *)directive path:path];
	}
	if ([directive isKindOfClass:[LDrawLSynth class]]) {
		return [self entryForLSynth:(LDrawLSynth *)directive];
	}

	return nil;

}//end entryForDirective:path:


//---------- entryForPart: -------------------------------------------[static]--
///
/// @abstract	A one-instance entry for a part reference, or nil if the list
/// 			should not carry it.
///
//------------------------------------------------------------------------------
+ (nullable LDrawStepPartListEntry *) entryForPart:(LDrawPart *)part
												path:(NSHashTable *)path
{
	LDrawPartLibrary	*library	= [LDrawPartLibrary sharedPartLibraryIfRegistered];
	NSString			*partName	= [part referenceName];
	LDrawModel			*referenced	= [self submodelForPart:part library:library];
	BOOL				isSubmodel	= (referenced != nil);
	BOOL				isMissing	= NO;

	if (isSubmodel == NO && library != nil) {
		isMissing	= [part partIsMissing];
		referenced	= [library modelForName:partName];
	}

	// A submodel that is really a part is listed as one whatever the submodel
	// preference says, and is never opened.
	BOOL isInlinePart = isSubmodel && [self isPartLikeModel:referenced];

	// Decided before the bounds are measured, because measuring a submodel
	// resolves every part inside it.
	if (isSubmodel && isInlinePart == NO && [self includesSubmodels] == NO) {
		return nil;
	}

	// A submodel whose own list would be empty is not a row either: every part
	// in it is inside an IGN range, in a removed group, or is geometry.
	if (isSubmodel && isInlinePart == NO && [self modelListsAnything:referenced path:path] == NO) {
		return nil;
	}

	// A primitive or a subpart is geometry, not a part anyone picks up. LPub3D
	// leaves these out too.
	if (isSubmodel == NO && isMissing == NO && [self isPrimitiveOrSubpartName:partName library:library]) {
		return nil;
	}

	// Measuring means resolving the reference, which needs the catalog.
	Box3 bounds = (library != nil && referenced != nil) ? [referenced boundingBox3] : InvalidBox;

	NSString *title = partName;

	if (isSubmodel) {
		title = [self titleForSubmodel:referenced named:partName];
	}
	else if (library != nil && isMissing == NO) {
		NSString *described = [library descriptionForPart:part];
		if (described.length > 0) {
			title = described;
		}
	}

	return [[LDrawStepPartListEntry alloc] initWithPartName:partName
											   displayTitle:title
													  color:[part LDrawColor]
												   quantity:1
												modelBounds:bounds
												  isMissing:isMissing
												 isSubmodel:isSubmodel];

}//end entryForPart:path:


//---------- modelListsAnything:path: --------------------------------[static]--
///
/// @abstract	Whether any step of a submodel has something in its parts list.
///
/// @discussion	Checked with the same collector, so every rule about what is
/// 			left out applies here too. Stops at the first step that lists
/// 			something.
///
/// 			A submodel already on `path` counts as listing something: it is
/// 			being walked further up, and a loop is no proof that a row is
/// 			empty.
///
//------------------------------------------------------------------------------
+ (BOOL) modelListsAnything:(LDrawModel *)model path:(NSHashTable *)path
{
	if (model == nil || [path containsObject:model]) {
		return YES;
	}

	BOOL listsAnything = NO;

	[path addObject:model];

	for (LDrawStep *step in [model steps]) {
		if ([self entriesForStep:step path:path shouldMeasure:NO].count > 0) {
			listsAnything = YES;
			break;
		}
	}

	[path removeObject:model];

	return listsAnything;

}//end modelListsAnything:path:


//---------- submodelForPart:library: --------------------------------[static]--
///
/// @abstract	The submodel or peer file a part places, or nil.
///
/// @discussion	A peer file is looked for only with a catalog, because resolving
/// 			without one raises an assertion.
///
//------------------------------------------------------------------------------
+ (nullable LDrawModel *) submodelForPart:(LDrawPart *)part library:(nullable LDrawPartLibrary *)library
{
	LDrawModel *submodel = [part referencedMPDSubmodel];

	if (submodel == nil && library != nil) {
		submodel = [part referencedPeerFile];
	}

	return submodel;

}//end submodelForPart:library:


//---------- titleForSubmodel:named: ---------------------------------[static]--
///
/// @abstract	What a row for a submodel says: its first line, else the name it
/// 			was placed by.
///
//------------------------------------------------------------------------------
+ (NSString *) titleForSubmodel:(nullable LDrawModel *)submodel named:(NSString *)name
{
	NSString *described = [submodel modelDescription];

	return (described.length > 0) ? described : name;

}//end titleForSubmodel:named:


//---------- isPartLikeModel: ----------------------------------------[static]--
///
/// @abstract	Whether a model is a part rather than an assembly.
///
/// @discussion	It is a part when its header says so, or when every step holds
/// 			only primitives, subparts, raw geometry, hoses and bands, or
/// 			submodels that are parts themselves. One catalog part makes it
/// 			an assembly, and so does an empty model.
///
//------------------------------------------------------------------------------
+ (BOOL) isPartLikeModel:(nullable LDrawModel *)model
{
	if (model == nil) {
		return NO;
	}

	NSHashTable *path = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];

	return [self partnessOfModel:model path:path] == LDrawStepPartListPartnessPartLike;

}//end isPartLikeModel:


//---------- partnessOfModel:path: -----------------------------------[static]--
///
/// @abstract	Whether a model is part-like, an assembly, or unknown.
///
/// @discussion	`path` holds the models being judged. A model already on it is
/// 			unknown, and the models around it decide. Calling it part-like
/// 			would turn two submodels that only place each other into parts.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListPartness) partnessOfModel:(LDrawModel *)model path:(NSHashTable *)path
{
	if ([model isInlinePart]) {
		return LDrawStepPartListPartnessPartLike;
	}
	if ([path containsObject:model]) {
		return LDrawStepPartListPartnessUnknown;
	}

	[path addObject:model];

	LDrawPartLibrary	*library			= [LDrawPartLibrary sharedPartLibraryIfRegistered];
	BOOL				 hasPartGeometry	= NO;
	BOOL				 hasCatalogPart		= NO;

	for (LDrawStep *step in [model steps]) {

		for (LDrawDirective *directive in [self flattenedDirectives:[step subdirectives]]) {

			if ([directive isKindOfClass:[LDrawPart class]]) {
				LDrawPart	*part	= (LDrawPart *)directive;
				LDrawModel	*nested	= [self submodelForPart:part library:library];

				if (nested != nil) {
					switch ([self partnessOfModel:nested path:path]) {

						case LDrawStepPartListPartnessPartLike:
							hasPartGeometry = YES;
							break;

						case LDrawStepPartListPartnessAssembly:
							hasCatalogPart = YES;
							break;

						case LDrawStepPartListPartnessUnknown:
							// Already being judged further up, so it says
							// nothing here.
							break;
					}
				}
				else if ([self isPrimitiveOrSubpartName:[part referenceName] library:library]) {
					hasPartGeometry = YES;
				}
				else {
					hasCatalogPart = YES;
				}
			}
			else if ([directive isKindOfClass:[LDrawLSynth class]]
					 || [directive isKindOfClass:[LDrawDrawableElement class]]) {
				// A hose, a band, or raw geometry.
				hasPartGeometry = YES;
			}
			// Comments and metas say nothing either way.

			if (hasCatalogPart) {
				break;
			}
		}

		if (hasCatalogPart) {
			break;
		}
	}

	[path removeObject:model];

	return (hasPartGeometry && hasCatalogPart == NO) ? LDrawStepPartListPartnessPartLike
													 : LDrawStepPartListPartnessAssembly;

}//end partnessOfModel:path:


//---------- isPrimitiveOrSubpartName:library: -----------------------[static]--
///
/// @abstract	Whether a reference names a primitive or a subpart rather than a
/// 			part. Decided by its folder, and by the catalog's category when
/// 			a catalog is loaded.
///
//------------------------------------------------------------------------------
+ (BOOL) isPrimitiveOrSubpartName:(NSString *)partName library:(nullable LDrawPartLibrary *)library
{
	NSString *lowered = [partName lowercaseString];

	if ([lowered hasPrefix:@"s\\"] || [lowered hasPrefix:@"48\\"] || [lowered hasPrefix:@"8\\"]) {
		return YES;
	}

	if (library == nil) {
		return NO;
	}

	NSString *category = [library categoryForPartName:partName];

	return category != nil
		&& ([category isEqualToString:[LDrawLocalization stringForKey:Category_Primitives]]
			|| [category isEqualToString:[LDrawLocalization stringForKey:Category_Subparts]]);

}//end isPrimitiveOrSubpartName:library:


//---------- outlinePointsOfModel: -----------------------------------[static]--
///
/// @abstract	The corners of every part box inside a model, in the model's own
/// 			coordinates, or nil with no model or no catalog.
///
/// @discussion	The parts' own boxes fit a submodel closer than one box around
/// 			all of it. Corners rather than boxes, because boxing a turned
/// 			part again makes it bigger.
///
//------------------------------------------------------------------------------
+ (nullable NSData *) outlinePointsOfModel:(nullable LDrawModel *)submodel
{
	LDrawPartLibrary *library = [LDrawPartLibrary sharedPartLibraryIfRegistered];

	if (library == nil || submodel == nil) {
		return nil;
	}

	NSMutableData	*points	= [NSMutableData data];
	NSHashTable		*path	= [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];

	[self appendOutlinePointsOfModel:submodel
						   transform:IdentityMatrix4
							 library:library
								path:path
							intoData:points];

	return (points.length > 0) ? points : nil;

}//end outlinePointsOfModel:


//---------- appendOutlinePointsOfModel:transform:library:path:intoData: --[static]-
///
/// @discussion	Counts the steps and parts the model draws. `path` holds the
/// 			models being walked, so a model that places itself again is not
/// 			entered twice.
///
//------------------------------------------------------------------------------
+ (void) appendOutlinePointsOfModel:(LDrawModel *)model
						  transform:(Matrix4)transform
							library:(LDrawPartLibrary *)library
							   path:(NSHashTable *)path
						   intoData:(NSMutableData *)points
{
	NSArray *steps = [model steps];

	if (steps.count == 0 || [path containsObject:model]) {
		return;
	}

	[path addObject:model];

	NSUInteger lastStepIndex = MIN([model maxStepIndexToOutput], steps.count - 1);

	for (NSUInteger index = 0; index <= lastStepIndex; index++) {

		[(LDrawStep *)steps[index] applyToAllParts:^(LDrawPart *part) {

			if ([part isOmitted]) {
				return;
			}

			// The part's own placement first, then wherever its parent put
			// the model it sits in.
			Matrix4		 placed	= Matrix4Multiply([part transformationMatrix], transform);
			LDrawModel	*nested	= [self submodelForPart:part library:library];

			if (nested != nil) {
				[self appendOutlinePointsOfModel:nested
									   transform:placed
										 library:library
											path:path
										intoData:points];
				return;
			}

			// Checked first: asking nil for bounds answers a zeroed box, and
			// that would add a point at the origin.
			LDrawModel *piece = [library modelForName:[part referenceName]];

			if (piece == nil) {
				return;
			}

			Box3 box = [piece boundingBox3];

			if (V3EqualBoxes(box, InvalidBox)) {
				return;
			}

			for (NSUInteger corner = 0; corner < 8; corner++) {
				Point3 point = V3Make((corner & 1) ? box.max.x : box.min.x,
									  (corner & 2) ? box.max.y : box.min.y,
									  (corner & 4) ? box.max.z : box.min.z);

				point = V3MulPointByProjMatrix(point, placed);
				[points appendBytes:&point length:sizeof(Point3)];
			}
		}];
	}

	[path removeObject:model];

}//end appendOutlinePointsOfModel:transform:library:path:intoData:


//---------- entryForLSynth: -----------------------------------------[static]--
///
/// @abstract	A one-instance entry for a synthesized part.
///
/// @discussion	One row for the band or hose itself. The pieces it is made of
/// 			are inside it and are not counted separately.
///
/// 			It has no library model, so it reports no bounds. Whoever draws
/// 			the icon handles that like a missing reference.
///
//------------------------------------------------------------------------------
+ (nullable LDrawStepPartListEntry *) entryForLSynth:(LDrawLSynth *)synthesized
{
	NSString *type = [synthesized lsynthType];

	if (type.length == 0) {
		return nil;
	}

	return [[LDrawStepPartListEntry alloc] initWithPartName:type
											   displayTitle:type
													  color:[synthesized LDrawColor]
												   quantity:1
												modelBounds:InvalidBox
												  isMissing:NO
												 isSubmodel:NO];

}//end entryForLSynth:


//---------- sortedEntries: ------------------------------------------[static]--
///
/// @abstract	Puts the entries in display order: biggest first, then by name,
/// 			then by color code.
///
/// @discussion	Size is the volume of the part's own bounds. An entry with no
/// 			bounds sorts last. Full ties keep the order they came in.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawStepPartListEntry *> *) sortedEntries:(NSArray<LDrawStepPartListEntry *> *)entries
{
	return [entries sortedArrayWithOptions:NSSortStable
						   usingComparator:^NSComparisonResult(LDrawStepPartListEntry *a, LDrawStepPartListEntry *b) {

		double volumeA = [self boundsVolume:a.modelBounds];
		double volumeB = [self boundsVolume:b.modelBounds];

		if (volumeA != volumeB) {
			return (volumeA > volumeB) ? NSOrderedAscending : NSOrderedDescending;
		}

		NSComparisonResult byName = [a.partName compare:b.partName];
		if (byName != NSOrderedSame) {
			return byName;
		}

		int codeA = (int)[a.color colorCode];
		int codeB = (int)[b.color colorCode];
		if (codeA != codeB) {
			return (codeA < codeB) ? NSOrderedAscending : NSOrderedDescending;
		}

		return NSOrderedSame;
	}];

}//end sortedEntries:


//---------- boundsVolume: -------------------------------------------[static]--
///
/// @abstract	Volume of a bounding box, or zero if it has none.
///
//------------------------------------------------------------------------------
+ (double) boundsVolume:(Box3)bounds
{
	if (V3EqualBoxes(bounds, InvalidBox)) {
		return 0.0;
	}

	double width	= bounds.max.x - bounds.min.x;
	double height	= bounds.max.y - bounds.min.y;
	double depth	= bounds.max.z - bounds.min.z;

	return fabs(width) * fabs(height) * fabs(depth);

}//end boundsVolume:


@end
