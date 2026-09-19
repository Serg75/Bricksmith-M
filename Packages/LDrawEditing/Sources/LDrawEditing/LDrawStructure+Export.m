//==============================================================================
//
//  File:       LDrawStructure+Export.m
//  Package:    LDrawEditing
//
//  Purpose:    Step export and compliant submodel naming for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>


@implementation LDrawStructure (Export)

//---------- compliantNameChangesForSubmodels: -----------------------[static]--
//
// Purpose:		Ensures that the names of all submodels end in a recognized
//				LDraw extension (.ldr, .dat). Previous versions
//				did not force this, and it was a seemingly sensible, Maclike
//				thing to do. Alas, MLCad will NOT RECOGNIZE submodels whose
//				names do not have an extension. (Why...?!) Furthermore,
//				according to the LDraw File Specification, a type 1 MUST point
//				to a "valid LDraw filename," which MUST include the extension.
//				http://www.ldraw.org/Article218.html#lt1 Sigh...
//
// Notes:		Find submodels with bad names. If the model name does not have
//				a valid LDraw file extension, the LDraw spec says we must give
//				it one. Ugh.
//
//				For files with only one model, we synthesize a name based on
//				the model description. We can safely do a direct rename of
//				these files. This also means LDrawMPDModel doesn't have to
//				clean up every official part we parse from the LDraw folder.
//
//				For MPD documents, we need to do a complex rename. The host
//				still calls renameModel:toName: and marks the document dirty.
//
//------------------------------------------------------------------------------
+ (NSArray *)compliantNameChangesForSubmodels:(NSArray *)submodels
{
	NSMutableArray *changes = [NSMutableArray array];
	BOOL renameInPlace = ([submodels count] == 1);

	for (LDrawMPDModel *currentSubmodel in submodels)
	{
		NSString *currentName    = [currentSubmodel modelName];
		NSString *acceptableName = [LDrawMPDModel ldrawCompliantNameForName:currentName];

		if ([acceptableName isEqualToString:currentName] == NO)
		{
			[changes addObject:[[LDrawCompliantNameChange alloc] initWithModel:currentSubmodel
																 compliantName:acceptableName
																 renameInPlace:renameInPlace]];
		}
	}
	return changes;
}


//---------- stepExportFilesFromFile:folderNameFormat:fileNameFormat: [static]--
//
// Purpose:		Output all the steps for all the submodels as a series of files,
//				one for each progressive step.
//
// Notes:		Move the target model to the top of the file. That way L3P will
//				know to render it!
//
//				Write out each step, then remove the step we just wrote, so
//				that the next cycle won't include it. We can safely do this
//				because we are working with a copy of the file. The host still
//				makes folders and writes bytes.
//
//------------------------------------------------------------------------------
+ (NSArray *)stepExportFilesFromFile:(LDrawFile *)file
					folderNameFormat:(NSString *)folderNameFormat
					  fileNameFormat:(NSString *)fileNameFormat
{
	NSMutableArray *exports = [NSMutableArray array];
	if (file == nil) return exports;

	NSArray        *submodels = [file submodels];
	NSInteger       modelCounter;

	for (modelCounter = 0; modelCounter < [submodels count]; modelCounter++)
	{
		LDrawFile *fileCopy = [file copy];
		LDrawMPDModel *currentModel = [[fileCopy submodels] objectAtIndex:modelCounter];
		[fileCopy removeDirective:currentModel];
		[fileCopy insertDirective:currentModel atIndex:0];
		[fileCopy setActiveModel:currentModel];

		NSString *folderName = [NSString stringWithFormat:folderNameFormat, [currentModel modelName]];
		NSInteger counter;

		for (counter = [[currentModel steps] count]-1; counter >= 0; counter--)
		{
			NSString *ldrString = [fileCopy write];
			NSString *fileName  = [NSString stringWithFormat:fileNameFormat,
								   [currentModel modelName],
								   (long)counter+1];
			[exports addObject:[[LDrawStepExportFile alloc] initWithFolderName:folderName
																	  fileName:fileName
																	 ldrString:ldrString]];
			[currentModel removeDirectiveAtIndex:counter];
		}
	}
	return exports;
}


//---------- exportedStepsFolderFormatKey ----------------------------[static]--
//
// Purpose:		Localization format keys for step export. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)exportedStepsFolderFormatKey
{
	return @"ExportedStepsFolderFormat";
}


//---------- exportedStepsFileFormatKey -----------------------------[static]--
//
// Purpose:		Localization key format for an exported-steps file name. The
//				host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)exportedStepsFileFormatKey
{
	return @"ExportedStepsFileFormat";
}


//---------- duplicateModelNameMessageFormatKey ----------------------[static]--
//
// Purpose:		Duplicate model-name alert keys. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicateModelNameMessageFormatKey
{
	return @"DuplicateModelnameMessage";
}


//---------- duplicateModelNameInformativeKey -----------------------[static]--
//
// Purpose:		Localization key for the duplicate-model-name alert informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicateModelNameInformativeKey
{
	return @"DuplicateModelnameInformative";
}


//---------- shouldRejectDuplicateModelRenameFrom:to:whenModelNameExists: ------
//
// Purpose:		YES when renaming to a different name that already exists in
//				the file. Duplicate model names are not allowed, because they
//				cause nasty things to happen when automatically renaming
//				references to them.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldRejectDuplicateModelRenameFrom:(NSString *)oldValue
										  to:(NSString *)newValue
						 whenModelNameExists:(BOOL)nameExists
{
	if (nameExists == NO)
		return NO;
	if (oldValue == nil || newValue == nil)
		return nameExists;
	return [newValue caseInsensitiveCompare:oldValue] != NSOrderedSame;
}

@end
