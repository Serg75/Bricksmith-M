//==============================================================================
//
//  File:       LDrawStepPartListEntry.m
//  Package:    LDrawCore
//
//  Purpose:    One row of a step's parts list: a part design in a color, and
//              how many of it the step consumes.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LDrawStepPartListEntry.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawUtilities.h>


@implementation LDrawStepPartListEntry


// MARK: - INITIALIZATION -


//========== initWithPartName:... ==============================================
///
/// @abstract	Designated initializer.
///
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName
					 displayTitle:(NSString *)displayTitle
							color:(LDrawColor *)color
						 quantity:(NSUInteger)quantity
					  modelBounds:(Box3)modelBounds
						isMissing:(BOOL)isMissing
					   isSubmodel:(BOOL)isSubmodel
{
	self = [super init];
	if (self) {
		self->_partName			= [partName copy];
		self->_displayTitle		= [displayTitle copy];
		self->_color			= color;
		self->_quantity			= quantity;
		self->_modelBounds		= modelBounds;
		self->_isMissing		= isMissing;
		self->_isSubmodel		= isSubmodel;
		self->_listOrientation	= IdentityMatrix4;
	}
	return self;

}//end initWithPartName:...


// MARK: - ACCESSORS -


//========== groupKey ==========================================================
///
/// @abstract	Identity for grouping: part design plus color.
///
/// @discussion	A newline separates the two halves. A part name cannot hold
/// 			one, so two different pairs cannot make the same key.
///
//==============================================================================
- (NSString *) groupKey
{
	// No color at all is not color 0 (black), so keep the two apart.
	NSString *color = @"none";

	if (self.color != nil) {
		// Every custom RGB color has the same code, so use its written form.
		color = ([self.color colorCode] == LDrawColorCustomRGB)
			   ? [LDrawUtilities outputStringForColor:self.color]
			   : [NSString stringWithFormat:@"%d", (int)[self.color colorCode]];
	}

	return [NSString stringWithFormat:@"%@\n%@", self.partName, color];

}//end groupKey


// MARK: - UTILITIES -


//========== duplicateWithQuantity: ============================================
///
/// @abstract	A copy of this entry with the given quantity.
///
//==============================================================================
- (LDrawStepPartListEntry *) duplicateWithQuantity:(NSUInteger)quantity
{
	LDrawStepPartListEntry *duplicate = [[LDrawStepPartListEntry alloc] initWithPartName:self.partName
																			displayTitle:self.displayTitle
																				   color:self.color
																				quantity:quantity
																			 modelBounds:self.modelBounds
																			   isMissing:self.isMissing
																			  isSubmodel:self.isSubmodel];

	duplicate->_outlinePoints	= self->_outlinePoints;
	duplicate->_listOrientation	= self->_listOrientation;

	return duplicate;

}//end duplicateWithQuantity:


//========== entryByAddingInstance =============================================
///
/// @abstract	A copy of this entry with one more instance counted.
///
//==============================================================================
- (LDrawStepPartListEntry *) entryByAddingInstance
{
	return [self duplicateWithQuantity:self.quantity + 1];

}//end entryByAddingInstance


//========== entryWithOutlinePoints: ===========================================
///
/// @abstract	A copy of this entry outlined by these points.
///
//==============================================================================
- (LDrawStepPartListEntry *) entryWithOutlinePoints:(NSData *)outlinePoints
{
	LDrawStepPartListEntry *outlined = [self duplicateWithQuantity:self.quantity];

	outlined->_outlinePoints = [outlinePoints copy];

	return outlined;

}//end entryWithOutlinePoints:


//========== entryWithListOrientation: =========================================
///
/// @abstract	A copy of this entry turned by this matrix.
///
//==============================================================================
- (LDrawStepPartListEntry *) entryWithListOrientation:(Matrix4)listOrientation
{
	LDrawStepPartListEntry *turned = [self duplicateWithQuantity:self.quantity];

	turned->_listOrientation = listOrientation;

	return turned;

}//end entryWithListOrientation:


//========== description =======================================================
///
/// @abstract	Debugging aid; not shown to the user.
///
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@ x%lu color %d%@%@>",
			NSStringFromClass([self class]),
			self.partName,
			(unsigned long)self.quantity,
			(int)[self.color colorCode],
			self.isMissing ? @" missing" : @"",
			self.isSubmodel ? @" submodel" : @""];

}//end description


@end
