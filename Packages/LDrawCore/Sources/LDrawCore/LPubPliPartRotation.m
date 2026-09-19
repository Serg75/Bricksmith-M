//==============================================================================
//
//  File:       LPubPliPartRotation.m
//  Package:    LDrawCore
//
//  Purpose:    A rotation LPub3D applies to every icon in the parts list.
//
//              Line format:
//              0 !LPUB PLI PART_ROTATION [GLOBAL|LOCAL] <x> <y> <z> [ABS|REL|ADD]
//
//              Three numbers, then an optional type. Any other form stays a
//              plain LPubCommand.
//
//  Created by Sergey Slobodenyuk on 2026-09-13.
//
//==============================================================================

#import <LDrawCore/LPubPliPartRotation.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const LPUB_PART_ROTATION = @"PART_ROTATION";


@implementation LPubPliPartRotation


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 5
		|| [parameters[0] isEqualToString:LPUB_PLI] == NO
		|| [parameters[1] isEqualToString:LPUB_PART_ROTATION] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];
	double			x = 0.0, y = 0.0, z = 0.0;

	NSUInteger remaining = parameters.count - index;

	if ((remaining != 3 && remaining != 4)
		|| [LPubCommand getNumber:&x fromToken:parameters[index]] == NO
		|| [LPubCommand getNumber:&y fromToken:parameters[index + 1]] == NO
		|| [LPubCommand getNumber:&z fromToken:parameters[index + 2]] == NO) {
		return nil;
	}

	LPubPliPartRotationType type = LPubPliPartRotationTypeNone;

	if (remaining == 4) {
		NSString *keyword = parameters[index + 3];

		if ([keyword isEqualToString:@"ABS"]) {
			type = LPubPliPartRotationTypeAbsolute;
		}
		else if ([keyword isEqualToString:@"REL"]) {
			type = LPubPliPartRotationTypeRelative;
		}
		else if ([keyword isEqualToString:@"ADD"]) {
			type = LPubPliPartRotationTypeAdditive;
		}
		else {
			return nil;
		}
	}

	LPubPliPartRotation *command = [LPubPliPartRotation new];

	command->_scope		= scope;
	command->_angles	= V3Make(x, y, z);
	command->_type		= type;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ %@ [%g %g %g]", LPUB_PLI, LPUB_PART_ROTATION,
			self.angles.x, self.angles.y, self.angles.z];
}


// MARK: - ACCESSORS -


//========== rotationMatrix ====================================================
///
/// @abstract	The rotation, as Bricksmith multiplies points.
///
/// @discussion	The ROTSTEP matrix is built for column vectors. Bricksmith
/// 			puts the point on the left, so the same rotation is that
/// 			matrix transposed.
///
//==============================================================================
- (Matrix4) rotationMatrix
{
	if (self.type == LPubPliPartRotationTypeNone) {
		return IdentityMatrix4;
	}

	double s1 = sin(self.angles.x * M_PI / 180.0), c1 = cos(self.angles.x * M_PI / 180.0);
	double s2 = sin(self.angles.y * M_PI / 180.0), c2 = cos(self.angles.y * M_PI / 180.0);
	double s3 = sin(self.angles.z * M_PI / 180.0), c3 = cos(self.angles.z * M_PI / 180.0);

	double rm[3][3] = {
		{  c2 * c3,						-c2 * s3,						 s2      },
		{  c1 * s3 + s1 * s2 * c3,		 c1 * c3 - s1 * s2 * s3,		-s1 * c2 },
		{  s1 * s3 - c1 * s2 * c3,		 s1 * c3 + c1 * s2 * s3,		 c1 * c2 },
	};

	Matrix4 matrix = IdentityMatrix4;

	for (int row = 0; row < 3; row++) {
		for (int column = 0; column < 3; column++) {
			matrix.element[row][column] = rm[column][row];
		}
	}

	return matrix;

}//end rotationMatrix


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPliPartRotation *other = (LPubPliPartRotation *)command;

	self->_scope	= other->_scope;
	self->_angles	= other->_angles;
	self->_type		= other->_type;

}//end adoptPropertiesFromCommand:


@end
