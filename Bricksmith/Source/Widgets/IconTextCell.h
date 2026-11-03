//==============================================================================
//
// File:		IconTextCell.h
//
// Purpose:		Shows both text and an icon in a cell.
//
//  Created by Allen Smith on 2/24/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>


////////////////////////////////////////////////////////////////////////////////
//
// class IconTextCell
//
////////////////////////////////////////////////////////////////////////////////
@interface IconTextCell : NSTextFieldCell
{
	@private
		NSImage *image;
		CGFloat imagePadding; //amount of space to the left and right of the image.
		BOOL	verticallyCentersTitle;
}

// A badge at the end of the row: an image, and text after it in the given
// color, such as a count. The title gives up the room.
@property (nonatomic, strong) NSImage *badgeImage;
@property (nonatomic, copy) NSString *badgeText;
@property (nonatomic, strong) NSColor *badgeColor;

//Accessors
- (NSImage *)image;
- (CGFloat) imagePadding;
- (BOOL) verticallyCentersTitle;

- (void) setImage:(NSImage *)newImage;
- (void) setImagePadding:(CGFloat)newAmount;
- (void) setVerticallyCentersTitle:(BOOL)flag;

@end
