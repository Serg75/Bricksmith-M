//==============================================================================
//
//  File:       LDrawFile.h
//  Package:    LDrawCore
//
//  Purpose:    Represents an LDraw file, composed of one or more models.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawContainer.h>

// forward declarations
@class LDrawMPDModel;

NS_ASSUME_NONNULL_BEGIN

//Active model changed.
// Object is the LDrawFile in which the model resides. No userInfo.
#define LDrawFileActiveModelDidChangeNotification		@"LDrawFileActiveModelDidChangeNotification"


//------------------------------------------------------------------------------
///
/// @class      LDrawFile
///
/// @abstract   Represents an LDraw file, composed of one or more models.
///
//------------------------------------------------------------------------------
@interface LDrawFile : LDrawContainer
{
	NSDictionary			*nameModelDict;
	__weak LDrawMPDModel	*activeModel;
	NSString				*filePath;			//where this file came from on disk.
}

// Initialization
+ (LDrawFile *) file;
+ (nullable LDrawFile *) fileFromContentsAtPath:(NSString *)path;
+ (nullable LDrawFile *) parseFromFileContents:(NSString *) fileContents;

// Directives
- (void) collectColorsFromConfig;

// Accessors
- (nullable LDrawMPDModel *) activeModel;
- (LDrawMPDModel *) firstModel;							// For using another file, we always refer to the FIRST model even if the doc is open and another model is actively edited!
- (void) addSubmodel:(LDrawMPDModel *)newSubmodel;
- (nullable NSArray *) draggingDirectives;
- (NSArray *) modelNames;
- (nullable LDrawMPDModel *) modelWithName:(NSString *)soughtName;
- (nullable NSString *)path;
- (NSArray *) submodels;
- (NSArray<LDrawPart *> *) partsWithName:(NSString *)name;

- (void) setActiveModel:(nullable LDrawMPDModel *)newModel;
- (void) setDraggingDirectives:(nullable NSArray *)directives;
- (void) setPath:(nullable NSString *)newPath;

// Utilities
- (void) optimizeStructure;
- (void) renameModel:(LDrawMPDModel *)submodel toName:(NSString *)newName;

@end

NS_ASSUME_NONNULL_END
