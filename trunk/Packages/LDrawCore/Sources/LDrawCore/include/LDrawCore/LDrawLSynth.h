//==============================================================================
//
//  File:       LDrawLSynth.h
//  Package:    LDrawCore
//
//  Created by Robin Macharg on 16/11/2012.
//
//==============================================================================

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawLSynthConfigSource.h>
#import <LDrawCore/LDrawLSynthRuntimeSource.h>
#import <LDrawCore/LDrawMovableDirective.h>

// The LSynth LDraw format extensions have several mandatory and several optional directives.
// The following state diagram illustrates the order that directives could occur.
// The initWithLines: parser in this class implements this state machine.

// TODO: need a transition between begun and finished on 0 SYNTH END

//
//     State              Transitions
//     -----------------------------------------------
//
//     ready              o
//                        |    0 SYNTH BEGIN X X
//                        V
//     begun              o
//                        |    0 SYNTH SHOW or
//                        |    1 X X X ...
//                        V
//     constraints      /\o
//        1 X X X ... |_/|
//                        |    0 SYNTH SYNTHESIZED BEGIN
//                        V
//     synthesized      /\o
//        1 X X X ... |_/|
//                        |    0 SYNTH SYNTHESIZED END
//                        V
//     synth finished     o
//                        |    0 SYNTH END
//                        V
//     finished           o
//

// Lsynth block parser states
typedef NS_ENUM(NSInteger, LDrawLSynthParserState)
{
    LDrawLSynthParserReadyToParse        = 1, // Idle state - we've not found a SYNTH BEGIN <TYPE> <COLOR> line
    LDrawLSynthParserParsingBegun        = 2, // SYNTH BEGIN has been found
    LDrawLSynthParserParsingConstraints  = 3, // Parsing constraints
    LDrawLSynthParserParsingSynthesized  = 4, // Parsing synthesized parts
    LDrawLSynthParserSynthesizedFinished = 5, // Looking for SYNTH END
    LDrawLSynthParserFinished            = 6, // All finished.
    LDrawLSynthParserStateCount
};


NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLSynth
///
/// @abstract   LDraw container for an LSynth hose, band, or part: constraints,
///             synthesized geometry, and the SYNTH BEGIN/END parser.
///
//------------------------------------------------------------------------------
@interface LDrawLSynth : LDrawContainer <LDrawColorable, LDrawMovableDirective>
{
    NSMutableArray  *synthesizedParts;
    NSString        *synthType;
    int              lsynthClass;
    LDrawColor      *color;
    double			 transformation[16];	// column-major, see LDrawPart
    BOOL             hidden;
    BOOL             subdirectiveSelected;
    Box3			 cachedBounds;			// cached bounds of the enclosed directives
}

@property (strong, nullable) NSString * group;		// MLCAD group name or nil

// Accessors
- (void)setLsynthClass:(int)lsynthClass;
- (int)lsynthClass;
- (void)setLsynthType:(NSString *)lsynthType;
- (NSString *)lsynthType;
- (void)setHidden:(BOOL)flag;
- (BOOL)isHidden;
- (void)setLDrawColor:(LDrawColor *)color;

- (TransformComponents)transformComponents;
- (Matrix4)transformationMatrix;

// Utilities
- (void)synthesize;
- (void)colorSelectedSynthesizedParts:(BOOL)yesNo;
- (NSString *)determineIconName:(LDrawDirective *)directive;
- (NSMutableArray *)prepareAutoHullData;
- (int)synthesizedPartsCount;

+ (BOOL)lineIsLSynthBeginning:(NSString*)line;
+ (BOOL)lineIsLSynthTerminator:(NSString*)line;

// Adapter-injected configuration source. The host installs an adapter
// around LSynthConfiguration (in LDrawFeatures); LDrawCore itself does not
// know about LSynthConfiguration. Must be set before LSynth directives are
// parsed.
+ (nullable id<LDrawLSynthConfigSource>)configSource;
+ (void)setConfigSource:(nullable id<LDrawLSynthConfigSource>)source;

// Host-injected executable/config paths and selection-tint settings. Must
// be set before synthesize, write, or selection coloring. This class does
// not look up the app main bundle or standardUserDefaults.
+ (nullable id<LDrawLSynthRuntimeSource>)runtimeSource;
+ (void)setRuntimeSource:(nullable id<LDrawLSynthRuntimeSource>)source;

// Selection color from the injected runtime source. Falls back to opaque
// red when no source is installed or the preference is missing.
+ (void)getSelectionColorRGBA:(float *)outRGBA;

@end

NS_ASSUME_NONNULL_END
