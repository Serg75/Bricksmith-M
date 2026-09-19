//==============================================================================
//
//  File:       LDrawCompliantNameChange.m
//  Package:    LDrawEditing
//
//  Purpose:    A submodel that must be given a spec-compliant name (.ldr /
//              .dat).
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawCompliantNameChange.h>

@implementation LDrawCompliantNameChange

//========== initWithModel:compliantName:renameInPlace: =======================
//
// Purpose:		Record a pending MPD model rename to an LDraw-compliant name.
//
//==============================================================================
- (instancetype)initWithModel:(LDrawMPDModel *)model
				compliantName:(NSString *)compliantName
				renameInPlace:(BOOL)renameInPlace
{
	self = [super init];
	if (self)
	{
		_model          = model;
		_compliantName  = [compliantName copy];
		_renameInPlace  = renameInPlace;
	}
	return self;
}

@end
