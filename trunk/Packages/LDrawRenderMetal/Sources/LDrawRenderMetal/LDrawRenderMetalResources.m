//==============================================================================
//
//  File:       LDrawRenderMetalResources.m
//  Package:    LDrawRenderMetal
//
//  Purpose:    Resolves the NSBundle that contains LDrawRenderMetal's compiled
//              shader library and other packaged resources.
//
//  Info:       Uses the SwiftPM `SWIFTPM_MODULE_BUNDLE` macro when available,
//              otherwise locates the nested `<Target>_<Target>.bundle` beside
//              the class bundle.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawRenderMetal/LDrawRenderMetalResources.h>

@implementation LDrawRenderMetalResources

//---------- bundle -------------------------------------------------[static]--
//
// Purpose:		Return the bundle that owns default.metallib.
//
//				Prefers SWIFTPM_MODULE_BUNDLE when the package declares
//				resources. Otherwise looks for the nested
//				LDrawRenderMetal_LDrawRenderMetal.bundle beside the class
//				bundle.
//
//------------------------------------------------------------------------------
+ (NSBundle *)bundle
{
	// SwiftPM defines `SWIFTPM_MODULE_BUNDLE` for Obj-C and Swift targets
	// that declare `resources:`. Prefer it so the package owns default.metallib.
	NSBundle *classBundle = [NSBundle bundleForClass:[LDrawRenderMetalResources class]];

#ifdef SWIFTPM_MODULE_BUNDLE
	return SWIFTPM_MODULE_BUNDLE;
#else
	// Xcode local-package builds nest `<Target>_<Target>.bundle` beside the
	// class bundle. Prefer that; otherwise use the class bundle itself.
	NSURL *nestedURL = [classBundle URLForResource:@"LDrawRenderMetal_LDrawRenderMetal"
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


//---------- newDefaultLibraryForDevice: ----------------------------[static]--
//
// Purpose:		Load default.metallib from the package resource bundle.
//
//				Does not fall back to the app bundle. Logs the bundle path
//				and asserts in debug if the library is missing.
//
//------------------------------------------------------------------------------
+ (id<MTLLibrary>)newDefaultLibraryForDevice:(id<MTLDevice>)device
{
	NSBundle *bundle = [self bundle];
	NSError *error = nil;
	id<MTLLibrary> library = [device newDefaultLibraryWithBundle:bundle error:&error];
	if (library == nil) {
		NSLog(@"LDrawRenderMetal: failed to load default.metallib from bundle %@ (%@): %@",
			  bundle.bundleIdentifier, bundle.bundlePath, error);
		NSAssert(NO, @"LDrawRenderMetal shaders live in the package resource bundle, not the app bundle");
	}
	return library;
}

@end
