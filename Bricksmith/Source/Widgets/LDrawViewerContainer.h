//
//  LDrawViewerContainer.h
//  Bricksmith
//
//  Created by Allen Smith on 1/9/21.
//

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawView;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class		LDrawViewerContainer
///
/// @abstract	Holds an LDrawView. You should always use an
/// 			LDrawViewerContainer instead of instantiating a 3D view
/// 			directly; this level of abstraction allows more flexibility in
/// 			decorating the view with other Cocoa components.
///
//------------------------------------------------------------------------------
@interface LDrawViewerContainer : NSView

@property (nonatomic, weak, readonly) LDrawView* glView;
@property (nonatomic) BOOL showsScrollbars;

/// The part of the container the 3D view fills: all of it but the scroll bars,
/// or the placard when there are none.
@property (nonatomic, readonly) NSRect contentRect;

- (void) setVerticalPlacard:(NSView *)placardView;
- (void) reflectLogicalDocumentRect:(Box2)newDocumentRect visibleRect:(Box2)visibleRect;

@end

NS_ASSUME_NONNULL_END
