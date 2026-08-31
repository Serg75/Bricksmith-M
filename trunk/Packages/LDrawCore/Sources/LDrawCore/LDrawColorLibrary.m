//==============================================================================
//
//  File:       LDrawColorLibrary.m
//  Package:    LDrawCore
//
//  Purpose:    A repository of methods and functions used to select LDraw
//              colors. An LDraw color is defined by an index between 0-511.
//              They have been chosen somewhat arbirarily over LDraw's history.
//
//              In Bricksmith, the color is represented by the enumeration
//              LDrawColorT, which can be translated into RGBA or an NSColor by
//              functions found here.
//
//              The original LDraw (and other compliant modellers) support
//              dithering of basic colors. As these dithered colors do not
//              represent real Lego hues, I have chosen not to bother
//              supporting them here.
//
//  Created by Allen Smith on 2/26/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawColorLibrary.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPaths.h>

@implementation LDrawColorLibrary

static LDrawColorLibrary	*sharedColorLibrary	= nil;


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- sharedColorLibrary --------------------------------------[static]--
//
// Purpose:		Returns the global color library available to all LDraw objects. 
//				The colors are dynamically read from ldconfig.ldr. 
//
//------------------------------------------------------------------------------
+ (LDrawColorLibrary *)sharedColorLibrary
{
	NSString    *ldconfigPath   = nil;
	LDrawFile   *ldconfigFile   = nil;

	if (sharedColorLibrary == nil)
	{
		//---------- Read colors in ldconfig.ldr -------------------------------
		
		// Read it in.
		ldconfigPath		= [[LDrawPaths sharedPaths] ldconfigPath];
		ldconfigFile		= [LDrawFile fileFromContentsAtPath:ldconfigPath];
		
		[ldconfigFile collectColorsFromConfig];

		sharedColorLibrary	= [[ldconfigFile activeModel] colorLibrary];
		
		
		//---------- Special Colors --------------------------------------------
		// These meta-colors are chameleons that are interpreted based on the 
		// context. But we still need to create entries for them in the library 
		// so that they can be selected in the color palette. 
		
		LDrawColor	*currentColor			= [[LDrawColor alloc] init];
		LDrawColor	*edgeColor				= [[LDrawColor alloc] init];
		float		 currentColorRGBA[4]	= {1.0, 1.0, 0.81, 1.0};
		float		 edgeColorRGBA[4]		= {0.75, 0.75, 0.75, 1.0};
		
		// Make the "current color" a blah sort of beige. We display parts in 
		// the part browser using this "color"; that's the only time we'll ever 
		// see it. 
		[currentColor	setColorCode:LDrawCurrentColor];
		[currentColor	setColorRGBA:currentColorRGBA];
		
		// The edge color is never seen in models, but it still appears in the 
		// color panel, so we need to give it something. 
		[edgeColor		setColorCode:LDrawEdgeColor];
		[edgeColor		setColorRGBA:edgeColorRGBA];
		
		// Register both special colors in the library
		[sharedColorLibrary addColor:currentColor];
		[sharedColorLibrary addColor:edgeColor];
		
		
		//---------- Dithered Colors -------------------------------------------
		// I'm only providing these to be a nice team player in the LDraw world.
		
		LDrawColor  *blendedColor   = nil;
		int         counter         = 0;
		
		// Provide dithered colors for the entire valid range from LDRAW.EXE
		for (counter = 256; counter <= 511; counter++)
		{
			blendedColor = [LDrawColor blendedColorForCode:counter];
			[sharedColorLibrary addPrivateColor:blendedColor];
		}
	}
	
	return sharedColorLibrary;
	
} // end sharedColorLibrary


//========== init ==============================================================
//
// Purpose:		Initialize the object.
//
//==============================================================================
- (id)init
{
	self = [super init];
	
	colors = [[NSMutableDictionary alloc] init];
	
	return self;

} // end init


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== colors ============================================================
//
// Purpose:		Returns a list of the LDrawColor objects registered in this 
//				library. 
//
// Notes:		This does NOT return the private colors, because we are 
//				embarassed they even exist, and definitely don't want to let 
//				them slip to the outside world (especially the color picker!) 
//
//==============================================================================
- (NSArray *)colors
{
	return [self->colors allValues];
	
} // end LDrawColors


//========== colorForCode: =====================================================
//
// Purpose:		Returns the LDrawColor object representing colorCode, or nil if 
//				no such color number is registered. This method also searches 
//				the shared library, since its colors have global scope. 
//
//==============================================================================
- (LDrawColor *)colorForCode:(LDrawColorT)colorCode
{
	NSNumber	*key	= @(colorCode);
	LDrawColor	*color	= [self->colors objectForKey:key];
	
	// Try searching the private colors.
	if (color == nil)
	{
		color = [self->privateColors objectForKey:key];
	}
	
	// Try the shared library.
	if (color == nil && self != sharedColorLibrary)
	{
		color = [[LDrawColorLibrary sharedColorLibrary] colorForCode:colorCode];
	}
	
	// Return something!
	if (color == nil)
	{
		color = [[LDrawColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor];
	}
	
	return color;
	
} // end colorForCode:


//========== complimentColorForCode: ===========================================
//
// Purpose:		Returns the color that should be used when the compliment color 
//				is requested for the given code. Compliment colors are usually 
//				used to draw lines on the edges of parts. 
//
// Notes:		It may seem odd to have the method in the Color Library rather 
//				than the color object itself. The reason is that a color may 
//				specify its compliment color either as actual color components 
//				or as another color code. Since colors have no actual knowledge 
//				of the library in which they are contained, we must look up the 
//				actual code here. 
//
//				Also note that the default ldconfig.ldr file defines most 
//				compliment colors as black, which is well and good for printed 
//				instructions, but less than stellar for onscreen display. The 
//				visual looks a lot more realistic when red has an edge color of, 
//				say, pink. 
//
//==============================================================================
- (void)getComplimentRGBA:(float *)complimentRGBA
				  forCode:(LDrawColorT)colorCode
{
	LDrawColor	*mainColor		= [self colorForCode:colorCode];
	LDrawColorT	 edgeColorCode	= LDrawColorBogus;
	
	if (mainColor != nil)
	{
		edgeColorCode	= [mainColor edgeColorCode];
		
		// If the color has a defined RGBA edge color, use it. Otherwise, look 
		// up the components of the color it points to. 
		if (edgeColorCode == LDrawColorBogus)
			[mainColor getEdgeColorRGBA:complimentRGBA];
		else
			[[self colorForCode:edgeColorCode] getColorRGBA:complimentRGBA];
	}
	
} // end complimentColorForCode:


#pragma mark -
#pragma mark REGISTERING COLORS
#pragma mark -

//========== addColor: =========================================================
//
// Purpose:		Adds the given color to the receiver.
//
//==============================================================================
- (void)addColor:(LDrawColor *)newColor
{
	LDrawColorT	 colorCode	= [newColor colorCode];
	NSNumber	*key		= @(colorCode);

	[self->colors setObject:newColor forKey:key];
	
} // end addColor:


//========== addPrivateColor: ==================================================
//
// Purpose:		Adds the given color to the receiver, but doesn't make it 
//				visible to the color picker. 
//
// Notes:		This supports LDRAW.EXE's "dithered" colors, which sadly wormed 
//				their way into the part library, but should absolutely never be 
//				used in modeling. Keeping the "private" allows us to display 
//				old parts which may have been created with them without allowing 
//				them to otherwise pollute the user experience. 
//
//==============================================================================
- (void)addPrivateColor:(LDrawColor *)newColor
{
	LDrawColorT	 colorCode	= [newColor colorCode];
	NSNumber	*key		= @(colorCode);
	
	// Allocate if it doesn't exist. 
	if (self->privateColors == nil)
		self->privateColors = [[NSMutableDictionary alloc] init];

	[self->privateColors setObject:newColor forKey:key];
	
} // end addPrivateColor:


//---------- indexOfColor:inColors: ----------------------------------[static]--
//
// Purpose:		Returns the row index of colorCodeSought in the panel's table,
//				or NSNotFound if colorCodeSought is not displayed.
//
//------------------------------------------------------------------------------
+ (NSInteger)indexOfColor:(LDrawColor *)colorSought inColors:(NSArray *)colors
{
	LDrawColorT colorCodeSought = [colorSought colorCode];
	NSInteger   numberColors    = (NSInteger)[colors count];
	NSInteger   counter         = 0;

	// Search through all the colors in the current color set and see if the
	// one we are after is in there. A brute force search.
	for (counter = 0; counter < numberColors; counter++)
	{
		LDrawColor *currentColor = [colors objectAtIndex:(NSUInteger)counter];
		if ([currentColor colorCode] == colorCodeSought)
		{
			return counter;
		}
	}
	return NSNotFound;
}


//---------- shouldSelectFirstColorAfterFilterWhenPreviousIndex: ----[static]--
//
// Purpose:		The array controller will automatically maintain the selection
//				if it can. But if it can't, we need to come up a reasonable new
//				answer. If the previous color is no longer in the list, what
//				should we do? I have chosen to automatically select the first
//				color, since I don't want to introduce the UI confusion of
//				empty selection.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldSelectFirstColorAfterFilterWhenPreviousIndex:(NSInteger)index
{
	return index == NSNotFound;
}


//---------- shouldClearColorFilterWhenIndexNotFound: ----------------[static]--
//
// Purpose:		It wasn't in the currently-displayed list. Search the master
//				list.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldClearColorFilterWhenIndexNotFound:(NSInteger)index
{
	return index == NSNotFound;
}


//---------- canSelectColorAtRowIndex: -------------------------------[static]--
//
// Purpose:		We'd better have found it by now!
//
//------------------------------------------------------------------------------
+ (BOOL)canSelectColorAtRowIndex:(NSInteger)index
{
	return index != NSNotFound;
}


//---------- colorFromListSelection:fallbackColor: -------------------[static]--
//
// Purpose:		It is possible there are no rows selected, if a search has
//				limited the color list out of existence. Just return whatever
//				was last selected.
//
//------------------------------------------------------------------------------
+ (LDrawColor *)colorFromListSelection:(NSArray *)selection
						 fallbackColor:(LDrawColor *)fallbackColor
{
	if ([selection count] > 0)
		return [selection objectAtIndex:0];
	return fallbackColor;
}


//---------- tooltipForColorCode:localizedName: ----------------------[static]--
//
// Purpose:		Create a tool tip to identify the LDraw color code.
//
//------------------------------------------------------------------------------
+ (NSString *)tooltipForColorCode:(LDrawColorT)colorCode
					localizedName:(NSString *)localizedName
{
	return [NSString stringWithFormat:@"LDraw %d\n%@", colorCode, localizedName];
}


//---------- predicateForSearchString:material: ----------------------[static]--
//
// Purpose:		Returns a search predicate suitable for finding colors based on
//				the given search string.
//
//				If the search string consists entirely of numerals, the
//				predicate will search for colors having that exact integer code.
//
//------------------------------------------------------------------------------
+ (NSPredicate *)predicateForSearchString:(NSString *)searchString
								 material:(LDrawColorFilter)material
{
	NSString        *keywordFormat      = nil;
	NSArray         *keywordArguments   = nil;
	NSString        *materialFormat     = nil;
	NSArray         *materialArguments  = nil;
	NSMutableString *predicateFormat    = nil;
	NSMutableArray  *predicateArguments = nil;
	NSPredicate     *searchPredicate    = nil;
	BOOL             searchByCode       = NO; // color name search by default.
	NSScanner       *digitScanner       = nil;
	NSInteger        colorCode          = 0;

	// If there is no string, then clear the search predicate (find all).
	if ([searchString length] == 0)
	{
		searchPredicate = nil;
	}
	else
	{
		// Find out whether this search is intended to be based on the LDraw
		// code. If the search string can be parsed into an integer, we'll
		// assume this is a color-code search. Otherwise, it will be a name
		// search.
		digitScanner = [NSScanner scannerWithString:searchString];
		searchByCode = [digitScanner scanInteger:&colorCode];

		// If it is an LDraw code search, try to find a color code equal to the
		// search number entered.
		if (searchByCode == YES)
		{
			keywordFormat     = @"%K == %@";
			keywordArguments  = @[NSStringFromSelector(@selector(colorCode)), @(colorCode)];
		}
		else
		{
			// This is a search based on color names. If we can find the search
			// string in any component of the color string, we consider it a
			// match.
			keywordFormat     = @"%K CONTAINS[cd] %@";
			keywordArguments  = @[NSStringFromSelector(@selector(localizedName)), searchString];
		}
	}

	switch (material)
	{
		case LDrawColorFilterAll:
			break;
		case LDrawColorFilterSolid:
			materialFormat    = @"(%K == %@) AND (%K == 1.0)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialNone), NSStringFromSelector(@selector(alpha))];
			break;
		case LDrawColorFilterTransparent:
			materialFormat    = @"(%K == %@) AND (%K < 1.0)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialNone), NSStringFromSelector(@selector(alpha))];
			break;
		case LDrawColorFilterChrome:
			materialFormat    = @"(%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialChrome)];
			break;
		case LDrawColorFilterPearlescent:
			materialFormat    = @"(%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialPearlescent)];
			break;
		case LDrawColorFilterRubber:
			materialFormat    = @"(%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialRubber)];
			break;
		case LDrawColorFilterMetal:
			materialFormat    = @"(%K == %@) OR (%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialMetal), NSStringFromSelector(@selector(material)), @(LDrawColorMaterialMatteMetallic)];
			break;
		case LDrawColorFilterOther:
			materialFormat    = @"((%K == %@) OR (%K == %@) OR (%K == %@))";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialCustom),
								 NSStringFromSelector(@selector(colorCode)), @(LDrawCurrentColor),
								 NSStringFromSelector(@selector(colorCode)), @(LDrawEdgeColor)];
			break;
	}

	if (keywordFormat || materialFormat)
	{
		predicateFormat    = [NSMutableString string];
		predicateArguments = [NSMutableArray array];
	}

	if (keywordFormat)
	{
		[predicateFormat appendString:keywordFormat];
		[predicateArguments addObjectsFromArray:keywordArguments];
	}

	if (materialFormat)
	{
		if ([predicateFormat length])
			[predicateFormat appendString:@"AND "];

		[predicateFormat appendFormat:@"(%@)", materialFormat];
		[predicateArguments addObjectsFromArray:materialArguments];
	}

	if (predicateFormat)
	{
		searchPredicate = [NSPredicate predicateWithFormat:predicateFormat argumentArray:predicateArguments];
	}

	return searchPredicate;
}


#pragma mark -
#pragma mark UTILITY FUNCTIONS
#pragma mark -

//========== complimentColor() =================================================
//
// Purpose:		Changes the given RGBA color into a "complimentary" color, which 
//				stands out in the original color, but maintains the same hue.
//
//==============================================================================
void complimentColor(const float *originalColor, float *complimentColor)
{
	float	brightness		= 0.0;
	
	// Isolate the color's grayscale intensity http://en.wikipedia.org/wiki/Grayscale
	brightness =	originalColor[0] * 0.30
				+	originalColor[1] * 0.59
				+	originalColor[2] * 0.11;
	
	// compliment dark colors with light ones and light colors with dark ones.
	if (brightness > 0.5)
	{
		// Darken
		complimentColor[0] = MAX(originalColor[0] - 0.40, 0.0);
		complimentColor[1] = MAX(originalColor[1] - 0.40, 0.0);
		complimentColor[2] = MAX(originalColor[2] - 0.40, 0.0);
	}
	else
	{
		// Lighten
		complimentColor[0] = MIN(originalColor[0] + 0.40, 1.0);
		complimentColor[1] = MIN(originalColor[1] + 0.40, 1.0);
		complimentColor[2] = MIN(originalColor[2] + 0.40, 1.0);
	}
	
	complimentColor[3] = originalColor[3];
	
} // end complimentColor


@end
