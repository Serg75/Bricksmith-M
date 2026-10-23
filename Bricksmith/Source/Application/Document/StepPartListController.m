//==============================================================================
//
// File:		StepPartListController.m
//
// Purpose:		Owns the step parts list overlay for one document.
//
// Notes:		The decisions are made in the packages: the layout in
//				LDrawFeatures and LDrawStepRendering, the edits and the
//				gestures in LDrawStepEditing. What is left here is the AppKit
//				part: attaching a view, watching notifications and events,
//				menus, cursors and coalescing reloads.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import "StepPartListController.h"

#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubPliConstrain.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawFeatures/LDrawStepPartListEdit.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>
#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>
#import <LDrawFeatures/LDrawStepPartListPresentation.h>

#import <LDrawStepEditing/LDrawStepAssemblyScaleTracker.h>
#import <LDrawStepEditing/LDrawStepCalloutEdit.h>
#import <LDrawStepEditing/LDrawStepCalloutMenuItem.h>
#import <LDrawStepEditing/LDrawStepCalloutTracker.h>
#import <LDrawStepEditing/LDrawStepPartListMoveTracker.h>

#import <LDrawStepRendering/LDrawStepOverlayPresenter.h>

#import "LDrawView.h"
#import "LDrawViewerContainer.h"
#import "StepPartListChromeView.h"
#import "OverlayViewCategory.h"
#import "StepPartListView.h"


/// How long until a callout's box that is on its way is drawn again.
static const NSTimeInterval CALLOUT_MOVE_FRAME_SECONDS = 1.0 / 60.0;

/// The keys that end arranging, and the ones that move the step or the
/// selected item.
static const unsigned short RETURN_KEY_CODE			= 36;
static const unsigned short ENTER_KEY_CODE			= 76;
static const unsigned short ESCAPE_KEY_CODE			= 53;
static const unsigned short LEFT_ARROW_KEY_CODE		= 123;
static const unsigned short RIGHT_ARROW_KEY_CODE	= 124;
static const unsigned short DOWN_ARROW_KEY_CODE		= 125;
static const unsigned short UP_ARROW_KEY_CODE		= 126;

/// How far an arrow key moves the arranged step or the selected item on the
/// page, in inches, and with Shift.
static const double NUDGE_INCHES		= 0.05;
static const double SHIFT_NUDGE_INCHES	= 0.25;

/// No button of the turned view's strip is pressed.
static const NSInteger NO_TURNED_VIEW_BUTTON = -1;

/// A press of P shorter than this switches the previous step on or off. A
/// longer one shows it only while it is held.
static const NSTimeInterval PREVIOUS_STEP_TAP_SECONDS = 0.3;

/// How close the arranged angle must be to the reset angle for Reset Angle to
/// have nothing to do, as a rotation matrix's entries.
static const double RESET_ANGLE_TOLERANCE = 0.001;


//========== RectInView() ======================================================
///
/// @abstract	A rect of one view in another. The overlay is in a window of its
///				own, so the two are matched on the screen.
///
//==============================================================================
static NSRect RectInView(NSRect rect, NSView *from, NSView *to)
{
	if (from.window == nil || to.window == nil) {
		return NSZeroRect;
	}

	NSRect onScreen = [from.window convertRectToScreen:[from convertRect:rect toView:nil]];

	return [to convertRect:[to.window convertRectFromScreen:onScreen] fromView:nil];

}//end RectInView


//========== ScopeForModifiers() ===============================================
///
/// @abstract	The steps a drop or a click writes for: this step alone, or
///				with Option the later steps too.
///
//==============================================================================
static LDrawStepAssemblyScope ScopeForModifiers(NSEventModifierFlags modifiers)
{
	return (modifiers & NSEventModifierFlagOption) ? LDrawStepAssemblyScopeLaterSteps : LDrawStepAssemblyScopeStep;

}//end ScopeForModifiers


//========== KeyModifiers() ====================================================
///
/// @abstract	The modifiers that make a key someone else's: Command, Option,
///				Control and Shift.
///
//==============================================================================
static NSEventModifierFlags KeyModifiers(NSEvent *event)
{
	return event.modifierFlags & (NSEventModifierFlagCommand
								  | NSEventModifierFlagOption
								  | NSEventModifierFlagControl
								  | NSEventModifierFlagShift);

}//end KeyModifiers


//========== ArrowDirection() ==================================================
///
/// @abstract	Which way an arrow key moves something on the page, one unit
///				long, or nothing for another key. Down is +y, as the page's y
///				runs down.
///
//==============================================================================
static Vector2 ArrowDirection(unsigned short keyCode)
{
	switch (keyCode) {
		case LEFT_ARROW_KEY_CODE:	return V2Make(-1.0, 0.0);
		case RIGHT_ARROW_KEY_CODE:	return V2Make(1.0, 0.0);
		case UP_ARROW_KEY_CODE:		return V2Make(0.0, -1.0);
		case DOWN_ARROW_KEY_CODE:	return V2Make(0.0, 1.0);
		default:					return V2Make(0.0, 0.0);
	}

}//end ArrowDirection


//========== IsPreviousStepKey() ===============================================
///
/// @abstract	Whether the key is P, which shows the previous step while
///				arranging. Read as typed, so it is P on any keyboard layout.
///
//==============================================================================
static BOOL IsPreviousStepKey(NSEvent *event)
{
	return [[event charactersIgnoringModifiers] caseInsensitiveCompare:@"p"] == NSOrderedSame;

}//end IsPreviousStepKey


//------------------------------------------------------------------------------
///
/// @enum       StepPartListSelection
///
/// @abstract   The item on LPub3D's page the arrow keys move.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, StepPartListSelection) {
	StepPartListSelectionNone		= 0,
	StepPartListSelectionList		= 1,
	StepPartListSelectionCallout	= 2
};


// LDrawView already has the camera calls the overlay's layout needs.
@interface LDrawView (StepOverlayCamera) <LDrawStepOverlayCamera>
@end

@implementation LDrawView (StepOverlayCamera)
@end


@interface StepPartListController () <StepPartListViewDelegate>

/// The viewport the overlay is attached to, if any.
@property (nonatomic, weak, nullable) LDrawView				*hostView;
@property (nonatomic, strong, nullable) StepPartListView	*overlayView;

/// Lays the step out against the viewport's camera, and keeps a drag as a
/// preview until it is let go.
@property (nonatomic, strong) LDrawStepOverlayPresenter		*presenter;

/// Follows a press on a callout's box or on the button that leads back.
@property (nonatomic, strong) LDrawStepCalloutTracker		*calloutTracker;

/// Follows a drag of the parts list on the page.
@property (nonatomic, strong) LDrawStepPartListMoveTracker	*listMoveTracker;

/// Follows a drag of a handle on the frame around the step being arranged.
@property (nonatomic, strong) LDrawStepAssemblyScaleTracker	*scaleTracker;

/// The document window's events, watched while the overlay is attached.
@property (nonatomic, strong, nullable) id	eventMonitor;

/// The mouse-down was on the frame's controls, so its drag and mouse-up go to
/// the frame too, even after Escape.
@property (nonatomic) BOOL					ownsGesture;

/// This controller set the cursor, so the viewport's own must be put back when
/// the pointer leaves the frame's controls.
@property (nonatomic) BOOL					showsControlCursor;

/// While arranging, read from the file when arranging starts and again on the
/// reload after a change to it: the page's size in inches, the offset the step
/// has without its own line, as shares of the page, and what Reset puts back
/// for one step or later steps and for the whole model.
@property (nonatomic) BOOL					needsInheritedValues;
@property (nonatomic) Size2					pageInches;
@property (nonatomic) BOOL					hasInheritedOffset;
@property (nonatomic) Point2				inheritedOffset;
@property (nonatomic) Tuple3				stepResetAngle;
@property (nonatomic) Tuple3				modelResetAngle;
@property (nonatomic) double				modelResetScale;
@property (nonatomic) Point2				modelResetOffset;

/// The ROTSTEP numbers last typed while arranging. They are shown and written
/// as typed while they still say the arranged turn.
@property (nonatomic) Tuple3				typedRotation;

/// The arranged rotation as last worked out, and the angle it was worked out
/// from, so a pan does not read the file again. New typed numbers or a read of
/// the file forget it.
@property (nonatomic) BOOL					hasKeptRotation;
@property (nonatomic) Tuple3				keptRotation;
@property (nonatomic) Tuple3				keptRotationAngle;

/// The item on the page the arrow keys move outside arranging: the parts list,
/// or the callout whose BEGIN line is kept.
@property (nonatomic) StepPartListSelection	selection;
@property (nonatomic, weak, nullable) LPubCallout *selectedCallout;

/// Arrow keys held down move the selected item as a preview, from where it
/// was when the first one went down, and which box that is. The move is
/// written when they come up.
@property (nonatomic) BOOL					isNudging;
@property (nonatomic) Point2				nudgeStart;
@property (nonatomic) Vector2				nudgeDistance;
@property (nonatomic) NSUInteger			nudgeBoxIndex;

/// P is held down, and when it went down.
@property (nonatomic) BOOL					isPeekingPreviousStep;
@property (nonatomic) NSTimeInterval		peekStartTime;

/// A press on the turned view's strip is in progress, and the button it began
/// on, or NO_TURNED_VIEW_BUTTON.
@property (nonatomic) BOOL					pressesTurnedViewStrip;
@property (nonatomic) NSInteger				pressedTurnedViewButton;

/// Recollects, repacks and redraws. Safe to call when not attached.
- (void) reload;

@end


@implementation StepPartListController


// MARK: - INITIALIZATION -


- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_presenter		= [[LDrawStepOverlayPresenter alloc] init];
		self->_calloutTracker	= [[LDrawStepCalloutTracker alloc] init];
		self->_listMoveTracker	= [[LDrawStepPartListMoveTracker alloc] init];
		self->_scaleTracker		= [[LDrawStepAssemblyScaleTracker alloc] init];
		[self subscribeToChanges];
	}
	return self;

}//end init


//========== dealloc ===========================================================
///
/// @abstract	Takes the overlay down with the controller.
///
/// @discussion	A document can be released on another thread, and its controller
///				with it. A window and an event monitor are for the main thread
///				alone, so there they are handed to it. The block holds what it
///				needs and not the controller, which is going away.
///
//==============================================================================
- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if ([NSThread isMainThread]) {
		[self detach];
		return;
	}

	LDrawView			*hostView	= self.hostView;
	StepPartListView	*overlay	= self.overlayView;
	id					 monitor	= self.eventMonitor;

	dispatch_async(dispatch_get_main_queue(), ^{
		if (monitor != nil) {
			[NSEvent removeMonitor:monitor];
		}
		if (overlay != nil) {
			[hostView removeOverlayView:overlay];
		}
	});

}//end dealloc


// MARK: - ATTACHMENT -


//========== attachToView: =====================================================
///
/// @abstract	Puts the overlay on a viewport.
///
/// @discussion	The overlay goes in a child window, which is the only reliable
///				way to draw over a GL or Metal surface. That window follows the
///				viewport, so the overlay is always viewport-sized.
///
//==============================================================================
- (void) attachToView:(LDrawView *)view
{
	if (view == self.hostView) {
		[self reload];
		return;
	}

	[self detach];

	if (view == nil) {
		return;
	}

	self.hostView = view;
	self.presenter.camera = view;
	self.overlayView = [[StepPartListView alloc] initWithFrame:[view bounds]];
	self.overlayView.delegate = self;
	self.overlayView.returnTitle	= self.returnTitle;
	self.overlayView.useAngleTitle	= NSLocalizedString(@"StepUseThisAngle", nil);
	self.overlayView.stepAngleTitle	= NSLocalizedString(@"StepBackToStepAngle", nil);

	// The overlay is 1x1 until its window starts following the viewport, and
	// the layout depends on that size, so repack whenever it changes.
	[self.overlayView setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(setNeedsReloadForNotification:)
												 name:NSViewFrameDidChangeNotification
											   object:self.overlayView];

	// On LPub3D's page the frame and the outline are pinned to the model, so a
	// zoom, a scroll or a turn changes the layout.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(cameraDidChange:)
												 name:LDrawViewCameraDidChangeNotification
											   object:view];

	[view addOverlayView:self.overlayView];

	// The overlay's window ignores the mouse, so its controls are driven from
	// the document window's events.
	[self startWatchingEvents];

	[self reload];

}//end attachToView:


//========== detach ============================================================
///
/// @abstract	Takes the overlay down and releases its 3D surface.
///
//==============================================================================
- (void) detach
{
	[self stopWatchingEvents];

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];

	if (self.hostView != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:LDrawViewCameraDidChangeNotification
													  object:self.hostView];
		self.hostView.pageBackgroundColor = nil;
		self.hostView.outlineWidth = 0.0;
		[self lockHostOnPage:NO arranging:NO];
	}

	if (self.overlayView != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:NSViewFrameDidChangeNotification
													  object:self.overlayView];

		if (self.hostView != nil) {
			[self.hostView removeOverlayView:self.overlayView];
		}
	}

	self.overlayView		= nil;
	self.hostView			= nil;
	self.presenter.camera	= nil;
	[self.presenter reset];
	[self showLayoutInTracker];

}//end detach


// MARK: - ARRANGING -


//========== isArranging =======================================================
- (BOOL) isArranging
{
	return self.presenter.isArranging;

}//end isArranging


//========== beginArranging ====================================================
///
/// @abstract	Starts arranging the step as it is laid out now.
///
//==============================================================================
- (BOOL) beginArranging
{
	if (self.overlayView == nil) {
		return NO;
	}

	// The page is held where the last layout drew it, so lay out now.
	[self reload];

	if ([self.presenter beginArranging] == NO) {
		return NO;
	}

	self.typedRotation = ZeroPoint3;
	[self readInheritedValues];

	// The reload also makes a plain drag move the model on the page.
	[self reload];
	return YES;

}//end beginArranging


//========== readInheritedValues ===============================================
///
/// @abstract	Reads what the step has without its own lines, when arranging
///				starts and again when the file changes. The presenter snaps to
///				the scale and the angles, the scope bar shows what differs from
///				the scale and the offset, and Reset puts them back.
///
//==============================================================================
- (void) readInheritedValues
{
	LDrawStepOverlayPresenter	*presenter	= self.presenter;
	LDrawModel					*model		= self.model;
	LDrawStepAssemblyScope		 step		= LDrawStepAssemblyScopeStep;
	LDrawStepAssemblyScope		 whole		= LDrawStepAssemblyScopeModel;

	self.needsInheritedValues	= NO;
	self.hasKeptRotation		= NO;

	// One walk into the submodels for all the lookups.
	[LDrawStepPartListPolicy performWithCachedLookups:^{
		double	latitude	= 0.0;
		double	longitude	= 0.0;
		Point2	offset		= ZeroPoint2;
		Tuple3	inherited	= [LDrawStepAssemblyEdit inheritedViewingAngleInModel:model];

		presenter.arrangedSnapScale		= [LDrawStepAssemblyEdit inheritedScaleInModel:model];
		presenter.hasArrangedSnapAngles	= [LDrawStepPartListPolicy getAssemblyLatitude:&latitude
																			 longitude:&longitude
																	   forViewingAngle:inherited
																			   inModel:model];
		presenter.arrangedSnapLatitude	= latitude;
		presenter.arrangedSnapLongitude	= longitude;

		self.pageInches			= [LDrawStepPartListPolicy pageSizeInInchesInModel:model];
		self.hasInheritedOffset	= [LDrawStepAssemblyEdit getInheritedOffset:&offset inModel:model];
		self.inheritedOffset	= offset;

		[LDrawStepAssemblyEdit getResetOffset:&offset forScope:whole inModel:model];

		self.modelResetOffset	= offset;
		self.modelResetScale	= [LDrawStepAssemblyEdit resetScaleForScope:whole inModel:model];
		self.stepResetAngle		= [LDrawStepAssemblyEdit resetViewingAngleForScope:step inModel:model];
		self.modelResetAngle	= [LDrawStepAssemblyEdit resetViewingAngleForScope:whole inModel:model];
	}];

}//end readInheritedValues


//========== inheritedScale ====================================================
- (double) inheritedScale
{
	return self.presenter.arrangedSnapScale;

}//end inheritedScale


//========== getInheritedOffsetInches: =========================================
- (BOOL) getInheritedOffsetInches:(Vector2 *)offset
{
	Size2 page = self.pageInches;

	*offset = V2Make(self.inheritedOffset.x * page.width, self.inheritedOffset.y * page.height);

	return self.hasInheritedOffset;

}//end getInheritedOffsetInches:


//========== arrangedEditWithScope: ============================================
- (nullable LDrawStepAssemblyEdit *) arrangedEditWithScope:(LDrawStepAssemblyScope)scope
{
	LDrawStepOverlayPresenter	*presenter	= self.presenter;
	LDrawModel					*model		= self.model;

	if (presenter.isArranging == NO) {
		return nil;
	}

	NSMutableArray<LDrawStepAssemblyEdit *> *edits = [NSMutableArray array];

	[edits addObject:[LDrawStepAssemblyEdit editSettingScale:presenter.arrangedScale scope:scope inModel:model]];
	[edits addObject:[LDrawStepAssemblyEdit editSettingOffset:presenter.arrangedOffset scope:scope inModel:model]];

	LDrawStepAssemblyEdit *angle = [LDrawStepAssemblyEdit editSettingViewingAngle:presenter.arrangedViewingAngle
																		 rotation:self.arrangedRotation
																			scope:scope
																		  inModel:model];
	if (angle != nil) {
		[edits addObject:angle];
	}

	return [LDrawStepAssemblyEdit editCombiningEdits:edits];

}//end arrangedEditWithScope:


//========== canWriteArrangedScope: ============================================
- (BOOL) canWriteArrangedScope:(LDrawStepAssemblyScope)scope
{
	LDrawStepOverlayPresenter *presenter = self.presenter;

	if (presenter.isArranging == NO) {
		return NO;
	}

	return [LDrawStepAssemblyEdit editSettingViewingAngle:presenter.arrangedViewingAngle
												 rotation:self.arrangedRotation
													scope:scope
												  inModel:self.model] != nil;

}//end canWriteArrangedScope:


//========== arrangedScale =====================================================
- (double) arrangedScale
{
	return self.presenter.arrangedScale;

}//end arrangedScale


//========== setArrangedScale: =================================================
- (void) setArrangedScale:(double)scale
{
	if (self.isArranging == NO || scale <= 0.0) {
		return;
	}

	self.presenter.arrangedScale = scale;
	[self reload];

}//end setArrangedScale:


//========== arrangedOffsetInches ==============================================
///
/// @abstract	The arranged offset in page inches. The file says it as shares
///				of the page.
///
//==============================================================================
- (Vector2) arrangedOffsetInches
{
	Size2	page	= self.pageInches;
	Point2	offset	= self.presenter.arrangedOffset;

	return V2Make(offset.x * page.width, offset.y * page.height);

}//end arrangedOffsetInches


//========== setArrangedOffsetInches: ==========================================
- (void) setArrangedOffsetInches:(Vector2)inches
{
	Size2 page = self.pageInches;

	if (self.isArranging == NO || page.width <= 0.0 || page.height <= 0.0) {
		return;
	}

	self.presenter.arrangedOffset = V2Make(inches.x / page.width, inches.y / page.height);
	[self reload];

}//end setArrangedOffsetInches:


//========== arrangedViewingAngle ==============================================
- (Tuple3) arrangedViewingAngle
{
	return self.presenter.arrangedViewingAngle;

}//end arrangedViewingAngle


//========== setArrangedViewingAngle: ==========================================
///
/// @abstract	Turns the camera to the angle. The presenter reads that as a
///				turn, which keeps this exact angle.
///
//==============================================================================
- (void) setArrangedViewingAngle:(Tuple3)angle
{
	if (self.isArranging == NO) {
		return;
	}

	[self.presenter turnArrangedStepToViewingAngle:angle];
	[self reload];

}//end setArrangedViewingAngle:


//========== arrangedRotation ==================================================
///
/// @abstract	The arranged angle as a REL ROTSTEP. Worked out again only when
///				the angle, the typed numbers or the file change, since the
///				scope bar asks for it after every layout.
///
//==============================================================================
- (Tuple3) arrangedRotation
{
	Tuple3 angle = self.arrangedViewingAngle;

	if (self.hasKeptRotation == NO || V3EqualPoints(angle, self.keptRotationAngle) == NO) {
		self.keptRotation		= [LDrawStepAssemblyEdit rotationForViewingAngle:angle
															   preferring:self.typedRotation
																  inModel:self.model];
		self.keptRotationAngle	= angle;
		self.hasKeptRotation	= YES;
	}

	return self.keptRotation;

}//end arrangedRotation


//========== setArrangedRotation: ==============================================
///
/// @abstract	Turns the camera to the angle a REL ROTSTEP of these numbers
///				gives, and keeps the numbers as typed.
///
//==============================================================================
- (void) setArrangedRotation:(Tuple3)rotation
{
	self.typedRotation			= rotation;
	self.hasKeptRotation		= NO;
	self.arrangedViewingAngle	= [LDrawStepAssemblyEdit viewingAngleForRotation:rotation inModel:self.model];

}//end setArrangedRotation:


//========== resetAngleForScope: ===============================================
- (Tuple3) resetAngleForScope:(LDrawStepAssemblyScope)scope
{
	return (scope == LDrawStepAssemblyScopeModel) ? self.modelResetAngle : self.stepResetAngle;

}//end resetAngleForScope:


//========== resetArrangedViewingAngleForScope: ================================
- (void) resetArrangedViewingAngleForScope:(LDrawStepAssemblyScope)scope
{
	self.arrangedViewingAngle = [self resetAngleForScope:scope];

}//end resetArrangedViewingAngleForScope:


//========== canResetArrangedViewingAngleForScope: =============================
- (BOOL) canResetArrangedViewingAngleForScope:(LDrawStepAssemblyScope)scope
{
	return self.isArranging
		&& Matrix4AnglesWithinTolerance([self resetAngleForScope:scope],
										self.arrangedViewingAngle,
										RESET_ANGLE_TOLERANCE) == NO;

}//end canResetArrangedViewingAngleForScope:


//========== resetArrangedScaleForScope: =======================================
- (void) resetArrangedScaleForScope:(LDrawStepAssemblyScope)scope
{
	self.arrangedScale = (scope == LDrawStepAssemblyScopeModel) ? self.modelResetScale : self.inheritedScale;

}//end resetArrangedScaleForScope:


//========== resetArrangedOffsetForScope: ======================================
- (void) resetArrangedOffsetForScope:(LDrawStepAssemblyScope)scope
{
	if ([self canResetArrangedOffsetForScope:scope] == NO) {
		return;
	}

	self.presenter.arrangedOffset = (scope == LDrawStepAssemblyScopeModel) ? self.modelResetOffset
																		   : self.inheritedOffset;
	[self reload];

}//end resetArrangedOffsetForScope:


//========== canResetArrangedOffsetForScope: ===================================
- (BOOL) canResetArrangedOffsetForScope:(LDrawStepAssemblyScope)scope
{
	return self.isArranging && (scope == LDrawStepAssemblyScopeModel || self.hasInheritedOffset);

}//end canResetArrangedOffsetForScope:


//========== canAlignArrangedStepWithPreviousStep ==============================
- (BOOL) canAlignArrangedStepWithPreviousStep
{
	return [self.presenter canAlignArrangedStepWithPreviousStep];

}//end canAlignArrangedStepWithPreviousStep


//========== alignArrangedStepWithPreviousStep =================================
- (void) alignArrangedStepWithPreviousStep
{
	[self.presenter alignArrangedStepWithPreviousStep];
	[self reload];

}//end alignArrangedStepWithPreviousStep


//========== centerArrangedStepOnPage ==========================================
- (void) centerArrangedStepOnPage
{
	[self.presenter centerArrangedStepOnPage];
	[self reload];

}//end centerArrangedStepOnPage


//========== holdArrangedPage ==================================================
- (void) holdArrangedPage
{
	[self.presenter holdArrangedPage];

}//end holdArrangedPage


//========== fitArrangedPage ===================================================
- (void) fitArrangedPage
{
	[self.presenter fitArrangedPage];

}//end fitArrangedPage


//========== setShowsPreviousStep: =============================================
- (void) setShowsPreviousStep:(BOOL)flag
{
	self->_showsPreviousStep = flag;
	[self showPreviousStepAsAsked];

}//end setShowsPreviousStep:


//========== isShowingPreviousStep =============================================
- (BOOL) isShowingPreviousStep
{
	return self.showsPreviousStep || self.isPeekingPreviousStep;

}//end isShowingPreviousStep


//========== hasPreviousStep ===================================================
- (BOOL) hasPreviousStep
{
	NSUInteger index = [[self.model steps] indexOfObjectIdenticalTo:[self.model visibleStep]];

	return index != NSNotFound && index > 0;

}//end hasPreviousStep


//========== showPreviousStepAsAsked ===========================================
///
/// @abstract	Shows or hides the previous step as set and as P says. The
///				layout tells the document, which checks its box to match.
///
//==============================================================================
- (void) showPreviousStepAsAsked
{
	self.presenter.showsPreviousStep = self.isShowingPreviousStep;
	[self reload];

}//end showPreviousStepAsAsked


//========== arrangedPointsPerPageInch =========================================
- (double) arrangedPointsPerPageInch
{
	return self.presenter.arrangedPointsPerInch;

}//end arrangedPointsPerPageInch


//========== stopPeekingPreviousStep ===========================================
///
/// @abstract	Once arranging ends, shows the previous step as the checkbox
///				has it, not as P held it.
///
//==============================================================================
- (void) stopPeekingPreviousStep
{
	self.isPeekingPreviousStep			= NO;
	self.presenter.showsPreviousStep	= self.showsPreviousStep;

}//end stopPeekingPreviousStep


//========== endArranging ======================================================
- (void) endArranging
{
	[self stopPeekingPreviousStep];
	[self.presenter endArranging];
	[self lockHostOnPage:self.presentation.isOnPage arranging:NO];
	self.overlayView.showsArrangeFrame = NO;
	[self setNeedsReload];

}//end endArranging


// MARK: - ACCESSORS -


- (void) setModel:(LDrawModel *)model
{
	if (self->_model != model) {
		self->_model = model;
		self.presenter.model = model;

		// The pictures were kept through changes to the old model alone.
		[self.overlayView discardCalloutPictures];
		[self setNeedsReload];
	}

}//end setModel:


- (void) setReturnTitle:(NSString *)title
{
	self->_returnTitle = [title copy];
	self.overlayView.returnTitle = title;
	[self showLayoutInTracker];

}//end setReturnTitle:


- (LDrawStepPartListPageAnchor *) pageAnchor
{
	return self.presenter.pageAnchor;

}//end pageAnchor


- (void) setPageAnchor:(LDrawStepPartListPageAnchor *)pageAnchor
{
	self.presenter.pageAnchor = pageAnchor;

}//end setPageAnchor:


- (LDrawStepPartListPresentation *) presentation
{
	return self.presenter.presentation;

}//end presentation


// MARK: - RELOADING -


//========== reload ============================================================
///
/// @abstract	Recollects, repacks and redraws.
///
//==============================================================================
- (void) reload
{
	// This reload covers any coalesced one still queued.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];

	StepPartListView			*overlay	= self.overlayView;
	LDrawStepOverlayPresenter	*presenter	= self.presenter;
	LDrawStepCalloutTracker		*tracker	= self.calloutTracker;

	if (overlay == nil) {
		return;
	}

	if (presenter.isArranging && self.needsInheritedValues) {
		[self readInheritedValues];
	}

	presenter.viewSize = [self overlaySize];

	// Shift snaps a turn to steps of 15 degrees while arranging.
	presenter.snapsTurnsToSteps		= ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;

	// A box that is being dragged or nudged is laid out where it is held.
	BOOL nudgesBox = self.isNudging && self.selection == StepPartListSelectionCallout;

	presenter.hasCalloutPreview		= tracker.isDragging || nudgesBox;
	presenter.calloutPreviewBox		= nudgesBox ? self.nudgeBoxIndex : tracker.draggedBoxIndex;
	presenter.calloutPreviewPoint	= nudgesBox ? [self nudgedOrigin] : tracker.dragOrigin;

	// Read before the reload, which may end arranging. Then it is 0.
	BOOL	wasArranging	= presenter.isArranging;
	double	arrangedInch	= presenter.arrangedPointsPerInch;

	[presenter reload];

	// An edit can put another step on display, such as a step put in or taken
	// out before it. That ends arranging in the presenter.
	BOOL stoppedArranging = wasArranging && presenter.isArranging == NO;

	if (stoppedArranging) {
		[self stopPeekingPreviousStep];
	}

	// The arrows first, so the first draw already has them.
	[overlay setCalloutArrows:presenter.calloutArrows];
	[overlay showPresentation:presenter.presentation];

	// The overlay is drawn over the model, so the page's color goes behind it.
	// The overlay dims what lies outside the page.
	self.hostView.pageBackgroundColor = StepPartListPageColor(presenter.presentation);
	self.hostView.outlineWidth = presenter.presentation.outlineWidth;

	// Arranging can also end in the presenter, when another step is shown.
	[self lockHostOnPage:presenter.presentation.isOnPage arranging:presenter.isArranging];
	overlay.showsArrangeFrame	= presenter.isArranging;
	overlay.unobscuredRect		= [self unobscuredOverlayRect];

	// The guides of a list being dragged, else of the step being arranged.
	overlay.guides = self.listMoveTracker.isMoving ? self.listMoveTracker.guides : presenter.arrangedGuides;

	// Where the previous step sat on its page, while arranging.
	overlay.ghostOutline = presenter.previousStepOutline;
	[overlay showGhostPicture:presenter.previousStepPicture];

	// A view turned away from the step's angle says so.
	overlay.turnedViewText = presenter.isTurnedFromStepAngle ? NSLocalizedString(@"StepTurnedView", nil) : nil;

	// The item the arrow keys move, while it is still on the page.
	[self showSelection];

	[self showLayoutInTracker];

	// A callout's box that is changing places is drawn further along next
	// time. In every run loop mode, so it keeps moving while the mouse is
	// held down.
	if (presenter.isMovingCallouts) {
		[self performSelector:@selector(reload)
				   withObject:nil
				   afterDelay:CALLOUT_MOVE_FRAME_SECONDS
					  inModes:@[NSRunLoopCommonModes]];
	}

	if (presenter.isArranging) {
		[self.delegate stepPartListControllerDidArrange:self];
	}
	else if (stoppedArranging) {
		[self.delegate stepPartListController:self didStopArrangingWithPageScale:arrangedInch];
	}

}//end reload


//========== setNeedsReload ====================================================
///
/// @abstract	Coalesces a burst of change notifications into one reload.
///
/// @discussion	Stepping through a model, or one edit touching several
///				directives, sends a run of notifications.
///
///				The reload is due in every run loop mode. A drag or a gesture
///				that turns the camera keeps the run loop in its tracking mode,
///				and the overlay has to keep up with it.
///
//==============================================================================
- (void) setNeedsReload
{
	if (self.overlayView == nil) {
		return;
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
	[self performSelector:@selector(reload) withObject:nil afterDelay:0.0 inModes:@[NSRunLoopCommonModes]];

}//end setNeedsReload


//========== overlaySize =======================================================
- (Size2) overlaySize
{
	NSSize size = self.overlayView.bounds.size;

	return V2MakeSize(size.width, size.height);

}//end overlaySize


//========== lockHostOnPage:arranging: ==========================================
///
/// @abstract	Sets what the mouse and the keys do in the viewport. A plain drag
///				pans while arranging. On the page parts are only selected, and
///				the view turns only while the step is arranged. There Command,
///				which would turn it, shows that a click starts arranging.
///
//==============================================================================
- (void) lockHostOnPage:(BOOL)isOnPage arranging:(BOOL)isArranging
{
	LDrawView	*host		= self.hostView;
	BOOL		 canStart	= isOnPage && isArranging == NO;
	NSRect		 page		= StepPartListRectFromBox(self.presentation.pageRect);

	host.plainDragPans	= isArranging;
	host.locksParts		= isOnPage;
	host.locksTurning	= canStart;

	[host setLockedTurnCursor:(canStart ? [StepPartListView arrangeStartCursor] : nil)
					   inRect:(canStart ? RectInView(page, self.overlayView, host) : NSZeroRect)];

}//end lockHostOnPage:arranging:


//========== unobscuredOverlayRect =============================================
///
/// @abstract	The part of the overlay over the model, not over the viewport's
///				scroll bars.
///
//==============================================================================
- (NSRect) unobscuredOverlayRect
{
	NSView					*overlay	= self.overlayView;
	LDrawViewerContainer	*container	= (LDrawViewerContainer *)[self.hostView superview];

	if ([container isKindOfClass:[LDrawViewerContainer class]] == NO) {
		return overlay.bounds;
	}

	return NSIntersectionRect(overlay.bounds, RectInView(container.contentRect, container, overlay));

}//end unobscuredOverlayRect


//========== centerPageOnStep ==================================================
- (void) centerPageOnStep
{
	[self.presenter centerPageOnStep];

}//end centerPageOnStep


// MARK: - RESIZING -


//========== partListView:previewingAxis:atInches: =============================
///
/// @abstract	The drag moved. Repack at the new size without touching the
///				document.
///
//==============================================================================
- (void) partListView:(StepPartListView *)view
	   previewingAxis:(LPubPliAxis)axis
			 atInches:(double)inches
{
	self.presenter.hasSizePreview	= YES;
	self.presenter.previewAxis		= axis;
	self.presenter.previewInches	= inches;

	// At once, not coalesced: the frame has to keep up with the pointer.
	[self reload];

}//end partListView:previewingAxis:atInches:


//========== partListViewDidFinishResizing: ====================================
///
/// @abstract	The drag ended. One undoable edit, or none at all if the size
///				did not really change.
///
//==============================================================================
- (void) partListViewDidFinishResizing:(StepPartListView *)view
{
	if (self.presenter.hasSizePreview == NO) {
		return;
	}

	LDrawStep				*step	= [self.model visibleStep];
	LDrawStepPartListEdit	*edit	= [self previewEdit];

	self.presenter.hasSizePreview = NO;

	[self.delegate stepPartListController:self applyEdit:edit toStep:step];
	[self reload];

}//end partListViewDidFinishResizing:


//========== partListViewDidCancelResizing: ====================================
///
/// @abstract	The drag was abandoned. Nothing was written, so dropping the
///				preview undoes it.
///
//==============================================================================
- (void) partListViewDidCancelResizing:(StepPartListView *)view
{
	self.presenter.hasSizePreview = NO;
	[self reload];

}//end partListViewDidCancelResizing:


//========== partListView:didClickPinForAxis: ==================================
///
/// @abstract	A local pin was clicked: give the axis back to whatever it
///				inherits.
///
//==============================================================================
- (void) partListView:(StepPartListView *)view didClickPinForAxis:(LPubPliAxis)axis
{
	LDrawStep				*step	= [self.model visibleStep];
	LDrawStepPartListEdit	*edit	= [LDrawStepPartListEdit editClearingAxis:axis inStep:step];

	[self.delegate stepPartListController:self applyEdit:edit toStep:step];
	[self reload];

}//end partListView:didClickPinForAxis:


//========== partListViewDidClickPlacementPin: =================================
- (void) partListViewDidClickPlacementPin:(StepPartListView *)view
{
	[self.delegate stepPartListController:self
						applyAssemblyEdit:[LDrawStepAssemblyEdit editResettingListPlacementInModel:self.model]];
	[self reload];

}//end partListViewDidClickPlacementPin:


//========== previewEdit =======================================================
///
/// @abstract	The edit that letting go of the drag now would make.
///
//==============================================================================
- (LDrawStepPartListEdit *) previewEdit
{
	return [LDrawStepPartListEdit editForDraggingAxis:self.presenter.previewAxis
											 toInches:self.presenter.previewInches
											  inModel:self.model];

}//end previewEdit


// MARK: - CALLOUTS -


//========== menuItemsAtPoint: =================================================
///
/// @abstract	Makes the menu items for a right click at a point of the
///				overlay. Empty when there is nothing to offer there.
///
/// @discussion	LDrawStepEditing decides what to offer. Here each of its items
///				becomes an NSMenuItem with a localized title, and keeps the
///				edit to apply if it is chosen.
///
//==============================================================================
- (NSArray<NSMenuItem *> *) menuItemsAtPoint:(NSPoint)point
{
	NSMutableArray<NSMenuItem *>		*menuItems	= [NSMutableArray array];
	NSArray<LDrawStepCalloutMenuItem *>	*items		= nil;

	items = [LDrawStepCalloutMenuItem itemsAtPoint:V2Make(point.x, point.y)
									  presentation:self.presentation
											 model:self.model];

	for (LDrawStepCalloutMenuItem *item in items) {
		if (item.isSeparator) {
			[menuItems addObject:[NSMenuItem separatorItem]];
			continue;
		}

		NSString	*title		= [item titleFromLocalizedText:NSLocalizedString(item.titleKey, nil)];
		NSMenuItem	*menuItem	= [[NSMenuItem alloc] initWithTitle:title
															 action:@selector(applyEditOfMenuItem:)
													  keyEquivalent:@""];

		menuItem.target				= self;
		menuItem.representedObject	= item.edit;

		[menuItems addObject:menuItem];
	}

	// On the page the list can be put at a place of the page, or beside the
	// assembly. A callout's box over the list has the click.
	Point2 at = V2Make(point.x, point.y);

	if (self.presentation.isOnPage
		&& V2BoxContains(self.presentation.frameRect, at)
		&& [self.presentation calloutBoxAtPoint:at] == nil) {
		if (menuItems.count > 0) {
			[menuItems addObject:[NSMenuItem separatorItem]];
		}
		[menuItems addObject:[self listPositionMenuItem]];
	}

	return menuItems;

}//end menuItemsAtPoint:


//========== listPositionMenuItem ==============================================
///
/// @abstract	The Parts List Position submenu: the page's nine places, the
///				four sides of the assembly, and a reset to what the step
///				inherits. Each item keeps the edit it makes, for this step.
///
//==============================================================================
- (NSMenuItem *) listPositionMenuItem
{
	static const LPubPlacementPosition places[9] = {
		LPubPlacementPositionTopLeft,		LPubPlacementPositionTop,		LPubPlacementPositionTopRight,
		LPubPlacementPositionLeft,			LPubPlacementPositionCenter,	LPubPlacementPositionRight,
		LPubPlacementPositionBottomLeft,	LPubPlacementPositionBottom,	LPubPlacementPositionBottomRight
	};
	static const LPubPlacementPosition sides[4] = {
		LPubPlacementPositionLeft, LPubPlacementPositionRight, LPubPlacementPositionTop, LPubPlacementPositionBottom
	};

	NSArray<NSString *> *placeKeys = @[@"StepPartListPlaceTopLeft", @"StepPartListPlaceTop",
									   @"StepPartListPlaceTopRight", @"StepPartListPlaceLeft",
									   @"StepPartListPlaceMiddle", @"StepPartListPlaceRight",
									   @"StepPartListPlaceBottomLeft", @"StepPartListPlaceBottom",
									   @"StepPartListPlaceBottomRight"];
	NSArray<NSString *> *sideKeys = @[@"StepPartListBesideLeft", @"StepPartListBesideRight",
									  @"StepPartListBesideAbove", @"StepPartListBesideBelow"];

	LDrawModel	*model		= self.model;
	NSMenu		*submenu	= [[NSMenu alloc] initWithTitle:@""];

	for (NSUInteger index = 0; index < 9; index++) {
		LDrawStepAssemblyEdit *edit = [LDrawStepAssemblyEdit editPlacingListOnPageAt:places[index]
																			  offset:ZeroPoint2
																			   scope:LDrawStepAssemblyScopeStep
																			 inModel:model];
		[submenu addItem:[self menuItemWithTitleKey:placeKeys[index] edit:edit isPlace:YES]];
	}

	[submenu addItem:[NSMenuItem separatorItem]];

	for (NSUInteger index = 0; index < 4; index++) {
		LDrawStepAssemblyEdit *edit = [LDrawStepAssemblyEdit editPlacingListBesideAssemblyAt:sides[index]
																					   scope:LDrawStepAssemblyScopeStep
																					 inModel:model];
		[submenu addItem:[self menuItemWithTitleKey:sideKeys[index] edit:edit isPlace:YES]];
	}

	[submenu addItem:[NSMenuItem separatorItem]];
	[submenu addItem:[self menuItemWithTitleKey:@"StepPartListResetPosition"
										   edit:[LDrawStepAssemblyEdit editResettingListPlacementInModel:model]
										isPlace:NO]];

	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"StepPartListPosition", nil)
												  action:NULL
										   keyEquivalent:@""];
	item.submenu = submenu;

	return item;

}//end listPositionMenuItem


//========== menuItemWithTitleKey:edit:isPlace: ================================
///
/// @abstract	An item that applies an edit of the list's place. One that
///				would change nothing is grayed out, and checked when it is a
///				place the step already has.
///
//==============================================================================
- (NSMenuItem *) menuItemWithTitleKey:(NSString *)titleKey
								 edit:(LDrawStepAssemblyEdit *)edit
							  isPlace:(BOOL)isPlace
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(titleKey, nil)
												  action:edit.isEmpty ? NULL : @selector(applyAssemblyEditOfMenuItem:)
										   keyEquivalent:@""];

	item.target				= self;
	item.representedObject	= edit;

	if (edit.isEmpty && isPlace) {
		item.state = NSControlStateValueOn;
	}

	return item;

}//end menuItemWithTitleKey:edit:isPlace:


//========== applyAssemblyEditOfMenuItem: ======================================
- (void) applyAssemblyEditOfMenuItem:(NSMenuItem *)item
{
	[self.delegate stepPartListController:self applyAssemblyEdit:item.representedObject];
	[self reload];

}//end applyAssemblyEditOfMenuItem:


//========== applyEditOfMenuItem: ==============================================
///
/// @abstract	Runs when one of those menu items is chosen. Applies the item's
///				edit, then lays the step out again to show the change.
///
//==============================================================================
- (void) applyEditOfMenuItem:(NSMenuItem *)item
{
	[self applyCalloutEdit:item.representedObject];
	[self reload];

}//end applyEditOfMenuItem:


//========== applyCalloutEdit: =================================================
///
/// @abstract	Hands an edit to the document, which writes it into the step on
///				display so that it can be undone. Does nothing for nil.
///
//==============================================================================
- (void) applyCalloutEdit:(nullable LDrawStepCalloutEdit *)edit
{
	if (edit != nil) {
		[self.delegate stepPartListController:self applyCalloutEdit:edit toStep:[self.model visibleStep]];
	}

}//end applyCalloutEdit:


//========== showLayoutInTracker ===============================================
///
/// @abstract	Gives the tracker the callout boxes and the button that leads
///				back, as they are laid out now. Runs after every layout, and
///				when the button's title changes.
///
/// @discussion	The tracker follows clicks and drags on callouts. It needs the
///				current layout to know what the next press is on.
///
//==============================================================================
- (void) showLayoutInTracker
{
	NSRect	button		= [self.overlayView returnButtonRect];
	Box2	buttonBox	= StepPartListBoxFromRect(button);

	[self.calloutTracker showBoxes:self.presentation.calloutBoxes ?: @[]
							onPage:self.presentation.isOnPage
						  viewSize:[self overlaySize]
				  returnButtonRect:buttonBox];

}//end showLayoutInTracker


//========== actOnCalloutResult: ===============================================
///
/// @abstract	Carries out what the tracker decided about a mouse event on a
///				callout.
///
/// @discussion	A box being dragged is laid out again under the pointer. A
///				dropped box has its edit applied. A click is passed to the
///				document, which shows the called-out submodel or goes back.
///
/// @return		YES when the event was used, so the viewport does not get it.
///
//==============================================================================
- (BOOL) actOnCalloutResult:(LDrawStepCalloutTrackerResult)result
{
	LDrawStepCalloutTracker *tracker = self.calloutTracker;

	switch (result) {

		case LDrawStepCalloutTrackerResultNone:
			return NO;

		case LDrawStepCalloutTrackerResultUsed:
			return YES;

		case LDrawStepCalloutTrackerResultMoved:
			[[NSCursor closedHandCursor] set];
			self.showsControlCursor = YES;

			// Reload now, not on the next pass of the run loop, so the box
			// keeps up with the pointer.
			[self reload];
			return YES;

		case LDrawStepCalloutTrackerResultDropped: {
			NSArray<LDrawStepCalloutBox *>	*boxes	= self.presentation.calloutBoxes;
			NSUInteger						 index	= tracker.draggedBoxIndex;

			[self applyCalloutEdit:tracker.edit];
			[self restoreHostCursor];

			// The dropped box is the one the arrow keys move now.
			if (index < boxes.count) {
				[self selectItem:StepPartListSelectionCallout callout:boxes[index].callout.beginDirective];
			}

			[self reload];
			return YES;
		}

		case LDrawStepCalloutTrackerResultChoseCallout:
			[self restoreHostCursor];
			[self.delegate stepPartListController:self
								 didChooseCallout:tracker.chosenCallout
										 submodel:tracker.chosenSubmodel];
			return YES;

		case LDrawStepCalloutTrackerResultChoseReturn:
			[self restoreHostCursor];
			[self.delegate stepPartListControllerDidChooseReturn:self];
			return YES;
	}

	return NO;

}//end actOnCalloutResult:


// MARK: - EVENTS -


//========== startWatchingEvents ===============================================
///
/// @abstract	Routes the document window's events on the frame's controls to
///				the overlay.
///
/// @discussion	The overlay's window ignores the mouse so the model stays
///				clickable. This monitor sees the events first and keeps the ones
///				on an edge or a pin.
///
//==============================================================================
- (void) startWatchingEvents
{
	if (self.eventMonitor != nil) {
		return;
	}

	NSEventMask mask = NSEventMaskLeftMouseDown
					 | NSEventMaskLeftMouseDragged
					 | NSEventMaskLeftMouseUp
					 | NSEventMaskRightMouseDown
					 | NSEventMaskMouseMoved
					 | NSEventMaskKeyDown
					 | NSEventMaskKeyUp;

	__weak StepPartListController *weakSelf = self;

	self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
															  handler:^NSEvent *(NSEvent *event) {
		StepPartListController *controller = weakSelf;

		return (controller != nil) ? [controller handleEvent:event] : event;
	}];

}//end startWatchingEvents


//========== stopWatchingEvents ================================================
///
/// @abstract	Stops watching, abandoning any gesture in progress.
///
/// @discussion	Such a drag was never written to the document, so dropping the
///				preview cancels it.
///
//==============================================================================
- (void) stopWatchingEvents
{
	if (self.eventMonitor != nil) {
		[NSEvent removeMonitor:self.eventMonitor];
		self.eventMonitor = nil;
	}

	self.ownsGesture				= NO;
	self.pressesTurnedViewStrip		= NO;
	self.isNudging					= NO;
	self.selection					= StepPartListSelectionNone;
	self.presenter.hasSizePreview	= NO;
	self.presenter.hasListPreview	= NO;
	[self.calloutTracker reset];
	[self.listMoveTracker end];
	[self.scaleTracker end];

	[self restoreHostCursor];

}//end stopWatchingEvents


//========== handleEvent: ======================================================
///
/// @abstract	Takes the events that belong to the frame and passes on the
///				rest.
///
/// @return		nil when the frame used the event, so the viewport never sees
///				it. Otherwise the event itself.
///
//==============================================================================
- (NSEvent *) handleEvent:(NSEvent *)event
{
	StepPartListView	*overlay	= self.overlayView;
	NSWindow			*window		= [self.hostView window];

	if (overlay == nil || window == nil) {
		return event;
	}

	// A move by the arrow keys still shown is written before a press.
	if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown) {
		[self finishNudge];
	}

	// With Command on the page a click starts arranging, over the callouts
	// and the list too, and the viewport's own cursor says so.
	if ([self isArrangingStartEvent:event]) {
		if (event.type == NSEventTypeLeftMouseDown) {
			return [self handleArrangingStartClick:event atPoint:[self overlayPointForEvent:event]] ? nil : event;
		}
		[self restoreHostCursor];
		return event;
	}

	// A right click on a submodel in the list or on a callout's box opens a
	// menu, on the page and off it.
	if ([self handleMenuEvent:event]) {
		return nil;
	}

	// A callout's box and the button that leads back answer a click on the
	// page and off it, so they come before the frame's own controls.
	if ([self handleLinkEvent:event]) {
		return nil;
	}

	// Off the page the frame is not editable, so every other event belongs to
	// the model. Any cursor this controller set is given back.
	if (self.presentation.isOnPage == NO) {
		[self restoreHostCursor];
		return event;
	}

	// A gesture that started on the frame stays with it, wherever the pointer
	// goes. Anything else counts only in this document's window.
	if (self.ownsGesture == NO && event.window != window) {
		return event;
	}

	switch (event.type) {

		case NSEventTypeMouseMoved:
			return [self updateCursorForEvent:event] ? nil : event;

		case NSEventTypeLeftMouseDown: {
			NSPoint point = [self overlayPointForEvent:event];

			if (NSPointInRect(point, overlay.bounds) == NO) {
				return event;
			}

			// A press on the list selects it for the arrow keys. A press
			// anywhere else lets go of what they move.
			[self selectItem:StepPartListSelectionNone callout:nil];

			// The turned view's strip lies over everything else.
			if ([self beginTurnedViewPressAtPoint:point]) {
				[self updateCursorForEvent:event];
			}
			// While arranging, a handle on the step's frame scales the step.
			else if ([self beginScalingArrangedStepAtPoint:point]) {
				[self updateCursorForEvent:event];
			}
			else if ([overlay beginInteractionAtPoint:point]) {
				[self selectItem:StepPartListSelectionList callout:nil];
			}
			else {
				// Off the edges and pins, a press on the list moves it.
				if ([self.listMoveTracker beginAtPoint:V2Make(point.x, point.y) presentation:self.presentation] == NO) {
					return event;
				}

				[self selectItem:StepPartListSelectionList callout:nil];
				[[NSCursor closedHandCursor] set];
				self.showsControlCursor = YES;
			}

			// The viewport never sees this click, so give it the focus here.
			// A click on the frame would otherwise leave the focus wherever it
			// was, and the view's own menu commands would stay disabled.
			[window makeFirstResponder:self.hostView];

			self.ownsGesture = YES;
			return nil;
		}

		case NSEventTypeLeftMouseDragged:
			if (self.ownsGesture == NO) {
				return event;
			}
			if (self.pressesTurnedViewStrip) {
				return nil;
			}
			if (self.scaleTracker.isScaling) {
				[self scaleArrangedStepToPoint:[self overlayPointForEvent:event]];
				return nil;
			}
			if (self.listMoveTracker.isMoving) {
				[self moveListToPoint:[self overlayPointForEvent:event]];
				return nil;
			}
			[overlay continueResizingAtPoint:[self overlayPointForEvent:event]];
			return nil;

		case NSEventTypeLeftMouseUp:
			if (self.ownsGesture == NO) {
				return event;
			}
			self.ownsGesture = NO;
			if (self.pressesTurnedViewStrip) {
				[self endTurnedViewPressAtPoint:[self overlayPointForEvent:event] modifiers:event.modifierFlags];
			}
			[self.scaleTracker end];
			if (self.listMoveTracker.isMoving) {
				[self dropListWithModifiers:event.modifierFlags];
			}
			[overlay endResizingCommitting:YES];
			[self updateCursorForEvent:event];
			return nil;

		case NSEventTypeKeyDown:
			// Escape abandons the drag. The rest of the gesture is still
			// swallowed, until the mouse comes up.
			if (event.keyCode == ESCAPE_KEY_CODE) {
				if (overlay.isResizing) {
					[overlay endResizingCommitting:NO];
					return nil;
				}
				if (self.listMoveTracker.isMoving) {
					[self abandonListMove];
					return nil;
				}
				if (self.scaleTracker.isScaling) {
					[self abandonArrangedScale];
					return nil;
				}
			}
			if ([self handleNudgeKeyEvent:event]) {
				return nil;
			}
			return [self handleArrangingKeyEvent:event] ? nil : event;

		case NSEventTypeKeyUp:
			if ([self handleNudgeKeyUpEvent:event] || [self handlePreviousStepKeyUpEvent:event]) {
				return nil;
			}
			return event;

		default:
			return event;
	}

}//end handleEvent:


//========== handleMenuEvent: ==================================================
///
/// @abstract	Opens a menu for a right click on a submodel's row of the parts
///				list, or on a callout's box or one of the steps in it.
///
/// @return		YES when a menu is opened, so nothing else sees the click.
///
/// @discussion	A click with Control and nothing else counts too, as it does
///				in the viewport. Caps Lock is no part of a click.
///
//==============================================================================
- (BOOL) handleMenuEvent:(NSEvent *)event
{
	NSEventModifierFlags	modifiers	= event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask
										  & ~NSEventModifierFlagCapsLock;
	BOOL					isMenuClick	= (event.type == NSEventTypeRightMouseDown)
									   || (event.type == NSEventTypeLeftMouseDown
										   && modifiers == NSEventModifierFlagControl);
	LDrawView				*hostView	= self.hostView;

	if (isMenuClick == NO || event.window != [hostView window]) {
		return NO;
	}

	NSPoint point = [self overlayPointForEvent:event];

	if (NSPointInRect(point, self.overlayView.bounds) == NO) {
		return NO;
	}

	NSArray<NSMenuItem *> *items = [self menuItemsAtPoint:point];

	if (items.count == 0) {
		return NO;
	}

	NSMenu	*menu		= [[NSMenu alloc] initWithTitle:@""];
	NSPoint	 location	= [hostView convertPoint:event.locationInWindow fromView:nil];

	for (NSMenuItem *item in items) {
		[menu addItem:item];
	}

	// Once this event is done with: a menu runs an event loop of its own.
	dispatch_async(dispatch_get_main_queue(), ^{
		[menu popUpMenuPositioningItem:nil atLocation:location inView:hostView];
	});

	return YES;

}//end handleMenuEvent:


//========== handleLinkEvent: ==================================================
///
/// @abstract	Follows a click on a callout's box or on the button that leads
///				back, and moves a callout's box that is dragged.
///
/// @return		YES when the event was used, so neither the frame nor the
///				viewport should see it.
///
/// @discussion	The tracker decides what each event means. The drag between a
///				press and its release is kept from the viewport, or it would
///				start a selection.
///
//==============================================================================
- (BOOL) handleLinkEvent:(NSEvent *)event
{
	LDrawStepCalloutTracker	*tracker	= self.calloutTracker;
	NSPoint					 viewPoint	= [self overlayPointForEvent:event];
	Point2					 point		= V2Make(viewPoint.x, viewPoint.y);
	BOOL					 isInWindow	= (event.window == [self.hostView window]);

	switch (event.type) {

		case NSEventTypeMouseMoved:
			if (isInWindow == NO || [tracker isLinkAtPoint:point] == NO) {
				return NO;
			}
			[[NSCursor pointingHandCursor] set];
			self.showsControlCursor = YES;
			return YES;

		case NSEventTypeLeftMouseDown:
			if (isInWindow == NO) {
				[tracker reset];
				return NO;
			}
			if ([tracker beginAtPoint:point] == NO) {
				return NO;
			}

			// A box is selected once it is dropped. A click follows it.
			[self selectItem:StepPartListSelectionNone callout:nil];

			// The viewport never sees this click, so give it the focus here.
			[[self.hostView window] makeFirstResponder:self.hostView];
			return YES;

		case NSEventTypeLeftMouseDragged:
			return [self actOnCalloutResult:[tracker dragToPoint:point]];

		case NSEventTypeLeftMouseUp:
			return [self actOnCalloutResult:[tracker endAtPoint:point inStep:[self.model visibleStep]]];

		case NSEventTypeKeyDown:
			// Escape abandons the drag. The rest of the gesture is still
			// swallowed, until the mouse comes up.
			if (event.keyCode == ESCAPE_KEY_CODE && [tracker abandonDrag]) {
				[self reload];
				return YES;
			}
			return NO;

		default:
			return NO;
	}

}//end handleLinkEvent:


//========== overlayPointForEvent: =============================================
///
/// @abstract	Where an event happened, in the overlay view's coordinates.
///
/// @discussion	The event belongs to the document window and the overlay is in
///				a child window, so the point goes through the screen.
///
//==============================================================================
- (NSPoint) overlayPointForEvent:(NSEvent *)event
{
	StepPartListView	*overlay	= self.overlayView;
	NSPoint				 onScreen	= (event.window != nil)
									? [event.window convertPointToScreen:event.locationInWindow]
									: event.locationInWindow;
	NSPoint				 inWindow	= [[overlay window] convertPointFromScreen:onScreen];

	return [overlay convertPoint:inWindow fromView:nil];

}//end overlayPointForEvent:


//========== updateCursorForEvent: =============================================
///
/// @abstract	The cursor for what is under the pointer: a pointing hand over
///				a button of the turned view's strip or a pin, a resize cursor
///				over a handle of the arranged step or an edge of the list, and a
///				hand over the rest of the list on the page. The viewport's own
///				cursor comes back once the pointer leaves them.
///
/// @return		Whether the pointer is over one of the frame's controls.
///
/// @discussion	The overlay's window ignores the mouse, so the cursor is set by
///				hand. The viewport sets its own on entry only, so a cursor set
///				here stays until -resetCursor puts the viewport's back.
///
//==============================================================================
- (BOOL) updateCursorForEvent:(NSEvent *)event
{
	StepPartListView		*overlay	= self.overlayView;
	NSPoint					 point		= [self overlayPointForEvent:event];
	BOOL					 onOverlay	= NSPointInRect(point, overlay.bounds);
	NSCursor				*cursor		= onOverlay ? [overlay cursorAtPoint:point] : nil;
	Box2					 frame		= self.presentation.frameRect;
	LDrawStepArrangeHandle	 handle		= self.scaleTracker.handle;
	BOOL					 onStrip	= onOverlay && NSPointInRect(point, [overlay turnedViewStripRect]);

	// The turned view's strip lies over everything else.
	if (onStrip) {
		BOOL onButton = NSPointInRect(point, [overlay rectOfTurnedViewButton:LDrawStepTurnedViewButtonUseAngle])
					 || NSPointInRect(point, [overlay rectOfTurnedViewButton:LDrawStepTurnedViewButtonStepAngle]);

		cursor = onButton ? [NSCursor pointingHandCursor] : [NSCursor arrowCursor];
	}

	// While arranging, the step's handles come before the list's controls.
	if (onStrip == NO && handle == LDrawStepArrangeHandleNone && onOverlay && self.isArranging) {
		handle = [self.presentation arrangeHandleAtPoint:V2Make(point.x, point.y)];
	}
	if (handle != LDrawStepArrangeHandleNone) {
		cursor = [self cursorForArrangeHandle:handle];
	}

	// On the page the list can be dragged anywhere off its edges and pins.
	if (cursor == nil && onOverlay && self.presentation.isOnPage && V2BoxContains(frame, V2Make(point.x, point.y))) {
		cursor = self.listMoveTracker.isMoving ? [NSCursor closedHandCursor] : [NSCursor openHandCursor];
	}

	if (cursor != nil) {
		[cursor set];
		self.showsControlCursor = YES;
		return YES;
	}

	[self restoreHostCursor];
	return NO;

}//end updateCursorForEvent:


//========== restoreHostCursor =================================================
///
/// @abstract	Gives the viewport its own cursor back, if this controller had
///				replaced it.
///
//==============================================================================
- (void) restoreHostCursor
{
	if (self.showsControlCursor == NO) {
		return;
	}

	self.showsControlCursor = NO;
	[self.hostView resetCursor];

}//end restoreHostCursor


//========== moveListToPoint: ==================================================
///
/// @abstract	Holds the list where the drag has it, snapped to the page's
///				places. Nothing is written until the drop.
///
//==============================================================================
- (void) moveListToPoint:(NSPoint)point
{
	LDrawStepPartListMoveTracker	*tracker	= self.listMoveTracker;
	Point2							 held		= tracker.origin;

	[tracker dragToPoint:V2Make(point.x, point.y)];

	// The frame stays put before the drag starts and while it is snapped.
	if (tracker.origin.x == held.x && tracker.origin.y == held.y) {
		return;
	}

	self.presenter.hasListPreview		= YES;
	self.presenter.listPreviewOrigin	= tracker.origin;

	// At once, so the frame keeps up with the pointer.
	[self reload];

}//end moveListToPoint:


//========== dropListWithModifiers: ============================================
///
/// @abstract	Writes where the list was dropped, for this step, or with
///				Option for this step and the later ones.
///
//==============================================================================
- (void) dropListWithModifiers:(NSEventModifierFlags)modifiers
{
	LDrawStepPartListMoveTracker	*tracker	= self.listMoveTracker;
	LDrawStepAssemblyEdit			*edit		= [tracker editForDropInModel:self.model
																 scope:ScopeForModifiers(modifiers)];

	[tracker end];
	self.presenter.hasListPreview = NO;

	if (edit != nil && edit.isEmpty == NO) {
		[self.delegate stepPartListController:self applyAssemblyEdit:edit];
	}

	[self reload];

}//end dropListWithModifiers:


//========== abandonListMove ===================================================
- (void) abandonListMove
{
	[self.listMoveTracker end];
	self.presenter.hasListPreview = NO;
	[self reload];

}//end abandonListMove


// MARK: - THE SELECTED ITEM -


//========== selectItem:callout: ===============================================
///
/// @abstract	Makes this the item the arrow keys move, and outlines it. None
///				lets go of it.
///
//==============================================================================
- (void) selectItem:(StepPartListSelection)selection callout:(nullable LPubCallout *)callout
{
	self.selection			= selection;
	self.selectedCallout	= callout;

	[self showSelection];

}//end selectItem:callout:


//========== showSelection =====================================================
///
/// @abstract	Outlines the selected item as last laid out. One that is gone
///				from the page is no longer selected.
///
//==============================================================================
- (void) showSelection
{
	Box2 frame = [self selectedFrame];

	if (V2BoxWidth(frame) <= 0.0 || V2BoxHeight(frame) <= 0.0) {
		self.selection = StepPartListSelectionNone;
	}

	self.overlayView.selectionRect = StepPartListRectFromBox(frame);

}//end showSelection


//========== selectedFrame =====================================================
///
/// @abstract	The frame of the selected item, as last laid out. None while
///				arranging, when the arrow keys move the step.
///
//==============================================================================
- (Box2) selectedFrame
{
	LDrawStepPartListPresentation	*presentation	= self.presentation;
	NSUInteger						 boxIndex		= [self indexOfSelectedBox];

	if (self.isArranging || presentation.isOnPage == NO) {
		return ZeroBox2;
	}

	switch (self.selection) {
		case StepPartListSelectionList:
			return presentation.frameRect;

		case StepPartListSelectionCallout:
			return (boxIndex != NSNotFound) ? presentation.calloutBoxes[boxIndex].frameRect : ZeroBox2;

		case StepPartListSelectionNone:
			return ZeroBox2;
	}

	return ZeroBox2;

}//end selectedFrame


//========== indexOfSelectedBox ================================================
///
/// @abstract	Where the selected callout's box is among the step's boxes, or
///				NSNotFound when it is gone or the file does not place it.
///
//==============================================================================
- (NSUInteger) indexOfSelectedBox
{
	NSArray<LDrawStepCalloutBox *> *boxes = self.presentation.calloutBoxes;

	for (NSUInteger index = 0; index < boxes.count; index++) {
		if (boxes[index].callout.beginDirective == self.selectedCallout && boxes[index].isPlacedByFile) {
			return index;
		}
	}

	return NSNotFound;

}//end indexOfSelectedBox


//========== nudgedOrigin ======================================================
- (Point2) nudgedOrigin
{
	return V2Make(self.nudgeStart.x + self.nudgeDistance.x, self.nudgeStart.y + self.nudgeDistance.y);

}//end nudgedOrigin


//========== handleNudgeKeyEvent: ==============================================
///
/// @abstract	An arrow key moves the selected item on the page, further with
///				Shift. While the keys are held the move is a preview. Escape
///				drops a move still shown, or else lets go of the item.
///
/// @return		YES when the key was used, so the viewport does not move the
///				selected parts too.
///
//==============================================================================
- (BOOL) handleNudgeKeyEvent:(NSEvent *)event
{
	NSWindow				*window		= [self.hostView window];
	NSEventModifierFlags	 modifiers	= KeyModifiers(event);
	Vector2					 direction	= ArrowDirection(event.keyCode);
	double					 scale		= self.presentation.pointsPerPageInch;

	if (self.selection == StepPartListSelectionNone
		|| event.window != window
		|| self.ownsGesture
		|| [[window firstResponder] isKindOfClass:[NSText class]]) {
		return NO;
	}

	if (event.keyCode == ESCAPE_KEY_CODE && modifiers == 0) {
		if (self.isNudging) {
			[self abandonNudge];
		}
		else {
			[self selectItem:StepPartListSelectionNone callout:nil];
		}
		return YES;
	}

	if ((direction.x == 0.0 && direction.y == 0.0)
		|| (modifiers != 0 && modifiers != NSEventModifierFlagShift)
		|| scale <= 0.0) {
		return NO;
	}

	double inches = (modifiers == NSEventModifierFlagShift) ? SHIFT_NUDGE_INCHES : NUDGE_INCHES;

	if (self.isNudging == NO) {
		self.isNudging		= YES;
		self.nudgeStart		= [self selectedFrame].origin;
		self.nudgeDistance	= V2Make(0.0, 0.0);
		self.nudgeBoxIndex	= [self indexOfSelectedBox];
	}

	self.nudgeDistance = V2Make(self.nudgeDistance.x + direction.x * inches * scale,
								self.nudgeDistance.y + direction.y * inches * scale);

	// The list is held where the keys have it. A box is held by -reload.
	if (self.selection == StepPartListSelectionList) {
		self.presenter.hasListPreview		= YES;
		self.presenter.listPreviewOrigin	= [self nudgedOrigin];
	}

	// At once, so the item keeps up with a held key.
	[self reload];
	return YES;

}//end handleNudgeKeyEvent:


//========== handleNudgeKeyUpEvent: ============================================
///
/// @abstract	An arrow key came up: the move the keys made is written.
///
//==============================================================================
- (BOOL) handleNudgeKeyUpEvent:(NSEvent *)event
{
	Vector2 direction = ArrowDirection(event.keyCode);

	if (self.isNudging == NO || (direction.x == 0.0 && direction.y == 0.0)) {
		return NO;
	}

	[self finishNudge];
	return YES;

}//end handleNudgeKeyUpEvent:


//========== finishNudge =======================================================
///
/// @abstract	Writes the move the arrow keys made, as one undoable edit for
///				this step. Read from the layout the move is shown in, so what
///				is written is what is on screen.
///
//==============================================================================
- (void) finishNudge
{
	LDrawStepPartListPresentation	*presentation	= self.presentation;
	NSUInteger						 boxIndex		= self.nudgeBoxIndex;

	if (self.isNudging == NO) {
		return;
	}

	self.isNudging = NO;

	if (self.selection == StepPartListSelectionList) {
		LDrawStepAssemblyEdit *edit = nil;

		edit = [LDrawStepPartListMoveTracker editPlacingListAtOrigin:presentation.frameRect.origin
														presentation:presentation
															   scope:LDrawStepAssemblyScopeStep
															 inModel:self.model];
		self.presenter.hasListPreview = NO;

		if (edit != nil && edit.isEmpty == NO) {
			[self.delegate stepPartListController:self applyAssemblyEdit:edit];
		}
	}
	else if (self.selection == StepPartListSelectionCallout && boxIndex < presentation.calloutBoxes.count) {
		LDrawStepCalloutBox *box = presentation.calloutBoxes[boxIndex];

		[self applyCalloutEdit:[LDrawStepCalloutEdit editMovingBox:box
														  toOrigin:box.frameRect.origin
															inStep:[self.model visibleStep]]];
	}

	[self reload];

}//end finishNudge


//========== abandonNudge ======================================================
- (void) abandonNudge
{
	self.isNudging					= NO;
	self.presenter.hasListPreview	= NO;

	[self reload];

}//end abandonNudge


// MARK: - THE TURNED VIEW -


//========== beginTurnedViewPressAtPoint: ======================================
///
/// @abstract	Starts a press on the turned view's strip. A button acts when
///				the mouse comes up on it. The rest of the strip only keeps the
///				press from the model.
///
/// @return		NO when the point is not on the strip.
///
//==============================================================================
- (BOOL) beginTurnedViewPressAtPoint:(NSPoint)point
{
	StepPartListView *overlay = self.overlayView;

	self.pressedTurnedViewButton = NO_TURNED_VIEW_BUTTON;

	if (NSPointInRect(point, [overlay turnedViewStripRect]) == NO) {
		return NO;
	}

	if (NSPointInRect(point, [overlay rectOfTurnedViewButton:LDrawStepTurnedViewButtonUseAngle])) {
		self.pressedTurnedViewButton = LDrawStepTurnedViewButtonUseAngle;
	}
	else if (NSPointInRect(point, [overlay rectOfTurnedViewButton:LDrawStepTurnedViewButtonStepAngle])) {
		self.pressedTurnedViewButton = LDrawStepTurnedViewButtonStepAngle;
	}

	self.pressesTurnedViewStrip = YES;
	return YES;

}//end beginTurnedViewPressAtPoint:


//========== endTurnedViewPressAtPoint:modifiers: ==============================
///
/// @abstract	Acts on the button the press began on, when it ends there too.
///				Use This Angle writes the view's angle for this step, or with
///				Option for the later steps too.
///
//==============================================================================
- (void) endTurnedViewPressAtPoint:(NSPoint)point modifiers:(NSEventModifierFlags)modifiers
{
	NSInteger button = self.pressedTurnedViewButton;

	self.pressesTurnedViewStrip		= NO;
	self.pressedTurnedViewButton	= NO_TURNED_VIEW_BUTTON;

	if (button == NO_TURNED_VIEW_BUTTON
		|| NSPointInRect(point, [self.overlayView rectOfTurnedViewButton:button]) == NO) {
		return;
	}

	if (button == LDrawStepTurnedViewButtonStepAngle) {
		[self.delegate stepPartListControllerDidAskForStepAngle:self];
		return;
	}

	LDrawStepAssemblyEdit *edit = [LDrawStepAssemblyEdit editSettingViewingAngle:[self.hostView viewingAngle]
																		   scope:ScopeForModifiers(modifiers)
																		 inModel:self.model];

	if (edit == nil || edit.isEmpty) {
		NSBeep();
		return;
	}

	[self.delegate stepPartListController:self applyAssemblyEdit:edit];

}//end endTurnedViewPressAtPoint:modifiers:


// MARK: - ARRANGING EVENTS -


//========== isArrangingStartEvent: ============================================
///
/// @abstract	Whether a move or a press comes with Command alone in the
///				document's window, on the page, while the step is not arranged:
///				one that a Command-click starts arranging from.
///
//==============================================================================
- (BOOL) isArrangingStartEvent:(NSEvent *)event
{
	return (event.type == NSEventTypeMouseMoved || event.type == NSEventTypeLeftMouseDown)
		&& KeyModifiers(event) == NSEventModifierFlagCommand
		&& event.window == [self.hostView window]
		&& self.presentation.isOnPage
		&& self.isArranging == NO;

}//end isArrangingStartEvent:


//========== handleArrangingStartClick:atPoint: ================================
///
/// @abstract	A Command-click on the page starts arranging the step, wherever
///				it falls on the page. The caller has checked the click.
///
/// @return		YES when arranging was asked for, so the viewport does not see
///				the click.
///
/// @discussion	Command-drag turns the view, which the page does not allow
///				until the step is arranged, so the click is free there. The
///				rest of it is swallowed, up to the mouse-up, so the viewport
///				does not get half a click.
///
//==============================================================================
- (BOOL) handleArrangingStartClick:(NSEvent *)event atPoint:(NSPoint)point
{
	if (V2BoxContains(self.presentation.pageRect, V2Make(point.x, point.y)) == NO) {
		return NO;
	}

	[[self.hostView window] makeFirstResponder:self.hostView];
	self.ownsGesture = YES;

	[self.delegate stepPartListControllerDidAskToArrange:self];
	return YES;

}//end handleArrangingStartClick:atPoint:


//========== beginScalingArrangedStepAtPoint: ==================================
///
/// @abstract	Starts a drag of a handle on the frame around the step, while
///				it is arranged.
///
/// @return		NO when not arranging, or the point is not on a handle.
///
//==============================================================================
- (BOOL) beginScalingArrangedStepAtPoint:(NSPoint)point
{
	if (self.isArranging == NO) {
		return NO;
	}

	return [self.scaleTracker beginAtPoint:V2Make(point.x, point.y)
							  presentation:self.presentation
									 scale:self.presenter.arrangedScale];

}//end beginScalingArrangedStepAtPoint:


//========== scaleArrangedStepToPoint: =========================================
///
/// @abstract	Scales the step for the handle where the pointer is, snapped as
///				a zoom snaps. It is written when arranging is done.
///
//==============================================================================
- (void) scaleArrangedStepToPoint:(NSPoint)point
{
	[self.presenter zoomArrangedStepToScale:[self.scaleTracker scaleForDragToPoint:V2Make(point.x, point.y)]];

	// At once, so the model keeps up with the pointer.
	[self reload];

}//end scaleArrangedStepToPoint:


//========== abandonArrangedScale ==============================================
- (void) abandonArrangedScale
{
	self.presenter.arrangedScale = self.scaleTracker.startScale;
	[self.scaleTracker end];
	[self reload];

}//end abandonArrangedScale


//========== cursorForArrangeHandle: ===========================================
///
/// @abstract	The cursor over a handle: the system's frame resize cursor for
///				that corner, where there is one.
///
//==============================================================================
- (NSCursor *) cursorForArrangeHandle:(LDrawStepArrangeHandle)handle
{
	if (@available(macOS 15.0, *)) {
		NSCursorFrameResizePosition position = NSCursorFrameResizePositionTopLeft;

		switch (handle) {
			case LDrawStepArrangeHandleTopRight:	position = NSCursorFrameResizePositionTopRight;		break;
			case LDrawStepArrangeHandleBottomRight:	position = NSCursorFrameResizePositionBottomRight;	break;
			case LDrawStepArrangeHandleBottomLeft:	position = NSCursorFrameResizePositionBottomLeft;	break;
			default:																					break;
		}

		return [NSCursor frameResizeCursorFromPosition:position inDirections:NSCursorFrameResizeDirectionsAll];
	}

	return [NSCursor crosshairCursor];

}//end cursorForArrangeHandle:


//========== handleArrangingKeyEvent: ==========================================
///
/// @abstract	Return or Enter ends arranging and writes what was arranged.
///				Escape ends it and drops it. An arrow key moves the step on the
///				page, further with Shift.
///
/// @return		YES when the key was used, so nothing else sees it.
///
/// @discussion	Not while a text field is being edited, nor in the middle of
///				a drag on the frame or a box, which Escape abandons first. Any
///				other modifier makes the key someone else's.
///
//==============================================================================
- (BOOL) handleArrangingKeyEvent:(NSEvent *)event
{
	NSWindow				*window		= [self.hostView window];
	NSEventModifierFlags	 modifiers	= KeyModifiers(event);
	BOOL					 isShifted	= (modifiers == NSEventModifierFlagShift);

	if (self.isArranging == NO
		|| event.window != window
		|| self.ownsGesture
		|| self.calloutTracker.isDragging
		|| [[window firstResponder] isKindOfClass:[NSText class]]) {
		return NO;
	}

	// P shows the previous step while it is held. Its repeats are swallowed,
	// and so is P on the first step, which has none.
	if (IsPreviousStepKey(event) && modifiers == 0) {
		if (event.isARepeat == NO && self.hasPreviousStep) {
			self.isPeekingPreviousStep	= YES;
			self.peekStartTime			= event.timestamp;
			[self showPreviousStepAsAsked];
		}
		return YES;
	}

	switch (event.keyCode) {
		case RETURN_KEY_CODE:
		case ENTER_KEY_CODE:
			if (modifiers != 0) {
				return NO;
			}
			[self.delegate stepPartListControllerDidFinishArranging:self];
			return YES;

		case ESCAPE_KEY_CODE:
			if (modifiers != 0) {
				return NO;
			}
			[self.delegate stepPartListControllerDidCancelArranging:self];
			return YES;

		case LEFT_ARROW_KEY_CODE:
		case RIGHT_ARROW_KEY_CODE:
		case DOWN_ARROW_KEY_CODE:
		case UP_ARROW_KEY_CODE:
			if (modifiers != 0 && isShifted == NO) {
				return NO;
			}
			[self nudgeArrangedStepForKeyCode:event.keyCode
									 byInches:isShifted ? SHIFT_NUDGE_INCHES : NUDGE_INCHES];
			return YES;

		default:
			return NO;
	}

}//end handleArrangingKeyEvent:


//========== nudgeArrangedStepForKeyCode:byInches: =============================
///
/// @abstract	Moves the arranged step on the page the way an arrow key
///				points. Down is a larger offset, as the page's y runs down.
///
//==============================================================================
- (void) nudgeArrangedStepForKeyCode:(unsigned short)keyCode byInches:(double)inches
{
	Vector2 direction = ArrowDirection(keyCode);

	[self.presenter moveArrangedStepByInches:V2Make(direction.x * inches, direction.y * inches)];

	// At once, so the model keeps up with a held key.
	[self reload];

}//end nudgeArrangedStepForKeyCode:byInches:


//========== handlePreviousStepKeyUpEvent: =====================================
///
/// @abstract	P came up. After a tap the previous step is switched on or off,
///				and stays so. After a longer press it goes back to how it was.
///
//==============================================================================
- (BOOL) handlePreviousStepKeyUpEvent:(NSEvent *)event
{
	if (self.isPeekingPreviousStep == NO || IsPreviousStepKey(event) == NO) {
		return NO;
	}

	if (event.timestamp - self.peekStartTime < PREVIOUS_STEP_TAP_SECONDS) {
		self->_showsPreviousStep = (self.showsPreviousStep == NO);
	}

	self.isPeekingPreviousStep = NO;
	[self showPreviousStepAsAsked];
	return YES;

}//end handlePreviousStepKeyUpEvent:


// MARK: - UTILITIES -


//========== subscribeToChanges ================================================
///
/// @abstract	Everything that can change what the list should say.
///
//==============================================================================
- (void) subscribeToChanges
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

	for (NSString *name in @[LDrawDirectiveDidChangeNotification,
							 LDrawStepDidChangeNotification,
							 LDrawGroupSuppressionDidChangeNotification,
							 LDrawPartLibraryDidChangeNotification]) {

		[center addObserver:self
				   selector:@selector(setNeedsReloadForNotification:)
					   name:name
					 object:nil];
	}

}//end subscribeToChanges


//========== setNeedsReloadForNotification: ====================================
///
/// @abstract	Something the list depends on changed: the content, or the
///				overlay's size.
///
/// @discussion	These are observed for every document, so a change to a
///				directive in another file is ignored.
///
//==============================================================================
- (void) setNeedsReloadForNotification:(NSNotification *)notification
{
	// A resize of the overlay changes the layout and nothing else.
	if (notification.object != self.overlayView) {
		LDrawStepOverlayChange change = [self.presenter changeForChangedObject:notification.object];

		if (change == LDrawStepOverlayChangeNone) {
			return;
		}

		if (change & LDrawStepOverlayChangePictures) {
			[self.overlayView discardCalloutPictures];
		}

		// A part or a submodel the icons draw may have changed, and so may the
		// lines the arranged step inherits, which the next reload reads.
		[self.overlayView forgetIcons];
		self.needsInheritedValues	= YES;
		self.hasKeptRotation		= NO;
	}

	[self setNeedsReload];

}//end setNeedsReloadForNotification:


//========== cameraDidChange: ==================================================
///
/// @abstract	The viewport zoomed, scrolled or turned.
///
/// @discussion	The page and the frame on it follow the camera. Off the page
///				only the callouts' arrows do, since they point into the model.
///
//==============================================================================
- (void) cameraDidChange:(NSNotification *)notification
{
	LDrawStepOverlayChange change = [self.presenter changeForCameraMove];

	if (change & LDrawStepOverlayChangeLayout) {
		[self setNeedsReload];
	}
	else if (change & LDrawStepOverlayChangeArrows) {
		[self.overlayView setCalloutArrows:self.presenter.calloutArrows];
	}

}//end cameraDidChange:


@end
