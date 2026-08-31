//==============================================================================
//
//  File:       LDrawPart.h
//  Package:    LDrawCore
//
//  Purpose:    Part command. Inserts a part defined in another LDraw file.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawFile;
@class LDrawModel;
@class LDrawStep;
@class LDrawPartReport;

typedef NS_ENUM(NSInteger, LDrawPartType) {
	LDrawPartTypeUnresolved = 0,// We have not yet tried to figure out what we have.
	LDrawPartTypeNotFound,		// We went looking and the part is missing.  This keeps us from retrying on every query until someone tells us to try again.
	LDrawPartTypeLibrary,		// Part is in the library.
	LDrawPartTypeSubmodel,		// Part is an MPD submodel from our parent LDrawFile
	LDrawPartTypePeerFile		// Part is the first model in another file in the same directory as us.
};


NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPart
///
/// @abstract   Part command. Inserts a part defined in another LDraw file.
///
//------------------------------------------------------------------------------
@interface LDrawPart : LDrawDrawableElement <NSCoding, LDrawObserver>
{
@private
	NSString		*displayName;
	NSString		*referenceName; 		//lower-case version of display name

	float			transformation[16];

	LDrawDirective	*cacheDrawable;			// The drawable is the model we link to OR a VBO that represents it from the part library -- a drawable proxy.
	LDrawModel		*cacheModel;			// The model is the real model we link to.
	LDrawPartType	cacheType;
	NSLock			*drawLock;

	Box3			cacheBounds;			// Cached bonuding box of resolved parts, in part's coordinate (that is, _not_ in the coordinates of the underlying model.
}

@property (strong, nullable) NSString * group;		// MLCAD group name or nil

//Directives
- (void) drawBoundsWithColor:(LDrawColor *)drawingColor;
- (NSString *) write;

//Accessors
- (NSString *) displayName;
- (Point3) position;
- (NSString *) referenceName;
- (nullable LDrawModel *) referencedMPDSubmodel;
- (nullable LDrawModel *) referencedPeerFile;
- (TransformComponents) transformComponents;
- (Matrix4) transformationMatrix;
- (void) setDisplayName:(NSString *)newPartName;
- (void) setDisplayName:(NSString *)newPartName parse:(BOOL)shouldParse inGroup:(nullable dispatch_group_t)parentGroup;
- (void) setTransformComponents:(TransformComponents)newComponents;
- (void) setTransformationMatrix:(Matrix4 *)newMatrix;

//Actions
- (void) collectPartReport:(LDrawPartReport *)report;
- (void) applyToAllParts:(LDrawPartVisitor) visitor;

- (TransformComponents) componentsSnappedToGrid:(float) gridSpacing minimumAngle:(float)degrees;
- (TransformComponents) componentsSnappedToGrid:(float) gridSpacing byAxis:(Vector3)axis;
- (TransformComponents) components:(TransformComponents)components snappedToGrid:(float)gridSpacing minimumAngle:(float)degrees;
- (TransformComponents) componentsMirroredByAxis:(Vector3)axis;
- (void) rotateByDegrees:(Tuple3)degreesToRotate;
- (void) rotateByDegrees:(Tuple3)degreesToRotate centerPoint:(Point3)center;

//Utilities
- (BOOL) partIsMissing;

- (void) resolvePart;
- (void) unresolvePart;
- (void) unresolvePartIfPartLibrary;
- (void) followRedirectionAndUpdate;


@end

NS_ASSUME_NONNULL_END
