//==============================================================================
//
//  File:       LDrawRebrickableCSVReader.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Reads a CSV file of Rebrickable's downloads a row at a time,
//              gzipped or not.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>

#import <zlib.h>

NSString * const LDrawRebrickableErrorDomain = @"LDrawRebrickableErrorDomain";

static const size_t ChunkSize = 64 * 1024;

/// What the parser keeps between bytes: the bytes of the field being read, and
/// where it is in quotes.
typedef struct CSVState
{
	char		*field;
	size_t		 length;
	size_t		 capacity;
	BOOL		 isQuoted;			// inside a quoted field
	BOOL		 sawQuote;			// a quote inside a quoted field, which may be doubled
	BOOL		 fieldWasQuoted;	// the field opened with a quote, so a later one is text

} CSVState;


//========== LDrawRebrickableMakeError =========================================
//==============================================================================
NSError *LDrawRebrickableMakeError(LDrawRebrickableError code, NSString *reason, NSURL *url)
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];

	userInfo[NSLocalizedDescriptionKey]	= reason;
	userInfo[NSURLErrorKey]				= url;
	return [NSError errorWithDomain:LDrawRebrickableErrorDomain code:code userInfo:userInfo];
}


//========== AppendByte ========================================================
//==============================================================================
static void AppendByte(CSVState *state, char byte)
{
	if (state->length == state->capacity)
	{
		state->capacity	= MAX(state->capacity * 2, 64);
		state->field	= realloc(state->field, state->capacity);
	}
	state->field[state->length++] = byte;
}


@implementation LDrawRebrickableCSVReader
{
	NSURL *fileURL;
}


// MARK: - INITIALIZATION -


//========== initWithURL:error: ================================================
///
/// @abstract	Reads the first row, which names the columns.
///
//==============================================================================
- (instancetype) initWithURL:(NSURL *)url error:(NSError **)error
{
	__block NSArray *header = nil;

	self = [super init];
	if (self == nil)
		return nil;

	self->fileURL = [url copy];

	if ([self parseRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			header	= fields;
			*stop	= YES;
		} error:error] == NO)
		return nil;

	if (header == nil)
	{
		if (error != NULL)
			*error = LDrawRebrickableMakeError(LDrawRebrickableErrorUnreadableFile, @"The file has no rows.", url);
		return nil;
	}

	// A byte order mark would stick to the first column's name.
	NSString *first = header[0];
	if ([first hasPrefix:@"\uFEFF"])
	{
		NSMutableArray *names = [header mutableCopy];
		names[0] = [first substringFromIndex:1];
		header = names;
	}
	self->_columnNames = [header copy];

	return self;

}//end initWithURL:error:


// MARK: - COLUMNS -


//========== indexOfColumn: ====================================================
//==============================================================================
- (NSUInteger) indexOfColumn:(NSString *)name
{
	return [self.columnNames indexOfObject:name];
}


//========== indexesOfColumns:error: ===========================================
//==============================================================================
- (NSArray<NSNumber *> *) indexesOfColumns:(NSArray<NSString *> *)names error:(NSError **)error
{
	NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:[names count]];

	for (NSString *name in names)
	{
		NSUInteger index = [self indexOfColumn:name];
		if (index == NSNotFound)
		{
			if (error != NULL)
			{
				NSString *reason = [NSString stringWithFormat:@"%@ has no column \"%@\".",
									[self->fileURL lastPathComponent], name];

				*error = LDrawRebrickableMakeError(LDrawRebrickableErrorMissingColumn, reason, self->fileURL);
			}
			return nil;
		}
		[indexes addObject:@(index)];
	}
	return indexes;

}//end indexesOfColumns:error:


//---------- lastIndexOfColumns: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSUInteger) lastIndexOfColumns:(NSArray<NSNumber *> *)indexes
{
	NSUInteger last = 0;

	for (NSNumber *index in indexes)
		last = MAX(last, [index unsignedIntegerValue]);
	return last;
}


// MARK: - ROWS -


//========== enumerateRowsUsingBlock:error: ====================================
//==============================================================================
- (BOOL) enumerateRowsUsingBlock:(void (NS_NOESCAPE ^)(NSArray<NSString *> *fields, BOOL *stop))block
						   error:(NSError **)error
{
	__block BOOL isHeader = YES;

	return [self parseRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
		if (isHeader)
			isHeader = NO;
		else
			block(fields, stop);
	} error:error];

}//end enumerateRowsUsingBlock:error:


// MARK: - PARSING -


//========== parseRowsUsingBlock:error: ========================================
///
/// @abstract	Reads the file in pieces, inflating it when it starts with the
/// 			gzip mark, and hands each row to the block.
///
//==============================================================================
- (BOOL) parseRowsUsingBlock:(void (NS_NOESCAPE ^)(NSArray<NSString *> *fields, BOOL *stop))block
					   error:(NSError **)error
{
	FILE			*file			= fopen([[self->fileURL path] fileSystemRepresentation], "rb");
	uint8_t			*input			= NULL;
	uint8_t			*output			= NULL;
	unsigned char	 magic[2]		= {0};
	BOOL			 isGzip			= NO;
	BOOL			 streamEnded	= NO;
	BOOL			 stop			= NO;
	BOOL			 failed			= NO;
	z_stream		 stream;
	CSVState		 state			= {0};
	NSMutableArray	*fields			= [NSMutableArray array];

	if (file == NULL)
	{
		if (error != NULL)
			*error = LDrawRebrickableMakeError(LDrawRebrickableErrorUnreadableFile,
											   @"The file cannot be opened.", self->fileURL);
		return NO;
	}

	isGzip = (fread(magic, 1, 2, file) == 2 && magic[0] == 0x1f && magic[1] == 0x8b);
	rewind(file);

	memset(&stream, 0, sizeof(stream));
	if (isGzip && inflateInit2(&stream, 15 + 32) != Z_OK)
	{
		fclose(file);
		if (error != NULL)
			*error = LDrawRebrickableMakeError(LDrawRebrickableErrorUnreadableFile,
											   @"The file cannot be inflated.", self->fileURL);
		return NO;
	}

	input	= malloc(ChunkSize);
	output	= malloc(ChunkSize);

	while (stop == NO && failed == NO)
	{
		size_t count = fread(input, 1, ChunkSize, file);

		if (count == 0)
			break;

		if (isGzip == NO)
		{
			stop = [self feedBytes:input count:count state:&state fields:fields block:block];
			continue;
		}

		stream.next_in	= input;
		stream.avail_in	= (uInt)count;
		do
		{
			int result = 0;

			stream.next_out		= output;
			stream.avail_out	= (uInt)ChunkSize;
			result				= inflate(&stream, Z_NO_FLUSH);

			if (result != Z_OK && result != Z_STREAM_END && result != Z_BUF_ERROR)
			{
				failed = YES;
				break;
			}

			stop = [self feedBytes:output count:ChunkSize - stream.avail_out state:&state fields:fields block:block];

			// A file can hold more than one gzip member, one after another.
			streamEnded = (result == Z_STREAM_END);
			if (streamEnded && stream.avail_in > 0)
				inflateReset(&stream);
			else if (result == Z_BUF_ERROR)
				break;
		}
		while (stop == NO && (stream.avail_out == 0 || stream.avail_in > 0));
	}

	if (ferror(file) || (isGzip && stop == NO && failed == NO && streamEnded == NO))
		failed = YES;

	// The last row may have no line break after it.
	if (stop == NO && failed == NO)
	{
		[self endFieldOfState:&state fields:fields];
		[self endRowWithFields:fields block:block];
	}

	if (isGzip)
		inflateEnd(&stream);
	fclose(file);
	free(input);
	free(output);
	free(state.field);

	if (failed && error != NULL)
		*error = LDrawRebrickableMakeError(LDrawRebrickableErrorUnreadableFile,
										   @"The file stops partway, or is not gzipped right.", self->fileURL);

	return failed == NO;

}//end parseRowsUsingBlock:error:


//========== feedBytes:count:state:fields:block: ===============================
///
/// @abstract	Runs bytes through the parser. Returns YES when the block asked
/// 			to stop.
///
//==============================================================================
- (BOOL) feedBytes:(const uint8_t *)bytes
			 count:(size_t)count
			 state:(CSVState *)state
			fields:(NSMutableArray *)fields
			 block:(void (NS_NOESCAPE ^)(NSArray<NSString *> *fields, BOOL *stop))block
{
	BOOL stop = NO;

	for (size_t index = 0; index < count && stop == NO; index++)
	{
		char byte = (char)bytes[index];

		if (state->isQuoted)
		{
			if (state->sawQuote)
			{
				state->sawQuote = NO;
				if (byte == '"')
				{
					AppendByte(state, '"');
					continue;
				}
				// The quote closed the field; this byte is read as unquoted.
				state->isQuoted = NO;
			}
			else
			{
				if (byte == '"')
					state->sawQuote = YES;
				else
					AppendByte(state, byte);
				continue;
			}
		}

		switch (byte)
		{
			case '"':
				if (state->length == 0 && state->fieldWasQuoted == NO)
				{
					state->isQuoted			= YES;
					state->fieldWasQuoted	= YES;
				}
				else
					AppendByte(state, byte);
				break;

			case ',':
				[self endFieldOfState:state fields:fields];
				break;

			case '\n':
				[self endFieldOfState:state fields:fields];
				stop = [self endRowWithFields:fields block:block];
				break;

			case '\r':
				break;

			default:
				AppendByte(state, byte);
				break;
		}
	}
	return stop;

}//end feedBytes:count:state:fields:block:


//========== endFieldOfState:fields: ===========================================
//==============================================================================
- (void) endFieldOfState:(CSVState *)state fields:(NSMutableArray *)fields
{
	NSString *field = [[NSString alloc] initWithBytes:state->field
											   length:state->length
											 encoding:NSUTF8StringEncoding];

	// A field that is not UTF-8 is read as Latin-1, so a row is never lost.
	if (field == nil)
		field = [[NSString alloc] initWithBytes:state->field length:state->length encoding:NSISOLatin1StringEncoding];

	[fields addObject:field ?: @""];

	state->length			= 0;
	state->isQuoted			= NO;
	state->sawQuote			= NO;
	state->fieldWasQuoted	= NO;

}//end endFieldOfState:fields:


//========== endRowWithFields:block: ===========================================
///
/// @abstract	Hands a row to the block, unless it is a blank line. Returns YES
/// 			when the block asked to stop.
///
//==============================================================================
- (BOOL) endRowWithFields:(NSMutableArray *)fields
					block:(void (NS_NOESCAPE ^)(NSArray<NSString *> *fields, BOOL *stop))block
{
	BOOL stop = NO;

	if ([fields count] == 1 && [fields[0] length] == 0)
	{
		[fields removeAllObjects];
		return NO;
	}
	if ([fields count] > 0)
		block([fields copy], &stop);

	[fields removeAllObjects];
	return stop;

}//end endRowWithFields:block:

@end
