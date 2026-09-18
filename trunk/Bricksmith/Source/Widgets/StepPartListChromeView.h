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

@class LDrawStepPartListLayout;

NS_ASSUME_NONNULL_BEGIN

/// Makes an AppKit color from the four sRGB floats a policy color uses.
extern NSColor *StepPartListColorFromRGBA(const double *rgba);

/// Makes an AppKit rect from a layout box.
extern NSRect StepPartListRectFromBox(Box2 box);

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

@end

NS_ASSUME_NONNULL_END
