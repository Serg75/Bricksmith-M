//==============================================================================
//
// Category: UserDefaultsCategory.m
//
//		Allows storing certain objects that otherwise cannot be stored directly.
//
//  Created by Allen Smith on 3/12/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "UserDefaultsCategory.h"


@implementation NSUserDefaults (UserDefaultsCategory)

//========== setColor:forKey: ==================================================
//
// Purpose:		Saves a color into UserDefaults.
//
//==============================================================================
- (void)setColor:(NSColor *)aColor forKey:(NSString *)aKey
{
    NSData	*theData = [NSKeyedArchiver archivedDataWithRootObject:aColor requiringSecureCoding:NO error:nil];
	
    [self setObject:theData forKey:aKey];
	
}//end setColor:forKey:


//========== colorForKey: ======================================================
//
// Purpose:		Retrieves a color stored in UserDefaults.
//
//==============================================================================
- (NSColor *)colorForKey:(NSString *)aKey

{
	NSColor	*theColor	= nil;
    NSData	*theData	= [self dataForKey:aKey];
	
    if (theData != nil) {
        NSError *unarchiveError = nil;
        theColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:theData error:&unarchiveError];
        if (unarchiveError != nil) {
            NSLog(@"Failed to unarchive NSColor for key %@: %@", aKey, unarchiveError);
            
            // Try legacy NSUnarchiver for old archived colors
			// TODO: remove in the future
            @try {
                theColor = [NSUnarchiver unarchiveObjectWithData:theData];
                if (theColor && [theColor isKindOfClass:[NSColor class]]) {
                    NSLog(@"Successfully unarchived legacy NSColor for key %@", aKey);
                    // Re-save using modern format
                    [self setColor:theColor forKey:aKey];
                } else {
                    theColor = nil;
                }
            }
            @catch (NSException *exception) {
                NSLog(@"Failed to unarchive legacy NSColor for key %@: %@", aKey, exception);
                theColor = nil;
            }
        }
    }
	
    return theColor;
	
}//end colorForKey:


@end
