//==============================================================================
//
//  File:       LDrawRelatedParts.m
//  Package:    LDrawFeatures
//
//  Purpose:    Parses related.ldr and builds related-parts menu plans.
//
//  Created by bsupnik on 2/24/13.
//  Copyright 2013. All rights reserved.
//
//==============================================================================

#import <LDrawFeatures/LDrawRelatedParts.h>

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/NSString+LDraw.h>


@interface LDrawRelatedPart ()
- (id)initWithParent:(NSString *)parentName
			  offset:(double *)offset
			relation:(NSString *)relation
		   childLine:(NSString *)line;
- (void)dump;
- (NSString*)parent;
- (NSString*)child;
- (NSString*)childName;
- (NSString*)role;
- (TransformComponents)calcChildPosition:(TransformComponents)parentPosition;
- (LDrawPart *)childPartForParent:(LDrawPart *)parent color:(LDrawColor *)color;
@end


//---------- sort_by_part_description ------------------------------------------
//
// Purpose:		This is a comparison function to sort an array of part names
//				(e.g. 3001.dat) by their descriptions (e.g. Brick 1 x 4, etc.)
//
//------------------------------------------------------------------------------
static NSInteger sort_by_part_description(id a, id b, void * ref)
{
	LDrawPartLibrary * pl = (__bridge LDrawPartLibrary *) ref;
	NSString * aa = a;
	NSString * bb = b;
	
	NSString * da = [pl descriptionForPartName:aa];
	NSString * db = [pl descriptionForPartName:bb];
	
	return [da compare:db];
	
} // end sort_by_part_description


//---------- sort_by_child_name ------------------------------------------------
//
// Purpose:		This is a comparison function that sorts an array of related
//				parts by the child name.
//
//------------------------------------------------------------------------------
static NSInteger sort_by_child_name(id a, id b, void * ref)
{
	LDrawRelatedPart * aa = a;
	LDrawRelatedPart * bb = b;
	
	return [[aa childName] compare:[bb childName]];
	
} // end sort_by_child_name


//---------- sort_by_role ------------------------------------------------------
//
// Purpose:		This is a comparison function that sorts an array of related
//				parts by the part's role.
//
//------------------------------------------------------------------------------
static NSInteger sort_by_role(id a, id b, void * ref)
{
	LDrawRelatedPart * aa = a;
	LDrawRelatedPart * bb = b;
	
	return [[aa role] compare:[bb role]];	
} // end sort_by_role


@implementation LDrawRelatedPart


//========== initWithParent:offset:relation:childLine: =========================
//
// Purpose:		Init a single parent-child relation.  The relation name, parent,
//				and offset are passed in because they have been previously read;
//				the child line is a "1" record from an LDR file minus the "1"
//				identifier, which has been pulled off already.
//
//==============================================================================
- (id)initWithParent:(NSString *)parentName
			  offset:(double *)offset
			relation:(NSString *)relation
		   childLine:(NSString *)line
{
	NSCharacterSet	*whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];

	NSString	*parsedField = nil;
	NSString	*orig=line;
	self = [super init];
	
	@try {
		// Skip color
		parsedField = [LDrawUtilities readNextField:line remainder:&line];

		// Matrix XYZ
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[12] = [parsedField doubleValue] - offset[0];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[13] = [parsedField doubleValue] - offset[1];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[14] = [parsedField doubleValue] - offset[2];
		
		// Matrix rotation 3x3.  LDraw format is transpose of what we are
		// used to from GPU side.
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[0] = [parsedField doubleValue];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[4] = [parsedField doubleValue];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[8] = [parsedField doubleValue];

		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[1] = [parsedField doubleValue];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[5] = [parsedField doubleValue];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[9] = [parsedField doubleValue];

		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[2] = [parsedField doubleValue];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[6] = [parsedField doubleValue];
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		transform[10] = [parsedField doubleValue];
		
		transform[3]  = 0.0f;
		transform[7]  = 0.0f;
		transform[11] = 0.0f;		
		transform[15] = 1.0f;

		self->child = [line stringByTrimmingCharactersInSet:whitespaceCharacterSet];
		
		self->childName = [[LDrawPartLibrary sharedPartLibrary] descriptionForPartName:self->child];

		self->role = relation;
		
		self->parent = parentName;
	}
	@catch (NSException * e) {
		NSLog(@"a related part line '%@' was fatally invalid", orig);
		NSLog(@" raised exception %@", [e name]);
		self = nil;
	
	}
	return self;
} // end initWithParent:offset:relation:childLine:


//========== dump ==============================================================
//
// Purpose:		Print out a debug view of this relation for diagnostics.
//
//==============================================================================
- (void)dump
{
	NSLog(@"\t%s\t%s(%s)\t%s		%f,%f,%f		%f %f %f | %f %f %f | %f %f %f\n",
		[self->parent UTF8String], [self->child UTF8String], [self->childName UTF8String], [self->role UTF8String],
		self->transform[12],self->transform[13],self->transform[14],

		self->transform[0],self->transform[4],self->transform[8],
		self->transform[1],self->transform[5],self->transform[9],
		self->transform[2],self->transform[6],self->transform[10]);		
		
} // end dump


//========== parent ============================================================
//
// Purpose:		Return the file name (reference name) of the parent part for the
//				relationship.
//
//==============================================================================
- (NSString*)parent
{
	return parent;
	
} // end parent


//========== child =============================================================
//
// Purpose:		Return the file name (reference name) of the child part for the
//				relationship.
//
//==============================================================================
- (NSString*)child
{
	return child;
	
} // end child


//========== childName =========================================================
//
// Purpose:		Return the child name for a given relationship.  This is the
//				human-readable description of the child part.
//
//==============================================================================
- (NSString*)childName
{
	return childName;
	
} // end childName


//========== role ==============================================================
//
// Purpose:		Return the role name for the related part.
//
//==============================================================================
- (NSString*)role
{
	return role;

} // end role


//========== calcChildPosition: ================================================
//
// Purpose:		Calculate the net position for a child given this relationship
//				and a given parent's position.
//
//==============================================================================
- (TransformComponents)calcChildPosition:(TransformComponents)parentPosition
{
	TransformComponents ret;
	Matrix4	parentMatrix = Matrix4CreateTransformation(&parentPosition);
	Matrix4	childMatrix = Matrix4CreateFromDoubles(self->transform);
	Matrix4 effective_position = Matrix4Multiply(childMatrix,parentMatrix);
	Matrix4DecomposeTransformation(effective_position, &ret);
	return ret;
	
} // end calcChildPosition:


//========== childPartForParent:color: ========================================
//
// Purpose:		Build a new related child part, colored and positioned relative
//				to parent using this relation's offset.
//
//==============================================================================
- (LDrawPart *)childPartForParent:(LDrawPart *)parent color:(LDrawColor *)color;
{
	LDrawPart *newPart = [[LDrawPart alloc] init];
	[newPart setLDrawColor:color];
	[newPart setDisplayName:[self child]];

	TransformComponents transformation = [parent transformComponents];
	transformation = [self calcChildPosition:transformation];
	[newPart setTransformComponents:transformation];
	return newPart;
}


//========== childPartsForSelection:color: ====================================
//
// Purpose:		Build a related child part for every LDrawPart in selection.
//
//==============================================================================
- (NSArray<LDrawPart *> *)childPartsForSelection:(NSArray *)selection color:(LDrawColor *)color
{
	NSMutableArray *newParts = [NSMutableArray array];
	for (id parentPart in selection)
	{
		if ([parentPart isKindOfClass:[LDrawPart class]])
		{
			[newParts addObject:[self childPartForParent:parentPart color:color]];
		}
	}
	return newParts;
}

@end


@interface LDrawRelatedParts ()
- (void)dump;
- (NSArray*)getChildPartList:(NSString *)parent;
- (NSArray*)getChildRoleList:(NSString *)parent;
- (NSArray*)getRelatedPartList:(NSString*) parent withRole:(NSString*) role;
- (NSArray*)getRelatedPartList:(NSString*) parent withChild:(NSString*) role;
@end

@implementation LDrawRelatedParts

//---------- databasePathInBundle: -----------------------------------[static]--
//
// Purpose:		Bundled related.ldr. The host still decides whether to use this
//				or another file.
//
//------------------------------------------------------------------------------
+ (NSString *)databasePathInBundle:(NSBundle *)bundle
{
	return [bundle pathForResource:@"related.ldr" ofType:nil];
}


//---------- sharedRelatedPartsWithFilePath: -------------------------[static]--
//
// Purpose:		Process-wide related-parts database. First path wins.
//
//------------------------------------------------------------------------------
+ (instancetype)sharedRelatedPartsWithFilePath:(NSString *)filePath
{
	static LDrawRelatedParts *shared = nil;
	static dispatch_once_t    onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[LDrawRelatedParts alloc] initWithFilePath:filePath];
	});
	return shared;
}


//========== initWithFilePath: =================================================
//
// Purpose:		Create our new related-parts DB, loading related parts from
//				an LDR file. Nil or unreadable path yields an empty database.
//
//==============================================================================
- (instancetype)initWithFilePath:(NSString *)filePath
{
	NSUInteger			i;
	NSUInteger			count;
	NSString *			fileContents	= nil;
	NSString *			parsedField		= nil;

	NSCharacterSet	*whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];

	NSArray *			lines			= nil;
	NSMutableArray *	arr				= nil;

	self = [super init];
	if (filePath == nil)
	{
		self->relatedParts = [[NSArray alloc] init];
		return self;
	}

	fileContents	= [LDrawUtilities stringFromFile:filePath];
	if (fileContents == nil)
	{
		self->relatedParts = [[NSArray alloc] init];
		return self;
	}

	lines			= [fileContents separateByLine];			
	count			= [lines count];
	arr				= [[NSMutableArray alloc] initWithCapacity:count];

	NSMutableArray * parents = [NSMutableArray arrayWithCapacity:5];
	double offset[3] = { 0, 0, 0 };
	NSString * relName = nil;
	
	for (i = 0; i < count; ++i)
	{
		NSString * line = [lines objectAtIndex:i];
		NSString * orig_line = line;
		
		parsedField = [LDrawUtilities readNextField:line remainder:&line];
		
		if ([parsedField compare:@"0"] == NSOrderedSame)
		{
			// meta command - do we know what it is?
			parsedField = [LDrawUtilities readNextField:line remainder:&line];
			if ([parsedField compare:@"!PARENT"] == NSOrderedSame)
			{
				relName = nil;
				parents = [NSMutableArray arrayWithCapacity:5];
				offset[0] = offset[1] = offset[2] = 0.0f;
			}
			else if ([parsedField compare:@"!CHILD"] == NSOrderedSame)
			{
				relName = [line stringByTrimmingCharactersInSet:whitespaceCharacterSet];			
			}
			else
			{
#if DEBUG
				printf("Unparsable META command: %s\n", [orig_line UTF8String]);
#endif
			}
			
		}
		else if ([parsedField compare:@"1"] == NSOrderedSame)
		{
			if (relName == nil)
			{
				// skip color
				parsedField = [LDrawUtilities readNextField:line remainder:&line];

				// Grab offset
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				offset[0] = [parsedField doubleValue];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				offset[1] = [parsedField doubleValue];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				offset[2] = [parsedField doubleValue];
				
				// skip matrix

				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];

				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];

				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				parsedField = [LDrawUtilities readNextField:line remainder:&line];
				

				NSString * parentName = [line stringByTrimmingCharactersInSet:whitespaceCharacterSet];
				[parents addObject:parentName];

			}
			else
			{
				NSInteger num_parents = [parents count];
				NSInteger pidx;
				for (pidx = 0; pidx < num_parents; ++pidx)
				{
					NSString * pname = [parents objectAtIndex:pidx];
					LDrawRelatedPart * p = [[LDrawRelatedPart alloc] initWithParent:pname offset:offset relation:relName childLine:line];
					[arr addObject:p];
				}
			}
		}
		else
			printf("Unparsable line: %s\n", [orig_line UTF8String]);
	}
	
	self->relatedParts = arr;
	return self;

} // end initWithFilePath:


//========== getChildPartList: =================================================
//
// Purpose:		Given a parent part file name, return a sorted array of child
//				parts that have some relationship to the parent.  
//
// Notes:		Children are returned as NSString's with the filename.
//
//==============================================================================
- (NSArray*)getChildPartList:(NSString *)parent
{
	NSUInteger i;
	NSUInteger count = [self->relatedParts count];
	NSMutableSet * kids = [NSMutableSet setWithCapacity:10];
	
	for (i = 0; i < count; ++i)
	{
		LDrawRelatedPart * p = [self->relatedParts objectAtIndex:i];
		if ([parent compare:[p parent]] == NSOrderedSame)
		{
			[kids addObject:[p child]];
		}
	}

	NSArray * kids_sorted = [kids allObjects];
	return [kids_sorted sortedArrayUsingFunction:sort_by_part_description context:(__bridge void *)([LDrawPartLibrary sharedPartLibrary])];

} // end getChildPartList:


//========== getChildPartList: =================================================
//
// Purpose:		Given a parent part file name, return a sorted array of roles
//				between this part and all of its children.
//
// Notes:		Roles are returned as NSStrings.
//
//==============================================================================
- (NSArray*)getChildRoleList:(NSString *)parent
{
	NSUInteger i;
	NSUInteger count = [self->relatedParts count];
	NSMutableSet * kids = [NSMutableSet setWithCapacity:10];
	
	for (i = 0; i < count; ++i)
	{
		LDrawRelatedPart * p = [self->relatedParts objectAtIndex:i];
		if ([parent compare:[p parent]] == NSOrderedSame)
		{
			[kids addObject:[p role]];
		}
	}
	
	NSArray * kids_sorted = [kids allObjects];
	return [kids_sorted sortedArrayUsingSelector:@selector(compare:)];
	
} // end getChildRoleList:


//========== getRelatedPartList:withRole: ======================================
//
// Purpose:		Given a parent part and a particular role, return a sorted
//				array of specific LDrawRelatedPart objects - all of the releations
//				for this parent matching this role.  
//
// Notes:		The returned array contains LDrawRelatedPart objects and are sorted
//				by the description of the child part.
//
//==============================================================================
- (NSArray*)getRelatedPartList:(NSString*) parent withRole:(NSString*) role
{
	NSUInteger i;
	NSUInteger count = [self->relatedParts count];
	NSMutableArray * kids = [NSMutableArray arrayWithCapacity:10];
	
	for (i = 0; i < count; ++i)
	{
		LDrawRelatedPart * p = [self->relatedParts objectAtIndex:i];
		if ([parent compare:[p parent]] == NSOrderedSame)
		if ([role compare:[p role]] == NSOrderedSame)
		{
			[kids addObject:p];
		}
	}
	[kids sortUsingFunction:sort_by_child_name context:NULL];
	return kids;
	
} // end getRelatedPartList:withRole:


//========== getRelatedPartList:withChild: =====================================
//
// Purpose:		Given a parent part and a particular child file name, return a
//				sorted array of specific LDrawRelatedPart objects - all of the
//				releations for this parent matching this child.
//
// Notes:		The returned array contains LDrawRelatedPart objects and are sorted
//				by the role.
//
//==============================================================================
- (NSArray*)getRelatedPartList:(NSString*) parent withChild:(NSString*) child
{
	NSUInteger i;
	NSUInteger count = [self->relatedParts count];
	NSMutableArray * kids = [NSMutableArray arrayWithCapacity:10];
	
	for (i = 0; i < count; ++i)
	{
		LDrawRelatedPart * p = [self->relatedParts objectAtIndex:i];
		if ([parent compare:[p parent]] == NSOrderedSame)
		if ([child compare:[p child]] == NSOrderedSame)
		{
			[kids addObject:p];
		}
	}
	
	[kids sortUsingFunction:sort_by_role context:NULL];
	return kids;
	
} // end getRelatedPartList:withChild:


//========== dump ==============================================================
//
// Purpose:		Print the entire related-parts DB.
//
//==============================================================================
- (void)dump
{
	NSUInteger i, count;
	count = [self->relatedParts count];
	for (i = 0; i < count; ++i)
	{
		LDrawRelatedPart * p = [self->relatedParts objectAtIndex:i];
		[p dump];
	}
} // end dump


//========== menuPlanForParentName: ============================================
//
// Purpose:		This kills and rebuilds the related-parts menu. Shared part-type
//				among selected parts, or nil if none or mixed types — pass that
//				as parentName (from the host).
//
// Notes:		If we only have one role or one child type of part, don't build
//				two-level menus — there's no need. If we made the 'flat' menu,
//				we don't need a second menu by roles — everything is there in
//				the first menu. If this particular relation has only one child
//				for the role, we will 'flatten' the menu, rather than having a
//				menu item that has a submenu with only one menu item.
//
//				The host still builds NSMenu items.
//
//==============================================================================
- (LDrawRelatedPartsMenuPlan *)menuPlanForParentName:(NSString *)parentName
{
	if (parentName == nil)
	{
		return nil;
	}

	NSArray *kids  = [self getChildPartList:parentName];
	NSArray *roles = [self getChildRoleList:parentName];

	assert(([kids count] == 0) == ([roles count] == 0));

	if ([kids count] == 0)
	{
		return nil;
	}

	// If we only have one role or one child type of part, don't build two-level menus - there's no need.
	BOOL is_flat = ([kids count] == 1 || [roles count] == 1);

	NSMutableArray<LDrawRelatedPartsMenuGroup *> *childGroups = [NSMutableArray array];
	NSUInteger count, i;

	// Do all children
	count = [kids count];
	for (i = 0; i < count; ++i)
	{
		NSString *child   = [kids objectAtIndex:i];
		NSArray  *choices = [self getRelatedPartList:parentName withChild:child];
		LDrawRelatedPartsMenuGroup *group = [[LDrawRelatedPartsMenuGroup alloc] init];
		group.title   = [[choices objectAtIndex:0] childName];
		group.choices = choices;
		// If this particular relation has only one child fo the role, we will 'flatten' the menu, rather than having a menu item that has a submenu with
		// only one meu item.
		group.style = (is_flat || [choices count] == 1) ? LDrawRelatedPartsMenuMerged : LDrawRelatedPartsMenuListRole;
		[childGroups addObject:group];
	}

	NSMutableArray<LDrawRelatedPartsMenuGroup *> *roleGroups = [NSMutableArray array];

	// If we made the 'flat' menu, we don't need a second menu by roles - everything is there in the first menu.
	if (is_flat == NO)
	{
		count = [roles count];
		for (i = 0; i < count; ++i)
		{
			NSString *role    = [roles objectAtIndex:i];
			NSArray  *choices = [self getRelatedPartList:parentName withRole:role];
			LDrawRelatedPartsMenuGroup *group = [[LDrawRelatedPartsMenuGroup alloc] init];
			group.title   = role;
			group.choices = choices;
			group.style   = [choices count] == 1 ? LDrawRelatedPartsMenuMerged : LDrawRelatedPartsMenuListChild;
			[roleGroups addObject:group];
		}
	}

	LDrawRelatedPartsMenuPlan *plan = [[LDrawRelatedPartsMenuPlan alloc] init];
	plan.childGroups = childGroups;
	plan.roleGroups  = roleGroups;
	return plan;
}



//---------- relatedPartsMenuTitle -----------------------------------[static]--
//
// Purpose:		Titles used when the host builds NSMenu items (not localized).
//
//------------------------------------------------------------------------------
+ (NSString *)relatedPartsMenuTitle
{
	return @"Related Parts";
}


//---------- relatedPartsChoicesSubmenuTitle ------------------------[static]--
//
// Purpose:		Title of the nested choices submenu when the host builds NSMenu
//				items (not localized).
//
//------------------------------------------------------------------------------
+ (NSString *)relatedPartsChoicesSubmenuTitle
{
	return @"choices";
}

@end


@implementation LDrawRelatedPartsMenuGroup

//========== titleForChoice: ===================================================
//
// Purpose:		Unmerged: childName or role. Merged: "role: childName".
//
//==============================================================================
- (NSString *)titleForChoice:(LDrawRelatedPart *)relatedPart
{
	switch (self.style)
	{
		case LDrawRelatedPartsMenuListChild:
			return [relatedPart childName];
		case LDrawRelatedPartsMenuListRole:
			return [relatedPart role];
		case LDrawRelatedPartsMenuMerged:
			return [NSString stringWithFormat:@"%s: %s",
					[[relatedPart role] UTF8String],
					[[relatedPart childName] UTF8String]];
	}
	return [relatedPart childName];
}


@end


@implementation LDrawRelatedPartsMenuPlan

@end

