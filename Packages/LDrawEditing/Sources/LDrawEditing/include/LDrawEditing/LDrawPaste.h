//==============================================================================
//
//  File:       LDrawPaste.h
//  Package:    LDrawEditing
//
//  Purpose:    Paste and duplicate placement for models, steps, and
//              directives. The host still inserts (undo).
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawContainer;
@class LDrawDirective;
@class LDrawFile;
@class LDrawModel;
@class LDrawMPDModel;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPaste
///
/// @abstract   Bucket unarchived objects and resolve parent/index for paste
///             and duplicate.
///
//------------------------------------------------------------------------------
@interface LDrawPaste : NSObject

/// Reset default icons, then bucket unarchived objects into models / steps /
/// other directives. Paste inserts the first non-empty bucket.
+ (void)partitionPastedObjects:(NSArray *)objects
						models:(NSMutableArray *)models
						 steps:(NSMutableArray *)steps
					directives:(NSMutableArray *)directives;

/// Step paste goes into an MPD model. Nil if parent is not one.
+ (nullable LDrawMPDModel *)pasteModelParentFromParent:(nullable id)parent;

/// Index immediately after model in its file, or NSNotFound if model is nil
/// or not in the file. Used for "next model" insert and model duplicate.
+ (NSInteger)insertIndexAfterModel:(nullable LDrawModel *)model inFile:(LDrawFile *)file;

/// Resolves parent/index for one pasted step component. nextToSimilar uses
/// fallbackParentStep when no similar part is found.
+ (void)resolveStepPasteParent:(LDrawContainer * _Nullable * _Nullable)outParent
						 index:(NSInteger * _Nullable)outIndex
				  forDirective:(LDrawDirective *)directive
						parent:(nullable id)parent
				 insertAtIndex:(NSInteger)insertAtIndex
				 nextToSimilar:(BOOL)nextToSimilar
				   inSelection:(NSArray *)selection
			fallbackParentStep:(nullable LDrawContainer *)fallbackParentStep;

/// insertAtIndex when not NSNotFound; otherwise defaultIndex (e.g. next model).
+ (NSInteger)modelPasteStartIndexForInsertAtIndex:(NSInteger)insertAtIndex
									 defaultIndex:(NSInteger)defaultIndex;

/// index + 1 for sequential model paste, or NSNotFound when index is NSNotFound.
+ (NSInteger)nextSequentialModelInsertIndexAfter:(NSInteger)index;

/// Duplicate paste index: defaultNextModelIndex when duplicating a model;
/// otherwise NSNotFound (next-to-similar placement).
+ (NSInteger)duplicatePasteIndexForSelection:(NSArray *)selection
					   defaultNextModelIndex:(NSInteger)defaultNextModelIndex;

/// Localization key for -duplicate:. The host still localizes.
+ (NSString *)duplicateUndoActionKey;

@end

NS_ASSUME_NONNULL_END
