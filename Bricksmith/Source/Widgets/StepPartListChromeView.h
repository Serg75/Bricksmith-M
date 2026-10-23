//==============================================================================
//
// File:		StepPartListChromeView.h
//
// Purpose:		Draws everything in the step parts list that is not a part:
//				quantity labels, stud badges, placeholders for missing parts
//				and the truncation notice.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawCore/MatrixMath.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

@class LDrawStepCalloutText;
@class LDrawStepPartListLayout;

NS_ASSUME_NONNULL_BEGIN

/// Makes an AppKit color from the four sRGB floats a policy color uses.
extern NSColor *StepPartListColorFromRGBA(const double *rgba);

/// Makes an AppKit rect from a layout box, and back.
extern NSRect StepPartListRectFromBox(Box2 box);
extern Box2 StepPartListBoxFromRect(NSRect rect);

////////////////////////////////////////////////////////////////////////////////
//
// class StepPartListChromeView
//
////////////////////////////////////////////////////////////////////////////////

/// Sits above the nested 3D view, so its text draws on top of the icons. It
/// is flipped, to match the layout coordinates.
@interface StepPartListChromeView : NSView

@property (nonatomic, strong, nullable) LDrawStepPartListLayout *layout;
@property (nonatomic) LDrawStepPartListChrome chrome;

/// The font the counts are written in on LPub3D's page. Nil off the page.
@property (nonatomic, strong, nullable) LDrawStepCalloutText *countText;

/// The font the size badges are written in on LPub3D's page. Nil off the page,
/// and for a file that gives none.
@property (nonatomic, strong, nullable) LDrawStepCalloutText *annotationText;

@end

NS_ASSUME_NONNULL_END
