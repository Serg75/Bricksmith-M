//==============================================================================
//
//  File:       LDrawViewportDropMove.m
//  Package:    LDrawEditing
//
//  Purpose:    Drawable original plus the displacement to apply after a
//              same-document 3D-viewport drop.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawViewportDropMove.h>

@implementation LDrawViewportDropMove

//========== initWithDirective:displacement: ==================================
//
// Purpose:		Record one drawable and the displacement applied during a 3D-
//				viewport drop so the host can undo the move.
//
//==============================================================================
- (instancetype)initWithDirective:(LDrawDrawableElement *)directive
					 displacement:(Vector3)displacement
{
	self = [super init];
	if (self)
	{
		_directive    = directive;
		_displacement = displacement;
	}
	return self;
}

@end
