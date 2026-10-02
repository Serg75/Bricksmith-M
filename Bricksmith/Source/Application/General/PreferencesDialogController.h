//==============================================================================
//
// File:		PreferencesDialogController.h
//
// Purpose:		Handles the user interface between the application and its
//				preferences file.
//
//  Created by Allen Smith on 2/14/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>


////////////////////////////////////////////////////////////////////////////////
//
// class PreferencesDialogController
//
////////////////////////////////////////////////////////////////////////////////
@interface PreferencesDialogController : NSObject

// Initialization
+ (void) doPreferences;
- (void) showPreferencesWindow;

// Utilities
+ (void) ensureDefaults;
+ (void) loadStepPartListOrientations;
+ (void) pushStepPartListDefaults;

@end
