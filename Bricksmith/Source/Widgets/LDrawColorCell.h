//==============================================================================
//
// File:		LDrawColorCell.h
//
// Purpose:		Displays a swatch of an LDraw color in a cell.
//
//  Created by Allen Smith on 2/26/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>


@interface LDrawColorCell : NSCell {

}

// The swatch is drawn faded and crossed out, for a color that cannot be
// picked.
@property (nonatomic, assign) BOOL struck;

@end
