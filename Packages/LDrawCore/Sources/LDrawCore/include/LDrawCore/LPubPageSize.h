//==============================================================================
//
//  File:       LPubPageSize.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubPageSize
///
/// @abstract   LPub PAGE SIZE command: how big the printed page is.
///
/// @discussion The two numbers are in the unit the document's RESOLUTION
///             names, inches unless it says DPCM. They describe the page
///             before ORIENTATION is applied.
///
///             LPub3D also accepts a page name instead of measurements (A4,
///             Letter). A name with no numbers stays a plain LPubCommand,
///             because resolving it would need our own table of page sizes.
///             A name after the numbers is kept and written back.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPageSize : LPubCommand

@property (nonatomic, readonly) LPubMetaScope				scope;
/// In the document's unit, as written. Orientation is not applied.
@property (nonatomic, readonly) double						width;
@property (nonatomic, readonly) double						height;
/// The page name, when the line carries one after the measurements.
@property (nonatomic, copy, readonly, nullable) NSString	*pageName;

@end

NS_ASSUME_NONNULL_END
