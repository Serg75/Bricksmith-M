//==============================================================================
//
//  File:       LDrawPathNames.h
//  Package:    LDrawCore
//
//  Purpose:    Constant names of standard LDraw files or folders.
//
//  Modified:   05/03/2011 Allen Smith. Creation Date.
//
//==============================================================================

#ifndef LDrawPathNames_h
#define LDrawPathNames_h

////////////////////////////////////////////////////////////////////////////////
//
// Folder Names
//
////////////////////////////////////////////////////////////////////////////////
#define LDRAW_DIRECTORY_NAME					@"LDraw"

#define PRIMITIVES_DIRECTORY_NAME				@"p"
	#define PRIMITIVES_48_DIRECTORY_NAME		@"48"

#define PARTS_DIRECTORY_NAME					@"parts" //match case of LDraw.org complete distribution zip package.
	#define SUBPARTS_DIRECTORY_NAME				@"s"

#define TEXTURES_DIRECTORY_NAME					@"textures"

#define UNOFFICIAL_DIRECTORY_NAME				@"Unofficial"


////////////////////////////////////////////////////////////////////////////////
//
// File Names
//
////////////////////////////////////////////////////////////////////////////////

#define LDCONFIG								@"LDConfig"
#define LDCONFIG_EXTENSION						@"ldr"
#define LDCONFIG_FILE_NAME						LDCONFIG @"." LDCONFIG_EXTENSION

#define MLCAD									@"MLCad"
#define MLCAD_EXTENSION							@"ini"
#define MLCAD_INI_FILE_NAME						MLCAD @"." MLCAD_EXTENSION

// Cache file written into the user's LDraw folder. This used to carry the host
// app's name; since the catalog is derived entirely by scanning that folder,
// the only cost of renaming it was one rebuild. A catalog under the old name,
// if any is still sitting beside it, is simply ignored.
#define PART_CATALOG_NAME						@"LDraw Parts.plist"

#endif
