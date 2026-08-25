//==============================================================================
//
//  File:       LDrawLSynth.h
//  Package:    LDrawCore
//
//  Created by Robin Macharg on 16/11/2012.
//
//==============================================================================

#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawLSynthConfigSource.h>
#import <LDrawCore/LDrawMovableDirective.h>

// The LSynth LDraw format extensions have several mandatory and several optional directives.
// The following state diagram illustrates the order that directives could occur.
// The initWithLines: parser in this class implements this state machine.

// TODO: need a transition between PARSER_PARSING_BEGUN and PARSER_FINISHED on 0 SYNTH END

//
//     State                                         Transitions
//     ---------------------------------------------------------------------------------------
//
//     PARSER_READY_TO_PARSE                         o
//                                                   |
//                                                   |    0 SYNTH BEGIN X X
//                                                   V
//     PARSER_PARSING_BEGUN                          o
//                                                   |    0 SYNTH SHOW or
//                                                   |    1 X X X ...
//                                                   V
//     PARSER_PARSING_CONSTRAINTS                  /\o
//                                    1 X X X ... |_/|
//                                                   |    0 SYNTH SYNTHESIZED BEGIN
//                                                   V
//     PARSER_PARSING_SYNTHESIZED                  /\o
//                                    1 X X X ... |_/|
//                                                   |    0 SYNTH SYNTHESIZED END
//                                                   V
//     PARSER_SYNTHESIZED_FINISHED                   o
//                                                   |    0 SYNTH END
//                                                   |
//                                                   V
//     PARSER_FINISHED                               o
//

// Lsynth block parser states
typedef enum
{
    PARSER_READY_TO_PARSE       = 1, // Idle state - we've not found a SYNTH BEGIN <TYPE> <COLOR> line
    PARSER_PARSING_BEGUN        = 2, // SYNTH BEGIN has been found
    PARSER_PARSING_CONSTRAINTS  = 3, // Parsing constraints
    PARSER_PARSING_SYNTHESIZED  = 4, // Parsing synthesized parts
    PARSER_SYNTHESIZED_FINISHED = 5, // Looking for SYNTH END
    PARSER_FINISHED             = 6, // All finished.
    PARSER_STATE_COUNT
} LSynthParserStateT;


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
    float			 glTransformation[16];
    BOOL             hidden;
    BOOL             subdirectiveSelected;
    Box3			 cachedBounds;			// cached bounds of the enclosed directives
}

@property (strong) NSString * group;		// MLCAD group name or nil

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

// Adapter-injected configuration source. Bricksmith installs an adapter
// around LSynthConfiguration (in LDrawFeatures); LDrawCore itself does not
// know about LSynthConfiguration. Must be set before LSynth directives are
// parsed.
+ (id<LDrawLSynthConfigSource>)configSource;
+ (void)setConfigSource:(id<LDrawLSynthConfigSource>)source;

// Foundation-only selection color lookup; reads
// LSYNTH_SELECTION_COLOR_RGBA_KEY from standard user defaults. Falls back
// to opaque red when no preference is set.
+ (void)getSelectionColorRGBA:(float *)outRGBA;

@end
