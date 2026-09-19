//==============================================================================
//
//  File:       LPubCommand.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2023-02-08.
//
//==============================================================================

#import <LDrawCore/LDrawMetaCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubMetaScope
///
/// @abstract   The optional scope keyword most LPub metas accept between the
///             command and its value.
///
/// @discussion LPub3D writes GLOBAL in the top model's header, but reads it
///             like a line with no keyword: both hold from that line on, and
///             into submodels placed after it. LOCAL holds for the rest of its
///             step. Unspecified means the line has no scope keyword.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubMetaScope) {
	LPubMetaScopeUnspecified	= 0,
	LPubMetaScopeGlobal			= 1,
	LPubMetaScopeLocal			= 2
};


//------------------------------------------------------------------------------
///
/// @class      LPubCommand
///
/// @abstract   A generic LPub command.
///
//------------------------------------------------------------------------------
@interface LPubCommand : LDrawMetaCommand

/// Command's substring after !LPUB.
@property (nonatomic, copy) NSString *lPubCommandString;

/// Reads the scope keyword at *index, if there is one, and moves *index past
/// it. Returns Unspecified when there is none.
+ (LPubMetaScope) scopeInParameters:(NSArray<NSString *> *)parameters index:(NSUInteger *)index;

/// Reads a token as a finite number. A token with anything left over is
/// rejected. Locale-free, like the file.
+ (BOOL) getNumber:(double *)outValue fromToken:(NSString *)token;

/// Like +getNumber:fromToken:, but the number must be greater than zero.
+ (BOOL) getPositiveNumber:(double *)outValue fromToken:(NSString *)token;

/// Reads a token as a whole number no less than minimum. A token with
/// anything left over is rejected.
+ (BOOL) getInteger:(NSInteger *)outValue fromToken:(NSString *)token atLeast:(NSInteger)minimum;

/// Stores the text without re-deriving anything from it. Use it when the text
/// already matches the properties.
- (void) adoptCommandString:(NSString *)commandString;

/// Takes the properties from another instance of the same class. Called with
/// a parse of new text, and with the original when copying. The default does
/// nothing.
- (void) adoptPropertiesFromCommand:(LPubCommand *)command;

/// The command opening the file would make for this text, or nil when it has
/// the receiver's class.
- (nullable LPubCommand *) replacementForText:(NSString *)text;

/// The localization key for the undo action name.
- (NSString *) undoActionKey;

@end

NS_ASSUME_NONNULL_END
