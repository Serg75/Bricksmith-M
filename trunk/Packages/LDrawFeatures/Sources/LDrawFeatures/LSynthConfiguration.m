//==============================================================================
//
//  File:       LSynthConfiguration.m
//  Package:    LDrawFeatures
//
//  Purpose:    Parsed LSynth configuration (lsynth.ldr / lsynth.mpd): types,
//              constraints, and quick-reference menus.
//
//  Created by Robin Macharg on 24/09/2012.
//
//==============================================================================

#import <LDrawFeatures/LSynthConfiguration.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawPart.h>

@implementation LSynthConfiguration

#pragma mark -
#pragma mark CLASS CONSTANTS
#pragma mark -

//========== Class constants ===================================================
//
// Purpose:		Class Constants
//
// TODO: make configurable preferences
//
//==============================================================================

static NSString *DEFAULT_HOSE_CONSTRAINT = @"LS01.DAT";
static NSString *DEFAULT_BAND_CONSTRAINT = @"3648a.dat";
static NSString *DEFAULT_HOSE_TYPE = @"TECHNIC_PNEUMATIC_HOSE";
static NSString *DEFAULT_BAND_TYPE = @"TECHNIC_CHAIN_LINK";

//---------- defaultConstraintForClass: -----------------------------[static]--
//
// Purpose:		Return the default constraint part name for a hose or band
//				class, or nil for other classes.
//
//------------------------------------------------------------------------------
+ (NSString *)defaultConstraintForClass:(LDrawLSynthClass)classType
{
	if (classType == LDrawLSynthClassBand) return DEFAULT_BAND_CONSTRAINT;
	if (classType == LDrawLSynthClassHose) return DEFAULT_HOSE_CONSTRAINT;
	return nil;
}


//---------- defaultTypeNameForClass: -------------------------------[static]--
//
// Purpose:		Return the default LSynth type name for a hose or band class,
//				or nil for other classes.
//
//------------------------------------------------------------------------------
+ (NSString *)defaultTypeNameForClass:(LDrawLSynthClass)classType
{
	if (classType == LDrawLSynthClassBand) return DEFAULT_BAND_TYPE;
	if (classType == LDrawLSynthClassHose) return DEFAULT_HOSE_TYPE;
	return nil;
}

#pragma mark -
#pragma mark SINGLETON
#pragma mark -

// Container for our singleton instance
static LSynthConfiguration* instance = nil;

//========== sharedInstance ====================================================
//
// Purpose: Return the singleton LSynthConfiguration instance.
//
//==============================================================================
+ (LSynthConfiguration *)sharedInstance
{
    @synchronized(self)
    {
        if (instance == nil) {
            instance = [[LSynthConfiguration alloc] init];
        }
        return instance;
    }
}

//========== init ==============================================================
//
// Purpose:		initialize the LSynthConfiguration instance.
//
//==============================================================================
- (id)init
{
	self = [super init];
    if (self)
	{
        [self initializeArrays];
    }
    return self;
}


//========== initializeArrays ==================================================
//
// Purpose:		initialize the LSynthConfiguration arrays.
//
//==============================================================================
- (void)initializeArrays
{
    parts                   = [NSMutableArray array];
    hose_constraints        = [NSMutableArray array];
    hose_types              = [NSMutableArray array];
    band_constraints        = [NSMutableArray array];
    band_types              = [NSMutableArray array];

    quickRefBands           = [NSMutableArray array];
    quickRefHoses           = [NSMutableArray array];
    quickRefParts           = [NSMutableArray array];
    quickRefBandConstraints = [NSMutableArray array];
    quickRefHoseConstraints = [NSMutableArray array];
} // end initializeArrays

//========== defaultConfigPath =================================================
//
// Purpose:		Return the default config path in the main bundle
//
//==============================================================================
- (NSString *)defaultConfigPath
{
    return [[NSBundle mainBundle] pathForResource:@"lsynth" ofType:@"mpd"];;
} // end defaultConfigPath

//========== parseLsynthConfig: ================================================
//
// Purpose:		Parse an LSynth lsynth.mpd configuration file in order that we
//              can a) validate incoming ldraw files if required and b) populate
//              parts menus appropriately.  We only need to parse the file enough
//              to satisfy these requirements; LSynth has a better understanding
//              of this config file.
//
// TODO: do we need to parse in as much detail?  Surely we just need
//       description + part + type
//==============================================================================
- (void)parseLsynthConfig:(NSString *)lsynthConfigurationPath
{
    // Initialise all arrays, since we may be called after a config file change
    [self initializeArrays];
    
    // Read the file in
   	NSString   *fileContents = [LDrawUtilities stringFromFile:lsynthConfigurationPath];
    NSArray    *lines        = [fileContents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    // General parsing variables
    NSUInteger  lineIndex    = 0;
    NSRange     range        = {0, [lines count]};
    NSString   *currentLine  = nil;
    NSString   *previousLine = nil;
    
    // LSynth sscanf()-specific line scanning variables
    char        product[126],
                title[128],
                type[128],
                stretch[128],
                fill[128];
    int         d,             // diameter
                st;            // stiffness
    float       t,             // twist
                scale,
                thresh;
    NSMutableArray *tmp_parts = [NSMutableArray array];

    while (lineIndex < NSMaxRange(range)) {
        currentLine = [lines objectAtIndex:lineIndex];
        if ([currentLine length] > 0) {
            
            // HOSE CONSTRAINTS, e.g.
            //
            // 0 // LSynth Constraint Part - Type 1 - "Hose"
            // 1 0 0 0 0 1 0 0 0 1 0 0 0 1 LS01.dat
            
            if ([[lines objectAtIndex:lineIndex] isEqualToString:@"0 SYNTH BEGIN DEFINE HOSE CONSTRAINTS"]) {
                lineIndex++;
                
                // Local block line-parsing variables.  TODO: move to top 
                int flip;
                float offset[3];
                float orient[3][3];
                char type[128];
                
                while (! [[lines objectAtIndex:lineIndex] isEqualToString:@"0 SYNTH END"]) {
                    if (sscanf([[lines objectAtIndex:lineIndex] UTF8String],"1 %d %f %f %f %f %f %f %f %f %f %f %f %f %s",
                               &flip,
                               &offset[0],    &offset[1],    &offset[2],
                               &orient[0][0], &orient[0][1], &orient[0][2],
                               &orient[1][0], &orient[1][1], &orient[1][2],
                               &orient[2][0], &orient[2][1], &orient[2][2],
                               type) == 14) {
                        
                        // Extract description
                        // Big assumption: that we have useful contents in the previous line
                        // TODO: harden
                        NSString *desc = [[previousLine componentsSeparatedByString:@"- Type "] objectAtIndex:1];
                        
                        NSMutableDictionary *hose_constraint = [@{
                            @"flip": @(flip),
                            @"offset": @[@(offset[0]), @(offset[1]), @(offset[2])],
                            @"orient": @[
                                @[@(orient[0][0]), @(orient[0][1]), @(orient[0][2])],
                                @[@(orient[1][0]), @(orient[1][1]), @(orient[1][2])],
                                @[@(orient[2][0]), @(orient[2][1]), @(orient[2][2])],
                            ],
                            @"partName": @(type),
                            @"description": desc,
                            @"LSYNTH_CONSTRAINT_CLASS": @(LDrawLSynthClassHose),
                        } mutableCopy];

                        // A little post-processing
                        NSString *description = hose_constraint[@"description"];
                        description = [description stringByReplacingOccurrencesOfString:@"\"" withString:@""];
                        NSArray *descriptionParts = [description componentsSeparatedByString:@"-"];

                        // Skip constraints without a description.  It would be better to rely on the lsynth.mpd for
                        // correct constraints rather than enshrine it in code.  Hopefully these lines are short-lived
                        if ([descriptionParts count] == 1) {
                            lineIndex++;
                            continue;
                        }
                        
                        // Use our processed description
                        hose_constraint[@"description"] = description;
                        
                        
                        [hose_constraints addObject:hose_constraint];
                        [quickRefHoseConstraints addObject:[@(type) lowercaseString]];
                    }
                    
                    // The description precedes the constraint definition so save it for the next time round
                    else if ([[lines objectAtIndex:(lineIndex)] length] > 0) {
                        previousLine = [[NSString alloc] initWithString:[lines objectAtIndex:(lineIndex)]];
                    }
                
                    lineIndex++;
                }
            } // END HOSE CONSTRAINTS
            
            
            // BAND CONSTRAINTS, e.g.
            //
            // 0 // Technic Axle 2 Notched
            // 1 8 0 0 0 0 0 1 0 1 0 -1 0 0 32062.DAT
            
            else if ([[lines objectAtIndex:lineIndex] isEqualToString:@"0 SYNTH BEGIN DEFINE BAND CONSTRAINTS"]) {
                lineIndex++;
                
                // Local block line-parsing variables.  TODO: move to top 
                int radius;
                float offset[3];
                float orient[3][3];
                char type[128];
                
                while (! [[lines objectAtIndex:lineIndex] isEqualToString:@"0 SYNTH END"]) {
                    if (sscanf([[lines objectAtIndex:lineIndex] UTF8String],"1 %d %f %f %f %f %f %f %f %f %f %f %f %f %s",
                               &radius,
                               &offset[0],    &offset[1],    &offset[2],
                               &orient[0][0], &orient[0][1], &orient[0][2],
                               &orient[1][0], &orient[1][1], &orient[1][2],
                               &orient[2][0], &orient[2][1], &orient[2][2],
                               type) == 14) {
                        
                        // Extract description
                        // Big assumption: that we have useful contents in the previous line
                        // TODO: harden
                        NSString *desc = [[previousLine componentsSeparatedByString:@"// "] objectAtIndex:1];
                        
                        NSDictionary *band_constraint = @{
                            @"radius": @(radius),
                            @"offset": @[@(offset[0]), @(offset[1]), @(offset[2])],
                            @"orient": @[
                                @[@(orient[0][0]), @(orient[0][1]), @(orient[0][2])],
                                @[@(orient[1][0]), @(orient[1][1]), @(orient[1][2])],
                                @[@(orient[2][0]), @(orient[2][1]), @(orient[2][2])],
                            ],
                            @"partName": @(type),
                            @"description": desc,
                            @"LSYNTH_CONSTRAINT_CLASS": @(LDrawLSynthClassBand),
                        };

                        [band_constraints addObject:band_constraint];
                        [quickRefBandConstraints addObject:[@(type) lowercaseString]];
                    }
                    
                    // The description precedes the constraint definition so save it for the next time round
                    else if ([[lines objectAtIndex:(lineIndex)] length] > 0) {
                        previousLine = [lines objectAtIndex:(lineIndex)];
                    }
                    
                    lineIndex++;
                }
            } // END BAND CONSTRAINTS

            // SYNTH PART lines, e.g.
            //
            // 0 SYNTH PART 4297187.dat PLI_ELECTRIC_NXT_CABLE_20CM   ELECTRIC_NXT_CABLE

            else if (sscanf([currentLine UTF8String],"0 SYNTH PART %s %s %s\n", product, title, type) == 3) {
                NSString *titleString = @(title);
                NSMutableDictionary *part = [@{
                    @"product": @(product),
                    @"title": [[titleString stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString],
                    @"method": @(type),
                    @"LSYNTH_TYPE": titleString,
                    @"LSYNTH_CLASS": @"",
                } mutableCopy];

                [tmp_parts addObject:part];
                // This (& the two below) feel a little hacky.  Better to have them as class methods on the config.
                [quickRefParts addObject:titleString];

            } // END PART

            // HOSE DEFINITIONS, e.g.
            //
            // 0 SYNTH BEGIN DEFINE BRICK_ARC HOSE FIXED 1 100 0
            //
            // We don't care about the rest of the definition (LSynth does)
            
            else if (sscanf([[lines objectAtIndex:lineIndex] UTF8String], "0 SYNTH BEGIN DEFINE %s HOSE %s %d %d %f", type, stretch, &d, &st, &t) == 5) {
                NSString *typeString = @(type);
                NSDictionary *hose_def = @{
                    @"title": [[typeString stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString],
                    @"LSYNTH_TYPE": typeString,
                    @"LSYNTH_CLASS": @(LDrawLSynthClassHose),
                };

                [hose_types addObject:hose_def];
                [quickRefHoses addObject:typeString];
            }
            
            // BAND DEFINITIONS, e.g.
            //
            // 0 SYNTH BEGIN DEFINE CHAIN BAND FIXED 0.0625 8
            //
            // We don't care about the rest of the definition (LSynth does)
            
            else if (sscanf([[lines objectAtIndex:lineIndex] UTF8String], "0 SYNTH BEGIN DEFINE %s BAND %s %f %f", type, fill, &scale, &thresh) == 4) {
                NSString *typeString = @(type);
                NSDictionary *band_def = @{
                    @"title": [[typeString stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString],
                    @"LSYNTH_TYPE": typeString,
                    @"LSYNTH_CLASS": @(LDrawLSynthClassBand),
                };

                [band_types addObject:band_def];
                [quickRefBands addObject:typeString];
            }
        }
        lineIndex++;
    }

    // Now we've read in all the config we can go back over our SYNTH PARTs and apply the correct class to them,
    // based on a matching band or hose type.  Not performant, but run only once at startup.

    for (NSMutableDictionary *part in tmp_parts) {
        if ([self->quickRefBands containsObject:part[@"method"]]) {
            part[@"LSYNTH_CLASS"] = @(LDrawLSynthClassBand);
        }
        else if ([self->quickRefHoses containsObject:part[@"method"]]) {
            part[@"LSYNTH_CLASS"] = @(LDrawLSynthClassHose);
        }
        [parts addObject:part];
    }
}

//========== isLSynthConstraint: ===============================================
//
// Purpose:		Determine if a given part is an "official" LSynth constraint,
//              i.e. defined in lsynth.ldr, and parsed into the LSynthConfiguration
//              object.
//
//==============================================================================
- (BOOL)isLSynthConstraint:(LDrawPart *)part
{
    if ([quickRefBandConstraints containsObject:[part referenceName]] ||
        [quickRefHoseConstraints containsObject:[part referenceName]]) {
        return YES;
    }
    return NO;
} // end isLSynthConstraint:

#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

// TODO: move to properties

//========== parts ============================================================
//
// Purpose:		Return configured synthesizable parts.
//
//==============================================================================
- (NSArray *)parts
{
    return self->parts;
}

//========== constraintDefinitionForPart: ======================================
//
// Purpose:		Look up a constraint by part type.  Not especially performant.
//              Consider adding a dictionary for lookup?
//
//==============================================================================
- (NSDictionary *)constraintDefinitionForPart:(LDrawPart *)directive
{
    for (NSDictionary *constraint in self->hose_constraints) {
        if ([[[constraint objectForKey:@"partName"] lowercaseString] isEqualToString:[directive referenceName]]) {
            return constraint;
        }
    }

    for (NSDictionary *constraint in self->band_constraints) {
        if ([[[constraint objectForKey:@"partName"] lowercaseString] isEqualToString:[directive referenceName]]) {
            return constraint;
        }
    }

    return nil;
} //end constraintDefinitionForPart:

//========== typeForTypeName: ==================================================
//
// Purpose:		Look up a band or hose definition by name.  Used when the class
//              is changed.  Not especially performant.
//
//==============================================================================
- (NSDictionary *)typeForTypeName:(NSString *)typeName
{
    for (NSDictionary *type in band_types) {
        if ([[type valueForKey:@"LSYNTH_TYPE"] isEqualToString:typeName]) {
            return type;
        }
    }

    for (NSDictionary *type in hose_types) {
        if ([[type valueForKey:@"LSYNTH_TYPE"] isEqualToString:typeName]) {
            return type;
        }
    }
    return nil;
} // end typeForTypeName:


//========== typesForLSynthClass: =============================================
//
// Purpose:		Return configured type dictionaries for the given LSynth class.
//
//==============================================================================
- (NSArray *)typesForLSynthClass:(LDrawLSynthClass)classTag
{
	if (classTag == LDrawLSynthClassPart) return self->parts;
	if (classTag == LDrawLSynthClassHose) return self->hose_types;
	if (classTag == LDrawLSynthClassBand) return self->band_types;
	return nil;
}


//========== updateSynthTypeLabel: =============================================
//
// Purpose:		Show the label type.
//
//==============================================================================
+ (NSString *)typeLabelForClass:(LDrawLSynthClass)classType
{
	// Update the type title according to our class of synthesized part
	if (classType == LDrawLSynthClassPart) return @"Part Type:";
	if (classType == LDrawLSynthClassHose) return @"Hose Type:";
	if (classType == LDrawLSynthClassBand) return @"Band Type:";
	return nil;
}


//---------- selectionControlEnablementForMode: ---------------------[static]--
//
// Purpose:		Which inspector controls (color vs transparency) should be
//				enabled for the current LSynth selection-tint mode.
//
//------------------------------------------------------------------------------
+ (LSynthSelectionControlEnablement)selectionControlEnablementForMode:(LDrawLSynthSelectionMode)mode
{
	// Enable the correct bits of the selection section
	LSynthSelectionControlEnablement enablement = { NO, NO };
	if (mode == LDrawLSynthSelectionTransparent)
	{
		enablement.transparencyEnabled = YES;
		enablement.colorWellEnabled    = NO;
	}
	else if (mode == LDrawLSynthSelectionColored)
	{
		enablement.transparencyEnabled = NO;
		enablement.colorWellEnabled    = YES;
	}
	else if (mode == LDrawLSynthSelectionTransparentColored)
	{
		enablement.transparencyEnabled = YES;
		enablement.colorWellEnabled    = YES;
	}
	return enablement;
}


//========== entriesForMenuKind: ==============================================
//
// Purpose:		Return Model → LSynth submenu entries for the given kind.
//
//==============================================================================
- (NSArray *)entriesForMenuKind:(LDrawLSynthMenuKind)kind
{
	switch (kind)
	{
		case LDrawLSynthMenuParts:           return self->parts;
		case LDrawLSynthMenuHoseTypes:       return self->hose_types;
		case LDrawLSynthMenuHoseConstraints: return self->hose_constraints;
		case LDrawLSynthMenuBandTypes:       return self->band_types;
		case LDrawLSynthMenuBandConstraints: return self->band_constraints;
		default:                             return @[];
	}
}


//========== populateLSynthModelMenus ==========================================
//
// Purpose:		Populate the LSynth Model menus dynamically from configuration
//				file.
//
//==============================================================================
+ (NSArray *)applicationMenuSpecs
{
	// A declarative encoding of our LSynth menus
	// We process this, along with associated LSynthConfiguration data to generate our Model LSynth menu
	return @[
		@{
			@"tag": @(LDrawLSynthPartMenuTag),
			@"kind": @(LDrawLSynthMenuParts),
			@"entry_key": @"title",
			@"action": NSStringFromSelector(@selector(insertSynthesizableDirective:)),
			@"shouldFilter": @YES,
		},
		@{
			@"tag": @(LDrawLSynthHoseMenuTag),
			@"kind": @(LDrawLSynthMenuHoseTypes),
			@"entry_key": @"title",
			@"action": NSStringFromSelector(@selector(insertSynthesizableDirective:)),
			@"shouldFilter": @YES,
		},
		@{
			@"tag": @(LDrawLSynthHoseConstraintMenuTag),
			@"kind": @(LDrawLSynthMenuHoseConstraints),
			@"entry_key": @"description",
			@"action": NSStringFromSelector(@selector(insertLSynthConstraint:)),
			@"shouldFilter": @NO,
		},
		@{
			@"tag": @(LDrawLSynthBandMenuTag),
			@"kind": @(LDrawLSynthMenuBandTypes),
			@"entry_key": @"title",
			@"action": NSStringFromSelector(@selector(insertSynthesizableDirective:)),
			@"shouldFilter": @YES,
		},
		@{
			@"tag": @(LDrawLSynthBandConstraintMenuTag),
			@"kind": @(LDrawLSynthMenuBandConstraints),
			@"entry_key": @"description",
			@"action": NSStringFromSelector(@selector(insertLSynthConstraint:)),
			@"shouldFilter": @NO,
		},
	];
}


//---------- insideOutsideInsertMenuSpecs ---------------------------[static]--
//
// Purpose:		Menu specs for inserting LSynth INSIDE / OUTSIDE commands.
//
//------------------------------------------------------------------------------
+ (NSArray *)insideOutsideInsertMenuSpecs
{
	NSString *action = NSStringFromSelector(@selector(insertINSIDEOUTSIDELSynthDirective:));
	return @[
		@{
			@"title": @"Insert INSIDE",
			@"action": action,
			@"tag": @(LDrawLSynthInsertInsideTag),
		},
		@{
			@"title": @"Insert OUTSIDE",
			@"action": action,
			@"tag": @(LDrawLSynthInsertOutsideTag),
		},
		@{
			@"title": @"Insert CROSS",
			@"action": action,
			@"tag": @(LDrawLSynthInsertCrossTag),
		},
	];
}


//---------- shouldIncludeMenuEntry: --------------------------------[static]--
//
// Purpose:		Return YES if the LSynth menu should show this type, honoring
//				the basic-parts-list preference.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldIncludeMenuEntry:(NSDictionary *)entry
				  shouldFilter:(BOOL)shouldFilter
				  visibleTypes:(NSArray *)visibleTypes
			  showOnlyOfficial:(BOOL)showOnlyOfficial
{
	// The MLCad.ini file contains a list of semi-official LSynth types.  The
	// lsynth.mpd file also contains legacy entries for backward compatibility.
	// We want to filter out non-semi-official synth parts unless the user has
	// turned this off in the preferences.  Parts get filtered, constraints
	// don't.
	if (shouldFilter
	   && [visibleTypes indexOfObject:[entry valueForKey:@"LSYNTH_TYPE"]] != NSNotFound)
	{
		return YES;
	}
	if (shouldFilter == NO) return YES;
	if (showOnlyOfficial == NO) return YES;
	return NO;
}


//---------- constraintClassForSynthClass: --------------------------[static]--
//
// Purpose:		Map a synth class (hose/band) to its constraint class.
//
//------------------------------------------------------------------------------
+ (LDrawLSynthClass)constraintClassForSynthClass:(LDrawLSynthClass)classTag
								selectedType:(NSDictionary *)selectedType
{
	// For a complete Part the constraints depend on the part class.  Handily
	// we worked this out when we read in the LSynth config.
	if (classTag == LDrawLSynthClassPart && selectedType != nil)
	{
		return (LDrawLSynthClass)[[selectedType valueForKey:@"LSYNTH_CLASS"] integerValue];
	}
	return classTag;
}


//========== constraintsForClass: =============================================
//
// Purpose:		Return constraint definitions for the given LSynth class.
//
//==============================================================================
- (NSArray *)constraintsForClass:(LDrawLSynthClass)classType
{
	if (classType == LDrawLSynthClassBand) return self->band_constraints;
	if (classType == LDrawLSynthClassHose) return self->hose_constraints;
	return nil;
}


//---------- indexOfConstraintNamed:inConstraints: ------------------[static]--
//
// Purpose:		Find a constraint by part name in the given list. Returns
//				NSNotFound when missing.
//
//------------------------------------------------------------------------------
+ (NSUInteger)indexOfConstraintNamed:(NSString *)name inConstraints:(NSArray *)constraints
{
	NSString *target = [name uppercaseString];
	NSUInteger index = 0;
	for (NSDictionary *constraint in constraints)
	{
		if ([[[constraint valueForKey:@"partName"] uppercaseString] isEqualToString:target])
		{
			return index;
		}
		index++;
	}
	return NSNotFound;
}


//---------- typePopupTitlesFromTypes: ------------------------------[static]--
//
// Purpose:		Build inspector popup titles from LSynth type dictionaries.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)typePopupTitlesFromTypes:(NSArray *)types
{
	return [types valueForKey:@"title"];
}


//---------- constraintPopupDescriptionsFromConstraints: ------------[static]--
//
// Purpose:		Build inspector popup titles from constraint dictionaries.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)constraintPopupDescriptionsFromConstraints:(NSArray *)constraints
{
	return [constraints valueForKey:@"description"];
}


//---------- indexOfTypeNamed:inTypes: ------------------------------[static]--
//
// Purpose:		Find an LSynth type by name. Returns NSNotFound when missing.
//
//------------------------------------------------------------------------------
+ (NSUInteger)indexOfTypeNamed:(NSString *)typeName inTypes:(NSArray *)types
{
	NSUInteger index = 0;
	for (NSDictionary *type in types)
	{
		if ([[type valueForKey:@"LSYNTH_TYPE"] isEqualToString:typeName])
		{
			return index;
		}
		index++;
	}
	return NSNotFound;
}


//---------- typeNameAtIndex:inTypes: -------------------------------[static]--
//
// Purpose:		Return the type name at index, or nil if out of range.
//
//------------------------------------------------------------------------------
+ (NSString *)typeNameAtIndex:(NSInteger)index inTypes:(NSArray *)types
{
	return [[self entryAtIndex:index inEntries:types] valueForKey:@"LSYNTH_TYPE"];
}


//---------- entryAtIndex:inEntries: --------------------------------[static]--
//
// Purpose:		Return the dictionary at index, or nil if out of range.
//
//------------------------------------------------------------------------------
+ (NSDictionary *)entryAtIndex:(NSInteger)index inEntries:(NSArray *)entries
{
	if (index < 0 || index >= (NSInteger)[entries count]) return nil;
	return [entries objectAtIndex:(NSUInteger)index];
}


//---------- selectedTypeForClass:atIndex:inTypes:fallbackName: -----[static]--
//
// Purpose:		Return the type dictionary at index for classTag, or the
//				fallback name's dictionary when index is out of range.
//
//------------------------------------------------------------------------------
+ (NSDictionary *)selectedTypeForClass:(LDrawLSynthClass)classTag
							   atIndex:(NSInteger)index
{
	if (classTag != LDrawLSynthClassPart) return nil;
	return [self entryAtIndex:index
					inEntries:[[self sharedInstance] typesForLSynthClass:classTag]];
}


//---------- applyConstraintPartName:toLSynth: -----------------------[instance]
//
// Purpose:		If the synth class has changed convert the constraints to an
//				appropriate default.  Hoses only work with hose constraints,
//				bands similarly.
//
//				TODO: Our defaults are arbitrary but could be preferences
//
//------------------------------------------------------------------------------
- (void)applyConstraintPartName:(NSString *)partName toLSynth:(LDrawLSynth *)lsynth
{
	if (partName == nil) return;

	for (LDrawDirective *directive in [lsynth subdirectives])
	{
		if ([directive isKindOfClass:[LDrawPart class]] == NO) continue;
		[(LDrawPart *)directive setDisplayName:partName];
	}
}


//---------- applyDefaultConstraintsToLSynth:classType: --------------[instance]
//
// Purpose:		Change all constraints to the default one. Maybe update the
//				constraint icons (e.g. if the part class has changed).
//
//------------------------------------------------------------------------------
- (void)applyDefaultConstraintsToLSynth:(LDrawLSynth *)lsynth
							  classType:(LDrawLSynthClass)classType
{
	NSString *constraintName = [LSynthConfiguration defaultConstraintForClass:classType];
	if (constraintName == nil) return;

	for (LDrawDirective *directive in [lsynth subdirectives])
	{
		if ([directive isKindOfClass:[LDrawPart class]] == NO) continue;
		[(LDrawPart *)directive setDisplayName:constraintName];
		[directive setIconName:[lsynth determineIconName:directive]];
	}
}

//========== setLSynthClassForDirective:withType: ==============================
//
// Purpose:		Set the class of an LSynthDirective based on the part type name
//
//==============================================================================
- (void)setLSynthClassForDirective:(LDrawLSynth *)directive withType:(NSString *)type
{
	LDrawLSynthClass classType = [self classForType:type];
	if (classType != 0)
	{
		[directive setLsynthClass:classType];
	}
	else
	{
		NSLog(@"Unknown LSynth type");
	}
}


//========== classForType: ====================================================
//
// Purpose:		Look up the LSynth class (hose / band / part) for a type name.
//
//==============================================================================
- (LDrawLSynthClass)classForType:(NSString *)type
{
	if ([self->quickRefHoses containsObject:type])
	{
		return LDrawLSynthClassHose;
	}
	if ([self->quickRefBands containsObject:type])
	{
		return LDrawLSynthClassBand;
	}
	if ([self->quickRefParts containsObject:type])
	{
		return LDrawLSynthClassPart;
	}
	return (LDrawLSynthClass)0;
}


//========== insertSynthesizableDirective: =====================================
//
// Purpose:		Insert a synthesizable directive into the model.  This is a
//              hose, band or part.
//
//==============================================================================
- (LDrawLSynth *)synthesizableDirectiveWithType:(NSString *)type color:(LDrawColor *)color
{
	LDrawLSynth *synthesizedObject = [[LDrawLSynth alloc] init];
	[synthesizedObject setLDrawColor:color];
	[synthesizedObject setLsynthType:type];
	[self setLSynthClassForDirective:synthesizedObject withType:type];
	return synthesizedObject;
}


//---------- approximatePieceCountFormatKey --------------------------[static]--
//
// Purpose:		Inspector: “(approx. %i pieces)” format. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)approximatePieceCountFormatKey
{
	return @"(approx. %i pieces)";
}

@end
