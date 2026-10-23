//==============================================================================
//
//  File:       LDrawTransparentListsMTL.m
//  Package:    LDrawRenderMetal
//
//  Purpose:    The per-pixel lists a renderer puts its transparent fragments
//              in, so each pixel can blend them in depth order.
//
//              Each pixel has the index of its first fragment, and each
//              fragment the index of the next. Counters hand out the room for
//              fragments, and a frame that needs more than there is gets more
//              for the next frame. The render pass empties the heads itself,
//              with a tile shader, so the lists are made only when a frame
//              finds transparent parts.
//
//              A frame takes its counters from those that finished frames gave
//              back, so a frame still on the GPU keeps its own.
//
//  Created by Sergey Slobodenyuk on 2026-10-23.
//
//==============================================================================

#import "LDrawTransparentListsMTL.h"

#import <os/lock.h>
#import <stdatomic.h>

#import <LDrawRenderMetal/MetalGPU.h>

// At first there is room for a fragment for every other pixel.
static const NSUInteger	PixelsPerInitialFragment	= 2;
static const NSUInteger	MinimumFragmentCount		= 64 * 1024;
static const NSUInteger	MaximumFragmentBytes		= 1024 * 1024 * 1024;
// A head for each pixel of 8192 x 8192. A bigger surface blends its
// transparent parts one at a time.
static const NSUInteger	MaximumHeadBytes			= 256 * 1024 * 1024;
// Frames in a row that use under a third of the room before it shrinks.
static const NSUInteger	FramesBeforeShrinking		= 30;


@implementation LDrawTransparentLists
{
	CGSize							headsSize;
	NSUInteger						capacity;		// fragments
	NSUInteger						quietFrames;
	atomic_ulong					neededPer1024;	// fragments the last finished frame needed for 1024 pixels

	// Counters that finished frames gave back. Frames finish on another thread.
	os_unfair_lock					spareCountersLock;
	NSMutableArray<id<MTLBuffer>>	*spareCounters;
}


//========== init ==============================================================
//
// Purpose:		Lists with no buffers yet.
//
//==============================================================================
- (instancetype)init
{
	self = [super init];

	if (self)
	{
		spareCountersLock	= OS_UNFAIR_LOCK_INIT;
		spareCounters		= [NSMutableArray new];
	}

	return self;

} // end init


//---------- isSupported --------------------------------------------[static]--
//
// Purpose:		Whether the GPU can keep the lists. A pixel's fragments must
//				be in its list before the blend reads it, and a tile shader
//				empties the lists inside the render pass. That takes an Apple
//				GPU.
//
//------------------------------------------------------------------------------
+ (BOOL)isSupported
{
	id<MTLDevice> device = MetalGPU.device;

	return [device areRasterOrderGroupsSupported] && [device supportsFamily:MTLGPUFamilyApple4];

} // end isSupported


//---------- maximumFragmentCount -----------------------------------[static]--
//
// Purpose:		The most fragments the lists ever make room for, in equal
//				slices for the counters.
//
//------------------------------------------------------------------------------
+ (NSUInteger)maximumFragmentCount
{
	NSUInteger bytes = MIN(MaximumFragmentBytes, MetalGPU.device.maxBufferLength);

	return bytes / TransparentFragmentSize / TransparentCounterCount * TransparentCounterCount;

} // end maximumFragmentCount


//---------- canGrowBeyondUniform: ----------------------------------[static]--
//
// Purpose:		Whether the lists can have more room than a frame drawn with
//				this uniform had.
//
//------------------------------------------------------------------------------
+ (BOOL)canGrowBeyondUniform:(struct TransparencyUniform)uniform
{
	return (NSUInteger)uniform.slice * TransparentCounterCount < [self maximumFragmentCount];

} // end canGrowBeyondUniform:


//========== beginFrame ========================================================
//
// Purpose:		Starts a frame, which has found no transparent parts yet.
//
//==============================================================================
- (void)beginFrame
{
	_frameHasTransparentParts	= NO;
	_frameUsesLists				= NO;

} // end beginFrame


//========== prepareForPixelSize: ==============================================
//
// Purpose:		Gets the lists ready for a frame of this many pixels, which has
//				found transparent parts. Returns NO when the surface is too big
//				or a buffer cannot be made; the frame must not use the lists
//				then.
//
//==============================================================================
- (BOOL)prepareForPixelSize:(CGSize)pixelSize
{
	id<MTLDevice>	device		= MetalGPU.device;
	NSUInteger		width		= (NSUInteger)pixelSize.width;
	NSUInteger		height		= (NSUInteger)pixelSize.height;
	NSUInteger		headsLength	= MAX(width * height, 1) * sizeof(uint32_t);

	// Metal tracks these buffers, so the next frame does not empty or fill
	// them before this one has blended them.
	MTLResourceOptions options = MTLResourceStorageModePrivate | MTLResourceHazardTrackingModeTracked;

	_frameHasTransparentParts = YES;

	if (headsLength > MIN(MaximumHeadBytes, device.maxBufferLength)) {
		return NO;
	}

	NSUInteger wanted = [self capacityForPixelCount:width * height];

	if (_heads == nil || CGSizeEqualToSize(pixelSize, headsSize) == NO)
	{
		_heads			= [device newBufferWithLength:headsLength options:options];
		_heads.label	= @"Transparent list heads";
		headsSize		= pixelSize;
	}

	if (_fragments == nil || wanted != capacity)
	{
		_fragments			= [device newBufferWithLength:wanted * TransparentFragmentSize options:options];
		_fragments.label	= @"Transparent fragments";
		capacity			= wanted;
	}

	// A buffer that could not be made is tried again next frame.
	if (_heads == nil || _fragments == nil) {
		return NO;
	}

	_counters = [self takeCounters];

	if (_counters == nil) {
		return NO;
	}

	memset(_counters.contents, 0, _counters.length);

	_uniform.width	= (unsigned int)width;
	_uniform.height	= (unsigned int)height;
	_uniform.slice	= (unsigned int)(capacity / TransparentCounterCount);
	_frameUsesLists	= YES;

	return YES;

} // end prepareForPixelSize:


//========== takeCounters ======================================================
//
// Purpose:		Counters for a new frame: ones a finished frame gave back, or
//				new ones.
//
//==============================================================================
- (id<MTLBuffer>)takeCounters
{
	NSUInteger		length		= TransparentCounterCount * TransparentCounterStride * sizeof(uint32_t);
	id<MTLBuffer>	counters	= nil;

	os_unfair_lock_lock(&spareCountersLock);
	counters = spareCounters.lastObject;
	[spareCounters removeLastObject];
	os_unfair_lock_unlock(&spareCountersLock);

	if (counters == nil)
	{
		counters		= [MetalGPU.device newBufferWithLength:length options:MTLResourceStorageModeShared];
		counters.label	= @"Transparent fragment counters";
	}

	return counters;

} // end takeCounters


//========== memoryLength ======================================================
//
// Purpose:		The bytes the list buffers take.
//
//==============================================================================
- (NSUInteger)memoryLength
{
	return _heads.length + _fragments.length;

} // end memoryLength


//========== releaseBuffers ====================================================
//
// Purpose:		Lets go of the buffers. The next frame makes them anew, with
//				room for what the last frame needed, so it does not run out
//				first.
//
//==============================================================================
- (void)releaseBuffers
{
	_heads		= nil;
	_fragments	= nil;
	_counters	= nil;
	capacity	= 0;

} // end releaseBuffers


//========== releaseUnneededRoom ===============================================
//
// Purpose:		Lets go of the fragment buffer when the last finished frame
//				needed under half of it. The next frame makes one that fits.
//
// Notes:		For a view that has stopped drawing: frames shrink the buffer
//				only after a run of them that use under a third of it.
//
//==============================================================================
- (void)releaseUnneededRoom
{
	NSUInteger	pixelCount	= (NSUInteger)headsSize.width * (NSUInteger)headsSize.height;
	NSUInteger	needed		= atomic_load(&neededPer1024) * pixelCount / 1024;

	if (	_fragments != nil
		&&	needed < capacity / 2
		&&	capacity > [LDrawTransparentLists initialCapacityForPixelCount:pixelCount])
	{
		_fragments	= nil;
		capacity	= 0;
		quietFrames	= 0;
	}

} // end releaseUnneededRoom


//---------- initialCapacityForPixelCount: --------------------------[static]--
//
// Purpose:		The fragments the lists first make room for.
//
//------------------------------------------------------------------------------
+ (NSUInteger)initialCapacityForPixelCount:(NSUInteger)pixelCount
{
	return MAX(MinimumFragmentCount, pixelCount / PixelsPerInitialFragment);

} // end initialCapacityForPixelCount:


//========== capacityForPixelCount: ============================================
//
// Purpose:		The fragments to make room for: what the last frame needed and
//				half as much again, so a view that zooms in does not run out on
//				every frame. What it needed is kept per pixel, so a surface of
//				another size gets as much for its size.
//
// Notes:		It shrinks only after a while of using little of the room, so
//				a view that zooms in and out does not make a new buffer each
//				time.
//
//==============================================================================
- (NSUInteger)capacityForPixelCount:(NSUInteger)pixelCount
{
	NSUInteger	needed	= atomic_load(&neededPer1024) * pixelCount / 1024;
	NSUInteger	initial	= [LDrawTransparentLists initialCapacityForPixelCount:pixelCount];
	NSUInteger	maximum	= [LDrawTransparentLists maximumFragmentCount];
	NSUInteger	wanted	= MAX(capacity, initial);

	if (needed > wanted / 8 * 7)
	{
		wanted		= needed / 2 * 3;
		quietFrames	= 0;
	}
	else if (needed < wanted / 3 && wanted > initial)
	{
		if (++quietFrames >= FramesBeforeShrinking)
		{
			wanted		= MAX(initial, needed / 2 * 3);
			quietFrames	= 0;
		}
	}
	else
	{
		quietFrames = 0;
	}

	wanted = MIN(wanted, maximum);

	// Each counter gets a slice of the same size.
	return wanted / TransparentCounterCount * TransparentCounterCount;

} // end capacityForPixelCount:


//========== finishFrameWithCounters:uniform: ==================================
//
// Purpose:		Notes how many fragments a finished frame needed, and takes its
//				counters back for a later frame. Returns YES when some did not
//				fit.
//
// Notes:		A counter keeps counting past its slice, so it tells how much
//				it needed. The busiest one decides, since the slices are all of
//				one size.
//
//				Past its slice a counter counts each sample of a fragment that
//				found no room: no fragment was made for the samples to share.
//				So that part is divided by the samples in a pixel.
//
//==============================================================================
- (BOOL)finishFrameWithCounters:(id<MTLBuffer>)counters uniform:(struct TransparencyUniform)uniform
{
	const uint32_t	*counts	= counters.contents;
	NSUInteger		most	= 0;
	BOOL			ranOut	= NO;

	for (NSUInteger index = 0; index < TransparentCounterCount; ++index)
	{
		NSUInteger taken = counts[index * TransparentCounterStride];

		if (taken > uniform.slice)
		{
			taken	= uniform.slice + (taken - uniform.slice) / MSAASampleCount;
			ranOut	= YES;
		}

		most = MAX(most, taken);
	}

	NSUInteger pixels = MAX((NSUInteger)uniform.width * uniform.height, 1);

	atomic_store(&neededPer1024, most * TransparentCounterCount * 1024 / pixels);

	os_unfair_lock_lock(&spareCountersLock);
	[spareCounters addObject:counters];
	os_unfair_lock_unlock(&spareCountersLock);

	return ranOut;

} // end finishFrameWithCounters:uniform:


@end
