//==============================================================================
//
//  File:       LDrawStepAssemblyEdit.m
//  Package:    LDrawStepEditing
//
//  Purpose:    Decides what a change to the visible step's assembly writes:
//              its size, its place on the page, or its angle.
//
//              Each value has a kind of line. A step's own lines are its
//              lines of that kind from the first LOCAL one on: LPub3D keeps
//              them for the step alone. The lines before that carry on to
//              later steps.
//
//  Created by Sergey Slobodenyuk on 2026-10-20.
//
//==============================================================================

#import <LDrawStepEditing/LDrawStepAssemblyEdit.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/LPubModelScale.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawCore/LPubPliCameraAngles.h>

#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>


/// Scales and offsets closer than this are the same: both are written with
/// four decimals.
static const double VALUE_EPSILON	= 0.00005;

/// Views closer than this, element by element, are the same.
static const double VIEW_EPSILON	= 0.001;


typedef BOOL (^LDrawStepLineMatcher)(LDrawDirective *directive);


//------------------------------------------------------------------------------
///
/// @enum       LDrawStepAssemblyChangeKind
///
/// @abstract   One kind of change an edit makes, in the order they are made.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepAssemblyChangeKind) {
	LDrawStepAssemblyChangeRemove	= 0,
	LDrawStepAssemblyChangeUpdate	= 1,
	LDrawStepAssemblyChangeInsert	= 2,
	LDrawStepAssemblyChangeRotate	= 3
};


//------------------------------------------------------------------------------
///
/// @class      LDrawStepAssemblyChange
///
/// @abstract   One change: a line out, a line's new text, a line in after the
///             step's last line of its kind, or a step's ROTSTEP.
///
//------------------------------------------------------------------------------
@interface LDrawStepAssemblyChange : NSObject

@property (nonatomic) LDrawStepAssemblyChangeKind			kind;
@property (nonatomic, nullable) LDrawDirective				*directive;
@property (nonatomic, copy, nullable) NSString				*text;
@property (nonatomic, nullable) LDrawStep					*step;
@property (nonatomic, copy, nullable) LDrawStepLineMatcher	matcher;
@property (nonatomic) LDrawStepRotationT					rotationType;
@property (nonatomic) Tuple3								rotationAngle;

@end

@implementation LDrawStepAssemblyChange
@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepAssemblyValue
///
/// @abstract   A value to write, and the kind of line that holds it.
///
//------------------------------------------------------------------------------
@interface LDrawStepAssemblyValue : NSObject

/// Whether a directive is a line of this kind.
@property (nonatomic, copy) LDrawStepLineMatcher matches;

/// Whether a line, or no line for nil, gives the value.
@property (nonatomic, copy) BOOL (^isGivenBy)(LDrawDirective * _Nullable line);

/// The text of a line that gives the value in a scope.
@property (nonatomic, copy) NSString * (^textForScope)(LPubMetaScope scope);

/// The class a new line is made of.
@property (nonatomic) Class lineClass;

@end

@implementation LDrawStepAssemblyValue
@end


//========== ScopeOfLine() =====================================================
static LPubMetaScope ScopeOfLine(LDrawDirective *line)
{
	if ([line respondsToSelector:@selector(scope)]) {
		return [(id)line scope];
	}

	return LPubMetaScopeUnspecified;

}//end ScopeOfLine


//========== ScopeWord() =======================================================
///
/// @abstract	The scope keyword with a space before it, or nothing.
///
//==============================================================================
static NSString *ScopeWord(LPubMetaScope scope)
{
	switch (scope) {
		case LPubMetaScopeGlobal:		return [@" " stringByAppendingString:LPUB_SCOPE_GLOBAL];
		case LPubMetaScopeLocal:		return [@" " stringByAppendingString:LPUB_SCOPE_LOCAL];
		case LPubMetaScopeUnspecified:	return @"";
	}

	return @"";

}//end ScopeWord


//========== TextWithScope() ===================================================
///
/// @abstract	A line's text with its scope keyword, the third word, set.
///
//==============================================================================
static NSString *TextWithScope(NSString *text, LPubMetaScope scope)
{
	NSMutableArray<NSString *> *words = [NSMutableArray array];

	for (NSString *word in [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
		if (word.length > 0) {
			[words addObject:word];
		}
	}

	if (words.count < 2) {
		return text;
	}

	BOOL hasScope = words.count > 2
				 && ([words[2] isEqualToString:LPUB_SCOPE_GLOBAL] || [words[2] isEqualToString:LPUB_SCOPE_LOCAL]);

	if (hasScope) {
		[words removeObjectAtIndex:2];
	}

	if (scope == LPubMetaScopeGlobal) {
		[words insertObject:LPUB_SCOPE_GLOBAL atIndex:2];
	}
	else if (scope == LPubMetaScopeLocal) {
		[words insertObject:LPUB_SCOPE_LOCAL atIndex:2];
	}

	return [words componentsJoinedByString:@" "];

}//end TextWithScope


//========== LinesInStep() =====================================================
static NSArray<LDrawDirective *> *LinesInStep(LDrawStep *step, LDrawStepLineMatcher matches)
{
	NSMutableArray<LDrawDirective *> *lines = [NSMutableArray array];

	for (LDrawDirective *directive in [step subdirectives]) {
		if (matches(directive)) {
			[lines addObject:directive];
		}
	}

	return lines;

}//end LinesInStep


//========== IndexOfFirstOwnLine() =============================================
///
/// @abstract	Where the step's own lines start among its lines of a kind: at
/// 			the first LOCAL one. The count when there is none.
///
//==============================================================================
static NSUInteger IndexOfFirstOwnLine(NSArray<LDrawDirective *> *lines)
{
	for (NSUInteger index = 0; index < lines.count; index++) {
		if (ScopeOfLine(lines[index]) == LPubMetaScopeLocal) {
			return index;
		}
	}

	return lines.count;

}//end IndexOfFirstOwnLine


//========== OwnLinesInStep() ==================================================
///
/// @abstract	The step's own lines of a kind: from the first LOCAL one on.
///
//==============================================================================
static NSArray<LDrawDirective *> *OwnLinesInStep(LDrawStep *step, LDrawStepLineMatcher matches)
{
	NSArray<LDrawDirective *>	*lines	= LinesInStep(step, matches);
	NSUInteger					 first	= IndexOfFirstOwnLine(lines);

	return [lines subarrayWithRange:NSMakeRange(first, lines.count - first)];

}//end OwnLinesInStep


//========== CarriedLinesInStep() ==============================================
///
/// @abstract	The step's lines of a kind that carry on to later steps: those
/// 			before the first LOCAL one.
///
//==============================================================================
static NSArray<LDrawDirective *> *CarriedLinesInStep(LDrawStep *step, LDrawStepLineMatcher matches)
{
	NSArray<LDrawDirective *> *lines = LinesInStep(step, matches);

	return [lines subarrayWithRange:NSMakeRange(0, IndexOfFirstOwnLine(lines))];

}//end CarriedLinesInStep


//========== LineInForce() =====================================================
///
/// @abstract	The line of a kind in force for a step, reading the lines in
/// 			`excluded` as if they were not there.
///
//==============================================================================
static LDrawDirective *LineInForce(LDrawStep *step, LDrawStepLineMatcher matches, NSArray *excluded)
{
	return [LDrawStepPartListPolicy directiveInForceForStep:step
												  excluding:nil
												   matching:^BOOL(LDrawDirective *directive) {
		return matches(directive) && (excluded == nil || [excluded indexOfObjectIdenticalTo:directive] == NSNotFound);
	}];

}//end LineInForce


//========== IndexAfterLastLine() ==============================================
///
/// @abstract	Just after the step's last line of a kind, or 0 when it has
/// 			none. A line put there is not overridden by one of its kind.
///
//==============================================================================
static NSUInteger IndexAfterLastLine(LDrawStep *step, LDrawStepLineMatcher matches)
{
	NSArray		*directives	= [step subdirectives];
	NSUInteger	 index		= 0;

	for (NSUInteger counter = 0; counter < directives.count; counter++) {
		if (matches(directives[counter])) {
			index = counter + 1;
		}
	}

	return index;

}//end IndexAfterLastLine


//========== HeaderStep() ======================================================
///
/// @abstract	The step a GLOBAL line goes into: the first step of the file's
/// 			first model.
///
//==============================================================================
static LDrawStep *HeaderStep(LDrawModel *model)
{
	LDrawFile	*file	= [model enclosingFile];
	LDrawModel	*first	= (file != nil) ? [file firstModel] : model;

	return [[first steps] firstObject];

}//end HeaderStep


//========== IsAssemblyCameraLine() ============================================
static BOOL IsAssemblyCameraLine(LDrawDirective *directive)
{
	return [directive isKindOfClass:[LPubPliCameraAngles class]]
		&& ((LPubPliCameraAngles *)directive).branch == LPubCameraAnglesBranchAssembly;

}//end IsAssemblyCameraLine


//========== OwnCameraLines() ==================================================
///
/// @abstract	The step's own ASSEM CAMERA_ANGLES lines.
///
//==============================================================================
static NSArray<LDrawDirective *> *OwnCameraLines(LDrawStep *step)
{
	return OwnLinesInStep(step, ^BOOL(LDrawDirective *directive) {
		return IsAssemblyCameraLine(directive);
	});

}//end OwnCameraLines


//========== StepWithRotationInForce() =========================================
///
/// @abstract	The last step at or before `index` with a ROTSTEP, or nil when
///				no rotation is in force. `index` is a step of the model.
///
//==============================================================================
static LDrawStep *StepWithRotationInForce(NSArray<LDrawStep *> *steps, NSUInteger index)
{
	for (NSInteger counter = (NSInteger)index; counter >= 0; counter--) {
		if ([steps[counter] stepRotationType] != LDrawStepRotationNone) {
			return steps[counter];
		}
	}

	return nil;

}//end StepWithRotationInForce


//========== InheritedCamera() =================================================
///
/// @abstract	The view LPub3D's camera puts after a step's rotation, without
/// 			the step's own camera lines, `ownCamera`.
///
//==============================================================================
static Matrix4 InheritedCamera(LDrawModel *model, NSUInteger index, NSArray *ownCamera)
{
	LPubPliCameraAngles *camera = [LDrawStepPartListPolicy assemblyCameraAnglesForStepAtIndex:index
																					   inModel:model
																					 excluding:ownCamera];

	return [LDrawStepPartListPolicy assemblyCameraForAngles:camera];

}//end InheritedCamera


//========== InheritedView() ===================================================
///
/// @abstract	The view LPub3D draws a step at without its own camera lines,
/// 			`ownCamera`. Without its own ROTSTEP too, when `keepsRotation` is
/// 			NO: then the rotation is the one held before the step.
///
//==============================================================================
static Matrix4 InheritedView(LDrawModel *model, NSUInteger index, NSArray *ownCamera, BOOL keepsRotation)
{
	LPubPliCameraAngles	*camera		= [LDrawStepPartListPolicy assemblyCameraAnglesForStepAtIndex:index
																						  inModel:model
																						excluding:ownCamera];
	Matrix4				 rotation	= IdentityMatrix4;
	BOOL				 isAbsolute	= NO;

	// Before the first step nothing is turned.
	if (keepsRotation || index > 0) {
		NSUInteger rotationIndex = keepsRotation ? index : index - 1;

		rotation	= [LDrawStepPartListPolicy assemblyRotationForStepAtIndex:rotationIndex inModel:model];
		isAbsolute	= [LDrawStepPartListPolicy isAbsoluteRotationAtStepIndex:rotationIndex inModel:model];
	}

	return [LDrawStepPartListPolicy assemblyViewWithRotation:rotation camera:camera isAbsolute:isAbsolute];

}//end InheritedView


//========== InheritedViewingAngle() ===========================================
///
/// @abstract	The angle the visible step is seen at without its own camera
/// 			lines, and without its own ROTSTEP when `keepsRotation` is NO.
///
//==============================================================================
static Tuple3 InheritedViewingAngle(LDrawModel *model, BOOL keepsRotation)
{
	LDrawStep	*step	= [model visibleStep];
	NSUInteger	 index	= [[model steps] indexOfObjectIdenticalTo:step];

	if (step == nil) {
		return ZeroPoint3;
	}

	NSArray<LDrawDirective *> *own = OwnCameraLines(step);

	return [LDrawStepPartListPolicy viewingAngleForView:InheritedView(model, index, own, keepsRotation)];

}//end InheritedViewingAngle


//========== IsListPlacementLine() =============================================
static BOOL IsListPlacementLine(LDrawDirective *directive)
{
	return [directive isKindOfClass:[LPubPlacement class]]
		&& ((LPubPlacement *)directive).branch == LPubPlacementBranchPartsList;

}//end IsListPlacementLine


//========== PlacementOnPage() =================================================
///
/// @abstract	The line, when it places the assembly inside the page. Bricksmith
/// 			reads any other placement of the assembly as none.
///
//==============================================================================
static LPubPlacement *PlacementOnPage(LDrawDirective *line)
{
	LPubPlacement *placement = (LPubPlacement *)line;

	return placement.isInsidePage ? placement : nil;

}//end PlacementOnPage


//========== PlacesAlike() =====================================================
///
/// @abstract	Whether two placements on the page put the step at the same
/// 			place before their offsets. No line is the middle of the page.
///
//==============================================================================
static BOOL PlacesAlike(LPubPlacement *first, LPubPlacement *second)
{
	if (first == nil || second == nil) {
		LPubPlacement *other = first ?: second;

		return other == nil
			|| (other.position == LPubPlacementPositionCenter && other.justification == LPubPlacementPositionCenter);
	}

	return first.position == second.position && first.justification == second.justification;

}//end PlacesAlike


@interface LDrawStepAssemblyEdit ()

@property (nonatomic) NSMutableArray<LDrawStepAssemblyChange *>	*changes;
@property (nonatomic, readwrite, copy) NSString					*undoActionKey;

@end


@implementation LDrawStepAssemblyEdit

//---------- editWithUndoActionKey: ----------------------------------[static]--
///
/// @abstract	An edit that changes nothing yet.
///
//------------------------------------------------------------------------------
+ (instancetype) editWithUndoActionKey:(NSString *)undoActionKey
{
	LDrawStepAssemblyEdit *edit = [[self alloc] initPrivately];

	edit.changes		= [NSMutableArray array];
	edit.undoActionKey	= undoActionKey;

	return edit;

}//end editWithUndoActionKey:


//========== initPrivately =====================================================
- (instancetype) initPrivately
{
	return [super init];

}//end initPrivately


//========== isEmpty ===========================================================
- (BOOL) isEmpty
{
	return self.changes.count == 0;

}//end isEmpty


// MARK: - APPLYING -


//========== applyWithHost: ====================================================
///
/// @abstract	Makes the change through a host.
///
/// @discussion	Lines go out first, so a line put in finds its place among the
/// 			lines that stay.
///
//==============================================================================
- (BOOL) applyWithHost:(id<LDrawStepCalloutEditHost>)host
{
	if (self.isEmpty) {
		return NO;
	}

	for (NSInteger kind = LDrawStepAssemblyChangeRemove; kind <= LDrawStepAssemblyChangeRotate; kind++) {
		for (LDrawStepAssemblyChange *change in self.changes) {
			if (change.kind == kind) {
				[self applyChange:change withHost:host];
			}
		}
	}

	return YES;

}//end applyWithHost:


//========== applyChange:withHost: =============================================
- (void) applyChange:(LDrawStepAssemblyChange *)change withHost:(id<LDrawStepCalloutEditHost>)host
{
	switch (change.kind) {
		case LDrawStepAssemblyChangeRemove:
			if ([change.directive enclosingDirective] != nil) {
				[host deleteDirective:change.directive];
			}
			break;

		case LDrawStepAssemblyChangeUpdate:
			// Before the text is set, so the host keeps the old line. After it
			// the line says it changed, which a new text does not do.
			[host preserveDirectiveState:change.directive];
			[(LPubCommand *)change.directive setLPubCommandString:change.text];
			[change.directive noteNeedsDisplay];
			break;

		case LDrawStepAssemblyChangeInsert:
			[host addDirective:change.directive
					  toParent:change.step
					   atIndex:IndexAfterLastLine(change.step, change.matcher)];
			break;

		case LDrawStepAssemblyChangeRotate:
			// Before the setters, so the host keeps the old rotation.
			[host preserveDirectiveState:change.step];
			[change.step setStepRotationType:change.rotationType];
			[change.step setRotationAngle:change.rotationAngle];
			break;
	}

}//end applyChange:withHost:


// MARK: - SIZE AND PLACE -


//---------- editSettingScale:scope:inModel: -------------------------[static]--
+ (instancetype) editSettingScale:(double)scale
							scope:(LDrawStepAssemblyScope)scope
						  inModel:(nullable LDrawModel *)model
{
	LDrawStepAssemblyEdit *edit = [self editWithUndoActionKey:@"UndoStepAssemblyScale"];

	[edit setValue:[self scaleValue:scale] scope:scope inModel:model];

	return edit;

}//end editSettingScale:scope:inModel:


//---------- editSettingOffset:scope:inModel: ------------------------[static]--
///
/// @abstract	The edit that moves the step by `offset` on the page.
///
/// @discussion	The line keeps the words of the placement in force, so only the
/// 			offset changes, as LPub3D writes a dragged assembly. With none,
/// 			the step is centered on the page.
///
//------------------------------------------------------------------------------
+ (instancetype) editSettingOffset:(Point2)offset
							 scope:(LDrawStepAssemblyScope)scope
						   inModel:(nullable LDrawModel *)model
{
	LDrawStepAssemblyEdit	*edit		= [self editWithUndoActionKey:@"UndoStepAssemblyMove"];
	LPubPlacement			*current	= PlacementOnPage([LDrawStepPartListPolicy
														   assemblyPlacementForVisibleStepOfModel:model]);

	[edit setValue:[self offsetValue:offset placedLike:current] scope:scope inModel:model];

	return edit;

}//end editSettingOffset:scope:inModel:


//---------- scaleValue: ---------------------------------------------[static]--
+ (LDrawStepAssemblyValue *) scaleValue:(double)scale
{
	LDrawStepAssemblyValue *value = [LDrawStepAssemblyValue new];

	value.lineClass	= [LPubModelScale class];
	value.matches	= ^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubModelScale class]]
			&& ((LPubModelScale *)directive).branch == LPubModelScaleBranchAssembly;
	};

	// With no line LPub3D draws life size.
	value.isGivenBy = ^BOOL(LDrawDirective *line) {
		double given = (line != nil) ? ((LPubModelScale *)line).scale : 1.0;

		return fabs(given - scale) < VALUE_EPSILON;
	};

	value.textForScope = ^NSString *(LPubMetaScope scope) {
		return [NSString stringWithFormat:@"%@ %@%@ %.4f", LPUB_ASSEM, LPUB_MODEL_SCALE, ScopeWord(scope), scale];
	};

	return value;

}//end scaleValue:


//---------- offsetValue:placedLike: ---------------------------------[static]--
///
/// @abstract	An offset, in a line that places the step as `current` does.
///
/// @discussion	A line gives the value only when it places the step the same
/// 			way, so taking a line out never moves the step somewhere else.
///
//------------------------------------------------------------------------------
+ (LDrawStepAssemblyValue *) offsetValue:(Point2)offset placedLike:(nullable LPubPlacement *)current
{
	LDrawStepAssemblyValue *value = [LDrawStepAssemblyValue new];

	value.lineClass	= [LPubPlacement class];
	value.matches	= ^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPlacement class]]
			&& ((LPubPlacement *)directive).branch == LPubPlacementBranchAssembly;
	};

	value.isGivenBy = ^BOOL(LDrawDirective *line) {
		LPubPlacement	*placement	= PlacementOnPage(line);
		Point2			 given		= (placement != nil) ? placement.offset : ZeroPoint2;

		if (fabs(given.x - offset.x) >= VALUE_EPSILON || fabs(given.y - offset.y) >= VALUE_EPSILON) {
			return NO;
		}

		return PlacesAlike(placement, current);
	};

	value.textForScope = ^NSString *(LPubMetaScope scope) {
		if (current != nil) {
			return TextWithScope([current commandStringWithOffset:offset], scope);
		}

		return [NSString stringWithFormat:@"%@ %@%@ %@ %@ %@ %.4f %.4f", LPUB_ASSEM, LPUB_PLACEMENT, ScopeWord(scope),
				[LPubPlacement nameForPosition:LPubPlacementPositionCenter], LPUB_PAGE, LPUB_PLACEMENT_INSIDE,
				offset.x, offset.y];
	};

	return value;

}//end offsetValue:placedLike:


//========== setValue:scope:inModel: ===========================================
///
/// @abstract	Adds the changes that give the visible step a value.
///
/// @discussion	For the step alone, its own line is changed, or one is put in
/// 			after its lines of that kind, which would otherwise override
/// 			it. For later steps, the step's own lines go, and its last line
/// 			that carries on is changed or one is put in. Lines that only say
/// 			what the step would have anyway are taken out.
///
/// 			For the model, only the GLOBAL line in the header is changed or
/// 			put in, as LPub3D writes it. The steps' lines stay, and go on
/// 			overriding it where they hold, the visible step's too.
///
//==============================================================================
- (void) setValue:(LDrawStepAssemblyValue *)value
			scope:(LDrawStepAssemblyScope)scope
		  inModel:(nullable LDrawModel *)model
{
	LDrawStep *step = [model visibleStep];

	if (step == nil) {
		return;
	}

	NSArray<LDrawDirective *> *own = OwnLinesInStep(step, value.matches);

	switch (scope) {
		case LDrawStepAssemblyScopeStep: {
			LDrawDirective *inherited = LineInForce(step, value.matches, own);

			if (value.isGivenBy(inherited)) {
				[self removeLines:own];
			}
			else if (own.lastObject != nil) {
				[self setLine:own.lastObject toValue:value scope:LPubMetaScopeLocal];
			}
			else {
				[self insertValue:value scope:LPubMetaScopeLocal inStep:step];
			}
			break;
		}

		case LDrawStepAssemblyScopeLaterSteps: {
			NSArray<LDrawDirective *>	*carried	= CarriedLinesInStep(step, value.matches);
			LDrawDirective				*carriedIn	= LineInForce(step, value.matches,
															  [own arrayByAddingObjectsFromArray:carried]);

			[self removeLines:own];

			if (value.isGivenBy(carriedIn)) {
				[self removeLines:carried];
			}
			else if (carried.lastObject != nil) {
				[self setLine:carried.lastObject toValue:value scope:ScopeOfLine(carried.lastObject)];
			}
			else {
				[self insertValue:value scope:LPubMetaScopeUnspecified inStep:step];
			}
			break;
		}

		case LDrawStepAssemblyScopeModel: {
			LDrawStep		*header	= HeaderStep(model) ?: step;
			LDrawDirective	*global	= nil;

			// A value the step shows already writes nothing, so a value left
			// alone does not change the rest of the model.
			if (value.isGivenBy(LineInForce(step, value.matches, nil))) {
				break;
			}

			for (LDrawDirective *line in LinesInStep(header, value.matches)) {
				if (ScopeOfLine(line) == LPubMetaScopeGlobal) {
					global = line;
				}
			}

			if (global != nil) {
				[self setLine:global toValue:value scope:LPubMetaScopeGlobal];
			}
			else {
				[self insertValue:value scope:LPubMetaScopeGlobal inStep:header];
			}
			break;
		}
	}

}//end setValue:scope:inModel:


//========== removeLines: ======================================================
- (void) removeLines:(NSArray<LDrawDirective *> *)lines
{
	for (LDrawDirective *line in lines) {
		LDrawStepAssemblyChange *change = [LDrawStepAssemblyChange new];

		change.kind			= LDrawStepAssemblyChangeRemove;
		change.directive	= line;

		[self.changes addObject:change];
	}

}//end removeLines:


//========== setLine:toValue:scope: ============================================
///
/// @abstract	Changes a line's text to give the value, unless it does.
///
//==============================================================================
- (void) setLine:(LDrawDirective *)line toValue:(LDrawStepAssemblyValue *)value scope:(LPubMetaScope)scope
{
	if (value.isGivenBy(line) && ScopeOfLine(line) == scope) {
		return;
	}

	LDrawStepAssemblyChange *change = [LDrawStepAssemblyChange new];

	change.kind			= LDrawStepAssemblyChangeUpdate;
	change.directive	= line;
	change.text			= value.textForScope(scope);

	[self.changes addObject:change];

}//end setLine:toValue:scope:


//========== insertValue:scope:inStep: =========================================
- (void) insertValue:(LDrawStepAssemblyValue *)value scope:(LPubMetaScope)scope inStep:(LDrawStep *)step
{
	LDrawStepAssemblyChange	*change	= [LDrawStepAssemblyChange new];
	LPubCommand				*line	= [value.lineClass new];

	line.lPubCommandString = value.textForScope(scope);

	change.kind			= LDrawStepAssemblyChangeInsert;
	change.directive	= line;
	change.step			= step;
	change.matcher		= value.matches;

	[self.changes addObject:change];

}//end insertValue:scope:inStep:


// MARK: - ANGLE -


//---------- editSettingViewingAngle:scope:inModel: ------------------[static]--
///
/// @abstract	The edit that shows the visible step at a viewing angle.
///
/// @discussion	LPub3D turns the parts by the ROTSTEP, then looks at them with
/// 			the camera: the view is the rotation times the camera.
///
/// 			A turn is written as a REL ROTSTEP on the step, after which the
/// 			camera in force still looks. The step's own camera lines go. For
/// 			the step alone the next step gets the rotation that held before,
/// 			so later steps keep theirs. The whole model takes no turn.
///
/// 			The view the step has without its own ROTSTEP, as Reset Angle
/// 			puts it, takes the ROTSTEP out. The whole model takes only the
/// 			angle the step has, and writes nothing.
///
//------------------------------------------------------------------------------
+ (nullable instancetype) editSettingViewingAngle:(Tuple3)angle
											scope:(LDrawStepAssemblyScope)scope
										  inModel:(nullable LDrawModel *)model
{
	return [self editSettingViewingAngle:angle
								rotation:[self rotationForViewingAngle:angle inModel:model]
								   scope:scope
								 inModel:model];

}//end editSettingViewingAngle:scope:inModel:


//---------- editSettingViewingAngle:rotation:scope:inModel: ---------[static]--
+ (nullable instancetype) editSettingViewingAngle:(Tuple3)angle
										 rotation:(Tuple3)rotation
											scope:(LDrawStepAssemblyScope)scope
										  inModel:(nullable LDrawModel *)model
{
	LDrawStepAssemblyEdit	*edit	= [self editWithUndoActionKey:@"UndoStepAssemblyTurn"];
	LDrawStep				*step	= [model visibleStep];

	if (step == nil) {
		return edit;
	}

	// A ROTSTEP holds from its step on, so it cannot turn the whole model, and
	// the whole model leaves the step's lines alone. Only the angle the step
	// has already is taken, and writes nothing.
	if (scope == LDrawStepAssemblyScopeModel) {
		Tuple3 current = [self resetViewingAngleForScope:scope inModel:model];

		return Matrix4AnglesWithinTolerance(angle, current, VIEW_EPSILON) ? edit : nil;
	}

	NSUInteger					 index	= [[model steps] indexOfObjectIdenticalTo:step];
	Matrix4						 view	= Matrix4Rotate(IdentityMatrix4, angle);
	NSArray<LDrawDirective *>	*own	= OwnCameraLines(step);

	// The step has this view without lines of its own.
	if (Matrix4RotationsWithinTolerance(view, InheritedView(model, index, own, YES), VIEW_EPSILON)) {
		[edit removeLines:own];
		return edit;
	}

	[edit removeLines:own];

	// The step has this view without its own ROTSTEP either, as Reset Angle
	// puts it. For the step alone the next step takes the ROTSTEP, so later
	// steps keep their rotation.
	if ([step stepRotationType] != LDrawStepRotationNone
		&& Matrix4RotationsWithinTolerance(view, InheritedView(model, index, own, NO), VIEW_EPSILON)) {
		if (scope == LDrawStepAssemblyScopeStep) {
			[edit putBackRotationAfterStepAtIndex:index inModel:model];
		}
		[edit rotateStep:step type:LDrawStepRotationNone angle:ZeroPoint3];
		return edit;
	}

	// Before the step's rotation changes, which it reads.
	if (scope == LDrawStepAssemblyScopeStep) {
		[edit putBackRotationAfterStepAtIndex:index inModel:model];
	}

	Matrix4 turn = Matrix4Multiply(view, Matrix4Invert(InheritedCamera(model, index, own)));

	// The numbers given, as they were typed, when they say this turn.
	if (Matrix4RotationsWithinTolerance(turn, Matrix4Rotate(IdentityMatrix4, rotation), VIEW_EPSILON)) {
		[edit rotateStep:step type:LDrawStepRotationRelative angle:rotation];
	}
	else {
		[edit rotateStep:step type:LDrawStepRotationRelative turn:turn];
	}
	return edit;

}//end editSettingViewingAngle:rotation:scope:inModel:


//========== rotateStep:type:turn: =============================================
- (void) rotateStep:(LDrawStep *)step type:(LDrawStepRotationT)type turn:(Matrix4)turn
{
	[self rotateStep:step type:type angle:[LDrawStepPartListPolicy viewingAngleForView:turn]];

}//end rotateStep:type:turn:


//========== rotateStep:type:angle: ============================================
///
/// @abstract	Sets a step's ROTSTEP, unless it says that already.
///
//==============================================================================
- (void) rotateStep:(LDrawStep *)step type:(LDrawStepRotationT)type angle:(Tuple3)angle
{
	if ([step stepRotationType] == type
		&& Matrix4AnglesWithinTolerance([step rotationAngle], angle, VIEW_EPSILON)) {
		return;
	}

	LDrawStepAssemblyChange *change = [LDrawStepAssemblyChange new];

	change.kind				= LDrawStepAssemblyChangeRotate;
	change.step				= step;
	change.rotationType		= type;
	change.rotationAngle	= angle;

	[self.changes addObject:change];

}//end rotateStep:type:angle:


//========== putBackRotationAfterStepAtIndex:inModel: ==========================
///
/// @abstract	Gives the next step the ROTSTEP in force for the step before the
/// 			edit, so a change to the step does not reach the later ones.
///
/// @discussion	That is the step's own ROTSTEP when it has one. A next step with
/// 			a ROTSTEP of its own keeps it. With no rotation in force, the
/// 			next step gets an END.
///
//==============================================================================
- (void) putBackRotationAfterStepAtIndex:(NSUInteger)index inModel:(LDrawModel *)model
{
	NSArray<LDrawStep *>	*steps		= [model steps];
	LDrawStep				*rotated	= nil;

	if (index + 1 >= steps.count || [steps[index + 1] stepRotationType] != LDrawStepRotationNone) {
		return;
	}

	rotated = StepWithRotationInForce(steps, index);

	if (rotated == nil) {
		[self rotateStep:steps[index + 1] type:LDrawStepRotationEnd angle:ZeroPoint3];
	}
	else {
		[self rotateStep:steps[index + 1] type:[rotated stepRotationType] angle:[rotated rotationAngle]];
	}

}//end putBackRotationAfterStepAtIndex:inModel:


// MARK: - WHAT THE STEP INHERITS -


//---------- inheritedScaleInModel: ----------------------------------[static]--
+ (double) inheritedScaleInModel:(nullable LDrawModel *)model
{
	LDrawStep				*step	= [model visibleStep];
	LDrawStepAssemblyValue	*value	= [self scaleValue:1.0];

	if (step == nil) {
		return 1.0;
	}

	LPubModelScale *line = (LPubModelScale *)LineInForce(step, value.matches, OwnLinesInStep(step, value.matches));

	return (line != nil) ? line.scale : 1.0;

}//end inheritedScaleInModel:


//---------- getInheritedOffset:inModel: -----------------------------[static]--
///
/// @abstract	The offset the step has without its own placement line.
///
/// @discussion	NO when that line puts the step at another place before its
/// 			offset, such as at the bottom where the line it inherits has the
/// 			middle: an offset from the step's own place cannot say that.
///
//------------------------------------------------------------------------------
+ (BOOL) getInheritedOffset:(Point2 *)outOffset inModel:(nullable LDrawModel *)model
{
	LDrawStep				*step		= [model visibleStep];
	LDrawStepAssemblyValue	*value		= [self offsetValue:ZeroPoint2 placedLike:nil];
	LPubPlacement			*current	= nil;
	LPubPlacement			*inherited	= nil;

	if (step == nil) {
		return NO;
	}

	current		= PlacementOnPage([LDrawStepPartListPolicy assemblyPlacementForVisibleStepOfModel:model]);
	inherited	= PlacementOnPage(LineInForce(step, value.matches, OwnLinesInStep(step, value.matches)));

	if (PlacesAlike(inherited, current) == NO) {
		return NO;
	}

	*outOffset = (inherited != nil) ? inherited.offset : ZeroPoint2;
	return YES;

}//end getInheritedOffset:inModel:


//---------- inheritedViewingAngleInModel: ---------------------------[static]--
///
/// @abstract	The angle the step is seen at without its own camera lines. Its
/// 			ROTSTEP stays: it holds for later steps too.
///
//------------------------------------------------------------------------------
+ (Tuple3) inheritedViewingAngleInModel:(nullable LDrawModel *)model
{
	return InheritedViewingAngle(model, YES);

}//end inheritedViewingAngleInModel:


//---------- resetScaleForScope:inModel: -----------------------------[static]--
///
/// @abstract	The scale Reset puts back: for one step or later steps what the
/// 			step has without its own lines, and for the whole model, which
/// 			leaves them alone, the scale the step has.
///
//------------------------------------------------------------------------------
+ (double) resetScaleForScope:(LDrawStepAssemblyScope)scope inModel:(nullable LDrawModel *)model
{
	if (scope == LDrawStepAssemblyScopeModel) {
		return [LDrawStepPartListPolicy modelScaleForBranch:LPubModelScaleBranchAssembly inModel:model];
	}

	return [self inheritedScaleInModel:model];

}//end resetScaleForScope:inModel:


//---------- getResetOffset:forScope:inModel: ------------------------[static]--
///
/// @abstract	The offset Reset puts back, by the same rule as the scale. NO for
/// 			one step or later steps when no offset can say it.
///
//------------------------------------------------------------------------------
+ (BOOL) getResetOffset:(Point2 *)outOffset
			   forScope:(LDrawStepAssemblyScope)scope
				inModel:(nullable LDrawModel *)model
{
	if (scope != LDrawStepAssemblyScopeModel) {
		return [self getInheritedOffset:outOffset inModel:model];
	}

	LPubPlacement *placement = [LDrawStepPartListPolicy assemblyPlacementForVisibleStepOfModel:model];

	*outOffset = placement.isInsidePage ? placement.offset : ZeroPoint2;
	return YES;

}//end getResetOffset:forScope:inModel:


//---------- resetViewingAngleForScope:inModel: ----------------------[static]--
///
/// @abstract	The angle Reset Angle puts back. For one step or later steps it
/// 			is the step without its own camera lines and ROTSTEP, with the
/// 			rotation held before the step. The whole model takes no turn and
/// 			leaves the step's lines alone, so for it the reset is the angle
/// 			the step has.
///
//------------------------------------------------------------------------------
+ (Tuple3) resetViewingAngleForScope:(LDrawStepAssemblyScope)scope inModel:(nullable LDrawModel *)model
{
	LDrawStep	*step	= [model visibleStep];
	NSUInteger	 index	= [[model steps] indexOfObjectIdenticalTo:step];

	if (step != nil && scope == LDrawStepAssemblyScopeModel) {
		return [LDrawStepPartListPolicy assemblyViewingAngleForStepAtIndex:index inModel:model];
	}

	return InheritedViewingAngle(model, NO);

}//end resetViewingAngleForScope:inModel:


// MARK: - THE PARTS LIST'S PLACE -


//---------- editPlacingListOnPageAt:offset:scope:inModel: -----------[static]--
+ (instancetype) editPlacingListOnPageAt:(LPubPlacementPosition)position
								  offset:(Point2)offset
								   scope:(LDrawStepAssemblyScope)scope
								 inModel:(nullable LDrawModel *)model
{
	LDrawStepAssemblyEdit *edit = [self editWithUndoActionKey:@"UndoStepPartListMove"];

	[edit setValue:[self listPlacementValueAt:position relativeTo:LPUB_PAGE isInside:YES offset:offset]
			 scope:scope
		   inModel:model];

	return edit;

}//end editPlacingListOnPageAt:offset:scope:inModel:


//---------- editPlacingListBesideAssemblyAt:scope:inModel: ----------[static]--
+ (instancetype) editPlacingListBesideAssemblyAt:(LPubPlacementPosition)side
										   scope:(LDrawStepAssemblyScope)scope
										 inModel:(nullable LDrawModel *)model
{
	LDrawStepAssemblyEdit *edit = [self editWithUndoActionKey:@"UndoStepPartListMove"];

	[edit setValue:[self listPlacementValueAt:side relativeTo:LPUB_ASSEM isInside:NO offset:ZeroPoint2]
			 scope:scope
		   inModel:model];

	return edit;

}//end editPlacingListBesideAssemblyAt:scope:inModel:


//---------- editResettingListPlacementInModel: ----------------------[static]--
+ (instancetype) editResettingListPlacementInModel:(nullable LDrawModel *)model
{
	LDrawStepAssemblyEdit	*edit	= [self editWithUndoActionKey:@"UndoStepPartListResetPosition"];
	LDrawStep				*step	= [model visibleStep];

	if (step != nil) {
		[edit removeLines:OwnLinesInStep(step, ^BOOL(LDrawDirective *directive) {
			return IsListPlacementLine(directive);
		})];
	}

	return edit;

}//end editResettingListPlacementInModel:


//---------- listPlacementValueAt:relativeTo:isInside:offset: --------[static]--
///
/// @abstract	A place for the parts list, in a PLI PLACEMENT line.
///
/// @discussion	No line never gives it: LPub3D then puts the list beside the
/// 			step number. On a side outside, the list sits in the middle of
/// 			that side. An offset of zero is left out, as LPub3D writes it.
///
//------------------------------------------------------------------------------
+ (LDrawStepAssemblyValue *) listPlacementValueAt:(LPubPlacementPosition)position
									   relativeTo:(NSString *)relativeTo
										 isInside:(BOOL)isInside
										   offset:(Point2)offset
{
	LDrawStepAssemblyValue	*value		= [LDrawStepAssemblyValue new];
	BOOL					 isOnSide	= (position == LPubPlacementPositionTop
										   || position == LPubPlacementPositionRight
										   || position == LPubPlacementPositionBottom
										   || position == LPubPlacementPositionLeft);

	value.lineClass	= [LPubPlacement class];
	value.matches	= ^BOOL(LDrawDirective *directive) {
		return IsListPlacementLine(directive);
	};

	value.isGivenBy = ^BOOL(LDrawDirective *line) {
		LPubPlacement *placement = (LPubPlacement *)line;

		return placement != nil
			&& placement.position == position
			&& placement.isInside == isInside
			&& (isInside || isOnSide == NO || placement.justification == LPubPlacementPositionCenter)
			&& [placement.relativeTo isEqualToString:relativeTo]
			&& fabs(placement.offset.x - offset.x) < VALUE_EPSILON
			&& fabs(placement.offset.y - offset.y) < VALUE_EPSILON;
	};

	value.textForScope = ^NSString *(LPubMetaScope scope) {
		NSMutableString *text = [NSMutableString stringWithFormat:@"%@ %@%@ %@", LPUB_PLI, LPUB_PLACEMENT,
								 ScopeWord(scope), [LPubPlacement nameForPosition:position]];

		if (isInside == NO && isOnSide) {
			[text appendFormat:@" %@", [LPubPlacement nameForPosition:LPubPlacementPositionCenter]];
		}

		[text appendFormat:@" %@ %@", relativeTo, isInside ? LPUB_PLACEMENT_INSIDE : LPUB_PLACEMENT_OUTSIDE];

		if (fabs(offset.x) >= VALUE_EPSILON || fabs(offset.y) >= VALUE_EPSILON) {
			[text appendFormat:@" %.4f %.4f", offset.x, offset.y];
		}

		return text;
	};

	return value;

}//end listPlacementValueAt:relativeTo:isInside:offset:


// MARK: - LPUB3D'S ANGLES -


//---------- viewingAngleForLatitude:longitude: ----------------------[static]--
///
/// @abstract	The viewing angle of LPub3D's camera at these angles, looking at
/// 			the parts with no rotation, as a named view shows them.
///
//------------------------------------------------------------------------------
+ (Tuple3) viewingAngleForLatitude:(double)latitude longitude:(double)longitude
{
	Matrix4 camera = [LDrawStepPartListLayout viewTransformForLatitude:latitude longitude:longitude];

	return [LDrawStepPartListPolicy viewingAngleForView:camera];

}//end viewingAngleForLatitude:longitude:


//---------- viewingAngle:afterTurn: ---------------------------------[static]--
///
/// @abstract	A viewing angle after a quick turn of the parts about their own
/// 			axes, before they are seen.
///
//------------------------------------------------------------------------------
+ (Tuple3) viewingAngle:(Tuple3)angle afterTurn:(LDrawStepQuickTurn)turn
{
	Tuple3 axisTurn = ZeroPoint3;

	switch (turn) {
		case LDrawStepQuickTurnLeft:		axisTurn = V3Make(0.0, 90.0, 0.0);	break;
		case LDrawStepQuickTurnRight:		axisTurn = V3Make(0.0, -90.0, 0.0);	break;
		case LDrawStepQuickTurnAround:		axisTurn = V3Make(0.0, 180.0, 0.0);	break;
		case LDrawStepQuickTurnUpsideDown:	axisTurn = V3Make(0.0, 0.0, 180.0);	break;
	}

	Matrix4 view = Matrix4Multiply(Matrix4Rotate(IdentityMatrix4, axisTurn), Matrix4Rotate(IdentityMatrix4, angle));

	return [LDrawStepPartListPolicy viewingAngleForView:view];

}//end viewingAngle:afterTurn:


// MARK: - THE STEP'S ROTSTEP -


//---------- rotationForViewingAngle:inModel: ------------------------[static]--
///
/// @abstract	The REL ROTSTEP a turn of the visible step to a viewing angle
/// 			writes, in degrees: the rotation that the camera in force looks
/// 			through, without the step's own camera lines.
///
/// @discussion	When the REL ROTSTEP in force for the step says the same turn,
/// 			its own numbers come back, as the file has them.
///
//------------------------------------------------------------------------------
+ (Tuple3) rotationForViewingAngle:(Tuple3)angle inModel:(nullable LDrawModel *)model
{
	NSArray<LDrawStep *>	*steps	= [model steps];
	LDrawStep				*step	= [model visibleStep];
	NSUInteger				 index	= [steps indexOfObjectIdenticalTo:step];

	if (step == nil) {
		return ZeroPoint3;
	}

	NSArray<LDrawDirective *> *own = OwnCameraLines(step);

	Matrix4 view = Matrix4Rotate(IdentityMatrix4, angle);
	Matrix4 turn = Matrix4Multiply(view, Matrix4Invert(InheritedCamera(model, index, own)));

	LDrawStep	*rotated	= StepWithRotationInForce(steps, index);
	Tuple3		 given		= [rotated rotationAngle];

	if ([rotated stepRotationType] == LDrawStepRotationRelative
		&& Matrix4RotationsWithinTolerance(turn, Matrix4Rotate(IdentityMatrix4, given), VIEW_EPSILON)) {
		return given;
	}

	return [LDrawStepPartListPolicy viewingAngleForView:turn];

}//end rotationForViewingAngle:inModel:


//---------- rotationForViewingAngle:preferring:inModel: -------------[static]--
///
/// @abstract	As -rotationForViewingAngle:inModel:, but `preferred` comes back
/// 			as it is when it says the same turn, as numbers typed do.
///
//------------------------------------------------------------------------------
+ (Tuple3) rotationForViewingAngle:(Tuple3)angle
						preferring:(Tuple3)preferred
						   inModel:(nullable LDrawModel *)model
{
	Tuple3 preferredAngle = [self viewingAngleForRotation:preferred inModel:model];

	if (Matrix4AnglesWithinTolerance(angle, preferredAngle, VIEW_EPSILON)) {
		return preferred;
	}

	return [self rotationForViewingAngle:angle inModel:model];

}//end rotationForViewingAngle:preferring:inModel:


//---------- viewingAngleForRotation:inModel: ------------------------[static]--
///
/// @abstract	The viewing angle a REL ROTSTEP of the visible step gives, with
/// 			the camera in force after it, without the step's own camera
/// 			lines.
///
//------------------------------------------------------------------------------
+ (Tuple3) viewingAngleForRotation:(Tuple3)rotation inModel:(nullable LDrawModel *)model
{
	LDrawStep	*step	= [model visibleStep];
	NSUInteger	 index	= [[model steps] indexOfObjectIdenticalTo:step];

	if (step == nil) {
		return rotation;
	}

	NSArray<LDrawDirective *> *own = OwnCameraLines(step);

	Matrix4 view = Matrix4Multiply(Matrix4Rotate(IdentityMatrix4, rotation), InheritedCamera(model, index, own));

	return [LDrawStepPartListPolicy viewingAngleForView:view];

}//end viewingAngleForRotation:inModel:


// MARK: - COMBINING -


//---------- editCombiningEdits: -------------------------------------[static]--
///
/// @abstract	Several edits as one. The undo name is the one edit's that
/// 			changes something, or one for them all.
///
//------------------------------------------------------------------------------
+ (instancetype) editCombiningEdits:(NSArray<LDrawStepAssemblyEdit *> *)edits
{
	LDrawStepAssemblyEdit	*combined	= [self editWithUndoActionKey:@"UndoStepAssemblyArrange"];
	NSUInteger				 changing	= 0;

	for (LDrawStepAssemblyEdit *edit in edits) {
		if (edit.isEmpty) {
			continue;
		}

		[combined.changes addObjectsFromArray:edit.changes];
		combined.undoActionKey = edit.undoActionKey;
		changing++;
	}

	if (changing > 1) {
		combined.undoActionKey = @"UndoStepAssemblyArrange";
	}

	return combined;

}//end editCombiningEdits:


@end
