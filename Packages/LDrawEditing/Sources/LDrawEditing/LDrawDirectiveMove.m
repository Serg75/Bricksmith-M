//==============================================================================
//
//  File:       LDrawDirectiveMove.m
//  Package:    LDrawEditing
//
//  Purpose:    A movable directive plus the displacement to move it by.
//
//  Created by Sergey Slobodenyuk on 2026-11-11.
//
//==============================================================================

#import <LDrawEditing/LDrawDirectiveMove.h>

@implementation LDrawDirectiveMove

//========== initWithDirective:displacement: ===================================
//
// Purpose:		Records one directive and how far to move it.
//
//==============================================================================
- (instancetype)initWithDirective:(LDrawDirective<LDrawMovableDirective> *)directive
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
