//==============================================================================
//
//  File:       LDrawLibraryZipReader.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    Lists a zip archive's entries and unpacks them one at a time.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import "LDrawLibraryZipReader.h"

#import "LDrawLibraryUpdateErrorInternal.h"

#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <zlib.h>

static const uint32_t EndRecordSignature	= 0x06054b50;
static const uint32_t Zip64LocatorSignature	= 0x07064b50;
static const uint32_t Zip64RecordSignature	= 0x06064b50;
static const uint32_t DirectorySignature	= 0x02014b50;
static const uint32_t LocalSignature		= 0x04034b50;

static const size_t EndRecordLength			= 22;
static const size_t Zip64LocatorLength		= 20;
static const size_t Zip64RecordLength		= 56;
static const size_t DirectoryHeaderLength	= 46;
static const size_t LocalHeaderLength		= 30;
static const size_t MaxCommentLength		= 65535;
static const size_t ChunkLength				= 64 * 1024;

// A directory bigger than this is not a part library's.
static const uint64_t MaxDirectoryLength	= 256 * 1024 * 1024;

static const uint16_t Zip64ExtraIdentifier	= 0x0001;
static const uint16_t EncryptedFlag			= 0x0001;

enum
{
	MethodStored	= 0,
	MethodDeflated	= 8
};


//========== Read16, Read32, Read64 ============================================
///
/// @abstract	A little-endian number at the address.
///
//==============================================================================
static uint16_t Read16(const uint8_t *bytes)
{
	return (uint16_t)(bytes[0] | (bytes[1] << 8));
}

static uint32_t Read32(const uint8_t *bytes)
{
	return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static uint64_t Read64(const uint8_t *bytes)
{
	return (uint64_t)Read32(bytes) | ((uint64_t)Read32(bytes + 4) << 32);
}


//========== WriteAll ==========================================================
//==============================================================================
static BOOL WriteAll(int output, const void *bytes, size_t length)
{
	size_t done = 0;

	while (done < length)
	{
		ssize_t count = write(output, (const uint8_t *)bytes + done, length - done);

		if (count < 0 && errno == EINTR)
			continue;
		if (count < 0)
			return NO;
		done += (size_t)count;
	}
	return YES;
}


@interface LDrawLibraryZipEntry ()

@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic) uint64_t size;					// once unpacked
@property (nonatomic) uint16_t method;
@property (nonatomic) uint32_t crc;
@property (nonatomic) uint64_t compressedSize;
@property (nonatomic) uint64_t headerOffset;

@end


@implementation LDrawLibraryZipEntry

//========== readZip64Extra:length: ============================================
///
/// @abstract	Takes the sizes and the offset that did not fit in 32 bits from
/// 			the entry's extra fields.
///
//==============================================================================
- (void) readZip64Extra:(const uint8_t *)extra length:(size_t)length
{
	size_t offset = 0;

	while (offset + 4 <= length)
	{
		uint16_t		 identifier		= Read16(extra + offset);
		size_t			 fieldLength	= Read16(extra + offset + 2);
		const uint8_t	*field			= extra + offset + 4;
		size_t			 used			= 0;

		if (fieldLength > length - offset - 4)
			return;

		if (identifier == Zip64ExtraIdentifier)
		{
			if (self.size == UINT32_MAX && used + 8 <= fieldLength)
			{
				self.size = Read64(field + used);
				used += 8;
			}
			if (self.compressedSize == UINT32_MAX && used + 8 <= fieldLength)
			{
				self.compressedSize = Read64(field + used);
				used += 8;
			}
			if (self.headerOffset == UINT32_MAX && used + 8 <= fieldLength)
				self.headerOffset = Read64(field + used);
			return;
		}
		offset += 4 + fieldLength;
	}

}//end readZip64Extra:length:

@end


@implementation LDrawLibraryZipReader
{
	NSURL		*archiveURL;
	int			 archive;		// the open file, or -1
	uint64_t	 archiveLength;
}


// MARK: - INITIALIZATION -


//========== initWithFileURL:error: ============================================
//==============================================================================
- (instancetype) initWithFileURL:(NSURL *)fileURL error:(NSError **)error
{
	self = [super init];
	if (self) {
		struct stat info = { 0 };

		self->archiveURL	= [fileURL copy];
		self->archive		= open([fileURL fileSystemRepresentation], O_RDONLY);

		if (self->archive >= 0 && fstat(self->archive, &info) == 0)
		{
			self->archiveLength	= (uint64_t)info.st_size;
			self->_entries		= [self readEntries];
		}
		if (self->_entries == nil)
		{
			if (error != NULL)
				*error = [self badArchiveError];
			return nil;
		}
	}
	return self;

}//end initWithFileURL:error:


//========== dealloc ===========================================================
//==============================================================================
- (void) dealloc
{
	if (self->archive >= 0)
		close(self->archive);
}


// MARK: - THE DIRECTORY -


//========== readEntries =======================================================
///
/// @abstract	The archive's entries, from the directory at its end, or nil
/// 			when it cannot be read.
///
//==============================================================================
- (NSArray<LDrawLibraryZipEntry *> *) readEntries
{
	uint64_t		 longestTail		= EndRecordLength + MaxCommentLength + Zip64LocatorLength;
	size_t			 tailLength			= (size_t)MIN(self->archiveLength, longestTail);
	NSData			*tail				= [self dataAtOffset:self->archiveLength - tailLength length:tailLength];
	const uint8_t	*bytes				= [tail bytes];
	const uint8_t	*end				= NULL;
	uint64_t		 count				= 0;
	uint64_t		 directoryLength	= 0;
	uint64_t		 directoryOffset	= 0;
	NSData			*directory			= nil;

	if (tail == nil || tailLength < EndRecordLength)
		return nil;

	// The end record is the last thing in the file, before a comment.
	for (size_t index = tailLength - EndRecordLength + 1; index-- > 0; )
	{
		if (Read32(bytes + index) == EndRecordSignature)
		{
			end = bytes + index;
			break;
		}
	}
	if (end == NULL)
		return nil;

	count			= Read16(end + 10);
	directoryLength	= Read32(end + 12);
	directoryOffset	= Read32(end + 16);

	// Numbers that do not fit are in the zip64 record, found by its locator.
	if (count == UINT16_MAX || directoryLength == UINT32_MAX || directoryOffset == UINT32_MAX)
	{
		const uint8_t	*locator	= end - Zip64LocatorLength;
		NSData			*record		= nil;
		const uint8_t	*fields		= NULL;

		if ((size_t)(end - bytes) < Zip64LocatorLength || Read32(locator) != Zip64LocatorSignature)
			return nil;

		record = [self dataAtOffset:Read64(locator + 8) length:Zip64RecordLength];
		fields = [record bytes];
		if (record == nil || Read32(fields) != Zip64RecordSignature)
			return nil;

		count			= Read64(fields + 32);
		directoryLength	= Read64(fields + 40);
		directoryOffset	= Read64(fields + 48);
	}

	if (directoryLength > MaxDirectoryLength)
		return nil;

	directory = [self dataAtOffset:directoryOffset length:(size_t)directoryLength];
	if (directory == nil)
		return nil;

	return [self entriesInDirectory:directory count:count];

}//end readEntries


//========== entriesInDirectory:count: =========================================
//==============================================================================
- (NSArray<LDrawLibraryZipEntry *> *) entriesInDirectory:(NSData *)directory count:(uint64_t)count
{
	const uint8_t							*cursor		= [directory bytes];
	const uint8_t							*end		= cursor + [directory length];
	NSMutableArray<LDrawLibraryZipEntry *>	*entries	= [NSMutableArray array];

	for (uint64_t index = 0; index < count; index++)
	{
		LDrawLibraryZipEntry	*entry			= [[LDrawLibraryZipEntry alloc] init];
		size_t					 nameLength		= 0;
		size_t					 extraLength	= 0;
		size_t					 commentLength	= 0;

		if ((size_t)(end - cursor) < DirectoryHeaderLength || Read32(cursor) != DirectorySignature)
			return nil;

		nameLength		= Read16(cursor + 28);
		extraLength		= Read16(cursor + 30);
		commentLength	= Read16(cursor + 32);
		if ((size_t)(end - cursor) - DirectoryHeaderLength < nameLength + extraLength + commentLength)
			return nil;

		if (Read16(cursor + 8) & EncryptedFlag)
			return nil;

		entry.method			= Read16(cursor + 10);
		entry.crc				= Read32(cursor + 16);
		entry.compressedSize	= Read32(cursor + 20);
		entry.size				= Read32(cursor + 24);
		entry.headerOffset		= Read32(cursor + 42);
		entry.path				= [self pathWithBytes:cursor + DirectoryHeaderLength length:nameLength];
		if (entry.path == nil)
			return nil;

		[entry readZip64Extra:cursor + DirectoryHeaderLength + nameLength length:extraLength];
		[entries addObject:entry];

		cursor += DirectoryHeaderLength + nameLength + extraLength + commentLength;
	}
	return entries;

}//end entriesInDirectory:count:


//========== pathWithBytes:length: =============================================
///
/// @abstract	An entry's path. Old archives write it in the DOS character
/// 			set.
///
//==============================================================================
- (NSString *) pathWithBytes:(const uint8_t *)bytes length:(size_t)length
{
	NSStringEncoding	 dos	= CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSLatinUS);
	NSString			*path	= [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];

	return path ?: [[NSString alloc] initWithBytes:bytes length:length encoding:dos];
}


// MARK: - UNPACKING -


//========== writeEntry:toURL:error: ===========================================
//==============================================================================
- (BOOL) writeEntry:(LDrawLibraryZipEntry *)entry toURL:(NSURL *)fileURL error:(NSError **)error
{
	NSData			*header		= [self dataAtOffset:entry.headerOffset length:LocalHeaderLength];
	const uint8_t	*bytes		= [header bytes];
	uint64_t		 start		= 0;
	int				 output		= -1;
	NSError			*failure	= nil;

	if (header == nil || Read32(bytes) != LocalSignature)
		failure = [self badArchiveError];

	if (failure == nil)
	{
		// The entry's bytes follow its header, name and extra fields.
		start	= entry.headerOffset + LocalHeaderLength + Read16(bytes + 26) + Read16(bytes + 28);
		output	= open([fileURL fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
		if (output < 0)
			failure = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
	}

	if (failure == nil)
	{
		failure = [self unpackEntry:entry from:start to:output];
		close(output);
		if (failure != nil)
			unlink([fileURL fileSystemRepresentation]);
	}

	if (failure != nil && error != NULL)
		*error = failure;
	return (failure == nil);

}//end writeEntry:toURL:error:


//========== unpackEntry:from:to: ==============================================
///
/// @abstract	Writes the entry's unpacked bytes to the open file. Returns nil,
/// 			or what went wrong.
///
//==============================================================================
- (NSError *) unpackEntry:(LDrawLibraryZipEntry *)entry from:(uint64_t)start to:(int)output
{
	NSMutableData	*unpacked	= [NSMutableData dataWithLength:ChunkLength];
	z_stream		 stream		= { 0 };
	uint64_t		 offset		= start;
	uint64_t		 remaining	= entry.compressedSize;
	uint64_t		 written	= 0;
	uLong			 crc		= crc32(0L, Z_NULL, 0);
	BOOL			 deflated	= (entry.method == MethodDeflated);
	BOOL			 finished	= NO;
	NSError			*failure	= nil;

	if (deflated == NO && entry.method != MethodStored)
		return [self badArchiveError];
	if (deflated && inflateInit2(&stream, -MAX_WBITS) != Z_OK)
		return [self badArchiveError];

	while (finished == NO && failure == nil)
	{
		size_t	 length	= (size_t)MIN(remaining, (uint64_t)ChunkLength);
		NSData	*packed	= [self dataAtOffset:offset length:length];

		// A deflated entry that needs more bytes than it has is cut short.
		if (packed == nil || (deflated && length == 0))
		{
			failure = [self badArchiveError];
			break;
		}
		offset		+= length;
		remaining	-= length;

		if (deflated == NO)
		{
			failure		= [self appendBytes:[packed bytes]
									 length:length
									ofEntry:entry
										 to:output
									written:&written
										crc:&crc];
			finished	= (remaining == 0);
			continue;
		}

		stream.next_in	= (Bytef *)[packed bytes];
		stream.avail_in	= (uInt)length;
		do
		{
			int status = Z_OK;

			stream.next_out		= [unpacked mutableBytes];
			stream.avail_out	= (uInt)ChunkLength;

			// Z_BUF_ERROR only says the input ran out.
			status = inflate(&stream, Z_NO_FLUSH);
			if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR)
			{
				failure = [self badArchiveError];
				break;
			}
			failure		= [self appendBytes:[unpacked bytes]
									 length:ChunkLength - stream.avail_out
									ofEntry:entry
										 to:output
									written:&written
										crc:&crc];
			finished	= (status == Z_STREAM_END);
		}
		while (failure == nil && finished == NO && stream.avail_out == 0);
	}

	if (deflated)
		inflateEnd(&stream);

	if (failure == nil && (written != entry.size || (uint32_t)crc != entry.crc))
		failure = [self badArchiveError];
	return failure;

}//end unpackEntry:from:to:


//========== appendBytes:length:ofEntry:to:written:crc: ========================
///
/// @abstract	Writes unpacked bytes, and counts them into the size and CRC.
/// 			Bytes beyond the size the entry gives are an error, so a bad
/// 			archive cannot fill the disk.
///
//==============================================================================
- (NSError *) appendBytes:(const void *)bytes
				   length:(size_t)length
				  ofEntry:(LDrawLibraryZipEntry *)entry
					   to:(int)output
				  written:(uint64_t *)written
					  crc:(uLong *)crc
{
	if (length > entry.size - *written)
		return [self badArchiveError];
	if (WriteAll(output, bytes, length) == NO)
		return [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];

	*crc		= crc32(*crc, bytes, (uInt)length);
	*written	+= length;
	return nil;
}


// MARK: - UTILITIES -


//========== dataAtOffset:length: ==============================================
///
/// @abstract	Bytes of the archive, or nil when it does not have them all.
///
//==============================================================================
- (NSData *) dataAtOffset:(uint64_t)offset length:(size_t)length
{
	NSMutableData	*data	= nil;
	size_t			 done	= 0;

	if (offset > self->archiveLength || length > self->archiveLength - offset)
		return nil;

	data = [NSMutableData dataWithLength:length];
	while (done < length)
	{
		uint8_t	*target	= (uint8_t *)[data mutableBytes] + done;
		ssize_t	 count	= pread(self->archive, target, length - done, (off_t)(offset + done));

		if (count <= 0)
			return nil;
		done += (size_t)count;
	}
	return data;

}//end dataAtOffset:length:


//========== badArchiveError ===================================================
//==============================================================================
- (NSError *) badArchiveError
{
	NSString *reason = [NSString stringWithFormat:@"%@ is not a zip archive that can be read.",
						[self->archiveURL lastPathComponent]];

	return LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadArchive, reason, self->archiveURL);
}

@end
