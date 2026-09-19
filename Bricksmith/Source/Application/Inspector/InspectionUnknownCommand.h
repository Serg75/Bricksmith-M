//==============================================================================
//
// File:		InspectionUnknownCommand.h
//
// Purpose:		Inspector Controller for an LDrawLine.
//
//  Created by Allen Smith on 2/25/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import "ObjectInspectionController.h"

@interface InspectionUnknownCommand : ObjectInspectionController {

	__weak IBOutlet	NSTextField		*commandField;

	NSArray							*topLevelObjects;	// holds NIB objects
}

//Actions
- (IBAction) commandFieldChanged:(id)sender;

@end
