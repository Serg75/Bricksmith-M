//==============================================================================
//
//  File:       LDrawMLCadIni.h
//  Package:    LDrawFeatures
//
//  Purpose:    Parses the contents of LDraw/MLCad.ini, the file which defines
//              settings for the minifigure generator.
//
//  Info:       The host passes a file path, usually LDraw/MLCad.ini when it
//              exists, otherwise +bundledIniPathInBundle:. Parse does not look
//              up the app main bundle.
//
//  Created by Allen Smith on 7/2/06.
//  Copyright 2006. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


//------------------------------------------------------------------------------
///
/// @class      LDrawMLCadIni
///
/// @abstract   Parses the contents of LDraw/MLCad.ini, the file which defines
///             settings for the minifigure generator.
///
//------------------------------------------------------------------------------
@interface LDrawMLCadIni : NSObject
{
	NSArray				*lsynthVisibleTypes;

	//Minifigure Generator
	NSMutableArray		*minifigureHats;
	NSMutableArray		*minifigureHeads;
	NSMutableArray		*minifigureNecks;
	NSMutableArray		*minifigureTorsos;
	NSMutableArray		*minifigureHips;
	NSMutableArray		*minifigureArmsLeft;
	NSMutableArray		*minifigureArmsRight;
	NSMutableArray		*minifigureHandsLeft;
	NSMutableArray		*minifigureHandsLeftAccessories;
	NSMutableArray		*minifigureHandsRight;
	NSMutableArray		*minifigureHandsRightAccessories;
	NSMutableArray		*minifigureLegsLeft;
	NSMutableArray		*minifigureLegsLeftAccessories;
	NSMutableArray		*minifigureLegsRight;
	NSMutableArray		*minifigureLegsRightAccessories;
}

//Initialization
/// Bundled MLCad.ini, or nil if the bundle has no such resource.
+ (nullable NSString *)bundledIniPathInBundle:(NSBundle *)bundle;

/// Process-wide parsed ini. First path wins. Host passes
/// MLCadIniPathWithBundledPath: plus bundledIniPathInBundle:.
+ (instancetype)sharedIniFileWithPath:(nullable NSString *)filePath;

//Accessors
- (NSArray *) lsynthVisibleTypes;
- (NSArray *) minifigureHats;
- (NSArray *) minifigureHeads;
- (NSArray *) minifigureNecks;
- (NSArray *) minifigureTorsos;
- (NSArray *) minifigureHips;
- (NSArray *) minifigureArmsLeft;
- (NSArray *) minifigureArmsRight;
- (NSArray *) minifigureHandsLeft;
- (NSArray *) minifigureHandsLeftAccessories;
- (NSArray *) minifigureHandsRight;
- (NSArray *) minifigureHandsRightAccessories;
- (NSArray *) minifigureLegsLeft;
- (NSArray *) minifigureLegsLeftAccessories;
- (NSArray *) minifigureLegsRight;
- (NSArray *) minifigureLegsRightAccessories;

- (float) armAngleForTorsoName:(NSString *)torsoName;

//Parsing
- (void) parseFromPath:(NSString *) path;

@end

NS_ASSUME_NONNULL_END
