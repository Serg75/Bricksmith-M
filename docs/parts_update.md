# Parts updates

Bricksmith keeps the LDraw folder up to date with LDraw's part library. It looks for a new update at
launch, offers it, and installs it into the folder chosen in Settings > General > LDraw Folder.

## Where the code is

The package `LDrawLibraryUpdate` does the work and holds the rules. It depends on Foundation only.

| Type | Does |
|------|------|
| `LDrawLibraryReleaseList` | Reads the server's list and picks the releases a folder needs |
| `LDrawLibraryUpdater` | Tells which update a folder holds, fetches the list, installs releases |
| `LDrawLibraryInstallation` | One install run (inside the package) |
| `LDrawLibraryZipReader` | Reads the archives (inside the package) |
| `LDrawLibraryUpdatePolicy` | When a launch looks for an update, and what to do with the list: offer, install, or say why there is nothing |
| `LDrawLibraryNewParts` | The parts an update added, as kept in the defaults |

In the app, `PartsUpdateController` shows the offer and the progress and reads the defaults, and
`DownloadProgressPanel` is the progress panel it shares with the parts limit's download.

## Where updates come from

`https://library.ldraw.org/ptreleases/tab` lists every release as a row of tab-separated text: kind,
update, date, format, address, size and MD5.

```
UPDATE    2026-10  2026-10-26  ZIP  https://library.ldraw.org/library/updates/lcad2610.zip  995699     ae44…
COMPLETE  2026-10  2026-10-26  ZIP  https://library.ldraw.org/library/updates/complete.zip  146853687  9b89…
```

An `UPDATE` holds the files one update added or changed, about 1 MB. `COMPLETE` is the whole library
up to its update, about 150 MB. `BASE` rows and archives that are not zips are not used, nor
addresses that are not https. A row whose update is not a year and number, such as `2026-10`, is
left out: updates are compared as text, so another shape could sort after every real one.

## Which update a folder holds

Every update leaves its release notes in `models`, named `Note2610CA.txt` for update 2026-10.
`+[LDrawLibraryUpdater installedReleaseInFolderURL:]` reads the newest of these names. Years from 97
on are 19xx. A folder without such notes holds an unknown update.

## What is installed

`-[LDrawLibraryReleaseList releasesToInstallAfter:]` picks the updates after the folder's own,
oldest first. It picks the complete library instead when the folder's update is unknown, when an
update in between has no zip archive, or when the updates together are the bigger download.

The newest update is the newest of the complete library and the updates. When the complete library
is older than the newest update, the updates after it follow it. When no zip archives reach the
newest update, the complete library alone is picked if it is newer than the folder.

`LDrawLibraryUpdater` then works in this order, through `LDrawLibraryInstallation`:

1. Checks that the folder can be written.
2. Locks the folder. When another run holds it, that is an error. Then removes the staging folders
   of runs that did not finish. A folder that cannot be locked, such as one on some network
   volumes, is updated without the lock, and its old staging folders are left, since another run
   may be using one.
3. Downloads each archive into a hidden staging folder inside the LDraw folder, named
   `.bricksmith-update-` and a UUID, and checks its size and MD5 against the list.
4. Unpacks the files under `ldraw/` into the staging folder. A later update's file replaces an
   earlier one's.
5. Moves the files into the LDraw folder. A file with the same bytes as the one in place is skipped.
   A replaced file is kept in the staging folder until every file is in.
6. Removes the staging folder, and unlocks the folder.

Rules that keep the folder safe:

- Nothing is removed from the folder. LDraw leaves a "~Moved to" file where a part was renamed.
- Entries under `ldraw/Unofficial` are not installed, so the user's own parts stay as they are.
- An entry is skipped when a part of its path starts with a dot. That covers `..`, which could lead
  out of the folder, and the hidden files a Mac adds to archives.
- The zip reader never uses an entry's path as a place on disk. The updater builds the place from
  the checked path.
- A file never replaces a folder of the same name. That is an error.
- The files in `models` are moved last. The release notes among them say which update the folder
  holds, so a run that was cut short leaves the folder at its old update and the next check offers
  the update again.
- When a move fails, the files already moved are taken out, the old ones put back, and the new
  folders removed when they are empty. After an error or a cancel the folder holds the old files.
- A file in place counts as itself, so a link that leads nowhere is kept in the staging folder too,
  and put back after an error. A link to a folder counts as the folder.
- A cancel works until the moves start. They run to the end.
- Quitting Bricksmith cancels a download, or waits for the moves to end.

LDraw's own files are replaced like any other, `LDConfig.ldr` included.

## After an update

`PartsUpdateController` saves the names of the files that are new in `parts` as an
`LDrawLibraryNewParts`, then calls
`-[PartLibraryController reloadPartCatalog:]`. That scans the folder, reads again the changed parts
the open models use, and reports the part overrides the library now has newer versions of.

The Part Browser lists the new parts as "New in 2026-11" under Library, after Favorites
(`Category_LastUpdate`). Moved parts and aliases are left out. The list stays until an update adds
parts again, and is used only for the folder it was made for. An update that adds none, such as one
another copy of the app already installed, keeps it.

## The catalog and updates made elsewhere

A scan stamps the folder's update into `LDraw Parts.plist` as `LibraryRelease`. At launch
`-[LDrawPartLibrary load]` scans again a catalog whose stamp is not the folder's update, so an update
installed by another program or by hand shows up without Reload Parts. A catalog from before the
stamp is scanned once. In a folder that cannot be written the old catalog is kept: the new one could
not be saved, and every launch would scan the folder.

## What the user sees

- Bricksmith > Check for Parts Update… looks now and says what it found.
- `LDrawLibraryUpdatePolicy` decides when to look and what to do with what was found.
- At launch the check runs at most once a day, quietly. An update is offered in a floating panel
  with Update, Later and Skip This Update, and a box to install future updates without asking. The
  panel does not stop the user from opening or editing a model.
- An update installed without asking shows its progress in a floating panel that does not take the
  keyboard, so Esc in a model window does not cancel it. The complete library is always offered,
  never installed without asking: it replaces every file in the folder. When another copy of the
  app is already updating the folder, such an update gives up quietly, with a line in the log.
- When the LDraw folder changed since the check, Update looks again for the new folder. A check the
  user asked for looks again too; a launch check of the old folder is dropped and not counted as
  the day's check.
- Settings > General > LDraw Folder shows the folder's update and when the server was last asked,
  with Check Now, and "Look for updates at launch": Never, Ask before installing, or Install without
  asking.

## Defaults

| Key | Value |
|-----|-------|
| `Library Update Mode` | an `LDrawLibraryUpdateMode`: 0 never, 1 ask (the default), 2 install |
| `Library Update Check Date` | when the server was last asked |
| `Library Update Skipped Release` | the update the user chose to skip |
| `Library Update New Parts` | an `LDrawLibraryNewParts`: the last update's `folder`, `release` and new part `names` |

## Not done

- A first install into a new folder. The folder must exist and be chosen in Settings.
- Unofficial parts from the Parts Tracker.
- A command to install the complete library over a folder that claims to be up to date.
