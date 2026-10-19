//==============================================================================
//
//  File:       LPubPageNumberDisplay.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-18.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubPageNumberSwitch
///
/// @abstract   What a line about the page's number turns on or off.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPageNumberSwitch) {
	/// Whether the number is printed. LPub3D's default is TRUE.
	LPubPageNumberSwitchDisplay		= 0,
	/// Whether an even page puts the number on the other side. LPub3D's
	/// default is FALSE.
	LPubPageNumberSwitchToggle		= 1
};


//------------------------------------------------------------------------------
///
/// @class      LPubPageNumberDisplay
///
/// @abstract   Whether LPub3D prints the page's number, and on which side:
///             0 !LPUB PAGE DISPLAY_PAGE_NUMBER [GLOBAL|LOCAL] (TRUE|FALSE)
///             0 !LPUB PAGE TOGGLE_PAGE_NUMBER_PLACEMENT [GLOBAL|LOCAL]
///                 (TRUE|FALSE)
///
/// @discussion The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPageNumberDisplay : LPubCommand

@property (nonatomic, readonly) LPubPageNumberSwitch	kind;
@property (nonatomic, readonly) LPubMetaScope			scope;

/// YES for TRUE.
@property (nonatomic, readonly) BOOL					isOn;

@end

NS_ASSUME_NONNULL_END
