//==============================================================================
//
//  File:       LPubPliCameraAngles.m
//  Package:    LDrawCore
//
//  Purpose:    The angle LPub3D draws the parts list icons from.
//
//              Line format:
//              0 !LPUB PLI (CAMERA_ANGLES | VIEW_ANGLE) [GLOBAL|LOCAL]
//                  ( <latitude> <longitude>
//                  | FRONT|BACK|TOP|BOTTOM|LEFT|RIGHT|HOME|LAT_LON
//                  | (HOME|LAT_LON) <latitude> <longitude> )
//
//              Named views resolve to the angles LPub3D uses for them. Any
//              other form stays a plain LPubCommand.
//
//  Created by Sergey Slobodenyuk on 2026-09-13.
//
//==============================================================================

#import <LDrawCore/LPubPliCameraAngles.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const	LPUB_CAMERA_ANGLES	= @"CAMERA_ANGLES";
static NSString * const	LPUB_VIEW_ANGLE		= @"VIEW_ANGLE";

static const double		DEFAULT_LATITUDE	= 23.0;
static const double		DEFAULT_LONGITUDE	= -45.0;


//========== AnglesForView() ===================================================
///
/// @abstract	Gives the latitude and longitude for a named view. Returns NO
/// 			for a name it does not know.
///
//==============================================================================
static BOOL AnglesForView(NSString *name, double *latitude, double *longitude)
{
	NSDictionary<NSString *, NSArray<NSNumber *> *> *views =
		@{ @"FRONT":	@[@0.0,   @0.0],
		   @"BACK":		@[@0.0,   @180.0],
		   @"TOP":		@[@90.0,  @0.0],
		   @"BOTTOM":	@[@-90.0, @0.0],
		   @"LEFT":		@[@0.0,   @90.0],
		   @"RIGHT":	@[@0.0,   @-90.0],
		   @"HOME":		@[@30.0,  @45.0],
		   @"LAT_LON":	@[@(DEFAULT_LATITUDE), @(DEFAULT_LONGITUDE)] };

	NSArray<NSNumber *> *angles = views[name];

	if (angles == nil) {
		return NO;
	}

	*latitude	= angles[0].doubleValue;
	*longitude	= angles[1].doubleValue;
	return YES;

}//end AnglesForView


@implementation LPubPliCameraAngles


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	Starts out with LPub3D's default angles.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_latitude		= DEFAULT_LATITUDE;
		self->_longitude	= DEFAULT_LONGITUDE;
	}
	return self;

}//end init


//---------- lpubCommandInstance: ------------------------------------[static]--
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 3
		|| [parameters[0] isEqualToString:LPUB_PLI] == NO
		|| ([parameters[1] isEqualToString:LPUB_CAMERA_ANGLES] == NO
			&& [parameters[1] isEqualToString:LPUB_VIEW_ANGLE] == NO)) {
		return nil;
	}

	NSUInteger		index		= 2;
	LPubMetaScope	scope		= [LPubCommand scopeInParameters:parameters index:&index];
	double			latitude	= 0.0;
	double			longitude	= 0.0;
	BOOL			customViewpoint	= NO;

	NSUInteger remaining = parameters.count - index;

	if (remaining == 2) {
		if ([LPubCommand getNumber:&latitude fromToken:parameters[index]] == NO
			|| [LPubCommand getNumber:&longitude fromToken:parameters[index + 1]] == NO) {
			return nil;
		}
	}
	else if (remaining == 1) {
		if (AnglesForView(parameters[index], &latitude, &longitude) == NO) {
			return nil;
		}
	}
	else if (remaining == 3) {
		// Only HOME and LAT_LON may carry angles of their own.
		NSString *view = parameters[index];

		if (([view isEqualToString:@"HOME"] == NO && [view isEqualToString:@"LAT_LON"] == NO)
			|| [LPubCommand getNumber:&latitude fromToken:parameters[index + 1]] == NO
			|| [LPubCommand getNumber:&longitude fromToken:parameters[index + 2]] == NO) {
			return nil;
		}
		customViewpoint = YES;
	}
	else {
		return nil;
	}

	LPubPliCameraAngles *command = [LPubPliCameraAngles new];

	command->_scope		= scope;
	command->_latitude			= latitude;
	command->_longitude			= longitude;
	command->_customViewpoint	= customViewpoint;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ %@ [%g %g]", LPUB_PLI, LPUB_CAMERA_ANGLES, self.latitude, self.longitude];
}


// MARK: - ACCESSORS -


+ (double) defaultLatitude
{
	return DEFAULT_LATITUDE;
}

+ (double) defaultLongitude
{
	return DEFAULT_LONGITUDE;
}


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPliCameraAngles *other = (LPubPliCameraAngles *)command;

	self->_scope			= other->_scope;
	self->_latitude			= other->_latitude;
	self->_longitude		= other->_longitude;
	self->_customViewpoint	= other->_customViewpoint;

}//end adoptPropertiesFromCommand:


@end
