//==============================================================================
//
//  File:       LDrawShadowFile.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Reads the SNAP metas of one LDCad shadow library file.
//
//  Notes:      Only lines that begin "0 !LDCAD" are read, so a meta written as
//              "0 //!LDCAD" is off. Unknown attributes are skipped.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawConnector.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, LDrawShadowMetaKind)
{
	LDrawShadowMetaKindCylinder	= 0,	// SNAP_CYL
	LDrawShadowMetaKindClear	= 1,	// SNAP_CLEAR
	LDrawShadowMetaKindInclude	= 2,	// SNAP_INCL
};


/// One SNAP meta, converted to connector types.
@interface LDrawShadowMeta : NSObject

@property (nonatomic, readonly) LDrawShadowMetaKind			kind;
@property (nonatomic, readonly, copy, nullable) NSString	*identifier;	// id
@property (nonatomic, readonly, copy, nullable) NSString	*reference;		// ref, for an include
@property (nonatomic, readonly) Matrix4						frame;			// pos and ori together
@property (nonatomic, readonly) LDrawConnectorGender		gender;
@property (nonatomic, readonly) LDrawConnectorCaps			caps;
@property (nonatomic, readonly) LDrawConnectorGrid			grid;			// steps in the file's coordinates
@property (nonatomic, readonly) LDrawConnectorScaleRule		scaleRule;
@property (nonatomic, readonly) BOOL						centered;
@property (nonatomic, readonly) BOOL						slide;
@property (nonatomic, readonly, copy) NSData				*sections;		// LDrawConnectorSection array

@end


@interface LDrawShadowFile : NSObject

/// Nil when the file cannot be read. A file with no metas gives an empty
/// list.
+ (nullable instancetype)shadowFileWithContentsOfFile:(NSString *)path;

@property (nonatomic, readonly) NSArray<LDrawShadowMeta *> *metas;

@end

NS_ASSUME_NONNULL_END
