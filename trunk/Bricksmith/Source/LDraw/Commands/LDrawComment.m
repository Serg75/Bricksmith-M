//==============================================================================
//
// File:		LDrawComment.m
//
// Purpose:		A comment. It serves only as explanatory text in the model.
//
//				Line format:
//				0 // message-text
//					or
//				0 WRITE message-text
//					or
//				0 PRINT message-text
//
//				where
//
//				* message-text is a comment string
//
//  Created by Allen Smith on 3/12/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import "LDrawComment.h"

#import "LDrawKeywords.h"
#import "LDrawUtilities.h"

@implementation LDrawComment

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- metaCommandInstanceByMarker:scanner: --------------------[static]--
///
/// @abstract	Creates Comment instance if we have proper command marker.
///
//------------------------------------------------------------------------------
+ (LDrawMetaCommand *) metaCommandInstanceByMarker:(NSString *)ldrawMarker scanner:(NSScanner *)scanner
{
	if ([ldrawMarker isEqualToString:LDRAW_COMMENT_SLASH] ||
		[ldrawMarker isEqualToString:LDRAW_COMMENT_WRITE] ||
		[ldrawMarker isEqualToString:LDRAW_COMMENT_PRINT])
	{
		return [[LDrawComment alloc] init];
	}
	return nil;
	
}//end metaCommandInstanceByMarker:scanner:


//========== finishParsing: ====================================================
//
// Purpose:		-[LDrawMetaCommand initWithLines:inRange:] is 
//				responsible for parsing out the line code and comment command 
//				(i.e., "0 //"); now we just have to finish the comment-command 
//				specific syntax. As it happens, that is everything after the 
//				comment command. 
//
//==============================================================================
- (BOOL) finishParsing:(NSScanner *)scanner
{
	NSString	*remainder	= nil;

	remainder = [[scanner string] substringFromIndex:[scanner scanLocation]];
	[self setCommandString:remainder];
	
	return YES;
	
}//end finishParsing


#pragma mark -
#pragma mark DIRECTIVES
#pragma mark -

//========== write =============================================================
//
// Purpose:		Returns a line that can be written out to a file.
//				Line format:
//				0 // comment-text
//
// Notes:		Bricksmith only attempts to write out one style of comments.
//				Per the LDraw File Format 1.0.0, the "0 // comment" form is
//				preferred. http://ldraw.org/Article218.html#lt0
//
//==============================================================================
- (NSString *) write
{
	return [NSString stringWithFormat:	@"0 %@ %@",
										LDRAW_COMMENT_SLASH,
										[self commandString]	];
}//end write


#pragma mark -
#pragma mark DISPLAY
#pragma mark -

//========== browsingDescription ===============================================
//
// Purpose:		Returns a representation of the directive as a short string 
//				which can be presented to the user.
//
//==============================================================================
- (NSString *) browsingDescription
{
	return [self commandString];
	
}//end browsingDescription


//========== iconName ==========================================================
//
// Purpose:		Returns the name of image file used to display this kind of 
//				object, or nil if there is no icon.
//
//==============================================================================
- (NSString *) iconName
{
	return @"Comment";
	
}//end iconName


//========== inspectorClassName ================================================
//
// Purpose:		Returns the name of the class used to inspect this one.
//
//==============================================================================
- (NSString *) inspectorClassName
{
	return @"InspectionComment";
	
}//end inspectorClassName


@end
