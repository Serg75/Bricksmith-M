//==============================================================================
//
//  File:       LDrawStepExportFile.h
//  Package:    LDrawEditing
//
//  Purpose:    One LDR file in a step-export: per-model folder name, file name,
//              and file contents. The host still creates directories and writes
//              bytes.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepExportFile
///
/// @abstract   One LDR file in a step-export: per-model folder name, file name,
///             and file contents. The host still creates directories and writes
///             bytes.
///
//------------------------------------------------------------------------------
@interface LDrawStepExportFile : NSObject

@property (nonatomic, copy) NSString *folderName;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *ldrString;

- (instancetype)initWithFolderName:(NSString *)folderName
						  fileName:(NSString *)fileName
						 ldrString:(NSString *)ldrString;

@end

NS_ASSUME_NONNULL_END
