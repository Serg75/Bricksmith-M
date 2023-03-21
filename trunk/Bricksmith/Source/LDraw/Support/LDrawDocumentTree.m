//==============================================================================
//
//  LDrawDocumentTree.m
//  Bricksmith
//
//  Contains methods to examine document structure.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import "LDrawDocumentTree.h"

#import "LDrawStep.h"
#import "LDrawModel.h"
#import "LDrawPart.h"
#import "MatrixMath.h"

@implementation LDrawDocumentTree

//---------- mostInnerDirectives: ------------------------------------[static]--
//
// Purpose:		Filters directives out from the list and leaves only ones with
//				the lowest hierarchical level.
//				Levels of hierarchy (highest to lowest):
//					- model
//					- step
//					- part/primitive/meta/lsynth
//				Examples:
//					- list with parts, steps and models returns parts only
//					- list with steps and models returns steps only
//
//------------------------------------------------------------------------------
+ (NSArray *)mostInnerDirectives:(NSArray *)objects
{
	NSArray *types = @[[LDrawModel class], [LDrawStep class], [LDrawDirective class]];
	NSMutableArray *excludeTypes = [NSMutableArray array];
	NSMutableSet *foundTypes = [NSMutableSet set];
	Class type;
	Class lowestType = nil;
	
	for (id object in objects) {
		for (type in types) {
			if ([object isKindOfClass:type]) {
				[foundTypes addObject:type];
				break;
			}
		}
	}
	for (type in types) {
		if ([foundTypes containsObject:type]) {
			if (lowestType != nil) {
				[excludeTypes addObject:lowestType];
			}
			lowestType = type;
		}
	}

	if (lowestType != nil) {
		return [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
			return [object isKindOfClass:lowestType] && [excludeTypes indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
				return [object isKindOfClass:obj];
			}] == NSNotFound;
		}]];
	}
	return objects;
}//end mostInnerDirectives


//---------- similarDirective:amongObjects: --------------------------[static]--
///
/// @abstract	Returns the part that is similar to the given one, or NSNotFound
///				if there is no such directive or given directive is not a part.
///
/// @param 		directive	- given directive which copy we are looking for.
/// @param 		objects		- we are searching withing this set of objects.
///
//------------------------------------------------------------------------------
+ (LDrawDirective *)similarDirective:(LDrawDirective *)directive
						amongObjects:(id)objects
{
	if ([directive isKindOfClass:[LDrawPart class]]) {
		LDrawPart *part = (LDrawPart *)directive;
		for (id object in objects) {
			if ([object isKindOfClass:[LDrawPart class]]) {
				LDrawPart *p = (LDrawPart *)object;
				Matrix4 m1 = part.transformationMatrix;
				Matrix4 m2 = p.transformationMatrix;
				if (	[part.displayName isEqualToString:p.displayName]
					&& 	part.LDrawColor == p.LDrawColor
					&& 	Matrix4EqualMatrices(&m1, &m2))
				{
					return object;
				}
			}
		}
	}
	return nil;
	
}//end similarDirective:amongObjects:


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
	
}//end groupsBeforeStep


@end
