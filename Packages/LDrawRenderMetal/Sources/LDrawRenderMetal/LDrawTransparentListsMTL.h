//==============================================================================
//
//  File:       LDrawTransparentListsMTL.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    The per-pixel lists a renderer puts its transparent fragments
//              in, so each pixel can blend them in depth order.
//
//  Created by Sergey Slobodenyuk on 2026-10-23.
//
//==============================================================================
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>

#include <LDrawRenderMetal/MetalCommonDefinitions.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawTransparentLists : NSObject

/// YES when the GPU can keep the lists. They need raster order groups, and a
/// tile shader to empty them inside the render pass.
+ (BOOL)isSupported;

/// YES when the lists can have more room than a frame drawn with this uniform
/// had. When they cannot, drawing again does not help.
+ (BOOL)canGrowBeyondUniform:(struct TransparencyUniform)uniform;

/// Starts a frame, which has found no transparent parts yet.
- (void)beginFrame;

/// Gets the lists ready for a frame of this many pixels, when it finds
/// transparent parts: room for what the last frames needed, and counters at
/// 0. The render pass must empty the heads before it puts fragments in.
/// Returns NO when the surface is too big for the lists or a buffer cannot be
/// made; the frame must then blend its transparent parts without them.
- (BOOL)prepareForPixelSize:(CGSize)pixelSize;

/// Whether the frame since beginFrame found transparent parts, and whether it
/// put them into the lists.
@property (nonatomic, readonly) BOOL frameHasTransparentParts;
@property (nonatomic, readonly) BOOL frameUsesLists;

/// The bytes the list buffers take.
@property (nonatomic, readonly) NSUInteger memoryLength;

/// Lets go of the buffers, but keeps how much room the last frame needed.
- (void)releaseBuffers;

/// Lets go of the fragment buffer when the last finished frame needed under
/// half of it. For a view that has stopped drawing.
- (void)releaseUnneededRoom;

/// Notes how many fragments a finished frame needed, from the counters and
/// uniform it was drawn with, and takes the counters back for a later frame.
/// Call it once for each frame that used the lists. Returns YES when some
/// fragments did not fit, so the frame is missing them; the next frame has
/// room for them. Safe on any thread.
- (BOOL)finishFrameWithCounters:(id<MTLBuffer>)counters uniform:(struct TransparencyUniform)uniform;

// The current frame's buffers and settings, for the shaders.
@property (nonatomic, readonly) id<MTLBuffer>				heads;
@property (nonatomic, readonly) id<MTLBuffer>				fragments;
@property (nonatomic, readonly) id<MTLBuffer>				counters;
@property (nonatomic, readonly) struct TransparencyUniform	uniform;

@end

NS_ASSUME_NONNULL_END
