//==============================================================================
//
//  File:       LDrawStepCalloutMenuItem.m
//  Package:    LDrawStepEditing
//
//  Purpose:    What a host's menu offers for a point of the overlay.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepEditing/LDrawStepCalloutMenuItem.h>

#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>
#import <LDrawStepEditing/LDrawStepCalloutEdit.h>


@interface LDrawStepCalloutMenuItem ()

@property (nonatomic) BOOL										isSeparator;
@property (nonatomic, copy, nullable) NSString					*titleKey;
@property (nonatomic) NSInteger									 stepNumber;
@property (nonatomic, strong, nullable) LDrawStepCalloutEdit	*edit;

@end


@implementation LDrawStepCalloutMenuItem


//========== initPrivately =====================================================
- (instancetype) initPrivately
{
	return [super init];

}//end initPrivately


//---------- itemWithTitleKey:stepNumber:edit: -----------------------[static]--
///
/// @abstract	An item that applies an edit, or nil when the edit changes
///				nothing.
///
//------------------------------------------------------------------------------
+ (nullable instancetype) itemWithTitleKey:(NSString *)titleKey
								stepNumber:(NSInteger)stepNumber
									  edit:(nullable LDrawStepCalloutEdit *)edit
{
	if (edit == nil || edit.kind == LDrawStepCalloutEditKindNone) {
		return nil;
	}

	LDrawStepCalloutMenuItem *item = [[self alloc] initPrivately];

	item.titleKey	= titleKey;
	item.stepNumber	= stepNumber;
	item.edit		= edit;

	return item;

}//end itemWithTitleKey:stepNumber:edit:


//---------- separatorItem -------------------------------------------[static]--
+ (instancetype) separatorItem
{
	LDrawStepCalloutMenuItem *item = [[self alloc] initPrivately];

	item.isSeparator = YES;

	return item;

}//end separatorItem


//---------- itemsAtPoint:presentation:model: ------------------------[static]--
+ (NSArray<LDrawStepCalloutMenuItem *> *) itemsAtPoint:(Point2)point
										  presentation:(nullable LDrawStepPartListPresentation *)presentation
												 model:(nullable LDrawModel *)model
{
	LDrawStepCalloutBox *box = [presentation calloutBoxAtPoint:point];

	// A box may lie over the list, and it is the box that is on top.
	if (box != nil) {
		return [self itemsForBox:box atPoint:point onPage:presentation.isOnPage];
	}

	LDrawStepPartListEntry *entry = [presentation entryAtPoint:point];

	return (entry != nil) ? [self itemsForEntry:entry inModel:model] : @[];

}//end itemsAtPoint:presentation:model:


//---------- itemsForEntry:inModel: ----------------------------------[static]--
+ (NSArray<LDrawStepCalloutMenuItem *> *) itemsForEntry:(LDrawStepPartListEntry *)entry
												inModel:(nullable LDrawModel *)model
{
	LDrawStepCalloutMenuItem *item = [self itemWithTitleKey:@"StepCalloutAdd"
												 stepNumber:0
													   edit:[LDrawStepCalloutEdit editCallingOutEntry:entry
																							  inModel:model]];

	return (item != nil) ? @[item] : @[];

}//end itemsForEntry:inModel:


//---------- itemsForBox:atPoint:onPage: -----------------------------[static]--
+ (NSArray<LDrawStepCalloutMenuItem *> *) itemsForBox:(LDrawStepCalloutBox *)box
											  atPoint:(Point2)point
											   onPage:(BOOL)isOnPage
{
	NSMutableArray<LDrawStepCalloutMenuItem *>	*items	= [NSMutableArray array];
	LDrawStepCalloutMenuItem					*item	= [self dividerItemForStep:[box stepAtPoint:point]];

	if (item != nil) {
		[items addObject:item];
	}

	item = isOnPage ? [self arrangeItemForBox:box] : nil;

	if (item != nil) {
		[items addObject:item];
	}

	item = [self itemWithTitleKey:@"StepCalloutRemove"
					   stepNumber:0
							 edit:[LDrawStepCalloutEdit editRemovingCallout:box.callout]];

	if (item != nil) {
		if (items.count > 0) {
			[items addObject:[self separatorItem]];
		}
		[items addObject:item];
	}

	item = [self itemWithTitleKey:@"StepCalloutToParts"
					   stepNumber:0
							 edit:[LDrawStepCalloutEdit editExpandingCallout:box.callout]];

	if (item != nil) {
		[items addObject:item];
	}

	return items;

}//end itemsForBox:atPoint:onPage:


//---------- dividerItemForStep: -------------------------------------[static]--
///
/// @abstract	The item that puts a divider before a step of a callout's box,
///				or takes away the one it has. Nil for no step, and for the
///				first step of a submodel, which starts a column or row anyway.
///
//------------------------------------------------------------------------------
+ (nullable instancetype) dividerItemForStep:(nullable LDrawStepCalloutStep *)step
{
	if (step == nil || step.isFirstOfSubmodel) {
		return nil;
	}

	if (step.hasDividerBefore) {
		return [self itemWithTitleKey:@"StepCalloutDividerRemove"
						   stepNumber:step.number
								 edit:[LDrawStepCalloutEdit editRemovingDividerBeforeStep:step.step]];
	}

	return [self itemWithTitleKey:@"StepCalloutDividerAdd"
					   stepNumber:step.number
							 edit:[LDrawStepCalloutEdit editAddingDividerBeforeStep:step.step]];

}//end dividerItemForStep:


//---------- arrangeItemForBox: --------------------------------------[static]--
///
/// @abstract	The item that makes the steps of a callout's box run the other
///				way. Nil for a box that shows one picture, where nothing would
///				change.
///
//------------------------------------------------------------------------------
+ (nullable instancetype) arrangeItemForBox:(LDrawStepCalloutBox *)box
{
	NSUInteger shownCount = 0;

	for (LDrawStepCalloutPicture *picture in box.pictures) {
		if (picture.isPartsList == NO) {
			shownCount += 1;
		}
	}

	if (shownCount < 2) {
		return nil;
	}

	BOOL isVertical = box.callout.isVertical;

	return [self itemWithTitleKey:(isVertical ? @"StepCalloutStepsAcross" : @"StepCalloutStepsDown")
					   stepNumber:0
							 edit:[LDrawStepCalloutEdit editArrangingStepsOfCallout:box.callout
																		 vertically:(isVertical == NO)]];

}//end arrangeItemForBox:


//========== titleFromLocalizedText: ===========================================
- (NSString *) titleFromLocalizedText:(NSString *)text
{
	return (self.stepNumber > 0) ? [NSString stringWithFormat:text, (long)self.stepNumber] : text;

}//end titleFromLocalizedText:

@end
