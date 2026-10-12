//==============================================================================
//
//  File:       LDrawStepCalloutEdit.m
//  Package:    LDrawStepEditing
//
//  Purpose:    Decides what a dragged callout box writes to the document.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawStepEditing/LDrawStepCalloutEdit.h>

#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawCore/LPubCallout.h>
#import <LDrawCore/LPubCalloutAlloc.h>
#import <LDrawCore/LPubCalloutBackground.h>
#import <LDrawCore/LPubCalloutBorder.h>
#import <LDrawCore/LPubCalloutFont.h>
#import <LDrawCore/LPubCalloutMargins.h>
#import <LDrawCore/LPubCalloutPliPerStep.h>
#import <LDrawCore/LPubCalloutPointer.h>
#import <LDrawCore/LPubCalloutSeparator.h>
#import <LDrawCore/LPubCalloutSubmodelColor.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawCore/LPubPliIgnore.h>
#import <LDrawCore/LPubPliSubstitute.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>



/// Where along the box's side a new arrow leaves: the middle.
static const double NEW_POINTER_LOCATION = 0.5;


@interface LDrawStepCalloutEdit ()

@property (nonatomic, readwrite) LDrawStepCalloutEditKind	kind;
@property (nonatomic, readwrite, nullable) LPubCommand		*directiveToInsert;
@property (nonatomic, readwrite) NSUInteger					insertIndex;
@property (nonatomic, readwrite, nullable) LPubCommand		*existingDirective;
@property (nonatomic, readwrite, copy, nullable) NSString	*commandString;
@property (nonatomic, readwrite) NSArray<LDrawDirective *>	*directivesToRemove;
@property (nonatomic, readwrite) NSArray<LDrawDirective *>	*directivesToInsert;
@property (nonatomic, readwrite) NSArray<NSNumber *>		*insertIndexes;
@property (nonatomic, readwrite, nullable) LDrawStep		*targetStep;
@property (nonatomic, readwrite, copy) NSString				*undoActionKey;

@end


@implementation LDrawStepCalloutEdit

//---------- editWithUndoActionKey: ----------------------------------[static]--
///
/// @abstract	An edit that changes nothing yet.
///
//------------------------------------------------------------------------------
+ (instancetype) editWithUndoActionKey:(NSString *)undoActionKey
{
	LDrawStepCalloutEdit *edit = [[self alloc] initPrivately];

	edit.kind				= LDrawStepCalloutEditKindNone;
	edit.undoActionKey		= undoActionKey;
	edit.directivesToRemove	= @[];
	edit.directivesToInsert	= @[];
	edit.insertIndexes		= @[];

	return edit;

}//end editWithUndoActionKey:


//========== initPrivately =====================================================
- (instancetype) initPrivately
{
	return [super init];

}//end initPrivately


//========== applyToStep:host: =================================================
///
/// @abstract	Makes the change through a host.
///
/// @discussion	A divider's lines go into a step of the called-out submodel,
///				which the edit names. Every other edit is for the step the
///				callout is in.
///
//==============================================================================
- (BOOL) applyToStep:(nullable LDrawStep *)step host:(id<LDrawStepCalloutEditHost>)host
{
	LDrawStep *target = self.targetStep ?: step;

	switch (self.kind) {
		case LDrawStepCalloutEditKindNone:
			return NO;

		case LDrawStepCalloutEditKindInsert:
			if (target == nil || self.directiveToInsert == nil) {
				return NO;
			}
			[host addDirective:self.directiveToInsert toParent:target atIndex:self.insertIndex];
			return YES;

		case LDrawStepCalloutEditKindUpdate:
			if (self.existingDirective == nil || self.commandString == nil) {
				return NO;
			}

			// Before the text is set, so the host keeps the old line.
			[host preserveDirectiveState:self.existingDirective];
			[self.existingDirective setLPubCommandString:self.commandString];
			return YES;

		case LDrawStepCalloutEditKindRewrite:
			if (target == nil) {
				return NO;
			}

			for (LDrawDirective *directive in self.directivesToRemove) {
				[host deleteDirective:directive];
			}

			for (NSUInteger index = 0; index < self.directivesToInsert.count; index++) {
				[host addDirective:self.directivesToInsert[index]
						  toParent:target
						   atIndex:self.insertIndexes[index].integerValue];
			}
			return YES;
	}

	return NO;

}//end applyToStep:host:


//---------- editMovingBox:toOrigin:inStep: --------------------------[static]--
///
/// @abstract	The edit that leaves a callout's box with its corner at
/// 			`origin`.
///
/// @discussion	The callout's own PLACEMENT line gets the new offset. A callout
/// 			with no such line gets one that says what LPub3D assumes, plus
/// 			the offset, just before its END line.
///
//------------------------------------------------------------------------------
+ (instancetype) editMovingBox:(LDrawStepCalloutBox *)box
					  toOrigin:(Point2)origin
						inStep:(nullable LDrawStep *)step
{
	LDrawStepCalloutEdit	*edit	= [self editWithUndoActionKey:@"UndoStepCalloutMove"];
	Point2					 offset	= ZeroPoint2;

	if ([box getPlacementOffset:&offset forOrigin:origin] == NO) {
		return edit;
	}

	LPubPlacement *placement = box.callout.placement;

	if (placement != nil) {
		NSString *text = [placement commandStringWithOffset:offset];

		if ([text isEqualToString:placement.lPubCommandString] == NO) {
			edit.kind				= LDrawStepCalloutEditKindUpdate;
			edit.existingDirective	= placement;
			edit.commandString		= text;
		}
		return edit;
	}

	if (step == nil) {
		return edit;
	}

	LPubPlacement *line = [LPubPlacement new];

	line.lPubCommandString = [LPubPlacement defaultCalloutCommandStringWithOffset:offset];

	edit.kind				= LDrawStepCalloutEditKindInsert;
	edit.directiveToInsert	= line;
	edit.insertIndex		= [self indexBeforeEndOfCallout:box.callout inStep:step];

	return edit;

}//end editMovingBox:toOrigin:inStep:


//---------- indexBeforeEndOfCallout:inStep: -------------------------[static]--
///
/// @abstract	Where a new line of a callout goes in its step: just before the
/// 			END line.
///
/// @discussion	An END inside something else in the step is not found, and
/// 			neither is a missing one. The line then goes last.
///
//------------------------------------------------------------------------------
+ (NSUInteger) indexBeforeEndOfCallout:(LDrawStepCallout *)callout inStep:(LDrawStep *)step
{
	NSArray		*directives	= [step subdirectives];
	NSUInteger	 endIndex	= NSNotFound;

	if (callout.endDirective != nil) {
		endIndex = [directives indexOfObjectIdenticalTo:callout.endDirective];
	}

	return (endIndex != NSNotFound) ? endIndex : directives.count;

}//end indexBeforeEndOfCallout:inStep:


// MARK: - ADDING A CALLOUT -


//---------- editCallingOutEntry:inModel: ----------------------------[static]--
///
/// @abstract	The edit that calls out the submodel a row of the parts list
/// 			shows.
///
/// @discussion	The lines are written in the order LPub3D writes them: BEGIN,
/// 			the placements, an arrow for each, END. The box gets no
/// 			PLACEMENT line, so it starts where LPub3D puts one: to the right
/// 			of the assembly. The arrows leave its left side.
///
//------------------------------------------------------------------------------
+ (instancetype) editCallingOutEntry:(LDrawStepPartListEntry *)entry inModel:(nullable LDrawModel *)model
{
	LDrawStepCalloutEdit	*edit		= [self editWithUndoActionKey:@"UndoStepCalloutAdd"];
	LDrawStep				*step		= [model visibleStep];
	NSArray<LDrawPart *>	*placements	= [LDrawStepCallout placementsOfEntry:entry inStep:step];
	NSUInteger				 count		= placements.count;

	if (count == 0) {
		return edit;
	}

	NSArray<LDrawDirective *>	*directives		= [step subdirectives];
	NSUInteger					 firstIndex		= [directives indexOfObjectIdenticalTo:placements[0]];
	BOOL						 isTogether		= YES;

	for (NSUInteger index = 1; index < count; index++) {
		if ([directives indexOfObjectIdenticalTo:placements[index]] != firstIndex + index) {
			isTogether = NO;
		}
	}

	NSMutableArray<LDrawDirective *>	*removed	= [NSMutableArray array];
	NSMutableArray<LDrawDirective *>	*inserted	= [NSMutableArray array];
	NSMutableArray<NSNumber *>			*indexes	= [NSMutableArray array];
	NSUInteger							 next		= firstIndex;

	LPubCallout *begin = [LPubCallout new];

	begin.lPubCommandString = [NSString stringWithFormat:@"%@ %@", LPUB_CALLOUT, LPUB_CALLOUT_BEGIN];

	[inserted addObject:begin];
	[indexes addObject:@(next)];

	// Past BEGIN and the first placement, which stays where it is.
	next += 2;

	// The other placements follow the first, so nothing else is in the callout.
	for (NSUInteger index = 1; index < count; index++) {
		if (isTogether == NO) {
			[removed addObject:placements[index]];
			[inserted addObject:placements[index]];
			[indexes addObject:@(next)];
		}
		next += 1;
	}

	for (NSString *text in [self pointerTextsForPlacements:placements inModel:model]) {
		LPubCalloutPointer *pointer = [LPubCalloutPointer new];

		pointer.lPubCommandString = text;

		[inserted addObject:pointer];
		[indexes addObject:@(next)];
		next += 1;
	}

	LPubCallout *end = [LPubCallout new];

	end.lPubCommandString = [NSString stringWithFormat:@"%@ %@", LPUB_CALLOUT, LPUB_CALLOUT_END];

	[inserted addObject:end];
	[indexes addObject:@(next)];

	edit.kind				= LDrawStepCalloutEditKindRewrite;
	edit.directivesToRemove	= removed;
	edit.directivesToInsert	= inserted;
	edit.insertIndexes		= indexes;

	return edit;

}//end editCallingOutEntry:inModel:


//---------- pointerTextsForPlacements:inModel: ----------------------[static]--
///
/// @abstract	The text of an arrow to the middle of each placement.
///
/// @discussion	The tips are measured on the step's assembly as its own angle
/// 			shows it, so they do not depend on how a view is turned. LPub3D
/// 			draws the assembly a little differently, so they are close, not
/// 			exact.
///
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *) pointerTextsForPlacements:(NSArray<LDrawPart *> *)placements
											inModel:(nullable LDrawModel *)model
{
	NSMutableArray<NSString *>	*texts		= [NSMutableArray arrayWithCapacity:placements.count];
	NSData						*outline	= [LDrawStepPartListPolicy assemblyOutlinePointsInModel:model];
	NSUInteger					 stepIndex	= [model maximumStepIndexForStepDisplay];
	Tuple3						 angle		= [model rotationAngleForStepAtIndex:stepIndex];
	Matrix4						 view		= [LDrawStepPartListLayout viewTransformForAngle:angle];

	for (LDrawPart *part in placements) {
		Point3		 middle	= [LDrawStepCalloutBox middleOfPlacement:part];
		Point2		 tip	= [self tipForModelPoint:middle inOutline:outline view:view];
		NSString	*text	= [LPubCalloutPointer commandStringWithPosition:LPubPlacementPositionLeft
																   location:NEW_POINTER_LOCATION
																		tip:tip];

		[texts addObject:text];
	}

	return texts;

}//end pointerTextsForPlacements:inModel:


//---------- tipForModelPoint:inOutline:view: ------------------------[static]--
///
/// @abstract	Where an arrow to a model point points, as a share of the box
/// 			around the outline points, from its top left.
///
/// @discussion	LDraw's y axis runs down, like a page's, so no axis is turned
/// 			over.
///
//------------------------------------------------------------------------------
+ (Point2) tipForModelPoint:(Point3)point inOutline:(nullable NSData *)outlinePoints view:(Matrix4)view
{
	const Point3	*points	= outlinePoints.bytes;
	NSUInteger		 count	= outlinePoints.length / sizeof(Point3);
	Box3			 box	= InvalidBox;

	for (NSUInteger index = 0; index < count; index++) {
		box = V3UnionBoxAndPoint(box, V3MulPointByProjMatrix(points[index], view));
	}

	double width	= box.max.x - box.min.x;
	double height	= box.max.y - box.min.y;

	if (count == 0 || width <= 0.0 || height <= 0.0) {
		return V2Make(0.5, 0.5);
	}

	Point3 seen = V3MulPointByProjMatrix(point, view);

	return V2Make(MIN(MAX((seen.x - box.min.x) / width, 0.0), 1.0),
				  MIN(MAX((seen.y - box.min.y) / height, 0.0), 1.0));

}//end tipForModelPoint:inOutline:view:


// MARK: - REMOVING A CALLOUT -


//---------- editRemovingCallout: ------------------------------------[static]--
///
/// @abstract	The edit that removes a callout and leaves its parts.
///
//------------------------------------------------------------------------------
+ (instancetype) editRemovingCallout:(LDrawStepCallout *)callout
{
	LDrawStepCalloutEdit				*edit		= [self editWithUndoActionKey:@"UndoStepCalloutRemove"];
	NSMutableArray<LDrawDirective *>	*removed	= [NSMutableArray arrayWithObject:callout.beginDirective];

	for (LDrawDirective *line in callout.ownLines) {
		if ([self isOwnLineOfOneCallout:line]) {
			[removed addObject:line];
		}
	}

	if (callout.endDirective != nil) {
		[removed addObject:callout.endDirective];
	}

	edit.kind				= LDrawStepCalloutEditKindRewrite;
	edit.directivesToRemove	= removed;

	return edit;

}//end editRemovingCallout:


//---------- isOwnLineOfOneCallout: ----------------------------------[static]--
///
/// @abstract	Whether a line between a callout's two lines holds for that
/// 			callout alone, so it goes when the callout goes.
///
/// @discussion	An arrow and a PLACEMENT do. A styling line does when it says
/// 			LOCAL. Without LOCAL it carries to the callouts after it, and
/// 			taking it out would change them. A line that is not a CALLOUT
/// 			line is not the callout's at all.
///
//------------------------------------------------------------------------------
+ (BOOL) isOwnLineOfOneCallout:(LDrawDirective *)line
{
	if ([line isKindOfClass:[LPubCalloutPointer class]]) {
		return YES;
	}

	if ([line isKindOfClass:[LPubPlacement class]]) {
		return ((LPubPlacement *)line).branch == LPubPlacementBranchCallout;
	}

	for (Class styleClass in @[[LPubCalloutAlloc class], [LPubCalloutPliPerStep class], [LPubCalloutBorder class],
							   [LPubCalloutBackground class], [LPubCalloutSubmodelColor class],
							   [LPubCalloutMargins class], [LPubCalloutSeparator class], [LPubCalloutFont class]]) {
		if ([line isKindOfClass:styleClass]) {
			return [(id)line scope] == LPubMetaScopeLocal;
		}
	}

	// A CALLOUT line Bricksmith does not read: how an arrow is drawn belongs
	// to the callout, and so does anything LOCAL.
	if ([line isMemberOfClass:[LPubCommand class]]) {
		NSArray<NSString *> *words = [(LPubCommand *)line lPubCommandWords];

		if (words.count < 2 || [words[0] isEqualToString:LPUB_CALLOUT] == NO) {
			return NO;
		}

		return [words[1] containsString:LPUB_CALLOUT_POINTER] || [words containsObject:LPUB_SCOPE_LOCAL];
	}

	return NO;

}//end isOwnLineOfOneCallout:


// MARK: - THE WAY THE STEPS RUN -


//---------- editArrangingStepsOfCallout:vertically: -----------------[static]--
///
/// @abstract	The edit that makes the steps in a callout's box run down, or
/// 			across, for that callout alone.
///
/// @discussion	The last ALLOC line between the callout's two lines says which
/// 			way they run. When that is a LOCAL line it is this edit's own
/// 			kind of line, and is changed or taken out. Any other line is
/// 			left alone, since later steps may go by it, and a LOCAL line is
/// 			put after it, just before END.
///
/// 			A LOCAL line also ends the ALLOC lines after it with the step.
/// 			So where later steps go by a line further down the step, the
/// 			line written has no LOCAL, and that later line carries on in
/// 			place of it. Such a line is this edit's own kind as well.
///
//------------------------------------------------------------------------------
+ (instancetype) editArrangingStepsOfCallout:(LDrawStepCallout *)callout vertically:(BOOL)isVertical
{
	LDrawStepCalloutEdit *edit = [self editWithUndoActionKey:@"UndoStepCalloutAlloc"];

	if (callout.isVertical == isVertical) {
		return edit;
	}

	NSString			*direction	= isVertical ? LPUB_CALLOUT_VERTICAL : LPUB_CALLOUT_HORIZONTAL;
	NSString			*localText	= [NSString stringWithFormat:@"%@ %@ %@ %@",
									   LPUB_CALLOUT, LPUB_CALLOUT_ALLOC, LPUB_SCOPE_LOCAL, direction];
	NSString			*plainText	= [NSString stringWithFormat:@"%@ %@ %@",
									   LPUB_CALLOUT, LPUB_CALLOUT_ALLOC, direction];
	LPubCalloutAlloc	*own		= nil;

	for (LDrawDirective *line in callout.ownLines) {
		if ([line isKindOfClass:[LPubCalloutAlloc class]]) {
			own = (LPubCalloutAlloc *)line;
		}
	}

	LDrawStep	*step		= callout.step;
	NSUInteger	 ownIndex	= NSNotFound;
	BOOL		 isLocal	= (own != nil && own.scope == LPubMetaScopeLocal);

	if (own != nil && step != nil) {
		ownIndex = [[step subdirectives] indexOfObjectIdenticalTo:own];
	}

	// A line with no LOCAL is the callout's own too, when a later line of the
	// step carries on in place of it: no later step goes by it then.
	BOOL isReplaced = (ownIndex != NSNotFound
					   && [self allocCarriesOnFromIndex:ownIndex + 1 inStep:step without:nil]);

	if (isLocal || isReplaced) {
		// What the callout goes by with that line gone.
		LPubCalloutAlloc *other = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
			return [directive isKindOfClass:[LPubCalloutAlloc class]] && directive != own;
		}];
		BOOL isVerticalWithout = (other == nil) ? YES : other.isVertical;

		// With a LOCAL line gone, a line after it in the step would carry on
		// again. So such a line is changed, not taken out.
		BOOL freesLaterLine = (isLocal && ownIndex != NSNotFound
							   && [self allocCarriesOnFromIndex:ownIndex + 1 inStep:step without:own]);

		if (isVerticalWithout == isVertical && freesLaterLine == NO) {
			edit.kind				= LDrawStepCalloutEditKindRewrite;
			edit.directivesToRemove	= @[own];
		}
		else {
			edit.kind				= LDrawStepCalloutEditKindUpdate;
			edit.existingDirective	= own;
			edit.commandString		= isLocal ? localText : plainText;
		}
		return edit;
	}

	if (step == nil) {
		return edit;
	}

	NSUInteger			 insertIndex	= [self indexBeforeEndOfCallout:callout inStep:step];
	BOOL				 isFollowed		= [self allocCarriesOnFromIndex:insertIndex inStep:step without:nil];
	LPubCalloutAlloc	*line			= [LPubCalloutAlloc new];

	// A LOCAL line would end the line that follows with the step.
	line.lPubCommandString = isFollowed ? plainText : localText;

	edit.kind				= LDrawStepCalloutEditKindInsert;
	edit.directiveToInsert	= line;
	edit.insertIndex		= insertIndex;

	return edit;

}//end editArrangingStepsOfCallout:vertically:


//---------- allocCarriesOnFromIndex:inStep:without: -----------------[static]--
///
/// @abstract	Whether later steps go by an ALLOC line at or after an index of
/// 			the step, with `removed` taken out of the step.
///
/// @discussion	Such a line has no LOCAL, and no ALLOC line before it in the
/// 			step has one. LPub3D drops a LOCAL line at the end of its step,
/// 			and with it every line of its kind that follows it there.
///
//------------------------------------------------------------------------------
+ (BOOL) allocCarriesOnFromIndex:(NSUInteger)index
						  inStep:(LDrawStep *)step
						 without:(nullable LDrawDirective *)removed
{
	NSArray<LDrawDirective *> *directives = [step subdirectives];

	for (NSUInteger current = 0; current < directives.count; current++) {
		LDrawDirective *directive = directives[current];

		if (directive == removed || [directive isKindOfClass:[LPubCalloutAlloc class]] == NO) {
			continue;
		}

		if (((LPubCalloutAlloc *)directive).scope == LPubMetaScopeLocal) {
			return NO;
		}

		if (current >= index) {
			return YES;
		}
	}

	return NO;

}//end allocCarriesOnFromIndex:inStep:without:


// MARK: - DIVIDERS -


//---------- editAddingDividerBeforeStep: ----------------------------[static]--
///
/// @abstract	The edit that makes a step of a called-out submodel start a
/// 			column or row.
///
/// @discussion	The line goes first in the step, right after the STEP line that
/// 			ends the step before, which is where LPub3D writes it.
///
//------------------------------------------------------------------------------
+ (instancetype) editAddingDividerBeforeStep:(LDrawStep *)step
{
	LDrawStepCalloutEdit *edit = [self editWithUndoActionKey:@"UndoStepCalloutDividerAdd"];

	if ([LDrawStepCallout stepBuildsSomething:step] == NO
		|| [LDrawStepCallout stepShownBeforeStep:step] == nil
		|| [LDrawStepCallout dividerLinesBeforeStep:step].count > 0) {
		return edit;
	}

	LPubCallout *divider = [LPubCallout new];

	divider.lPubCommandString = [NSString stringWithFormat:@"%@ %@", LPUB_CALLOUT, LPUB_CALLOUT_DIVIDER];

	edit.kind				= LDrawStepCalloutEditKindRewrite;
	edit.directivesToInsert	= @[divider];
	edit.insertIndexes		= @[@0];
	edit.targetStep			= step;

	return edit;

}//end editAddingDividerBeforeStep:


//---------- editRemovingDividerBeforeStep: --------------------------[static]--
///
/// @abstract	The edit that takes out the lines that put a divider before a
/// 			step.
///
//------------------------------------------------------------------------------
+ (instancetype) editRemovingDividerBeforeStep:(LDrawStep *)step
{
	LDrawStepCalloutEdit		*edit	= [self editWithUndoActionKey:@"UndoStepCalloutDividerRemove"];
	NSArray<LDrawDirective *>	*lines	= [LDrawStepCallout dividerLinesBeforeStep:step];

	if (lines.count == 0) {
		return edit;
	}

	edit.kind				= LDrawStepCalloutEditKindRewrite;
	edit.directivesToRemove	= lines;
	edit.targetStep			= step;

	return edit;

}//end editRemovingDividerBeforeStep:


@end
