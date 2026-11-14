//==============================================================================
//
// File:		DownloadProgressPanel.h
//
// Purpose:		Shows a download's progress in a sheet, or in a panel of its
//				own without a window.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//==============================================================================
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// class DownloadProgressPanel
//
////////////////////////////////////////////////////////////////////////////////
@interface DownloadProgressPanel : NSObject

// Shows a small panel with a bar, the message and Cancel, as a sheet on the
// window or on its own. Once the progress is complete the bar spins and the
// text is the finishing message, for the work after a download that reports no
// progress. On its own, the panel takes the keyboard only when makeKey is YES.
// Otherwise it floats over the windows, so Esc in a model does not cancel it.
- (instancetype) initWithProgress:(NSProgress *)progress
						   window:(nullable NSWindow *)window
						  makeKey:(BOOL)makeKey
						  message:(NSString *)message
				 finishingMessage:(NSString *)finishingMessage;
- (void) close;

@end

NS_ASSUME_NONNULL_END
