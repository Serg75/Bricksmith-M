//==============================================================================
//
//  File:       LDrawShortcutMap.m
//  Package:    LDrawInventory
//
//  Purpose:    The parts an LDraw shortcut is made of, so an assembly and its
//              parts can be counted alike.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <LDrawInventory/LDrawShortcutMap.h>

#import <LDrawInventory/LDrawPartIdentity.h>

#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawUtilities.h>

// How much of a part the library map reads first. A header fits in it.
static const NSUInteger LibraryReadLength = 4096;


//========== Fields ============================================================
///
/// @abstract	The words of a line. A byte order mark counts as a space.
///
//==============================================================================
static NSArray<NSString *> *Fields(NSString *line)
{
	static NSCharacterSet	*spaces		= nil;
	static dispatch_once_t	 onceToken;
	NSMutableArray			*fields		= [NSMutableArray array];
	NSScanner				*scanner	= [NSScanner scannerWithString:line];
	NSString				*field		= nil;

	dispatch_once(&onceToken, ^{
		NSMutableCharacterSet *set = [NSMutableCharacterSet whitespaceCharacterSet];
		[set addCharactersInString:@"\uFEFF"];
		spaces = [set copy];
	});

	[scanner setCharactersToBeSkipped:spaces];
	while ([scanner scanUpToCharactersFromSet:spaces intoString:&field])
		[fields addObject:field];
	return fields;

}//end Fields


//========== MayHavePieces =====================================================
///
/// @abstract	Whether the text can be a shortcut or a moved part. Most parts
/// 			are neither, so their files are not read whole or line by line.
///
//==============================================================================
static BOOL MayHavePieces(NSString *text)
{
	return		[text rangeOfString:@"~Moved"].location != NSNotFound
			||	[text rangeOfString:@"Shortcut" options:NSCaseInsensitiveSearch].location != NSNotFound;
}


@interface LDrawShortcutPiece ()

- (instancetype) initWithPartName:(NSString *)partName colorCode:(LDrawColorT)colorCode;

@end


@implementation LDrawShortcutPiece

//========== initWithPartName:colorCode: =======================================
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	self = [super init];
	if (self) {
		self->_partName		= [partName copy];
		self->_colorCode	= colorCode;
	}
	return self;
}


//========== colorCodeInAssemblyColor: =========================================
//==============================================================================
- (LDrawColorT) colorCodeInAssemblyColor:(LDrawColorT)assemblyColor
{
	return (self.colorCode == LDrawCurrentColor) ? assemblyColor : self.colorCode;
}


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"%@ in %d", self.partName, (int)self.colorCode];
}

@end


@implementation LDrawShortcutMap
{
	NSString * _Nullable (^reader)(NSString *partName);
	NSMutableDictionary<NSString *, id>	*cache;		// part name → its pieces, or NSNull for none
	NSMutableSet<NSString *>			*present;	// parts the reader found
	NSMutableSet<NSString *>			*opening;	// shortcuts being read, so a loop ends
}


// MARK: - INITIALIZATION -


//========== initWithFileReader: ===============================================
//==============================================================================
- (instancetype) initWithFileReader:(NSString * _Nullable (^)(NSString *partName))fileReader
{
	self = [super init];
	if (self) {
		self->reader	= [fileReader copy];
		self->cache		= [NSMutableDictionary dictionary];
		self->present	= [NSMutableSet set];
		self->opening	= [NSMutableSet set];
	}
	return self;
}


//---------- libraryMapWithPartNames: --------------------------------[static]--
///
/// @abstract	Reads the start of each part. A shortcut or a moved part is read
/// 			whole; any other part only needs its header.
///
//------------------------------------------------------------------------------
+ (instancetype) libraryMapWithPartNames:(NSSet<NSString *> *)partNames
{
	NSSet *names = [partNames copy];

	return [[self alloc] initWithFileReader:^NSString *(NSString *partName) {
		NSString		*path	= [names containsObject:partName] ? [[LDrawPaths sharedPaths] pathForPartName:partName]
																  : nil;
		NSFileHandle	*file	= (path != nil) ? [NSFileHandle fileHandleForReadingAtPath:path] : nil;
		NSData			*start	= [file readDataUpToLength:LibraryReadLength error:NULL];
		NSString		*text	= (start != nil) ? [LDrawUtilities stringFromFileData:start] : nil;

		[file closeAndReturnError:NULL];

		if ([start length] == LibraryReadLength && MayHavePieces(text))
			text = [LDrawUtilities stringFromFile:path];
		return text;
	}];

}//end libraryMapWithPartNames:


// MARK: - LOOKUPS -


//========== readPartsNamed: ===================================================
//==============================================================================
- (void) readPartsNamed:(NSSet<NSString *> *)partNames
{
	for (NSString *partName in partNames)
	{
		@autoreleasepool {
			[self piecesOfPartNamed:partName];
		}
	}
}


//========== piecesOfPartNamed: ================================================
//==============================================================================
- (NSArray<LDrawShortcutPiece *> *) piecesOfPartNamed:(NSString *)partName
{
	NSString	*name	= [LDrawPartIdentity libraryPartName:partName];
	id			 cached	= (name != nil) ? self->cache[name] : [NSNull null];
	NSString	*text	= nil;
	NSArray		*pieces	= nil;

	if (cached != nil)
		return (cached == [NSNull null]) ? nil : cached;
	if ([self->opening containsObject:name])
		return nil;

	[self->opening addObject:name];
	text = self->reader(name);
	if (text != nil && MayHavePieces(text))
		pieces = [self piecesInText:text];
	[self->opening removeObject:name];

	if (text != nil)
		[self->present addObject:name];

	self->cache[name] = pieces ?: [NSNull null];
	return pieces;

}//end piecesOfPartNamed:


//========== hasPartNamed: =====================================================
//==============================================================================
- (BOOL) hasPartNamed:(NSString *)partName
{
	NSString *name = [LDrawPartIdentity libraryPartName:partName];

	if (name == nil)
		return NO;
	[self piecesOfPartNamed:name];
	return [self->present containsObject:name];
}


// MARK: - UTILITIES -


//========== piecesInText: =====================================================
///
/// @abstract	The pieces of a shortcut file, or of the shortcut a moved file
/// 			points at. Nil for any other file.
///
//==============================================================================
- (NSArray<LDrawShortcutPiece *> *) piecesInText:(NSString *)text
{
	__block BOOL		 isFirst		= YES;
	__block BOOL		 isMoved		= NO;
	__block BOOL		 isShortcut		= NO;
	NSMutableArray		*references		= [NSMutableArray array];
	NSMutableArray		*pieces			= [NSMutableArray array];

	[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		NSArray<NSString *> *fields = Fields(line);

		if ([fields count] == 0)
			return;

		if ([fields[0] isEqualToString:@"0"])
		{
			NSString *word	= ([fields count] >= 3) ? fields[1] : nil;
			NSString *next	= ([fields count] >= 3) ? fields[2] : nil;

			if (isFirst)
				isMoved = ([word isEqualToString:@"~Moved"] && [next isEqualToString:@"to"]);
			else if ([word isEqualToString:@"!LDRAW_ORG"])
				isShortcut = ([next rangeOfString:@"Shortcut" options:NSCaseInsensitiveSearch].location != NSNotFound);
		}
		else if (isMoved == NO && isShortcut == NO)
		{
			// The header is over without naming a shortcut.
			*stop = YES;
		}
		else if ([fields[0] isEqualToString:@"1"] && [fields count] >= 15)
		{
			// 1 color x y z a b c d e f g h i file
			NSScanner	*scanner	= [NSScanner scannerWithString:fields[1]];
			int			 color		= LDrawCurrentColor;
			NSArray		*words		= [fields subarrayWithRange:NSMakeRange(14, [fields count] - 14)];
			NSString	*file		= [words componentsJoinedByString:@" "];

			if ([scanner scanInt:&color] == NO || [scanner isAtEnd] == NO)
				color = LDrawCurrentColor;
			[references addObject:@[file, @(color)]];
		}
		isFirst = NO;
	}];

	if (isMoved == NO && isShortcut == NO)
		return nil;

	// A moved file places its new name, which may or may not be a shortcut.
	if (isMoved && isShortcut == NO && [references count] != 1)
		return nil;

	for (NSArray *reference in references)
	{
		LDrawColorT	 color	= (LDrawColorT)[reference[1] intValue];
		NSString	*name	= [LDrawPartIdentity libraryPartName:reference[0]];
		NSArray		*inner	= [self piecesOfPartNamed:reference[0]];

		if (inner == nil)
		{
			if (isMoved && isShortcut == NO)
				return nil;
			[pieces addObject:[[LDrawShortcutPiece alloc] initWithPartName:name colorCode:color]];
			continue;
		}

		for (LDrawShortcutPiece *piece in inner)
		{
			LDrawColorT innerColor = [piece colorCodeInAssemblyColor:color];
			[pieces addObject:[[LDrawShortcutPiece alloc] initWithPartName:piece.partName colorCode:innerColor]];
		}
	}

	return ([pieces count] > 0) ? pieces : nil;

}//end piecesInText:

@end
