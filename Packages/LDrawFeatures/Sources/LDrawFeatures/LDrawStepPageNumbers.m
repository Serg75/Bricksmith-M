//==============================================================================
//
//  File:       LDrawStepPageNumbers.m
//  Package:    LDrawFeatures
//
//  Purpose:    Counts the pages of the instruction book, and keeps which
//              pages show each step.
//
//  Created by Sergey Slobodenyuk on 2026-10-18.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPageNumbers.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubCallout.h>

#import <LDrawFeatures/LDrawStepCallout.h>

#import "LDrawStepPartListInternal.h"


/// Put before the number of a page where the step is in a callout.
static NSString * const CALLOUT_MARK		= @"➟";

/// Put between the numbers of a step shown on more than one page.
static NSString * const PAGE_SEPARATOR		= @"/";


@implementation LDrawStepPageNumber

//========== initWithNumber:isInCallout: =======================================
- (instancetype) initWithNumber:(NSUInteger)number isInCallout:(BOOL)isInCallout
{
	self = [super init];
	if (self) {
		self->_number		= number;
		self->_isInCallout	= isInCallout;
	}
	return self;

}//end initWithNumber:isInCallout:

@end


// MARK: -

@implementation LDrawStepPageNumbers
{
	/// The pages of each step, in reading order.
	NSMapTable<LDrawStep *, NSMutableArray<LDrawStepPageNumber *> *>	*pagesOfSteps;
	NSHashTable<LDrawModel *>											*visitedModels;
	NSUInteger															 pageCount;
}

//---------- pageNumbersOfFile: --------------------------------------[static]--
+ (instancetype) pageNumbersOfFile:(nullable LDrawFile *)file
{
	return [[self alloc] initWithFile:file];

}//end pageNumbersOfFile:


//========== initWithFile: =====================================================
- (instancetype) initWithFile:(nullable LDrawFile *)file
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	self->_file			= file;
	self->pagesOfSteps	= [NSMapTable mapTableWithKeyOptions:NSMapTableWeakMemory | NSMapTableObjectPointerPersonality
											valueOptions:NSMapTableStrongMemory];
	self->visitedModels	= [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];

	LDrawMPDModel *main = [file firstModel];

	if (main != nil) {
		[self addPagesOfModel:main];

		// The finished model follows the last page that builds it.
		LDrawStep *lastStep = [[main steps] lastObject];

		if (lastStep != nil) {
			[self notePage:self->pageCount + 1 ofStep:lastStep isInCallout:NO];
		}
	}

	// Only needed while counting.
	self->visitedModels = nil;

	return self;

}//end initWithFile:


//========== addPagesOfModel: ==================================================
///
/// @abstract	Adds a page for each step of the model that places a part or a
/// 			hose, also inside a texture or a group, with a submodel's pages
/// 			before the step that first places it.
///
/// @discussion	A callout that shows a submodel's steps shows them each time,
/// 			and does not count as placing it. So the submodel still gets
/// 			pages where it is first placed outside a callout.
///
//==============================================================================
- (void) addPagesOfModel:(LDrawModel *)model
{
	[self->visitedModels addObject:model];

	for (LDrawStep *step in [model steps]) {
		BOOL								 placesSomething	= NO;
		BOOL								 inStepsCallout		= NO;
		NSMutableOrderedSet<LDrawModel *>	*calledOut			= [NSMutableOrderedSet orderedSet];

		for (LDrawDirective *directive in [LDrawStepPartList flattenedDirectives:[step subdirectives]]) {
			if ([directive isKindOfClass:[LPubCallout class]]) {
				LPubCallout *callout = (LPubCallout *)directive;

				if (callout.line == LPubCalloutLineBegin) {
					inStepsCallout = (callout.mode == LPubCalloutModeUnassembled);
				}
				else if (callout.line == LPubCalloutLineEnd) {
					inStepsCallout = NO;
				}
			}
			else if ([directive isKindOfClass:[LDrawLSynth class]]) {
				placesSomething = YES;
			}
			else if ([directive isKindOfClass:[LDrawPart class]]) {
				LDrawModel *submodel = [(LDrawPart *)directive referencedMPDSubmodel];

				if (submodel != nil && inStepsCallout) {
					[calledOut addObject:submodel];
				}
				else if (submodel != nil && [self->visitedModels containsObject:submodel] == NO) {
					[self addPagesOfModel:submodel];
				}
				placesSomething = YES;
			}
		}

		if (placesSomething) {
			self->pageCount += 1;
			[self notePage:self->pageCount ofStep:step isInCallout:NO];

			for (LDrawModel *submodel in calledOut) {
				[self noteCalloutPage:self->pageCount ofModel:submodel];
			}
		}
	}

}//end addPagesOfModel:


//========== noteCalloutPage:ofModel: ==========================================
///
/// @abstract	Notes a page whose callout shows the steps of a submodel: the
/// 			steps the box shows.
///
//==============================================================================
- (void) noteCalloutPage:(NSUInteger)page ofModel:(LDrawModel *)model
{
	for (LDrawStep *step in [model steps]) {
		if ([LDrawStepCallout stepBuildsSomething:step]) {
			[self notePage:page ofStep:step isInCallout:YES];
		}
	}

}//end noteCalloutPage:ofModel:


//========== notePage:ofStep:isInCallout: ======================================
- (void) notePage:(NSUInteger)page ofStep:(LDrawStep *)step isInCallout:(BOOL)isInCallout
{
	NSMutableArray<LDrawStepPageNumber *> *pages = [self->pagesOfSteps objectForKey:step];

	if (pages == nil) {
		pages = [NSMutableArray array];
		[self->pagesOfSteps setObject:pages forKey:step];
	}

	[pages addObject:[[LDrawStepPageNumber alloc] initWithNumber:page isInCallout:isInCallout]];

}//end notePage:ofStep:isInCallout:


// MARK: - QUESTIONS -


//========== pagesShowingStep: =================================================
- (NSArray<LDrawStepPageNumber *> *) pagesShowingStep:(nullable LDrawStep *)step
{
	return [[self->pagesOfSteps objectForKey:step] copy] ?: @[];

}//end pagesShowingStep:


//---------- textForPages: -------------------------------------------[static]--
+ (NSString *) textForPages:(NSArray<LDrawStepPageNumber *> *)pages
{
	NSMutableArray<NSString *> *numbers = [NSMutableArray arrayWithCapacity:pages.count];

	for (LDrawStepPageNumber *page in pages) {
		NSString *mark = page.isInCallout ? CALLOUT_MARK : @"";

		[numbers addObject:[NSString stringWithFormat:@"%@%lu", mark, (unsigned long)page.number]];
	}

	return [numbers componentsJoinedByString:PAGE_SEPARATOR];

}//end textForPages:

@end
