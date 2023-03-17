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

@implementation LDrawDocumentTree

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
