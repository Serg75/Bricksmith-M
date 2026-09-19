//==============================================================================
//
//  File:       LDrawCompliantNameChange.h
//  Package:    LDrawEditing
//
//  Purpose:    A submodel that must be given a spec-compliant name (.ldr /
//              .dat).
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawMPDModel;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawCompliantNameChange
///
/// @abstract   A submodel that must be given a spec-compliant name (.ldr /
///             .dat).
///
//------------------------------------------------------------------------------
@interface LDrawCompliantNameChange : NSObject

@property (nonatomic, strong) LDrawMPDModel *model;
@property (nonatomic, copy)   NSString      *compliantName;

/// Single-submodel files can setModelName: directly. MPD files need
/// renameModel:toName: so references update, then the host marks dirty.
@property (nonatomic) BOOL renameInPlace;

- (instancetype)initWithModel:(LDrawMPDModel *)model
				compliantName:(NSString *)compliantName
				renameInPlace:(BOOL)renameInPlace;

@end

NS_ASSUME_NONNULL_END
