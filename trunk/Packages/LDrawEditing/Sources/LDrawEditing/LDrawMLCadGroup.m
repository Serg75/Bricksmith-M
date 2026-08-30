//==============================================================================
//
//  File:       LDrawMLCadGroup.m
//  Package:    LDrawEditing
//
//  Purpose:    MLCAD group names and group-change undo pairs.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawMLCadGroup.h>

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawObjectWithValue.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>

static BOOL LDrawDirectiveSupportsGroup(id object)
{
	return [object isKindOfClass:[LDrawDirective class]]
		&& [object respondsToSelector:@selector(group)];
}


@implementation LDrawMLCadGroup

//---------- groupsBeforeStep ----------------------------------------[static]--
///
/// @abstract	Gathers all group names declared until given step.
///
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *)groupsBeforeStep:(LDrawStep *)step
{
	NSMutableSet<NSString *>	*groups	= [NSMutableSet set];
	LDrawModel					*model 	= step.enclosingModel;
	
	for (LDrawStep *currentStep in model.steps) {
		if (currentStep == step) {
			break;
		}
		
		for (id object in currentStep.subdirectives) {
			if ([object respondsToSelector:@selector(group)]) {
				NSString *group = [object group];
				if (group.length > 0) {
					[groups addObject:group];
				}
			}
		}
	}
	
	return groups;
	
} // end groupsBeforeStep


//---------- selectionCanSetGroup: -----------------------------------[static]--
//
// Purpose:		Set/edit MLCAD group. Menu enable: every selected object can
//				take a group.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanSetGroup:(NSArray *)selection
{
	if ([selection count] == 0)
	{
		return NO;
	}
	for (id directive in selection)
	{
		if (LDrawDirectiveSupportsGroup(directive) == NO)
		{
			return NO;
		}
	}
	return YES;
}


//---------- groupNamesInSelection: ----------------------------------[static]--
//
// Purpose:		Set/edit MLCAD group. Unique current group names (nil stored as
//				@""). Returns nil if any selected object cannot take a group.
//
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *)groupNamesInSelection:(NSArray *)selection
{
	NSMutableSet<NSString *> *groups = [NSMutableSet set];
	for (id object in selection)
	{
		if (LDrawDirectiveSupportsGroup(object) == NO)
		{
			return nil;
		}
		NSString *group = [object group];
		[groups addObject:(group != nil) ? group : @""];
	}
	return groups;
}


//---------- nonEmptyGroupNamesFromSet: ------------------------------[static]--
//
// Purpose:		Non-empty names for a combo list. Order is that of the set.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)nonEmptyGroupNamesFromSet:(NSSet<NSString *> *)groups
{
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	for (NSString *name in groups)
	{
		if ([name length] > 0)
		{
			[names addObject:name];
		}
	}
	return names;
}


//---------- normalizedGroupName: ------------------------------------[static]--
//
// Purpose:		Trim whitespace; nil stays nil.
//
//------------------------------------------------------------------------------
+ (NSString *)normalizedGroupName:(NSString *)name
{
	if (name == nil)
	{
		return nil;
	}
	return [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


//---------- groupChangesInSelection:toGroupName: --------------------[static]--
//
// Purpose:		Set/edit MLCAD group. LDrawObjectWithValue pairs for directives
//				whose group differs from newName.
//
//------------------------------------------------------------------------------
+ (NSArray *)groupChangesInSelection:(NSArray *)selection
						 toGroupName:(NSString *)newName
{
	NSMutableArray *changes = [NSMutableArray array];
	for (id object in selection)
	{
		if (LDrawDirectiveSupportsGroup(object) == NO)
		{
			continue;
		}
		if ([newName isEqualToString:[object group]] == NO)
		{
			[changes addObject:[[LDrawObjectWithValue alloc] initWithObject:object value:newName]];
		}
	}
	return changes;
}


//---------- invertedGroupChanges: -----------------------------------[static]--
//
// Purpose:		Current groups of the same objects, for undo. Must run before
//				applying.
//
//------------------------------------------------------------------------------
+ (NSArray *)invertedGroupChanges:(NSArray *)directivesAndGroups
{
	NSMutableArray *inverted = [NSMutableArray array];
	for (LDrawObjectWithValue *pair in directivesAndGroups)
	{
		id        directive = pair.object;
		NSString *oldGroup  = [directive valueForKey:@"group"];
		[inverted addObject:[[LDrawObjectWithValue alloc] initWithObject:directive
																   value:(oldGroup != nil) ? oldGroup : @""]];
	}
	return inverted;
}


//---------- applyGroupChanges: --------------------------------------[static]--
//
// Purpose:		Set/edit MLCAD group. Sets each pair's group name. The host
//				still registers undo.
//
//------------------------------------------------------------------------------
+ (void)applyGroupChanges:(NSArray *)directivesAndGroups
{
	for (LDrawObjectWithValue *pair in directivesAndGroups)
	{
		[pair.object setValue:pair.value forKey:@"group"];
	}
}


//---------- mlcadGroupDialogMessageKey ------------------------------[static]--
//
// Purpose:		MLCAD group dialog localization keys. The host still localizes
//				and shows the alert.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogMessageKey
{
	return @"MLCADGroupDialogMessage";
}


//---------- mlcadGroupDialogInformativeKey -------------------------[static]--
//
// Purpose:		Localization key for the MLCAD group-name dialog informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogInformativeKey
{
	return @"MLCADGroupDialogInformative";
}


//---------- mlcadGroupDialogSetButtonKey ---------------------------[static]--
//
// Purpose:		Localization key for the MLCAD group-name dialog Set button.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogSetButtonKey
{
	return @"SetButtonName";
}


//---------- mlcadGroupDialogCancelButtonKey ------------------------[static]--
//
// Purpose:		Localization key for the MLCAD group-name dialog Cancel button.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)mlcadGroupDialogCancelButtonKey
{
	return @"CancelButtonName";
}


@end
