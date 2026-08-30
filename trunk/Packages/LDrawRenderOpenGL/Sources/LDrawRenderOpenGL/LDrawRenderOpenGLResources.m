//==============================================================================
//
//  File:       LDrawRenderOpenGLResources.m
//  Package:    LDrawRenderOpenGL
//
//  Purpose:    Resolves the NSBundle that contains LDrawRenderOpenGL's GLSL
//              shader sources and other packaged resources.
//
//  Info:       Uses the SwiftPM `SWIFTPM_MODULE_BUNDLE` macro when available,
//              otherwise locates the nested `<Target>_<Target>.bundle` beside
//              the class bundle.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import "LDrawRenderOpenGLResources.h"

@implementation LDrawRenderOpenGLResources

//---------- bundle -------------------------------------------------[static]--
//
// Purpose:		Return the bundle that owns this package's GLSL shader
//				sources.
//
//				Prefers SWIFTPM_MODULE_BUNDLE when the package declares
//				resources. Otherwise looks for the nested
//				LDrawRenderOpenGL_LDrawRenderOpenGL.bundle beside the class
//				bundle.
//
//------------------------------------------------------------------------------
+ (NSBundle *)bundle
{
	NSBundle *classBundle = [NSBundle bundleForClass:[LDrawRenderOpenGLResources class]];

#ifdef SWIFTPM_MODULE_BUNDLE
	return SWIFTPM_MODULE_BUNDLE;
#else
	NSURL *nestedURL = [classBundle URLForResource:@"LDrawRenderOpenGL_LDrawRenderOpenGL"
									 withExtension:@"bundle"];
	if (nestedURL != nil) {
		NSBundle *nested = [NSBundle bundleWithURL:nestedURL];
		if (nested != nil) {
			return nested;
		}
	}
	return classBundle;
#endif
}

@end
