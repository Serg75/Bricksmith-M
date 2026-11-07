# Part overrides

The overrides folder holds part files that Bricksmith uses instead of the library parts of the
same name. It is set in Preferences > General > Part Overrides and saved as `Part Overrides Path`.

## Layout

The folder has the LDraw folder's layout, without `Unofficial`:

```
overrides/
  parts/        4592.dat          fixes, used at every resolution
  parts/s/      15413s01.dat
  p/            h1.dat
  parts/48/s/   54087s00.dat      high versions of parts and subparts, used in High
  p/48/         t01q1429.dat      high versions of primitives, used in High
```

A part line names a file the same way as in the library: `s\56145s02.dat` finds
`overrides/parts/s/56145s02.dat`, and `48\s\56145s01.dat` finds `overrides/parts/48/s/56145s01.dat`.
Files directly in the folder are not read, nor hidden files and folders, such as the `._4592.dat`
files some disks keep next to each file.

## Search order

`-[LDrawPaths pathForPartName:]` looks in the overrides folder's `parts` and `p` first, and then in
the library: LDraw `parts` and `p`, then `Unofficial`, then the tree bundled in the app. Within the
library, the last match wins. `-libraryPathForPartName:` leaves the overrides folder out, to find
the part an override replaces. `-pathForPartName:usingOverrides:` asks for one side, whether or not
the folder is turned off.

The part catalog scans the overrides folder after every library folder. Its first file of a name is
the one cataloged, so an override keeps the library part's description and category. A part that
only the overrides folder has is added to the catalog, marked `Only In Overrides`, and shows in the
Part Browser while the folder is turned on.

## Resolution

View > Resolution picks Low, Normal or High (Option-Command-1, 2, 3), saved as `Part Resolution`.
A saved value that is none of the three, such as one from a later version, means Normal.
LDraw keeps 48-segment primitives in `p/48` and 8-segment ones in `p/8`, under the primitives' own
names. In High, `-pathForPartName:` looks up `48\` and the name first, and falls back to the name;
Low does the same with `8\`. The overrides folder still comes first, so the order in High is: the
folder's high version, the folder's fix, the library's high version, the library's part. The search
covers `parts` and `p`, so `parts/48` can hold high versions of parts and subparts too. LDraw has no
such folder, so only the overrides folder uses it. A name that already starts with `48\` or `8\` is
looked up as it is.

`LDrawPaths` lists the files in each `48` and `8` folder once, and looks for a high or low version
on disk only when the list names it. Most parts have none, so High costs few extra file checks.
The lists are read again after any change to the paths, a switch of resolution, or turning the
folder off and on.

This makes every part built from standard primitives high or low with no override. A part whose
curves are plain triangles, such as `s\54087s00.dat`, needs its own high version in
`overrides/parts/48/`. Where a high primitive meets triangles drawn for 16 segments, small steps can
show. Model files keep the normal names, so parts lists and the parts limit do not change.

A switch refreshes the loaded parts as described under "Turning the overrides off".
`-libraryPathForPartName:` ignores the resolution, and the compare window shows both sides at the
resolution in use.

How to override:

- A fix goes under the library's own name, in `parts/` or `p/`. It is used at every resolution,
  also where the library has a high or low version of it.
- A high version goes in `parts/48/` or `p/48/` under the same relative path. A part that is fixed
  and high has a file in each.
- A fixed part should use a primitive's normal name where one exists, so it follows the switch.

## Outdated overrides

The release of a file is in its `!LDRAW_ORG` line: `UPDATE 2022-01`, or `ORIGINAL`, which is older
than any update. A part copied from the library and fixed keeps that line. So when the library's
file has a later release, LDraw changed the part after it was copied, and the fix may no longer
be needed. A file with no release, such as one marked `Unofficial_Part`, is not checked. A high or
low version the library does not have, such as `48\s\54087s00.dat`, is checked against the part it
was made from, `s\54087s00.dat`.

`LDrawPartOverride` lists the overrides with both releases, at once or on a background queue.
Preferences shows how many there are and names the first outdated ones; the tooltip has the
releases. It does not mark them as reported. At launch, an alert lists every outdated override,
in a box that scrolls, when one was not reported before. Reported overrides are saved in
`Part Overrides Reported` as "name library-release", so a later library release of the same part is
reported again. A saved part that the listing does not have keeps its entry, so a folder that could
not be read, such as one on a disk that is not mounted, does not clear the record. The text and the
record are in `LDrawPartOverridePresentation` (LDrawFeatures), so another host can show the same.

## Turning the overrides off

View > Use Part Overrides (Option-Command-O) turns the folder off and on, saved as
`Part Overrides Enabled`. Off, `pathForPartName:` skips the folder but keeps its path, so the
Preferences list and the launch alert still read it. The Part Browser leaves out the parts only the
folder has while it is off, and the categories only those parts fill. It is told with the
documents, once the changed parts are read, so the step pictures are not drawn twice.

Library parts are flattened when they load, so a part keeps the geometry of every part it used.
`LDrawPartLibrary` records the file each loaded part was read from, and the names its file uses,
before flattening. A switch, a new resolution or a new folder calls
`-markPartsWhoseFilesChangedWithCompletionHandler:`. On a background queue, against a copy of the
paths, it finds each loaded part that `pathForPartName:` now finds in another file, and each used
part that was missing and is found now. Back on the main queue it adds each loaded part that uses
one of them, however deep, from the parts loaded by then, so a part read meanwhile is not missed. It
marks them, and keeps them loaded, so the documents can still draw them.

`PartLibraryController` then reads the marked parts of the open models and the files they use from
beside them (`+[LDrawUtilities libraryPartNamesInDirective:]`, `-[LDrawModelManager peerFiles]`)
behind a progress panel, for about 40 ms at a
time, with `-freshModelForName:`. It also reads the parts the models use that were not loaded and
have a file now, such as a part only a new folder has. A marked part is read again whenever a part
file that uses it is read, so each part is flattened with the new files. With Metal,
`+[LDrawRenderer prepareDrawingOfDirective:]` draws each once off screen so its smoothed mesh is
built there.

Meanwhile the documents keep drawing the parts they had, and `-modelForName:` still returns them,
so a document that looks its parts up meanwhile does not read them all at once. Last,
`-dropStaleParts` drops the marked parts no model used, and the controller posts
`LDrawPartLibraryReloaded`: the documents, the Part Browser preview and the compare window look
their library parts up again and redraw from the cache. The controller does the same for the peer
files first, since they have no document. Told first, their next draw would read and
smooth every part at once and stop the app; a resolution switch changes every stud, so that is
nearly every part. Turning the folder off and on also shows a file in it that was edited while
Bricksmith runs.

One reload runs at a time. A switch during it, or during a catalog reload, is noted, and the files
are checked again before the documents are told. Every catalog reload, for a new overrides folder,
a new LDraw folder or Reload in Preferences, reads the changed parts after it, so one progress
panel shows at a time. The catalog reload itself does not post `LDrawPartLibraryReloaded`. A
library updated in place, with the same paths, is not found this way.

## Comparing a part

Piece > Compare with Library shows the selected part from the overrides folder next to the
library's. The two views turn, zoom and scroll together. It is off for a part that names a model of
its own file, since that part draws the model. After a reload the window builds the part again
with the same angle, zoom and center, or closes when the two sides are now the same. A minimized
window waits until it is restored, and a closed one is not built again.

`LDrawPartComparison` builds each side as an MPD file. Its first model is the part's file from
that side, and after it come that side's files of every part between it and an overridden part.
A submodel is found before the library, so each side draws its own files whichever way the
switch is set. A part that leads to no override is the same on both sides and comes from the
library. A part the library lacks is an empty model on its side, so the library cannot fill it
in from the overrides folder. Models inside a part's own file are renamed `part#model`, so the
models of two files cannot have the same name. The file is then flattened, as the library
flattens a part. Otherwise each use of a submodel would be its own mesh, and smoothing could not
cross from one to the next, so a curved part would show bands that a model does not.
`-[LDrawFile optimizeStructure]` flattens each model after the submodels it uses: a flattened copy
of a submodel is outside the file, so it could not find a submodel of its own, such as the
`subpart.dat` inside an override file.

Both views stand back from the box around both sides. One view is fitted, and the other copies
its angle, zoom and center, so the parts line up. After that, each change of either camera is
copied to the other once the change is done.

Each comparison gets a new pair of views. A Metal view that is given a second file could stop
being redrawn by AppKit, even though a direct `draw` still worked, so it kept showing the first
part.

## Limits

- The folder applies to every model. To fix a part for one model only, put the fixed part in the
  model's MPD file as `0 FILE 4592.dat` with `0 !LDRAW_ORG Unofficial_Part`. A submodel is found
  before the library, in Bricksmith and in other LDraw programs.
- Other LDraw programs do not read this folder.
