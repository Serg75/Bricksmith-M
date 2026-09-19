//==============================================================================
//
//  File:       LDrawStepExportFile.m
//  Package:    LDrawEditing
//
//  Purpose:    One LDR file in a step-export: per-model folder name, file name,
//              and file contents.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawStepExportFile.h>

@implementation LDrawStepExportFile

//========== initWithFolderName:fileName:ldrString: ===========================
//
// Purpose:		Record one exported-steps file: destination folder, file name,
//				and LDR contents.
//
//==============================================================================
- (instancetype)initWithFolderName:(NSString *)folderName
						  fileName:(NSString *)fileName
						 ldrString:(NSString *)ldrString
{
	self = [super init];
	if (self)
	{
		_folderName = [folderName copy];
		_fileName   = [fileName copy];
		_ldrString  = [ldrString copy];
	}
	return self;
}

@end
