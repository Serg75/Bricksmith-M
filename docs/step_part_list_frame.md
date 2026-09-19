# Step part list frame

**Overview:** Draw a framed parts list for the step currently on display, in the top-left corner of the main (largest) 3D viewport, visible only in Steps view mode and only when the user turns it on in Preferences. Parts are grouped by design + color with a quantity multiplier, drawn at one common scale in a fixed orientation, and packed into the frame. The user can resize the frame per step by dragging its edge, and the size is written back into the open LDraw/MPD document as an LPub-compatible `0 !LPUB PLI CONSTRAIN` meta.

## Plan status

| ID | Phase | Status |
|----|-------|--------|
| `pli_metas` | Phase 0: parse and round-trip `PLI CONSTRAIN`, `PLI SHOW`, `PLI BEGIN IGN`/`PLI END`, `PART BEGIN IGN`/`PART END`, `PLI BEGIN SUB` | completed |
| `pli_collector` | Phase 1: `LDrawStepPartList` — collect and group the current step's parts | completed |
| `pli_packer` | Phase 2: shelf packer with the five constrain modes and oversized-part handling | completed |
| `pli_view` | Phase 3: `StepPartListView` overlay and nested 3D view that draws the layout | completed |
| `pli_prefs` | Phase 4: preference, notification, document wiring, Steps-mode gating | completed |
| `pli_resize` | Phase 5: edge-drag resize, constraint indicators, removal, undoable write-back of `CONSTRAIN LOCAL WIDTH` | completed (routes 1, 3, 4; contextual menu is Phase 6) |
| `pli_polish` | Phase 6 (optional): size annotations, per-entry scale marker, HEIGHT/COLS UI | not started |

Phases 0–2 and 5 land entirely in the packages; Phases 3–4 are the only ones with macOS-app code, and even there the geometry and policy halves stay portable. The iOS smoke build must keep passing after every phase.

## Goals

- A parts list for **the current step only**, in **Steps view mode only**, in the **top-left** of `-[LDrawDocument main3DViewport]` (already defined as the largest viewport).
- Visibility toggled from the Preferences dialog; off by default.
- Parts drawn in a stable, readable orientation that does not depend on how the part happens to be placed in the model.
- Identical parts grouped into one entry with a count, to keep the frame small.
- Per-step frame width (and height) adjustable by the user and persisted **into the document**, in a format LPub3D can read.
- Works on both the Metal and OpenGL app variants. The only renderer change is a shared one: both size their camera from the view's bounds rather than its visible rect, so a nested, clipped view draws at the right scale (see *As built* under Phase 3).
- The layout logic stays Foundation-only and unit-testable without a GPU or a part library render.
- **Maximum reuse on iOS.** Everything except the AppKit chrome lives in the Swift Packages, so an iOS host reuses it by writing only a `UIView` subclass and a pan gesture. See [Module placement](#module-placement).

## Non-goals

- Page layout, printing, or PDF export. Bricksmith has no page model; this is a viewport overlay.
- Full LPub3D PLI fidelity (borders, gradients, substitutions, annotation styles, POV/LDView renderer parameters).
- Bill of materials for the whole model — `PieceCountPanel` already does that.

---

## Part 1 — How other projects do this

### LPub / LPub3D

LPub (Kevin Clague) and its successor [LPub3D](https://trevorsandy.github.io/lpub3d/) (Trevor Sandy) are page-layout engines: they read an LDraw/MPD file, render each step's assembly (CSI, "current step image") and each step's parts list (PLI, "parts list image") with an external renderer (Native/LeoCAD, LDGLite, LDView, POV-Ray), and lay the results out on printable pages. Everything configurable is expressed as an `0 !LPUB …` meta comment written back into the model file, so the layout travels with the model. That is the mechanism this feature copies.

The relevant metas ([full list](https://trevorsandy.github.io/lpub3d/assets/docs/lpub3d/metacommands.html), [mirror](https://www.bouwstone.nl/ldraw-manual/meta-commands/)):

| Meta | Meaning |
|------|---------|
| `0 !LPUB PLI CONSTRAIN (AREA/SQUARE/(WIDTH/HEIGHT/COLS) <n>)` | how the icons are packed into the box |
| `0 !LPUB PLI SHOW <TRUE/FALSE>` | show/hide the parts list |
| `0 !LPUB PLI SORT <TRUE/FALSE>`, `PLI SORT_BY SORT_OPTION <"…">` | sort on/off; key is Part Size / Part Color / Part Category / Part Element / No Sort |
| `0 !LPUB PLI MODEL_SCALE <float>` | one global scale for every icon — **parsed**, see *Drawing at LPub3D's scale* |
| `0 !LPUB PLI VIEW_ANGLE <float> <float>` | latitude/longitude the icons are rendered at — **independent of the assembly's rotation** |
| `0 !LPUB PLI INCLUDE_SUBMODELS <TRUE/FALSE>` | whether submodel references get an entry |
| `0 !LPUB PLI BEGIN IGN` … `0 !LPUB PLI END` | exclude a range of parts from the list |
| `0 !LPUB PLI BEGIN SUB <part> [<color>]` … `PLI END` | show a different part in the list than the one in the model |
| `0 !LPUB PLI INSTANCE_COUNT FONT/FONT_COLOR/MARGINS …` | styling of the "3x" multiplier |
| `0 !LPUB PLI ANNOTATE …`, `PLI ANNOTATION DISPLAY/USE_TITLE/USE_FREE_FORM …` | text stamped on an icon (e.g. a beam's stud length) |
| `0 !LPUB PLI MARGINS`, `PLI PART MARGINS`, `PLI BORDER …`, `PLI BACKGROUND …` | box chrome |
| `0 !LPUB PLI PLACEMENT …` | where the box sits relative to PAGE / ASSEM / STEP_NUMBER / CALLOUT |

Every meta takes an optional scope keyword between the command and the value: `GLOBAL` (LPub3D writes it in the top model's header, but reads it like a line with no keyword: from that line on) or `LOCAL` (for the rest of this step). See *Which meta line is in force* below. So a per-step width is written as:

```
0 !LPUB PLI CONSTRAIN LOCAL WIDTH 3.2400
```

placed inside the step it applies to, after any other CONSTRAIN in that step. LPub3D writes these lines itself when the user drags or right-clicks the parts list, which is exactly the interaction model requested here.

**What counts as a part.** Two rules, both copied. First, the parts list only ever holds what LPub3D's part library has a piece for: in `Pli::partSize()` a part with no `PieceInfo` that is neither a submodel nor an unofficial inline part is dropped with *"Part [x] was not found - part removed from list"*. LeoCAD's library files primitives and the `s\` subparts as primitives, not pieces, so a step made of primitives — the inside of a hand-built part — lists nothing. Second, an MPD subfile is a submodel unless its header says otherwise: `getUnofficialFileType()` in `ldrawfiles.cpp` matches `0 !LDRAW_ORG Unofficial_Part` (Subpart, Primitive, 8_/48_Primitive, Shortcut, with or without an Alias or Physical_Color qualifier), the older `0 Unofficial Part` / `0 UNOFFICIAL PART`, and `0 !LDCAD GENERATED`, case-insensitively, among the subfile's header lines; nothing found means `UNOFFICIAL_SUBMODEL`. A subfile so marked fails `isSubmodel()`, so it gets no pages of its own, is listed in its parent's PLI regardless of `INCLUDE_SUBMODELS`, is rendered from its contents, and is titled by its first line (`Pli::titleDescription()`). Note that an *official* header — `0 !LDRAW_ORG Part` — is not in the list: an official part inlined verbatim reads as a submodel to LPub3D.

*As built:* `-[LDrawModel isInlinePart]` applies the header rule (the type line must be among the leading meta commands of the first step, where the header parses to); `+[LDrawStepPartList entryForPart:]` lists such a submodel as one part titled by its description whatever the submodel preference says, and drops a reference to a primitive or subpart — by folder (`s\`, `48\`, `8\`) always, and by the catalog's Primitives / Subparts category when a library is registered. A hand-built part like `88704 orig` therefore shows an empty list while its own step is on display, and one row in the step that places it once its header carries `0 !LDRAW_ORG Unofficial_Part`.

*Bricksmith's own extension, beyond LPub3D:* people keep hand-built parts as headerless MPD submodels, and the Porsche's whip is three of them deep — `88704 bent` places `88704 handle` (subparts and primitives) and `88704 hose` (an LSynth hose plus two `88704 hose part half`, which are raw quads and conditional lines). `+[LDrawStepPartList isPartLikeModel:]` calls a model a part when its header says so, *or* when every step holds nothing but primitives, subparts, raw geometry, LSynth directives and submodels that are themselves part-like; one catalog part, or one assembly submodel, makes it an assembly, and an empty or meta-only model is not a part. A part-like submodel is listed as one row titled by its description whatever the submodel preference says, and a part-like model on display lists nothing — LPub3D makes no pages for a part, so its insides never meet a PLI. Cycles are guarded by the path being walked.

**Grouping.** LPub3D merges entries on the pair *(part design ID, color code)* and prints a quantity multiplier. Known caveat worth copying deliberately or not at all: for a submodel built *N* times, LPub3D's PLI counts one instance, not *N* ([issue #298](https://github.com/trevorsandy/lpub3d/issues/298) asks for a manual override).

**Frame size.** `CONSTRAIN` picks the packing strategy; `WIDTH`/`HEIGHT` values are in page units (inches, or centimeters depending on a global preference), `COLS` is an integer column count. `AREA` minimizes the box area, `SQUARE` aims for a square box. Internally the type is `PliConstrain { Area, Square, Width, Height, Columns }` with a `{ width, height, columns }` value struct. Because LPub3D's units are *printed page* units, the common alternative to `CONSTRAIN` for making a list fit is `PLI MODEL_SCALE`, and users routinely swap `0 !LPUB BOM CONSTRAIN LOCAL WIDTH 11` in for `0 !LPUB BOM MODEL_SCALE 0.6`.

**Manual placement.** There is no per-icon drag; sorting is the only ordering control, and a per-part offset exists in the data model (`PliPartGroupData` carries `offset[2]`) but is applied via the `PLI PART GROUP` machinery rather than free dragging.

### BrickLink Studio — Instruction Maker

[Studio](https://studiohelp.bricklink.com/hc/en-us/articles/5627862550935-Parts-List-Settings) exposes the same object as direct manipulation instead of metas. The parts list is a box at the top of each step; clicking it opens settings for background color, border (color / thickness / roundness), **Parts size** (a slider + numeric field that scales every icon in the box), and part-count font/color/size. There is no per-part scale; the single global slider is the escape hatch for a list that doesn't fit. Callouts are the answer for submodels: a submodel's steps collapse into a beige box with a leader line, [recommended for submodels of three steps or fewer](https://open-l-gauge.eu/making-building-instructions-in-studio/).

The lesson: a single "parts size" control plus a resizable box covers almost all real cases, and users understand it immediately.

### Lic / Web Lic

[Lic](http://bugeyedmonkeys.com/lic/about/) (and Web Lic) auto-lay-out steps to fill a page and can generate a whole-model inventory page. Its PLI packing is not documented; the standard approach for this shape of problem is 2-D shelf packing with a decreasing-size presort — [first-fit-decreasing](https://en.wikipedia.org/wiki/First-fit-decreasing_bin_packing) or [next-fit-decreasing](https://en.wikipedia.org/wiki/Next-fit-decreasing_bin_packing) — because all item sizes are known up front. Exact minimization is NP-hard, so a heuristic is the right call. Note that part icons are rectangles only in the sense of their projected bounding box; angled and irregular parts waste a lot of cell area, which is why real LEGO instruction books hand-tune.

### Ideas worth stealing

1. **Store the layout in the file, as `!LPUB` metas.** Portable, diffable, already how this codebase handles `!LPUB REMOVE GROUP`.
2. **A fixed PLI view angle, independent of the assembly rotation** (`PLI VIEW_ANGLE`). Without it the same brick appears at a different angle in every step.
3. **One common scale for all icons**, so relative part sizes read correctly — plus one global scale control as the escape hatch.
4. **`PLI BEGIN IGN` / `PLI END`** to exclude repositioning helpers and jigs from the count. Cheap to honor and a real compatibility win.
5. **Annotations** (stud length / part title) stamped on the icon. For a 1×32 Technic beam the annotation, not the picture, is what identifies it.
6. **Callouts** as the long-term answer to submodels, rather than dumping submodel contents into the step list.

---

## Part 2 — What we build

### Existing machinery to reuse

| Need | Existing code |
|------|---------------|
| Target viewport | `-[LDrawDocument main3DViewport]` — already "the largest viewport" (`LDrawDocument.m:4839`) |
| Compositing a Cocoa view over a GL/Metal surface | `NSView (OverlayViewCategory)` `addOverlayView:` / `removeOverlayView:` (`Bricksmith/Categories/OverlayViewCategory.m`), via `OverlayHelperView` + `OverlayHelperWindow` child window. Already used by `FocusRingView` |
| Drawing arbitrary directives in a small view | `LDrawViewerContainer` + `LDrawView` (`setLDrawDirective:`, `setViewOrientation:`, `setViewingAngle:`, `zoomToFit:`, `setFocusRingVisible:NO`, `setAcceptsFirstResponder:NO`) — the pattern `PieceCountPanel` and the part browser already use |
| Grouping parts by design + color with counts | `LDrawPartReport` (`partReportForContainer:`, `getPieceCountReport`, `flattenedReport`, `PART_REPORT_PART_QUANTITY`), `+previewPartFromRecord:` |
| Current step | `-[LDrawModel stepDisplay]`, `-visibleStep`, `-maximumStepIndexForStepDisplay`, `-rotationAngleForStepAtIndex:` |
| Default 3D angle | `+[LDrawUtilities angleForViewOrientation:]`, `LDrawViewportPolicy` |
| LPub meta parsing with auto-registered subclasses | `LPubCommand` + `LDrawClassInspector firstLevelSubclassesFor:`; `LPubRemoveGroup` is the worked example |
| Host-injected preference into portable code | `+[LDrawModel setGhostsPreviousSteps:]` / `setGhostAlpha:` pushed from `LDrawApplication.m:390-392` |
| Preference plumbing | `LDrawKeys.h` key + notification, `LDrawPreferences.m` `initialDefaults`, `PreferencesDialogController`, `-[LDrawDocument ghostAlphaChanged:]` as the observer template |
| Undoable directive insert | `-[LDrawDocument addStepComponent:parent:index:]`, `LDrawInsertion` |

### Module placement

**Guiding rule: as much of this feature as possible lives in the Swift Packages, so an iOS host gets it for free.** The macOS app target keeps only the AppKit chrome — the view that draws the frame, the mouse tracking, the Preferences checkbox, and the `LDrawDocument` glue. Everything else (parsing, collecting, grouping, packing, frame geometry, resize arithmetic, label text, color and font *values*, document write-back, localization keys) is Foundation-only package code, unit-testable without a GPU and compilable for iOS.

Concretely: on iOS the whole of Phases 0–2 and 5, and the non-drawing half of Phases 3–4, should be reusable verbatim. The only work an iOS host should have to do is subclass a `UIView` for the frame chrome, add it as a subview of its `MTKView`, and wire a pan gesture to the resize API.

| Module | Platforms | Contents |
|--------|-----------|----------|
| **LDrawCore** | macOS + iOS | `LPubPliConstrain` — parse + serialize. `LPubPliShow`, `LPubPliIgnore` — parse only. New keywords in `LDrawKeywords.h`, new preference keys and the change notification in `LDrawKeys.h`. `LDrawStepPartListEntry` (the value type) |
| **LDrawFeatures** | macOS + iOS | `LDrawStepPartList` — collector, grouper, sort. `LDrawStepPartListLayout` — the packer, the five constrain modes, oversized-part rules, scale floor, overflow reporting. `LDrawStepPartListModelBuilder` — turns a layout into an `LDrawModel` of positioned `LDrawPart`s, built of LDrawCore types only. `LDrawStepPartListPolicy` — frame origin/margins/insets in the host view, resize and pin hit-test regions, drag→size arithmetic and where a drag stops, inch↔point conversion and both clamps, whether each axis is pinned by the step's own CONSTRAIN (Phase 5), plus the *values* the chrome needs (border and badge RGBA, label point size, multiplier format string). Preference defaults seeded in `LDrawPreferences.m`; host-injected statics following the `+[LDrawModel setGhostsPreviousSteps:]` convention |
| **LDrawEditing** | macOS + iOS | Nothing, as built. `LDrawStepPartListEdit` was planned here — find-or-create/update/remove the `LPubPliConstrain` directive in a step and the undo-action localization key; mirrors `LDrawInsertion` in that the module decides *what* changes and the host owns the undo manager and the actual insert — but lives in LDrawFeatures; see *As built* under Phase 5 |
| **LDrawRenderCore** | macOS + iOS | Nothing new expected. If a camera preset for the icon view is needed, it goes here — **not** in the app, and never in LDrawRenderOpenGL, which cannot build for iOS |
| **Bricksmith app** (macOS only) | — | `StepPartListView` (`NSView`: border, pins, the nested `LDrawView`, and a point-based resize API), `StepPartListChromeView` (quantity labels, size annotations), and `StepPartListController` (attaches via `addOverlayView:`, observes the notifications, and routes the document window's mouse and key events to the frame through an `NSEvent` monitor, since the overlay's window ignores the mouse). Preferences checkbox + XIB. `LDrawDocument` wiring |

Conventions this has to respect, all already established in the codebase:

- **No `standardUserDefaults` reads inside the packages.** The host pushes preference values into statics, as `LDrawApplication.m:390-392` does for the ghost settings.
- **No AppKit/UIKit types in package headers.** Geometry uses `MatrixMath`'s `Point2` / `Size2` / `Box2` / `Box3`, not `NSRect`. Colors cross the boundary as RGBA floats (precedent: `LSYNTH_SELECTION_COLOR_RGBA_KEY`, `setBackgroundColorRGBA`). Fonts cross as a point size and a weight enum.
- **Strings cross as localization keys**, localized by the host — the pattern `+[LDrawPartReport pieceCountSaveDialogTitleKey]` and `+[LDrawInsertion undoActionKeyForInsertKind:]` use.
- **Contextual-menu content is enumerated by the module** (a list of command identifiers + enabled state + title keys); the host builds the `NSMenu`. That keeps the Phase 6 menu portable too.

The practical test for whether the split is right: `LDrawStepPartListLayout` and `LDrawStepPartListPolicy` must be exercisable end-to-end from a test that never creates a view, and the iOS smoke build (`ios_smoke_build` in the modularization plan) must keep passing after each phase.

---

### Phase 0 — `pli_metas`: the meta commands

Three new `LPubCommand` subclasses, each following `LPubRemoveGroup` exactly (`+lpubCommandInstance:` token match, `finishParsing:` no-op, `browsingDescription`, `iconName`, `initWithCoder:`/`encodeWithCoder:`/`copyWithZone:` (CONSTRAIN only, as built), `registerUndoActions:`):

```objc
// 0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] (AREA | SQUARE | (WIDTH|HEIGHT) <float> | COLS <int>)
@interface LPubPliConstrain : LPubCommand
@property (nonatomic) LPubMetaScope        scope;      // Unspecified | Global | Local
@property (nonatomic) LPubPliConstrainMode mode;       // Area | Square | Width | Height | Cols
@property (nonatomic) float                inches;     // for Width/Height
@property (nonatomic) NSInteger            columns;    // for Cols
@end

// 0 !LPUB PLI SHOW [GLOBAL|LOCAL] (TRUE|FALSE)
@interface LPubPliShow : LPubCommand
@property (nonatomic, readonly) LPubMetaScope scope;
@property (nonatomic, readonly) BOOL          isShown;
@end

// 0 !LPUB PLI BEGIN IGN   /   0 !LPUB PLI END
@interface LPubPliIgnore : LPubCommand
@property (nonatomic, readonly) BOOL beginsRange;
@end
```

Rules:

- Any other `PLI …` line keeps falling through to plain `LPubCommand`, which already round-trips the text verbatim via `lPubCommandString`. **This is a hard requirement** — a file using the other ~30 PLI metas must survive open/save unchanged.
- CONSTRAIN, which Bricksmith writes, is written back in the canonical form (`CONSTRAIN LOCAL WIDTH %.4f` — four decimals, matching LPub3D's page-size precision convention), not the parsed-from text. A meta Bricksmith only reads keeps its text, as LPub3D rewrites a line only when its user changes the setting.
- `LDrawInspection` / `LDrawOutline` / syntax coloring: reuse the existing `SYNTAX_COLOR_REMOVE_GROUP_KEY` treatment for LPub commands; add inspector rows only if the generic `InspectorLPubCommand.xib` is insufficient.

Tests (Xcode `UnitTests` target, next to `LPubRemoveGroup_Tests.m` / `LPubCommand_Tests.m`): each grammar variant parses; scope keyword optional; unknown variants stay `LPubCommand`; write-out round-trips; malformed lines do not crash the parser (see commit `2c68ba0`).

**As built.** `LPubMetaScope` lives on `LPubCommand`, which also reads the optional scope keyword for every subclass (`+scopeInParameters:index:`). Only `LPubPliConstrain` writes one, in `-updateCommandString`. One thing the plan did not anticipate: the generic `InspectionLPubCommand` edits an LPub directive by writing `lPubCommandString` straight through, which would leave a PLI directive's parsed properties stale while Phase 5's write-back reads them. So the base `-setLPubCommandString:` parses the new text again with the subclass's `+lpubCommandInstance:` and hands the result to `-adoptPropertiesFromCommand:`, which each subclass overrides; the setter never changes the class, so text that no longer matches the grammar stands as typed and the properties keep their last valid values. The same hook serves the base `-copyWithZone:` (properties from the original, then the text as typed) and undo (the base registers only the old text, and each subclass names its action through `-undoActionKey`). The base `-finishParsing:` hands the rest of the line to that setter for every class, so a line read from the file is kept as typed, like one typed in the inspector, and CONSTRAIN still writes its own form.

*Read-only metas.* Only `LPubPliConstrain` has setters, a fixed write-back format and coders of its own. The metas Bricksmith only reads — `LPubPliShow`, `LPubPliIgnore`, `LPubPliSubstitute`, `LPubModelScale`, `LPubResolution`, `LPubPageSize`, `LPubPageOrientation`, like `LPubPliCameraAngles` and `LPubPliPartRotation` — have read-only properties. The text is their only source of truth and is kept as typed, spaces included, so `PLI MODEL_SCALE 1.2` is saved as it was read, and to change one a caller sets `lPubCommandString`. They archive nothing but the base's text, which decoding parses again. So a line edited into text that no longer parses and then pasted comes back with zero properties rather than its last valid ones; the inspector swaps such a line for a plain command first, so this does not happen through it.

The inspector does not use the setter when the class changes. When editing ends (Enter, Tab, or focus loss), `InspectionLPubCommand` asks `-[LPubCommand replacementForText:]`, which parses `0 !LPUB <text>` the way opening the file does and returns nil when that gives the same class. Then the setter takes the text, as above. Otherwise the inspector waits one main-queue turn, finds the open document that holds the command, and calls the undoable `-[LDrawDocument replaceDirective:withDirective:]`. It puts the new directive at the same index, selects it in place of the old one if that was selected, and registers the reverse swap as its undo. The wait is needed because the swap rebuilds the inspector while its text field is still ending editing. So a plain command typed as `PLI CONSTRAIN LOCAL WIDTH 3` becomes a real CONSTRAIN, and a CONSTRAIN typed out of the grammar becomes a plain command: the parts list stops reading it, and a resize inserts a new line instead of overwriting the typed text, which is LPub3D's rule too. Only an edit in `InspectionLPubCommand` swaps; the raw-command inspector does not.

Syntax coloring is unchanged on purpose: these lines were generic `LPubCommand`s before and fell to `SYNTAX_COLOR_UNKNOWN_KEY`; they still do, so nothing in the outline shifts color.

---

### Phase 1 — `pli_collector`: what goes in the list

`LDrawStepPartList` walks the step on display and returns ordered entries.

```objc
@interface LDrawStepPartListEntry : NSObject
@property (nonatomic, readonly) NSString   *partName;      // e.g. "3001.dat"
@property (nonatomic, readonly) NSString   *displayTitle;  // library description
@property (nonatomic, readonly) LDrawColor *color;
@property (nonatomic, readonly) NSUInteger  quantity;
@property (nonatomic, readonly) Box3        modelBounds;   // untransformed part bounds
@property (nonatomic, readonly) BOOL        isMissing;     // reference does not resolve
@end
```

Collection rules:

- Source is **only** `[model visibleStep]` — not the accumulated steps before it.
- Group key is *(canonical part name, LDraw color code)*, the same key `LDrawPartReport` uses. Prefer building on `LDrawPartReport partReportForContainer:` with the step as the container rather than writing a second traversal.
- **Parts hidden by the user are still listed.** Hiding is a viewing convenience — the builder still needs the part for this step, so leaving it out of the list would be wrong. The list therefore does *not* track "what is currently drawn"; it tracks "what this step consumes". An entry carried an `isHidden` flag for a while, on the theory that a later phase would mark such rows; nothing ever drew it, and it was dropped. A marker would collect the flag again.
- Parts suppressed by `0 !LPUB REMOVE GROUP` **are** excluded. That is a statement in the document that the group is not part of the build at this point, not a viewing preference — so those parts genuinely aren't consumed. Reuse `-[LDrawModel updateGroupSuppressionIfNeeded]` and the `LDrawGroupable` state for the check.
- Skip parts inside an `0 !LPUB PLI BEGIN IGN` … `0 !LPUB PLI END` range.
- Submodel references: excluded by default, matching LPub3D's `PLI INCLUDE_SUBMODELS FALSE`. When included, one entry per submodel reference, not its contents.
- LSynth: one entry for the LSynth part itself; its synthesized children are not counted.
- Missing/moved parts still get an entry (with a placeholder icon), so a broken reference is visible rather than silently dropped.
- Default sort: projected size descending → part name → color code. Size-descending is both the LPub3D default and what makes the packer in Phase 2 behave.

Tests: same part in two colors → two entries; same part twice in one step → quantity 2; hidden part still listed; `REMOVE GROUP` part excluded; `PLI BEGIN IGN` range excluded; submodel reference excluded by default; previous steps' parts excluded; deterministic ordering.

**As built.** Three things came out differently from the sketch above.

*`LDrawPartReport` is not the right base.* The plan preferred building on `partReportForContainer:`; it turned out to disagree with this feature on every requirement that matters. It flattens a submodel reference into the submodel's contents (we want the reference, or nothing), drops unresolved references (we want to show them), knows nothing of the hidden or removed-group flags, and walks a tree rather than a sequence — so it cannot see where a `PLI BEGIN IGN` range starts and stops. `LDrawStepPartList` walks the step's directives directly. What it does reuse is the grouping key, part design plus color code.

*Ghosted counts as removed.* The plan says parts suppressed by `REMOVE GROUP` are excluded. A ghosted part is suppressed too — the ghost is a reading aid for something taken out of the build — so the test is `groupVisibility != Visible`, not `== Hidden`. In practice Steps mode always hides rather than ghosts, so this only matters if the ghosting preference ever reaches step display.

*What needs a part library, and what does not.* Whether a reference resolves, what the part is called, and what its bounds are all need the catalog, and asking for it when none is registered trips `+[LDrawPartLibrary sharedPartLibrary]`'s assertion. A new `+sharedPartLibraryIfRegistered` returns nil instead, and the collector degrades honestly: with no catalog, every non-submodel reference reads as an ordinary part, `displayTitle` falls back to the part name, and `modelBounds` is `InvalidBox3`. That is what makes the collector testable in the renderer-free `UnitTests` target — but it also means the catalog-fed half is not covered there. Submodel detection is covered, because `referencedMPDSubmodel` resolves from the enclosing file's model names alone. Note that bounds must be measured *after* the include-submodels decision: measuring a submodel we are about to discard resolves every part inside it.

`LDrawStepPartListEntry` gained an `isSubmodel` flag alongside `isMissing`, and is immutable — accumulating an instance returns a new entry. Sorting is by bounds volume descending, then name, then color code, and is stable, so full ties keep the step's order; with no catalog every volume is zero, so the name/color keys carry the ordering. Phase 2 replaces volume with the projected footprint.

LSynth is handled as the plan asks — one row for the band or hose itself, its synthesized children never counted, since the collector does not open it. It has no library model behind it, so it carries `InvalidBox3` bounds; whatever draws an icon has to treat that the way it treats a missing reference. Every other container, such as a `!TEXMAP` texture, is opened in place before the walk, so its parts are listed and IGN and SUB ranges still read in file order.

---

**`PART BEGIN IGN` too (added later).** LPub3D writes `0 !LPUB PART BEGIN IGN … 0 !LPUB PART END` around an alternate or spare part -- the Porsche has 25 of them, e.g. a "motor left part alt" sitting next to the real motor -- and those parts are kept out of its parts list and bill of materials while still being built. It is parsed into `LPubPliIgnore` with `branch = LPubPliIgnoreBranchPart`, written back as it was read, and the collector keeps one depth per branch, so a `PART END` never closes a `PLI BEGIN IGN` range or the other way round.

**`PLI BEGIN SUB` (added later).** `0 !LPUB PLI BEGIN SUB <part> [<color> …] … 0 !LPUB PLI END` lists one part in place of everything in the range: a hinge plate is one part in the bag, but LDraw draws its two halves so each can turn, and the Porsche's left door wraps the halves in a SUB for `2429c01.ldr` in white. It is `LPubPliSubstitute` -- part name, optional color, anything after the color kept verbatim and written back. The collector keeps one stack of open PLI ranges, because IGN and SUB share `PLI END` and each END closes the range opened last; a SUB lists its substitute once when its range closes (or at the end of the step if it never does), nothing inside it is listed -- including parts in a nested `PART BEGIN IGN`, which is how the left door has it -- and a SUB inside a range that lists nothing of its own is not listed either. With no color, the substitute takes the first enclosed part's. The substitute goes through the same path as a real reference for bounds, title and whether it resolves; a `.ldr` or `.mpd` name the catalog does not know is tried as `.dat`, since LPub3D accepts `2429c01.ldr` for the library's `2429c01.dat`. *Later:* the file's own submodel of that name comes before either. LPub3D's `PliBeginSub1Rc` handling in `traverse.cpp` calls `setUnofficialPart(part, UNOFFICIAL_PART)` on a submodel the SUB names, so it is listed as one part, drawn from its contents, titled by its first line, and never opened — the Porsche's fenders name `2429c01.ldr`, a hand-assembled hinge kept as a submodel, and were being listed as the catalog's `2429c01.dat` instead. Every submodel row is now titled by the submodel's first line, as `Pli::titleDescription()` titles it, falling back to the name.

### Phase 2 — `pli_packer`: layout

**Common scale.** All entries render at one scale, as LPub3D and Studio do. The scale is a single number (points per LDU) derived from the frame width and the packed content, and exposed later as a "parts size" control.

**Cell size.** Project the entry's `modelBounds` through the frame's view rotation and take the screen-space extent; that plus the quantity label's height is the cell. This is a bounding-box approximation and will waste space on angled parts — accepted, same as every other tool.

**Packing.** Shelf packing, next-fit-decreasing:

1. Sort entries by cell height descending (ties by area).
2. Fill a row left→right while the next cell fits the frame's content width; otherwise start a new row.
3. Frame height = sum of row heights + margins.

**Constrain modes**, mapped from `LPubPliConstrain`:

| Mode | Behavior |
|------|-----------|
| `WIDTH <in>` | fixed width, grow downward. **The primary mode**; what the drag gesture writes |
| `HEIGHT <in>` | fixed height, grow rightward |
| `COLS <n>` | fixed column count; width follows from the widest cell per column |
| `SQUARE` | search candidate widths, minimize `abs(w - h)` |
| `AREA` | search candidate widths, minimize `w * h` |

Default when the step has no `CONSTRAIN` meta: the `CONSTRAIN` in force for the step (see *Which meta line is in force*), else the preference default, else `AREA`.

**Very large parts.** A 1×32 beam or a large baseplate is ~30× the extent of a 1×1 plate; at a common scale it either dominates the frame or forces everything else down to unreadable. Applied in order:

1. **Cap the cell.** If a cell's width exceeds a fraction of the content width (default 60%), scale *that entry only* down to fit and mark it (a small "reduced scale" glyph in the cell corner). Preserves legibility of the other 95% of parts. Neither LPub3D nor Studio does per-entry scale; this is a genuine improvement and cheap once the packer is ours.
2. **Give it its own shelf.** An oversized entry occupies a whole row, centered. Prevents the ragged rows that a wide cell would otherwise create.
3. **Annotate the real size.** Derive `1x32`-style dimensions in studs from `modelBounds` and stamp it on the cell. Cheap version of LPub3D's `PLI ANNOTATION`, and for long parts it is the actual identifying information.
4. **Global auto-shrink.** If the packed height still exceeds the frame's height budget, reduce the common scale, floored at a legibility minimum (a stud must stay a few points across). Same behavior as LPub3D's `MODEL_SCALE` escape hatch.
5. **Overflow affordance.** If the floor is hit and it still doesn't fit, truncate and show `+N more`, clickable to open the full `PieceCountPanel`-style list for the step. Better than a silently-clipped list.

Later options, not in the initial scope:

6. **Per-entry compact projection** — rotate an oversized part to its smallest projected footprint. Shrinks a long beam a lot, but breaks the "every icon at the same angle" rule; gate behind a threshold and a preference.
7. **Two-scale rendering** — normal parts at the common scale, long parts at a marked reduced scale, as printed LEGO books do.

Tests: width constraint respected for a mixed set; oversized entry gets its own row and a reduced scale; row count matches `COLS`; `SQUARE`/`AREA` beat a fixed width on their own metric; the scale floor is honored and overflow is reported rather than clipped; layout is a pure function of (entries, constraint) — same input, same output.

**As built.** `LDrawStepPartListLayout` takes four inputs — entries, an `LDrawStepPartListConstraint`, a `Matrix4` view transform, and an `LDrawStepPartListMetrics` struct — and returns `LDrawStepPartListPlacement`s. Two things the sketch left open had to be decided:

*Metrics are a struct, not preferences.* Everything the packer needs beyond the parts and the constraint — dpi, base and minimum scale, cell padding, label height, frame padding, the cell-width fraction, the height budget — is one plain struct with a `+defaultMetrics`. That is what makes "pure function of its inputs" literally true and the whole thing testable without a view. The host turns preferences into metrics; the packer never sees a preference.

*`COLS` is a grid, not a shelf.* The other four modes shelf-pack. Columns can't: "width follows from the widest cell per column" only means anything if cells line up in columns, so that mode runs its own grid packer and every cell in a column takes that column's width. Per-entry capping is also skipped there — capping exists to stop one oversized part deciding the scale inside a box whose width is *pinned*, but in `COLS` the width is derived from the parts, so an oversized one simply gets a wide column, which is what asking for N columns means.

The searching modes (`AREA`, `SQUARE`, and `HEIGHT`'s width search) try the running totals of the cell widths as candidate widths. This is a heuristic, not a full search: a width between two totals can still pack differently. Ties break toward the narrower candidate, which keeps the result reproducible.

Oversized rules 1–3 and 5 are in; rule 4's auto-shrink is a 0.9-per-round loop down to `minimumScale`. Rule 3's stud annotation (`"1x32"`) is computed for every placement, not just oversized ones — it is derived from the untransformed bounds and costs nothing, so the view can decide when to draw it. Rule 5 drops whole shelves off the bottom rather than clipping, and reports the count; it does not yet reserve room for the "+N more" line itself.

The cap compares the icon's padded box with the limit, because only the icon shrinks; a cell that is wide only for its labels is left alone. The box is as wide as its widest shelf, whatever the `WIDTH` asked for. A `WIDTH` narrower than that shelf grows to it, so no cell runs past the frame. A wider one closes up to the parts with no blank space, as in LPub3D, which sets the parts list's size to the packed size (`size[0] = pliWidth` in `Pli::resizePli`). A `WIDTH` only sets where the shelves wrap.

Coordinates are points with the origin at the content box's top-left and y increasing downward.

*Stacking (added later).* Shelves are *filled* tallest part first — the presort that keeps shelf packing tight — but *stacked* with the heaviest at the bottom, so the big parts settle and the small ones sit on top, the way parts laid out on a table do. The list knows no masses, so a part weighs as much as its bounding box's volume, and a shelf as much as its heaviest part; shelves of equal weight keep packing order reversed. When the list overflows it is the lightest shelves, at the top, that are dropped, and the "+N more" notice is drawn along the top where they were rather than over the biggest parts. Within a shelf the parts stand on a common line at the *bottoms of their icons*. Every cell on a shelf keeps its multiplier the same way, all beside their parts or all in strips, so every cell hangs the same distance below its icon. Aligning the cell bottoms therefore aligns the icons, and a shelf is as tall as its tallest cell. The annotation strip is above the icon, so it does not move the line.

*Room for the labels (added later).* A label in a strip is centered across its cell, but nothing made the cell as wide as the label. A hand-built part in the same model — `88704 orig` and `88704 handle`, a hose assembled from segment subparts and `3-8edge` / `4-4disc` primitives — gave each primitive a cell a point or two wide, and the "1x" under each piled onto the next; a tiny real part used a dozen times would do the same with "12x". A cell is now at least as wide as any label in its strips, the multiplier's and the badge's, with the icon kept at its own size and centered; `iconFrame` is the icon's own box, in a column-widened cell too. The searching modes take their candidate widths from these label-aware cells, so they do not search with widths narrower than the shelves they then build. The primitives themselves still draw as specks, which is their true size.

*Submodels draw (added later).* With *include submodels* on, a submodel reference got its cell but only the dashed placeholder, because the builder left submodels out: the icon model is a throwaway outside the document, and a part finds its submodel by name through its enclosing file, which the icon model does not have. The obvious ways to give it one were each worse — moving the submodel into the icon model takes it out of the document, copying it is a deep copy on every repack, and hanging the icon model under the document's file routes its change notifications into the document. Instead `+modelForLayout:viewTransform:submodelsFromFile:` takes the document's file, and a submodel entry becomes a private `LDrawPart` subclass whose `-referencedMPDSubmodel` returns the document's own submodel, or the peer file of that name, asked of `LDrawModelManager` for the document's file as the collector's `-referencedPeerFile` does. From there it is LDrawPart's usual path: the part observes the submodel while the icon model lives and stops when it is deallocated, since `-dealloc` unresolves. `-isDrawablePlacement:` is now simply "not a broken reference". A submodel also no longer carries a stud annotation, which would describe a part that is not there.

An entry with no bounds — a broken reference, a synthesized part, or anything at all when no catalog is loaded — gets a one-stud placeholder cell rather than a zero-size one, and no stud annotation. Any axis that projects to zero (a plate seen edge-on) is clamped to 1 LDU, which also keeps the capping arithmetic from dividing by zero.

---

**A submodel is measured by its parts (added later).** A cell was sized from one bounding box, projected. For a part that is close to exact; for a submodel it is one box around every part, and a single part reaching out along an axis nothing else uses stretches that box into empty space. At the list's angle the empty corner became a blank band beside the icon -- the Porsche's "motor left part" measured 166 LDU across as a box and 99 as drawn, because `88704.dat` reaches to x = −87 while everything else sits within ±30. A submodel entry now carries `outlinePoints`: the eight corners of each of its parts' own boxes, placed in the submodel (nested submodels followed down, omitted parts and steps past the displayed one skipped, the same way the submodel's bounds are counted). Corners rather than boxes, because re-boxing a rotated part grows the box again. The packer measures the cell from those points, keeps their hull with every corner as the outline, and `+projectedCenterOfEntry:viewTransform:` gives the middle of what it measured, which is where the model builder now centers the icon. For a single part that middle is the projection of the box's center, so nothing else moves. The points are collected once per row, not per instance.

**A pinned HEIGHT arranges, it does not shrink (added later).** A `CONSTRAIN HEIGHT` used to be a budget: the packer shrank every icon until the list fit it. LPub3D's resize grip writes heights of a few pixels into real files -- the Porsche's steps 39–41 carry `HEIGHT 0.0823529`, `0.111765` and `0.205882`, which are 14, 19 and 35 pixels at its 170 dpi -- and those lists shrank to the legibility floor, a strip of specks. LPub3D reads a HEIGHT as the height of the columns and gives a part taller than that a column of its own at full size. So does the packer now: the search still arranges by the pinned height, but only `maximumHeight`, the room on screen, shrinks icons or drops shelves.

**The icons are drawn from LPub3D's parts list angle (added later).** With "follows step rotation" off -- LPub3D's model, one angle for the document -- the icons used Bricksmith's MLCad-style 3D view. That turns out to be *exactly* LPub3D's assembly default, latitude 23, longitude 45, while its parts list defaults to 23, **-45** (`DEFAULT_PART_CAMERA_LATITUDE` / `_LONGITUDE` in `declarations.h`): the same tilt seen from the other side, so every icon was the mirror of LPub3D's -- obvious on a submodel such as "front bamper assembled", and on the left door's 1×2 plate, whose long side ran the other diagonal. LPub3D, like Bricksmith, draws each part at the identity rather than at its placement in the step (`pli.cpp` writes `1 <color> 0 0 0 1 0 0 0 1 0 0 0 1 <type>`).

The angle now comes from `0 !LPUB PLI CAMERA_ANGLES [GLOBAL|LOCAL] <latitude> <longitude>`, or a named view (FRONT, BACK, TOP, BOTTOM, LEFT, RIGHT, HOME, LAT_LON, resolved as `CameraAnglesMeta::parse()` does) with optional numbers of its own, or the legacy `VIEW_ANGLE` LPub3D rewrites to it -- `LPubPliCameraAngles`, written back verbatim -- else the 23, -45 default. `+viewTransformForLatitude:longitude:` reproduces `lcCamera::SetAngles`: the camera starts at LeoCAD's (0, -1, 0), turns about Z by the longitude, tilts about its side axis by the latitude, and comes back to LDraw axes as (x, -z, y); the rotation is built from the camera's right, up and viewing vectors rather than Euler angles. A test pins 23, 45 to the old MLCad angle, which is the check that no sign was lost.

**`PLI PART_ROTATION` (added later).** `0 !LPUB PLI PART_ROTATION [GLOBAL|LOCAL] <x> <y> <z> [ABS|REL|ADD]` is LPub3D's `PliMeta::rotStep`, parsed by the same `RotStepMeta::parse()` as a ROTSTEP: three angles and an optional type. `LPubPliPartRotation` builds LPub3D's `matrixMakeRot()` matrix, transposed for Bricksmith's row vectors, and the part is turned by it before the camera looks. As in `createPartImage()` and `rotateParts()`: `ABS` is the whole view, so the camera angles go to 0, 0 -- unless `CAMERA_ANGLES` is a custom viewpoint (`HOME` or `LAT_LON` with numbers of its own, which is also the only form LPub3D accepts numbers after a view name for); `REL` and `ADD` keep the camera; a line with no type is parsed but applies no rotation, because `rotateParts()` skips an empty type.

The per-part orientations LPub3D reads from its PLI control file are applied first; see below.

**LPub3D's PLI control file.** `Pli::orient()` gives every parts list icon a base orientation before any `PART_ROTATION` or camera: it looks the part up in the file named by `Preferences::pliControlFile` and, if a type-1 line references it, uses that line's 3×3 matrix; otherwise identity. The file is `pli.mpd` in LPub3D's `extras` folder (a per-library variant exists: `LEGOPliControl.ldr`, `TENTEPliControl.ldr`, `VEXIQPliControl.ldr`), chosen in LPub3D's preferences. The shipped one is an MLCad-authored MPD of 420 part lines grouped into submodels by category -- Technic angle connectors, beams, axles and the like -- each turned so it reads well in a list; `32523.dat`, which the Porsche uses, is among them. Only the matrix of a line counts; its position and color are ignored, and a part listed twice takes its first line. LPub3D's only editing is Configuration ▸ Edit Parameter Files ▸ PLI Parts Control File, which opens it as text in the detached command editor or the system editor -- there is no visual editor, but because it is an ordinary MPD it can be opened in any LDraw editor and the parts turned there.

**Reading the control file (added later).** `LDrawPartListOrientations` reads it as `Pli::orient()` does: fifteen-token lines starting `1`, keyed by lower-case part name, the first line for a part winning, only the matrix kept -- transposed for Bricksmith's row vectors. The collector gives each entry its `listOrientation`, and `+transformForEntry:viewTransform:` composes it before the list's view (which already carries `PART_ROTATION` and the camera), so the order is LPub3D's: orient, rotate, look. The packer measures with that transform and the model builder draws with it. Only in LPub3D's model -- icons not following the step's rotation -- because following the step, the icons are meant to line up with the assembly.

The file is chosen in Preferences ▸ Parts ▸ Part orientations (`Step Part List Orientations File`); with nothing chosen, LPub3D's own is used if it is installed, looked for as `extras/pli.mpd` or `extras/LEGOPliControl.ldr` under `~/Library/Application Support/LPub3D Software/LPub3D` (or `LPub3D Software Maint`). It is read once at launch and again whenever a file is chosen, not on every repack; an edit made to the file while Bricksmith is running is picked up by choosing it again. The row reports the file and how many parts it orients -- 413 distinct parts in LPub3D's shipped `pli.mpd` of 420 lines.

### Phase 3 — `pli_view`: drawing it

Two viable approaches; the recommendation is (A).

**(A) One nested `LDrawView` drawing a synthetic layout model — recommended.**

Build a throwaway `LDrawModel` containing one `LDrawPart` per entry, each with a translation placing it at its packed cell center and **identity rotation** (see "Orientation" below). Hand it to a single small `LDrawView` with an orthographic camera at the frame's view angle. Quantity labels and chrome go in a sibling transparent `NSView` layered above.

- One renderer change, applied to both variants: `-[LDrawRendererMTL mtkView:drawableSizeWillChange:]` and `-[LDrawViewGL reshape]` size the camera from `bounds`, not `visibleRect`. A clipped nested view otherwise gets a camera for the sliver on screen, and keeps it after it scrolls back into view. `LDrawRenderer` also gains `-viewPointForModelPoint:`, the inverse of `-modelPointForPoint:`, for pinning the overlay to the model.
- One extra GPU surface per document, created lazily only while the frame is visible.
- A single ortho camera naturally gives every part the same scale — which is the behavior we want.
- Per-entry scale-down (Phase 2, rule 1) is expressed as a scale in that part's transform, which the existing draw path already handles.

**(B) Offscreen render each icon to an `NSImage`, compose in a plain `NSView`.** Crisper per-cell control, trivial text, easy caching across steps. But there is no offscreen render path in either backend today (grep for `IOSurface`/`NSOpenGLPixelBuffer`/render-target textures finds nothing), so this means new code in both `LDrawRenderMetal` and `LDrawRenderOpenGL`. Worth revisiting if (A)'s extra surface causes trouble, or when this list needs to be exported to an image.

**(C) A HUD pass inside the main renderer** with its own viewport and projection. Cheapest at runtime, but requires touching `LDrawRendererMTL` and `LDrawRendererGL`, and text rendering in the GL path is painful. Rejected.

**View hierarchy**

```
LDrawViewerContainer  (main, largest viewport)
 └─ LDrawView                                   <- the assembly
     └─ addOverlayView: StepPartListView         <- child window, OS-composited
         ├─ LDrawView (nested, non-interactive)  <- the packed part icons
         └─ StepPartListChromeView               <- border, background, "3x" labels,
                                                    size annotations, resize handles
```

`StepPartListView` positions itself at the top-left of the host view's bounds inset by a margin, and re-lays-out when the host resizes (`OverlayHelperView` already tracks the parent's size). It asks `LDrawStepPartListPolicy` for that frame rather than computing it, so the same origin/margin/clamp rules apply on iOS; the view itself only draws. The synthetic layout model it renders is built by the LDrawFeatures builder, so nothing about the icon geometry is macOS-specific — the only per-platform piece is which view class hosts the surface (`LDrawView` here, an `MTKView` on iOS). The nested `LDrawView` gets `setAcceptsFirstResponder:NO`, `setFocusRingVisible:NO` (this method exists for exactly this reason — see its comment about the Minifigure window), `showsScrollbars = NO`, and editing disabled.

**Orientation.** Each icon is drawn from its *library-native* transform, not its placement transform in the model — otherwise the same brick shows up at a different angle in every step. The camera then supplies the angle. Two sources:

- **Default: the step's own rotation**, `[model rotationAngleForStepAtIndex:currentStep]` — i.e. the rotation the MPD file specifies for this step via `ROTSTEP`, matching the request and staying consistent with what `-[LDrawDocument updateViewingAngleToMatchStep]` already does for the assembly.
- **Alternative: a fixed angle**, `[LDrawUtilities angleForViewOrientation:LDrawViewOrientation3D]`, which is LPub3D's model (`PLI VIEW_ANGLE`, default lat 23 / lon −45) and gives a stable icon appearance across the whole book.

Make it a preference, defaulting to following the step. If a future `0 !LPUB PLI VIEW_ANGLE` is honored, it overrides both.

**Redraw triggers:** step changed, active model changed, step contents edited (`LDrawDirectiveDidChangeNotification`), `LDrawStepDidChangeNotification`, preference changed, viewport resized, group-suppression or part-library reload notifications.

**As built.** Approach (A), with four corrections to the sketch above.

*The builder is in LDrawFeatures, not LDrawCore.* It consumes an `LDrawStepPartListLayout`, and LDrawFeatures depends on LDrawCore rather than the other way round. It emits nothing but LDrawCore types, which is what that placement was really after.

*The camera must not be rotated.* The sketch has the parts at identity rotation and the camera at the frame's angle. That cannot work: the layout positions are screen positions, so rotating the camera would turn the whole list with it. Each part instead carries the rotation itself — `translate(-boundsCenter) · scale · rotate · translate(cellCenter)` — and the camera looks straight down -Z in orthographic. Recentering on the bounds first is what puts a part in the middle of its cell whatever its own origin is, and LDraw part origins are rarely at the centroid.

*The zoom is the load-bearing number.* `zoomPercentage = layout.scale × 100`, because the camera divides the visible model size by zoom/100 — so at 100% one LDU is one point. The labels and markers are drawn from the layout in points, so if this is wrong they sit beside their icons instead of on them. Same for the packer's `viewTransform`: it must be the same rotation the parts get, or the cells are measured for a different picture than the one drawn.

*The overlay is viewport-sized, not frame-sized.* `OverlayHelperWindow` always tracks the parent's whole visible rect, so `StepPartListView` fills the viewport and draws its frame in a sub-rectangle of its own bounds, the way `FocusRingView` draws a ring in its. That also means `-hitTest:` has to return nil, or the entire model becomes unclickable; Phase 5 claims just the resize edges.

Three layers, bottom to top: `StepPartListView` (the border — its background was a translucent white until it showed up as a pale inner band around the icons, and is now clear), a nested `LDrawViewerContainer` (the icons), and `StepPartListChromeView` (multipliers, stud annotations, reduced-scale markers, placeholders, the overflow notice). The top layer is separate because a superview draws *behind* its subviews — labels painted by the container would end up under the icons.

`LDrawStepPartListPolicy` arrived early, with the Phase-3 subset: frame origin and margin, the viewport height budget, the display clamp on a page-sized `WIDTH`, and the chrome values (RGBA, point sizes, the multiplier format). Phase 5 adds hit-testing, drag arithmetic and the per-axis indicators.

`StepPartListController` exists and works but nothing attaches it yet — that is Phase 4's `LDrawDocument` wiring, along with the preference and the Steps-mode gating. Until then the overlay is unreachable from the UI, so none of the drawing has been seen on screen; the geometry is covered by tests but the appearance is not.

---

### Phase 4 — `pli_prefs`: preference and wiring

New key and notification in `LDrawCore/…/LDrawKeys.h`, alongside the ghost keys:

```objc
#define SHOW_STEP_PART_LIST_KEY          @"Show Step Part List"
#define STEP_PART_LIST_SUBMODELS_KEY     @"Step Part List Includes Submodels"
#define STEP_PART_LIST_FOLLOWS_STEP_KEY  @"Step Part List Follows Step Rotation"

#define LDrawStepPartListDidChangeNotification  @"LDrawStepPartListDidChangeNotification"
```

- Seed in `LDrawPreferences.m` `initialDefaults`: `SHOW_STEP_PART_LIST_KEY` = `@NO` (a new overlay must not appear unannounced), width = `@2.5` in, submodels = `@NO`, follows-step = `@YES`.
- Checkbox (plus the secondary controls) in `PreferencesDialogController`, in the same pane as the existing ghosting controls (`PreferencesDialogController.m` ~301 / ~563 / ~587 / ~639), posting `LDrawStepPartListDidChangeNotification`.
- `LDrawApplication` pushes the values into `LDrawStepPartList` statics at launch and on change, exactly as it does at `LDrawApplication.m:390-392`. **LDrawFeatures must not read `standardUserDefaults` directly** — that is the established convention here.
- `LDrawDocument` observes the notification (template: `-ghostAlphaChanged:`, `LDrawDocument.m:4208`) and attaches or detaches the overlay.
- Gating: attached only when `[[docContents activeModel] stepDisplay] == YES` **and** the preference is on **and** either the step's effective `PLI SHOW` is not `FALSE` or the step is drawn on LPub3D's page (`+[LDrawStepPartListPolicy showsListOrPageInModel:]`). Detached in `-setStepDisplay:` when leaving Steps mode, and re-attached to the new main viewport when the viewport arrangement changes (`viewportArranger:willRemoveViewports:` and friends).

**As built.** The keys, the notification and the defaults are as specified. Three things are worth recording.

*A document may suppress the list, never force it on.* The gate is `preference AND stepDisplay AND not suppressed`. A `0 !LPUB PLI SHOW FALSE` in force for the step hides the list, read by the same scope rules as every other meta (see *Which meta line is in force*), but a `SHOW TRUE` in somebody else's file cannot switch on an overlay this user turned off. Files come from other people; the preference is the user's own. `+[LDrawStepPartList isShownForVisibleStepOfModel:]` resolves the whole rule, so an iOS host inherits it. The overlay itself is gated by `+[LDrawStepPartListPolicy showsListOrPageInModel:]`: a step that hides its list still gets the overlay when it is drawn on LPub3D's page, and the overlay draws only the page there.

*One gate, called from six places.* `-[LDrawDocument updateStepPartList]` is the only thing that attaches or detaches, and everything that can change the answer routes through it: the preference notification, `-setStepDisplay:`, `-setCurrentStep:`, `-activeModelChanged:`, `-loadDataIntoDocumentUI`, and both viewport-arranger callbacks. `-viewportArranger:willRemoveViewports:` detaches only when a removed viewport is the overlay's host or the one watched for the page fit — that viewport is about to deallocate and the overlay holds a child window on it. A surviving host stays attached and watched, so when a split closes it refits as it grows. `-viewportArrangerDidRemoveViewports:` then puts the overlay on whichever viewport is largest.

*The default constraint is `WIDTH <preference>`, not `AREA`.* The plan's ordering was GLOBAL, else the preference default, else AREA; since the preference always holds a value, AREA is only reached when a document asks for it with an explicit `CONSTRAIN AREA`. The document's lines are honored: `+[LDrawStepPartListPolicy constraintForVisibleStepOfModel:]` takes the CONSTRAIN in force for the step, else the preference, and `+inheritedInchesForAxis:inModel:` measures a resize against the same lookup with the step's own line left out. A GLOBAL or unscoped line carries on to later steps, so it is never the step's own: a resize on the step holding it inserts a LOCAL rather than rewriting it. (Later: that default width is only where the shelves wrap, so a step with no CONSTRAIN gets a frame that closes up to its widest shelf, where before it always took the full 2.5 in however few parts there were. Later still, a WIDTH written in the document or set by a drag closes up the same way, as in LPub3D, and the `widthIsLimit` flag that told the two apart is gone. Later again, the width preference was removed. On the page a step with no CONSTRAIN in force packs by `AREA`, as LPub3D does. Off the page the document's lines are not read, and `+viewportConstraintForHostSize:pointsPerInch:` packs with a `WIDTH` of four tenths of the view.)

The preference pane adds a "Parts List" section to the LDraw tab, below Ghosts: the show checkbox, include-submodels, follow-the-step-rotation, and a default width in inches. (Later: the width field is gone; see the default constraint above.) A dragged width is clamped to 0.75–6.0 in off the page. A dragged height has its own, lower floor of 0.25 in (`+minimumHeightInInches`): a height is a ceiling the icons shrink under, and LPub3D files pin heights well under an inch.

Verified at runtime under the debugger: the pane's nib loads with no KVC failures, all four outlets connect, the checkbox reflects the stored value, and `+[LDrawStepPartList isEnabled]` receives it.

**Two bugs the first run on a real model turned up**, both from the same root — an `LDrawView` cannot exist at a size its camera cannot project (`-[LDrawCamera makeProjection]` asserts on an empty visibility plane):

1. *The nested view was created at `NSZeroRect`* in `-initWithFrame:` and only resized later. It is now built lazily in `-showLayout:model:viewTransform:`, with the content rectangle it will actually occupy, and torn down again — not merely hidden — whenever there is no list. A content rectangle smaller than 8 points a side counts as no list, which also covers the case where the policy's viewport clamp leaves less room than the frame padding needs.

2. *The overlay's own bounds are 1×1 at first reload.* `OverlayHelperWindow` starts its child window off-screen at 1×1 and only sizes it once it begins tracking the parent, so the first reload after attaching sees a viewport with no room in it. The controller now observes `NSViewFrameDidChangeNotification` on the overlay and repacks — which is needed for window resizing anyway, and makes the initial jump to full size just another resize.

With those fixed, attaching to a real model produces a frame at the expected place and size (12 pt margin, 375 pt wide for the 2.5 in default at 150 dpi) with its placements packed.

**Two more the first look on screen turned up.**

*A removed overlay stayed on screen.* `-[NSView removeOverlayView:]` drops the helper view, which detaches the child window from its parent — but never orders it out, so the "removed" overlay carried on floating over the viewport, and the next `-addOverlayView:` stacked another on top. Visible as a parts list that survived switching back to All mode. Fixed in `OverlayViewCategory` itself, since a remove that leaves the thing on screen is plainly wrong; `FocusRingView`, the only other client, wants the same behavior. Verified: three Steps→All→Steps cycles leave exactly one overlay window (plus the focus ring's).

*Icons drew far too small, differently per step, and never recovered.* `-[LDrawRendererMTL mtkView:drawableSizeWillChange:]` sizes the camera from the view's `-visibleRect`, and AppKit only narrows a descendant's visible rect to its own bounds when some ancestor **clips**. Inside a non-clipping overlay the nested 3D view reported the whole viewport (1196×720) as visible while actually being 363×52, so its camera was built for a surface three times too big. Because the error tracked the window rather than the frame, the apparent scale changed with every repack and going back a step did not restore it. `StepPartListView` and the icon container now clip (through KVC, as `-clipsToBounds` is only declared from macOS 14 and the deployment target is 12). `-showLayout:` also forces `-layoutSubtreeIfNeeded` before touching the camera, because `LDrawCamera` ignores a zoom it already holds and would not re-derive the projection from a stale surface on the next reload either.

Verified on a real model: the camera's surface size now matches the icon container exactly, on first display and after stepping.

**Three more from looking at an LPub3D-authored model** (a 10274 Porsche RSR, which carries 897 `!LPUB` lines including 70-odd per-step `PLI CONSTRAIN LOCAL HEIGHT`):

*`HEIGHT` fell back to the worst layout when the budget was impossible.* Those file-authored heights are printed-page inches; at 150 dpi many are far too short for a screen overlay, so no candidate width fits. The search then minimized width among infeasible candidates, which picks the single-column tower — the tallest box available, and narrow enough that the 60% cell cap shrank every part on the way down. It now falls back to the *shortest* layout instead. This was the cause of the cramped, marker-covered frames, not the cap itself.

*Every entry is labeled now, `1x` included.* Suppressing it read as "the count is missing", and made the eye work out which label belonged to which cell. LPub3D and the printed books both show it.

*The stud annotation is drawn, in a strip of its own.* It was computed in Phase 2 and never used. Drawing it in the cell's top-right corner — the obvious place — turned out to be wrong for a reason worth writing down: **a cell is the part's projected bounding box, so which of its corners are empty depends entirely on the part's shape and the view angle.** On a compact plate the top-right corner is solid geometry and the text landed on the part; on a diagonal beam it is empty and the text floated away from it. LPub3D avoids this by placing annotations against a tightly cropped *rendered image*, where the edges are the part's real silhouette; we have no offscreen render, so the equivalent is to stop competing for space at all. The packer now reserves an `annotationHeight` strip at the top of any cell that will carry one, and the view draws into that. Placement becomes independent of the shape.

Deciding *whether* to annotate therefore moved from the policy to the packer, since it changes the cell's size: shown for a part at least three times longer than it is wide, and for any part the packer shrank on its own. *(Later changed to a size test; see below.)* `LDrawStepPartListPlacement` carries `annotationText` and `annotationFrame`.

*The 60% cell cap now applies only to a pinned width.* Looking at why so many parts came out orange: in `AREA`/`SQUARE`/`HEIGHT` the candidate width is derived *from* the cells, so the cap fired on the very part that set it — and with a single entry it fired every time, marking an ordinary part as reduced. The cap exists to stop one huge part crowding out the others in a box whose width was imposed from outside, which is only `WIDTH`. `COLS` was already exempt for the same reason.

**Two more from stepping through the same model.**

*Labels go beside the part, not past its ends.* Most of the long parts in that model — 1×4 to 2×8 plates and tiles, 1×6 and 1×8 Technic bricks — are diagonal bars at the step's three-quarter angle. A cell is the projected bounding box, so each bar sat in a tall cell with two opposite corners empty, and the strips put the multiplier below the bar's lower end and the annotation above its upper end, a long way from most of the part. Turning long parts to lie across the list was tried and dropped: it breaks the rule that every icon is drawn at the same angle.

Instead the packer looks at the shape. The part's bounding box, projected, is a convex polygon — a hexagon at most angles — that the part never crosses, and each cell keeps it as its `outline`. Each label first looks for room in an empty corner of the icon's padded box — the multiplier at the bottom, the annotation at the top, the same sides as their strips — then slides in toward the middle until it is `decorationGap` points clear of the polygon and of the other label. Only a label with no room in either corner falls back to its strip. Where both corners fit, the one that ends nearer the middle wins; the multiplier goes first, since it is what a builder counts. The packer has no fonts, so the room it looks for is sized from `labelCharacterWidth` and `annotationCharacterWidth`, set a little wide of the policy's point sizes. What it cannot see is empty space *inside* the box — a slope or a round part counts as solid to its corners — because only a rendered image knows the real silhouette.

In practice, at the default scale on that model: the multiplier finds a corner beside most diagonal bars; the wider badge fits beside the longer ones (the 1×8 Technic brick, the 2×8 plate) and otherwise stays in its strip, which for a diagonal bar is directly above the bar's upper end. A compact part fills its box, so its labels stay in their strips as before. At the identity view every box projects to a full rectangle with no empty corners, which is why the existing geometry tests did not change.

*Three from reading a full shelf (added later).* Shelves now carry `rowGap` blank points between them — a cell is its content's bounding box with no margin of its own, so neighboring shelves touched. The multiplier and the stud annotation both use `×` (U+00D7) instead of the letter x: it is what part names and the printed books use, and one character either way, so the packer's character-count sizing is unchanged. And the frame has an opaque background again, derived from the viewport's own color and moved 10% toward white over a dark viewport or toward black over a light one — the earlier translucent white read as a pale band, but fully clear left the list without an edge. The nested 3D view clears to its own color, so it is handed the same tint; it answers the background-color preference notification by reading the plain preference straight back, so the frame re-applies the tint on the next run-loop pass, where observer order cannot matter.

*One search, not two (added later).* The count was placed twice: nested along a diagonal path from whichever bottom corner of the cell the part left empty, then re-placed by the shelf pass, which recomputed both coordinates and threw the nested box away. Two search strategies answered one question by different methods, and they could disagree. `NestBoxInCorner`, `NestBoxInBestCorner`, `CornerStartForBox` and the corner enum went with the old path.

*Counts on the bottom line (added later).* A count beside its part now sits only on the bottom line of the icon's padded box. It is put in the bottom-left and in the bottom-right corner and slid with `SlideBoxToward` toward the centered place on that line, stopping `decorationGap` short of the outline; of the two, the one that ends nearer the middle is kept. The outline is convex, so along a line the places that touch it form one stretch: if any place on the line is clear, a corner is. That is the same test the earlier 33-place search made, so the same cells drop their strip, and cell sizes, shelf heights, shrinking and overflow did not change. Only the count's height moved: beside a long diagonal it no longer rises toward the middle of the box. The search for each count's highest clear line, the 33 sampled places and the shelf pass that brought counts back down to one line all went.

The strip is decided per shelf when the shelf is measured: `+heightOfRow:metrics:` adds `labelHeight` when any cell on the shelf has no room beside its part, and placement then draws every count on that shelf in its strip. Packing no longer changes cells, so the copies that let one set of cells be packed at several widths went too. A cell is as wide as its count either way, since a count that fits beside its part is never wider than the icon's box. The badge is let down clear of the count beside its part; on a strip shelf there is none, so it avoids nothing.

Outlines are kept in `NSData` of any length, so the fixed outline arrays went. The sixteen-corner cap (`FitOutline`) stays: a submodel's hull with more corners is still replaced by the sixteen-sided polygon around it, so a count that only just fits beside such a submodel goes to the strip as before, and no size changes.

*Annotated by size, not by shape (added later).* The trigger was elongation -- three times longer than wide -- which annotated a 1x4 and a 1x3 while leaving a 4x6 plate bare. Wrong way round: up to four studs a builder counts them off the drawing, and the number is clutter; past four a 1x6 and a 1x8 are the same drawing at different lengths and only the number tells them apart. A part is now annotated when its longer side measures more than `STUDS_WORTH_ANNOTATING` studs, so a 2x6 gets a badge and a 4x4 does not. The studs are rounded the way the badge's own text is, so the number shown and the number tested are never a hair apart. A part the packer shrank on its own still earns one whatever its size.

*Tiles are annotated sooner.* A tile is smooth, so there is nothing on top to count: a 1x3 and a 1x4 are the same blank strip, a 2x3 and a 2x4 the same blank slab. A part whose library description names it a tile -- first word `Tile`, after stripping LDraw's `=`, `~`, `_`, `|` markers -- is annotated when its longer side is more than `TILE_STUDS_WORTH_ANNOTATING` (2) studs, so a 1x3 or a 2x3 gets a badge and a 1x1, 1x2 or 2x2 does not. Only the first word decides, so "Brick 1 x 2 with Tile" keeps the brick rule, and "Tiled" is not "Tile". Corner and round tiles get their footprint ("2×2"), which is what a builder counts.

*Badges stopped competing for corners (added later).* Letting the badge nest in a corner the way the multiplier does was tried and dropped. It put the badge wherever the part's shape left room, which is a different place on every cell, and on a shelf mixing a long beam with a small brick no two badges could be brought onto one line: a cell's outline is at its widest across the middle -- it is a projected box, so it spans the whole cell there -- and a badge coming down from a top corner is stopped at the middle at the latest.

Every badge now goes in its strip, centered across the cell, and is then let straight down until it is `decorationGap` clear of the part, stopping at the middle of the icon's box at the latest. The strip is reserved above the whole icon box, and a part drawn at an angle does not reach the top of that box across its width -- so a badge left on the strip's own line hangs over an empty corner rather than over the part. Letting it down closes that gap without moving it off the middle, where the eye looks for it. Centering beats nestling here because the badge says what the part *is*, and a reader looks for that above the part, not wherever its silhouette happens to leave a hole.

The multiplier still nestles, but it is now pulled toward the middle of its cell rather than toward the part: of the clear places on its line, the one nearest the middle wins. A count reads as belonging to the cell it sits under, and a count pushed out to an edge reads as belonging to the gap between two cells. How near the middle it gets is whatever the part allows on that line and no further.

Both labels also sit a point closer to their parts: `decorationGap` went from 2 to 1.

*Counts line up along a shelf (added later).* Nesting each multiplier wherever its own part left room scattered them: three counts at three heights under three parts standing on the same line, which is exactly the row-by-row comparison the shelf is for. This is decided per shelf. If any part on the shelf has no room beside it, every count on that shelf goes in its strip — half a shelf tucked in and half hanging below reads as neither. Otherwise every count sits on the bottom line of its icon's box, and the icons on a shelf stand on one line, so the counts share it with no pass of their own.

*The annotation is a badge.* As bold text, the size annotation and the multiplier were the same kind of mark a few points apart, and the eye had to work out which was the count. LPub3D draws PLI annotations inside a filled, bordered shape — rectangle, square or circle by part category ([issue #186](https://github.com/trevorsandy/lpub3d/issues/186)) — and prints the instance count as plain text. This follows it: the multiplier stays plain bold text under the icon, and the annotation becomes a light, outlined pill in its strip above, turning orange with light text when the packer shrank the part on its own. The chrome gained `annotationFillRGBA`, `annotationBorderRGBA` and `annotationTextRGBA`, and `annotationHeight` went from 11 to 13 points to hold the outline.

---

### Drawing at LPub3D's scale

**What LPub3D's scale is.** `Render::stdCameraDistance` places the camera so that one stud covers `20 × resolution.ldu() × resolution.value() × scale` dots, and `ResolutionMeta::ldu()` answers `1.0/64`. So the size LPub3D aims for is **1 LDU = 1/64 inch × MODEL_SCALE** — life size on the printed page, since a stud then measures 20/64 in ≈ 7.94 mm, a real brick. (The true LDU is 0.4 mm = 1/63.5 in; LPub3D rounds, and matching LPub3D matters more than matching the millimetre.) LDView and POV-Ray get that distance multiplied by 0.775 and 0.455, which read as corrections so all three renderers land on the same on-page size.

Our `baseScale` was 0.5 points per LDU; it is now 1.0 -- a part in the list is the size it is in a viewport at 100%, which is how Bricksmith opens a model and how the part browser shows one. With our point at 1/150 in that is still **2.3× smaller** than LPub3D's absolute size; parity is `pointsPerInch / 64 × modelScale` = 2.34375 at the default resolution. Drawn on LPub3D's page, the page scale replaces it.

**Two metas parsed for it.** `LPubModelScale` covers `0 !LPUB (PLI|ASSEM|BOM) MODEL_SCALE [GLOBAL|LOCAL] <float>` — one class, three branches, since the leaf means the same thing under each — and `LPubResolution` covers `0 !LPUB RESOLUTION [GLOBAL|LOCAL] <float> (DPI|DPCM)`, which is what every length in a file is written in and the dots every picture is rendered at. `+[LPubModelScale inchesPerLDU]` is the 1/64 above, in one place. Both are read-only metas (see *Read-only metas* under Phase 0): the text is written back as it was read, a malformed line is left to the generic `LPubCommand`, and properties are re-derived when the raw text is edited.

Grammar checked against real files rather than the meta-command list, which gives the spelling but no defaults: LPub3D writes `0 !LPUB ASSEM MODEL_SCALE GLOBAL  1.1500` — two spaces before the value — and `0 !LPUB RESOLUTION GLOBAL 170 DPI`, with the scope keyword before the value in both.

**The preference is the switch between two behaviors.** Off, the list is ours: it is packed with `+[LDrawStepPartListPolicy viewportConstraintForHostSize:pointsPerInch:]` -- shelves four tenths of the view wide -- the document's own `PLI CONSTRAIN` lines are ignored, no pins are drawn, and the frame does not answer the mouse. Those lines are written in page inches, and off the page there is nothing to measure them against, nor a page for a resize to write one back in. On, the document decides: its `CONSTRAIN` is honored, the pins show which axes the step sets itself, and the frame can be dragged. (Later: "on" means there is a page, `+drawsPageInModel:` -- the preference, Steps mode and a file that measures its page. With the preference on and no `PAGE SIZE`, the list used to honor the document's inches against the bare viewport; it now behaves as with the preference off.)

*The presentation (added later).* What the host draws for a step is worked out in one package object, `LDrawStepPartListPresentation`, so an iOS host gets the same sequence: place the page around the projected anchor, choose the host box, scale the metrics and chrome to the page, fit the height budget after that, choose and clamp the constraint, pack, build the icon model and resolve the pins, including a drag's preview. The host passes what only a view can measure in an `LDrawStepPartListHostState` (view size, drawn scale, projected anchor, drag) and applies the result to its views. `-[StepPartListController reload]` went from about 110 lines to ten; the icon angle rule moved to `+[LDrawStepPartListPolicy viewTransformForVisibleStepOfModel:]` and the drag's edit to `+[LDrawStepPartListEdit editForDraggingAxis:toInches:inModel:]`. With the gate above, the "scaled but off the paper" branch of the metrics and chrome scaling had no caller and is gone. The presentation also places the frame and the icon area inside its padding (`frameRect`, `contentRect`, with the 8 point floor under which nothing is drawn) and hands over the icon camera, so the view takes one `-showPresentation:` and reads rectangles instead of working them out. Three smaller rules moved with it: `+controlAtPoint:inFrame:widthPinned:heightPinned:` answers which control is under the pointer (a drawn pin beats its edge), `+getListBackgroundRGBA:forViewportRGBA:` gives the frame's tint, and `LDrawStepPartListPageAnchor` keeps the drawn-scale ratio behind `-noteDrawnPointsPerLDU:atZoomScale:` and `-assemblyScaleForZoomScale:`, which the controller and the page fit both use.

*The page fit moved to the package (added later).* `LDrawStepPartListPageFitter` holds the rules of Zoom to Fit on the page: the target scale, the resize ratio against the size it last fitted, the two passes that aim the drawn scale at the target, when to measure the anchor again, and the drawn-scale ratio it leaves on the anchor. It drives the view through `LDrawStepPartListPageView`, four camera calls `LDrawView` already had (zoom, set zoom, points per LDU at a point, scroll a point to the center), so an iOS host only makes its view conform. `-[LDrawDocument fitLPubPageInViewport:keepingMagnification:]` passes the viewport and its visible size, and the fitted size moved from the document into the fitter.

*The press and the drawing decisions moved to the package (added later).* `LDrawStepPartListResizeTracker` follows one press on the frame: it asks the policy which control is under the point, starts a resize on an edge with the drag's origin and the inherited size it snaps to (now carried on the presentation, `-inheritedInchesForAxis:`, instead of asked of the controller), and answers the size each move asks for. The view keeps only the cursors and the delegate calls, so an iOS pan gesture drives the same object. The chrome view's remaining rules went to the policy too: `+badgeStyleForScaledDownPart:chrome:` gives a badge's fill, border and text colors, `+overflowNoticeRectForContentWidth:chrome:` places the notice of parts left out, and the placeholder's dash and gap are chrome values. What is left in the two views is AppKit: strokes and fills, fonts and text measuring, cursors, the child window and the nested 3D view.

*One walk per redraw (added later).* Every meta lookup for a step in a submodel walks the file from its first model to the submodel's first placement, and a redraw makes about a dozen of them. Measured on a 6,000-part main model with a submodel placed at its end, a redraw cost 20 ms for a submodel step against 1.3 ms for a main-model step, and the drag redraws on every move. `+performWithCachedLookups:` keeps that walk, as the `!LPUB` lines met on the way (one group per step, a dead-end submodel dropped), for the length of one block; the controller wraps each reload in it, so a submodel step now costs 1.8 ms. The cache lives only inside the block, so an edit can never read a stale walk. The mouse and camera gates read the last presentation's `isOnPage` instead of looking the page up on every event.

**Wired up behind a preference.** `Step Part List Uses LPub Scale`, default off. With it on, `baseScale` comes from the page — see *Drawing on LPub3D's page* below — and the rest of the packer is unchanged, so the height budget and auto-shrink still apply, and a frame that shrank is no longer at LPub3D's scale. The chrome marks each cell it had to shrink; there is no marker for a whole list that shrank.

RESOLUTION counts only on LPub3D's page. There its DPI cancels, and its unit says what PAGE SIZE is measured in. Off the page the preference width is read at LPub3D's default 150 dpi, so a file's RESOLUTION does not resize the list. A `CONSTRAIN` is always read and written in inches, even in a DPCM file, where LPub3D reads it in centimeters.

`+modelScaleForBranch:inModel:` and `+pageSizeInInchesInModel:` share one lookup with every other meta: the line in force for the step being shown (see *Which meta line is in force*). Each branch is read on its own, and the parts list asks for `PLI` — a file commonly sets `ASSEM`, `PLI` and `BOM` to three different values.

**Seeing a step at LPub3D's size.** `LPubPageSize` covers `0 !LPUB PAGE SIZE [GLOBAL|LOCAL] <width> <height> [<name>]` and `LPubPageOrientation` covers `PORTRAIT | LANDSCAPE`; `+pageSizeInInchesInModel:` reads them together. A document written in centimeters — `RESOLUTION … DPCM` — measures its page in them too, so the reader converts. The orientation is read as naming the *long* side rather than as an instruction to swap, because files disagree about which way round they write the two measurements and a swap-on-landscape rule turns an already-turned page twice; with no orientation line at all the measurements stand as written.

A page *named* rather than measured (`PAGE SIZE A4`) stays a generic `LPubCommand`, and Zoom to Fit fits the model as usual. Resolving the name would mean keeping our own table of page dimensions and hoping it agrees with LPub3D's; answering "this document does not say" is honest and cheap. A name after the measurements is kept and written back.

### Drawing on LPub3D's page

The preference `Step Part List Uses LPub Scale`, default off, makes the viewport a window onto the printed page rather than a box the overlay is fitted into. Everything it changes derives from one number:

```
page inch in points = (zoom / 100) / (inchesPerLDU × ASSEM MODEL_SCALE)
```

read backwards from the assembly: the viewport is drawing one LDU at `zoom/100` points, and LPub3D would draw it at `1/64 in × ASSEM`, so the page is on screen at that many points to the inch. From there,

* `metrics.pointsPerInch` becomes it, so a `CONSTRAIN WIDTH 1.5` frame covers the fraction of the viewport that 1.5 inches covers of the page;
* `metrics.baseScale` becomes `pointsPerPageInch × inchesPerLDU × PLI MODEL_SCALE`, which reduces to `zoom/100 × PLI / ASSEM` — the icons hold the proportion to the step that LPub3D prints, at every zoom;
* the page itself is drawn as a dashed rectangle at `pageInches × pointsPerPageInch`, with everything outside it dimmed -- what is off the paper will not be printed, and a bare rectangle leaves the reader to work out which side of it is the paper -- centered on a point in the model projected into the view -- the page is the paper the model is printed on, so it travels with the model under a pan and a zoom rather than sitting in the middle of the window. That point, `+[LDrawStepPartListPolicy pageAnchorInModel:]`, is the middle of the whole model, every step of it, and not of the steps on display: taken from the steps on display, the page slid across the window as the model grew, which in the Porsche starts at step 4. Re-centering the viewport on each step change instead keeps the page still but makes the model jump, so the anchor is what stays fixed and the camera is left alone. The anchor is measured once per Steps session, submodel switch or Zoom to Fit, and then kept in an `LDrawStepPartListPageAnchor` that the document owns and hands to the overlay controller, so the overlay, the fit and the camera hold below all use the same point and none of them re-measures on a pan, a zoom or a frame drag. Edits, REMOVE GROUP steps and group suppression changes do not change the anchor: after an edit that changes the model's extent, the model point stays the same until Zoom to Fit, a submodel switch, or leaving and re-entering Steps mode. In a perspective view an edit can still slide the page with the model, because an edit that changes the displayed extent moves the camera and is not held. Entering Steps mode forgets the old point and measures it again once at step 0, whatever the preferences, so the measurement sees no later REMOVE GROUP in scope, and it brings group suppression up to date before it reads the step bounds. A resize that keeps the magnification keeps the point. The camera changes the document makes itself are the exception. A ROTSTEP turns the view, and in a perspective view a new step's size moves the camera nearer or further; both move every model point on screen, the anchor with them. So `-[LDrawDocument holdLPubPageDuringChange:]` notes where the anchor sits on the main viewport, runs the change, and scrolls the anchor back to that point. It wraps the whole step change in `-setCurrentStep:` (the outline row selection, which redraws, the turn, and the redraw at the new step's size), the forced turn when `-setStepDisplay:` enters Steps mode, a ROTSTEP edited in the inspector (`-stepChanged:`), and the redraw after the group suppression preference changes (`-groupSuppressionChanged:`). It holds when `+[LDrawStepPartListPolicy drawsPageInModel:]` says the page is drawn before or after the change, not when the overlay happens to be attached, so stepping into or out of a step that hides its list, or that has no page, is held too. A run of two or more steps without a page is not held between them. The paper does not move when the model turns or changes size on it. A turn the user makes by hand is not held: the page follows the model, as it does for a pan. `LDrawView` gained `-scrollModelPoint:toViewPoint:` for that, which converts through the renderer's viewport rather than the view's bounds -- the viewport's y runs the other way, and dividing view points by the bounds mirrors the target. `LDrawRenderer` gained `-viewPointForModelPoint:`, the inverse of the `-modelPointForPoint:` it already had;
* the frame is packed against the *page* rather than the viewport and sits in the page's top-left corner, so a `CONSTRAIN WIDTH` is measured on the paper and the list does not drift across it as the user pans. Its margin, padding, lines and room are LPub3D's default lengths in inches (see *The frame on the page* below);
* every other length in the metrics and the chrome -- the room kept for text, the point sizes the text is drawn at, the scale floor -- is restated in the page's inches by the one ratio `pointsPerPageInch × inchesPerLDU / defaultMetrics.baseScale`. Without that the icons would scale with the zoom while the furniture between them did not, and the frame's proportions would drift on every zoom. The reference is the same LDU-per-inch rule the icons use, not the resolution: a metric point is one LDU at the default scale, so on the page it covers one LDU of paper and the text keeps the size it has beside the parts off the page. Measured against `pointsPerInch` instead, as it was at first, every label and badge came out 150/64 -- 2.3× -- too small beside its part.

Two consequences worth stating. The resolution drops out of everything on screen: dots per inch is a property of paper, and it cancels once the assembly and the list are measured against the same on-screen page. And the page size still does not decide scale: LPub3D derives both the camera distance and its field of view from the page width, so what survives is the scale alone. The page decides how much of the model fits, which is exactly what the outline is for.

**The frame on the page (added later).** On the page, every length that places or bounds the frame is one of LPub3D's defaults in inches, times the page inch. So the frame, its height budget and its width clamp stay put on the paper at any zoom. Before, the 12 point margin and the 24 points taken off the room were screen points: 0.19 in of paper at 64 points to the inch and 0.06 in at 200, so the corner slid as you zoomed. The values, from LPub3D's source:

* *Margin, 0.05 in.* The frame's corner is 0.05 in from the page's top-left corner on both axes. That is where LPub3D puts a `PLACEMENT TOP_LEFT PAGE` list: the gap is the larger of the page's and the list's margins (`placement.cpp`), and `PAGE MARGINS` and `PLI MARGINS` both default to `DEFAULT_MARGIN`, 0.05 in (`declarations.h`, `meta.cpp`).
* *Padding, 0.08125 in.* LPub3D pads a parts list by its border's margin plus its line: 0.05 in plus 1/32 in (`PliMeta` in `meta.cpp`, `pli.cpp`). `+metrics:scaledToPointsPerPageInch:` sets `framePadding` to that instead of scaling the default 6 points. `WIDTH` and `HEIGHT` are outer sizes in both programs, so a `WIDTH` leaves the parts the same room as in LPub3D. Bricksmith also pads each cell, so an icon sits a little further from the edge.
* *Lines.* The border is LPub3D's default square line, 1/32 in wide with no rounded corners; LPub3D only uses the radius for `ROUND`. The page outline is 1/48 in, the dashed guide LPub3D's editor draws around a transparent page (`backgrounditem.cpp`). The outline has its own `pageLineWidth` in the chrome, so it does not grow with the border.
* *Room, the page less its margins.* There is no 60% share on the page. LPub3D never limits a parts list by its page: every mode packs with no page limit (`pli.cpp`), and its only page fraction, a third of the page in multi-step auto sizing, picks a packing mode and does not clamp (`step.cpp`). So the height budget, the `WIDTH` clamp and a drag's stop all use the page less 0.1 in on that axis, and the budget also leaves out the padding on both sides. The 6 in top of the drag band does not apply on the page. A budget with no room left is 1 point, since the packer reads 0 as no limit.
* *Budget after scaling.* `+metrics:fittingHostSize:pointsPerPageInch:` runs after `+metrics:scaledToPointsPerPageInch:`, so the budget takes off the padding the frame is drawn with. Taken before scaling, it took off the default 6 points while the frame was drawn with the page's padding.

The three host methods (`+frameRectForFrameSize:inHostSize:pointsPerPageInch:`, `+metrics:fittingHostSize:pointsPerPageInch:`, `+constraint:clampedToHostSize:pointsPerInch:pointsPerPageInch:`) and the drag take `pointsPerPageInch`, which is 0 when the host is not the page. The controller passes the page inch only when there is a page rect. The view reads it from `layout.pointsPerInch` when it has a page, as the drag already did. Off the page nothing changes: a 12 point margin, 60% of the viewport, and the default 6 point padding and rounded 1 point border. With the preference on and a file that does not measure its page, the frame sits in the viewport with the 12 point margin and the 60% share, and keeps the default padding and rounded border, scaled with the icons (`onPage:` is NO).

Not read yet: `PAGE MARGINS`, `PLI MARGINS`, `PLI BORDER` and `PLI PLACEMENT`. A file that sets them is drawn with the defaults. `PAGE MARGINS` is the one that would move the frame, and the margin is worked out in one helper (`FrameInsetForPointsPerPageInch`), so it is the easy one to add.

Because the layout now depends on where the camera is, `LDrawView` posts `LDrawViewCameraDidChangeNotification` from `-reflectLogicalDocumentRect:visibleRect:` — every zoom and every scroll passes through there and nothing else does — and the controller repacks on it, deferred, since that callback runs inside a camera update. A turn keeps the visible rect, so the hand rotations post it themselves through `-postCameraDidChange`: a spin drag with either button, the trackpad twist, the orientation menu and `-setViewOrientation:`, which the orientation hotkeys use. Without that the page went stale during a turn and snapped into place at the next redraw.

**Fonts are the open piece.** The text is proportional now, but its *size* is still ours rather than LPub3D's: our 12-point label is 12 dots at 150 dpi, which is 0.08 in on the page, and LPub3D's own instance-count font is nearer 24 pt. The metas that carry it are `0 !LPUB PLI INSTANCE_COUNT FONT [GLOBAL|LOCAL] <"font attributes...">` and `0 !LPUB PLI ANNOTATE FONT`, each with a matching `FONT_COLOR <"color name | #RRGGBB">`; the attributes are Qt's comma-delimited descriptor, `"Arial,24,-1,255,75,0,0,0,0,0"`, whose second field is the point size. What has not been confirmed is what that point is measured against — the typographic 1/72 in of the page is the principled reading, but it wants checking against a real LPub3D render before it is hard-coded.

`0 !LPUB PLI PLACEMENT` is the other thing the page opens up: LPub3D places the list against `PAGE`, `ASSEM (INSIDE|OUTSIDE)`, `MULTI_STEP`, `STEP_NUMBER` or `CALLOUT`, in any of nine positions. Bricksmith always puts it at `TOP_LEFT PAGE`. That is not LPub3D's default, `RIGHT_TOP OUTSIDE STEP_NUMBER` (`meta.cpp`), which needs the step number and page header that Bricksmith does not draw.

**Fitting the page.** There is no separate command: while the document is drawn on its page, **Zoom to Fit** fits the page instead of the model. `-[LDrawView zoomToFit:]` first asks its delegate through the informal `-LDrawViewZoomToFit:`, and the document answers YES for the viewport its page is drawn in — so the menu item, the viewport's own button and the fit on opening a document all get the page, and the opening path skips its usual small back-off so the edges still meet. Any other viewport, or a document that does not measure its page, fits the model as before. The page fit matches the page's *width* to the viewport's, edge to edge, and scrolls the step to the middle -- the page is drawn around the step, so centering the step is what lands the page's edges on the viewport's. The width alone, because it is the dimension a reader judges a page by and the one that gives the same picture whatever the height of the window; a page taller than the window runs off it, which the dimmed surround makes legible rather than confusing. (Later: the fit shows the whole page, as LPub3D's Fit Page does (`LGraphicsView::fitVisible`): `+assemblyScaleFittingPageInHostSize:inModel:` takes the smaller of the width and height ratios, 6 points in from the edges. LPub3D leaves 2 pixels, but here that put the page's edge under the viewport's border. A tall page no longer runs off the window.)

*The page is sized from the scale the model is drawn at (added later).* The page inch came from `zoomPercentage`, which is the scale one LDU is drawn at *at the origin*: the perspective camera is built so that ortho and perspective agree there (`-nearFrustumClippingRectFromVisibleRect:`). A model sits wherever it sits, so a step nearer the camera than the origin is drawn larger than the zoom says, and it then covered more of the page than LPub3D gives it. Both programs map one LDU to 1/64 in times `ASSEM MODEL_SCALE` (`ResolutionMeta::ldu()`, `stdCameraDistance` in `render.cpp`), so the fix is to measure instead of read: `-[LDrawRenderer pointsPerLDUAtModelPoint:]` projects the anchor and a point 100 LDU along the view's x axis and divides. The controller's `-assemblyScale` measures beside the page anchor, and Zoom to Fit aims the measured scale at the fitted one, correcting once because the frustum is not exactly linear. The measurement is a *ratio* against the zoom, kept on `LDrawStepPartListPageAnchor` beside the point and dropped with it: measured afresh on every step, each step's `ROTSTEP` turned the model, moved the anchor's depth and so resized the page from step to step.

Switching the preference on fits the page once, so the user sees what they asked for; only on the switch, since every parts-list preference posts the same notification and taking the viewport's zoom away each time one changes would be rude.

**A resize re-fits.** Without this, resizing the window leaves the page at its old size in points while the window changes around it, and the step and its list slide off the paper -- the page is still correct against the model and wrong against everything the reader can see. So the document watches the viewport's frame and re-fits, *keeping the magnification*: the zoom is scaled by how much the fit changed rather than reset, so a reader who had zoomed in stays as far in as they were, the page still fits the window, and everything on the page is exactly where it was on the page. The cost is any pan they had made, since re-centering is what keeps the page framed by the window; a page half out of the window is worth less than the pan.

Checked against the Porsche, which carries `RESOLUTION GLOBAL 170 DPI` and `ASSEM MODEL_SCALE GLOBAL 1.1500`: at 1 point per LDU the page reads 55.65 points to the inch, and the old absolute command — one render dot per point — set 305.47%, which is 170 × 1.15 / 64 × 100.

The outline rides with the parts-list overlay, and the overlay stays for the page on a step whose `PLI SHOW` is `FALSE`: it draws the page and no frame, as LPub3D still prints that page (`formatpage.cpp` makes the page background for every page, and `PLI SHOW` only decides what goes into the PLI). So Zoom to Fit and a resize still fit the page on that step, and the page does not vanish and come back as the user steps past it. Turn the parts list preference off and the page goes with it.

Pinning the frame to the page's corner has a cost worth knowing about: zoom in past the page fit and the corner leaves the window, taking the list with it. That is what a magnified page does, and the alternative -- clamping the frame to stay on screen -- makes it drift across the page instead. Truth was chosen over convenience here, and it is a choice, not a consequence. A *resize* does not have this problem, because it re-fits.

**Not settled yet.** At parity a 1×1 brick icon is 47 pt and a 4×6 plate 188×281 pt, against a default frame of 363 pt of content — two parts per shelf, then overflow. LPub3D gets away with it because its PLI sits on a Letter page. So parity has to be a mode, not the only behavior, and auto-shrink inside it must say that the scale is no longer LPub3D's. The related idea — showing the step's assembly at the scale LPub3D would print it, from `ASSEM MODEL_SCALE` and the page size — reads on the same arithmetic, which is why `LPubModelScale` covers that branch too.

### Which meta line is in force

Every meta the parts list reads goes through one lookup, `+[LDrawStepPartListPolicy directiveInForceForStep:excluding:matching:]`: `PLI CONSTRAIN`, `PLI SHOW`, `PLI CAMERA_ANGLES`, `PLI PART_ROTATION`, `MODEL_SCALE`, `PAGE SIZE`, `PAGE ORIENTATION` and `RESOLUTION`. It reads a file the way LPub3D's parser does (`BranchMeta::parse`, `LeafMeta::pop` and `findPage` in `traverse.cpp`), for one kind of line at a time.

- **The rule.** There are two slots: the carried line and the step's line. A `LOCAL` line goes in the step's slot, and so does any later line of the same kind in that step. Any other line replaces the carried line. The step's slot empties at each step. The answer is the step's line, else the carried line. LPub3D writes `GLOBAL` in the top model's header, but its parser never checks where a `GLOBAL` line is, so it counts from where it is written, like a line with no keyword.
- **`PART_ROTATION` and `RESOLUTION`** keep one value in LPub3D, so `LOCAL` does not end with the step. Both are read as if unscoped.
- **Submodels.** For a step in a submodel, the walk starts at the file's first model. At a part that places a submodel it walks that submodel with a copy of the carried line, and drops the copy afterwards, so a submodel's lines never reach its parent or a later sibling. It stops at the first part, in file order, that places the step's model, and that model starts from what was carried there. A `LOCAL` open in the parent's step does not reach it. A placement inside `PART BEGIN IGN … PART END` is not followed, as in LPub3D. A submodel placed nowhere starts from nothing. So a submodel shown on its own gets the top model's page, resolution and scales, and its page is drawn.
- **The step's own `CONSTRAIN`** (`+constrainDirectiveInStep:`) is its last `CONSTRAIN`, but only when that line holds for this step alone: it, or an earlier `CONSTRAIN` in the step, is `LOCAL`. A `GLOBAL` or unscoped line with no `LOCAL` before it in the step carries on to later steps, so it shows no pin, and a click or a drag never removes or rewrites it.
- **The inherited size** (`+inheritedInchesForAxis:inModel:`) is the `CONSTRAIN` in force with the step's own line left out, if it pins that axis, else 0. Steps `[WIDTH 2]`, `[LOCAL WIDTH 3]`: the second inherits 2. One step `[WIDTH 2, LOCAL WIDTH 3]` inherits 2. One step `[LOCAL WIDTH 3, WIDTH 4]`: its own line is `WIDTH 4`, and it inherits 3.
- **Write-back.** A drag changes this step only. It updates or removes the step's own line. Otherwise it inserts `CONSTRAIN LOCAL …` just after the step's last `CONSTRAIN`, else first (`LDrawStepPartListEdit.insertIndex`). Above an unscoped or `GLOBAL` line, the new line would be overridden by it. LPub3D's own resize rewrites the line in force in place when it is in the step (`setMetaTopOf`), which also changes every later step; Bricksmith does not do that.

Left out of LPub3D's behavior on purpose, because they only change unusual hand-written files:

- `PLI SHOW` is answered for the whole step. LPub3D checks it at each part line, so there a `SHOW` after a step's parts does not hide that step.
- A step with no parts resets like any other step. LPub3D does not reset after it, and leaves its lines out of the next page.
- A parent's open `LOCAL` is not carried into a child. In LPub3D it can keep the child's unscoped lines in its first step from carrying on.
- `RESOLUTION` follows the same walk as the other metas, so one set inside a submodel does not reach later models. In LPub3D it is process-wide, so a later `RESOLUTION` can apply to earlier pages.
- Unassembled callouts are not parsed. LPub3D makes no pages for a called-out submodel and resets its `PLI CONSTRAIN`.
- A submodel placed in several colors inherits from its first placement only.
- LPub3D's multi-step groups size a parts list whose `CONSTRAIN` only carries in by themselves. Bricksmith uses the carried value, as a single-step page does.
- Lines inside containers such as `!TEXMAP` blocks are not read.

With a submodel on display, each lookup walks the file up to the first placement, and a reload makes about a dozen lookups. If that is slow on a large MPD, find the placement once per reload.

---

### Phase 5 — `pli_resize`: resizing, constraint indicators, and removal

**Gesture.** A grab area on the frame's right edge resizes width and the bottom edge height. Where they meet, the nearer edge wins: a CONSTRAIN holds one size, and LPub3D's parts list has only a bottom grabber. During the drag, only the in-memory constraint changes and the frame re-packs live — the document is untouched. On mouse-up, one undoable edit commits.

*Where a drag stops (added later).* A width drag stops at `oneRowFrameWidth`: the narrowest `WIDTH` that packs every part on one shelf with no icon drawn smaller. The frame drawn there can be narrower, since it closes up. That is the larger of the cells' total width and the widest padded icon over the 0.6 cell share, since a smaller icon takes a shelf of its own. A height drag stops between `oneRowFrameHeight` and `tallestFrameHeight`. Below the one-shelf height no packing fits and the one shelf is drawn. Above the packing as wide as the widest cell, `HEIGHT` always keeps that packing. The layout measures all three from the parts at the base scale, whatever the constraint, so a drag event only reads them. Both axes also stop at the room on the host, where a width is narrowed and a height shrinks the icons: 60% of the viewport less its 12 point margins, or on LPub3D's page the page less its 0.05 in margins. These stops apply after the band's floor, so a list that fits on one line below 0.75 in stops there. The layout's stops are rounded up to the 0.0001 in that `CONSTRAIN` writes, at least half a step, so reading the value back never wraps a part. The frame closes up to its widest shelf, so between stops a saved `WIDTH` can be wider than the frame drawn; it draws the same frame again, as LPub3D's saved `HEIGHT` does. A drag measures from where it was grabbed, not from the frame's corner: the grab reads as the smallest size that packs the list the same (`resizeStartSize`), rounded up to what `CONSTRAIN` writes, so grabbing a closed-up edge does not make the frame jump. Where a part is drawn smaller, the icons shrank or shelves were dropped, the grab reads as the `WIDTH` or `HEIGHT` packed with instead, since those depend on the size asked for. A document `WIDTH` or `GLOBAL` past the one-row width cannot be reached by a drag, and the snap to the inherited size does not reach past a stop, so a drag cannot remove the step's line there; clicking the pin still does.

The host contributes only event plumbing. Hit-testing which edge was grabbed, converting a drag delta into a new width, and clamping it all live in `LDrawStepPartListPolicy` (LDrawFeatures); deciding whether the commit inserts, updates, or removes the directive lives in `LDrawStepPartListEdit` (LDrawFeatures, see below). An iOS host swaps `mouseDown`/`mouseDragged`/`mouseUp` for a `UIPanGestureRecognizer` and calls the same three methods.

**What gets written.** Into the current step, as its first directive:

```
0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5000
```

- If the step already has an `LPubPliConstrain`, mutate it in place rather than inserting a second one.
- If the committed value equals the effective inherited value (the document's `GLOBAL`), remove the `LOCAL` line instead of writing a redundant one. *As built:* the inherited value is the `CONSTRAIN` in force with the step's own line left out, and only when it pins the dragged axis. A new line goes just after the step's last `CONSTRAIN`, not first (see *Which meta line is in force*). With no line in force, the step packs by `AREA`, so there is nothing to snap to. *Later, the snap:* a continuous drag almost never landed within the 0.0005 in the edit compares with, so letting go near the inherited size wrote a `LOCAL` line with nearly the same value. Now a drag within 6 screen points of the inherited size snaps to exactly it (`INHERITED_SNAP_DISTANCE` in `+inchesForDraggingAxis:…inheritedInches:`), and letting go there removes the step's line whatever it pinned. The inherited line pins that axis, so once the step's own line is gone the frame gets the size asked for; before, a `HEIGHT`, `COLS`, `AREA` or `SQUARE` line was turned into a redundant `LOCAL WIDTH`. With no inherited size on the dragged axis there is no snap. The snap is measured from the size after the stops, and only an inherited size between the stops snaps, so a stop always wins. The distance is in screen points, so zooming in lets a `LOCAL` size close to the inherited one be set; there is no key to turn the snap off. While a drag is on, the pins show what letting go would leave (`LDrawStepPartListEdit.resetsAxis`): no pin on the snap, unless an earlier line of the step's own still pins the axis, and a pin on the dragged axis elsewhere. For a height the frame may not move on the snap, since `HEIGHT` is a ceiling, so only the pin shows it. A step with two lines of its own loses only the last one, and the earlier one then applies; when that line pins the dragged axis, the pin stays and the undo name is a resize. LPub3D never removes a line on a resize: it rewrites a line already in the step (`setMetaTopOf`) and otherwise inserts a `LOCAL` one.
- Dragging the bottom edge writes `CONSTRAIN LOCAL HEIGHT <in>`; `WIDTH` and `HEIGHT` are mutually exclusive in LPub3D's grammar, so committing one replaces the other.
- Insert via `-[LDrawDocument addStepComponent:parent:index:]` so undo, the outline view, and the file-contents text view all update through the normal path. New undo-action localization key, registered the way `LDrawInsertUndoLPubCommand` is.

**Units — the one real compatibility compromise.** LPub3D's `WIDTH`/`HEIGHT` are *printed page* inches; Bricksmith has no page, so a literal round-trip is impossible. Options:

- **(a) Store inches, map to points with a fixed resolution — recommended.** Treat the stored value as inches and display at `inches × 150` points (150 dpi is LPub3D's default render resolution). A file authored in Bricksmith then opens in LPub3D with a sensible PLI width, and one authored in LPub3D opens here at a proportionate size. Clamp the editable range to roughly 0.75–6.0 in (as built, the 6 in top applies off the page only), and additionally clamp the *displayed* width to a fraction of the viewport (default 60%) without changing the stored value, so a page-sized value from LPub3D doesn't swallow the viewport. *As built:* a drag stops at the same share, so it never writes a width that this clamp would narrow. On LPub3D's page there is no share: the clamp and the drag stop are the page less its 0.05 in margins (see *The frame on the page*).
- **(b) Store view points.** Exact on screen, but a file saved here would render at a nonsense size in LPub3D. Rejected — it produces syntactically valid, semantically wrong metas, which is worse than an approximation.

Take (a), and document the 150 dpi convention in the header comment of `LPubPliConstrain` so the number is not a mystery later.

Also honor on read: the `CONSTRAIN` in force for the step, as LPub3D reads scope (see *Which meta line is in force*), and `PLI SHOW LOCAL FALSE` to suppress the frame for one step.

#### Visualizing the constraints

Without an indicator, a constrained frame and an auto-sized frame look identical, and the user cannot tell whether the size they see is something they set on *this* step, something inherited from the document, or just the packer's choice. Each of the two axes therefore has a visible state, resolved by the policy class and drawn on the corresponding edge:

| State | Meaning | Drawn as |
|-------|---------|----------|
| Auto | no constraint on this axis (`AREA`/`SQUARE`, or the axis the active mode doesn't pin) | plain edge; a faint dashed segment on hover to advertise that the edge is draggable |
| Local | `CONSTRAIN LOCAL WIDTH/HEIGHT` in this step | solid pin/handle in the accent color, at the edge midpoint |
| Inherited | a `CONSTRAIN` carried in from an earlier line, or the preference default | hollow/gray pin — same position, so the difference from Local is legible at a glance |
| Columns | `CONSTRAIN COLS <n>` | a small `n⃒` column glyph at the top-right; both edges read Auto |

*Later:* the hollow pin was dropped. It could not be clicked, the badge that was meant to explain it was never drawn, and once the preference's width became a limit the frame closes up within, it claimed a width the frame was not at. A step with no CONSTRAIN now reads Auto on both axes, and only a Local constraint gets a pin — solid, and clicking it clears the line. The indicator API went with it: the four-state source enum, the badge methods and their localization keys, and `+resizeHandleThickness` are gone. The policy answers `+isAxis:pinnedInStep:`, and `+constrainDirectiveInStep:` is the single lookup of a step's CONSTRAIN, shared by the policy, the edit and the controller — the controller's own copy had been taking the first line where the other two took the last.

Hovering a pin (or dragging either edge) shows a badge with the current value and its source — `W 2.50 in · this step`, `W 2.50 in · document`, `W auto`. The units string follows the same inch convention as the meta, so what the user reads is what lands in the file.

The whole of this is decisions, not drawing, so it lives in `LDrawStepPartListPolicy`:

```objc
typedef NS_ENUM(NSInteger, LDrawPliConstraintSource) {
    LDrawPliConstraintAuto      = 0,   // packer's choice
    LDrawPliConstraintLocal     = 1,   // CONSTRAIN LOCAL in this step
    LDrawPliConstraintInherited = 2,   // carried-in CONSTRAIN, or the preference default
    LDrawPliConstraintColumns   = 3
};

/// Per-axis indicator state, the rect its pin occupies, and the badge's
/// localization key + formatted value. The view only draws what it is told.
+ (LDrawPliConstraintSource)sourceForAxis:(LDrawPliAxis)axis inStep:(LDrawStep *)step;
+ (Box2)pinRectForAxis:(LDrawPliAxis)axis inFrame:(Box2)frame;
+ (NSString *)badgeValueTextForAxis:(LDrawPliAxis)axis inStep:(LDrawStep *)step;
+ (NSString *)badgeSourceKeyForAxis:(LDrawPliAxis)axis inStep:(LDrawStep *)step;
```

#### Removing the constraints

Four routes, so the user finds at least one:

1. **Click the pin.** A Local pin clears the constraint on that axis for this step; the axis falls back to whatever it inherits and the pin becomes hollow (Inherited) or disappears (Auto). Clicking an *Inherited* pin does nothing to the document — it is not this step's to clear — and instead shows the badge explaining where the value comes from.
2. **Contextual menu on the frame** — `Reset Frame Width`, `Reset Frame Height`, `Reset Frame Size` (both axes, this step), and `Reset Frame Size in All Steps`, which also removes the `GLOBAL` and unscoped `CONSTRAIN` lines that later steps inherit. The last one is destructive across the document, so it goes through the normal undo path and names itself accordingly.
3. **Escape during a drag** cancels it, leaving the document untouched — the drag was never committed anyway.
4. **Delete the directive directly.** `LPubPliConstrain` is a real directive, so it appears in the file-contents outline and the raw text view and can be selected and deleted there like any other line. Nothing extra to build; worth stating so it isn't reimplemented.

Removal is the same `LDrawStepPartListEdit` call as a commit, with a nil value — the module already has to decide insert/update/remove, and "remove" is just the case where the requested value equals the inherited one or is explicitly cleared. Distinct undo-action keys for set vs. reset, so the Edit menu reads correctly.

**As built.** The split is as planned: the policy answers which edge was grabbed, what a drag delta means and what each indicator says; `LDrawStepPartListEdit` decides insert/update/remove; the view sends events and the document performs the change. Four things are worth recording.

*`LDrawStepPartListEdit` is in LDrawFeatures, not LDrawEditing.* It needs nothing from LDrawEditing — only `LDrawStep` and `LPubPliConstrain` — and LDrawEditing links the renderer's display lists, whose implementations live in the GPU backends. Linking it into the `UnitTests` target to test the edit logic produced undefined `LDrawDL*` symbols; the alternative was to link a renderer, which would end the target's renderer-free premise and change what several existing tests exercise. The class sits beside the rest of the parts-list code instead.

*`LPubPliAxis` lives in LDrawCore*, beside the CONSTRAIN modes it names, because both the feature layer and the editing layer need to name an axis and neither depends on the other.

*The overlay never takes a click; the controller routes them (added later).* The first version answered `-hitTest:` for its edges and pins and handled `-mouseDown:` itself, and none of it ever ran: `OverlayHelperWindow` sets `ignoresMouseEvents`, as it must — the child window covers the whole viewport, and a window that took clicks would take every click meant for the model — so AppKit delivered nothing to the view, not its cursor rects and not Escape either. `StepPartListController` now installs a local `NSEvent` monitor while the overlay is attached and removes it on detach. Over an edge or a clearable pin, mouse-moved events set the resize or pointing-hand cursor, and `-[LDrawView resetCursor]` gives the viewport its tool cursor back on the way out. A mouse-down there goes to `-[StepPartListView beginInteractionAtPoint:]` and is swallowed, and so are the drags and the mouse-up that follow — even after Escape, so the viewport never sees a drag without its mouse-down. Everything else, clicks on the frame's interior included, reaches the model as before. The view's dead `-mouseDown:`/`-mouseDragged:`/`-mouseUp:`/`-keyDown:`/`-resetCursorRects` became that point-based API.

Checked in the running app by posting synthetic events on the Porsche model: dragging the right edge of a step carrying `CONSTRAIN LOCAL HEIGHT 2.1706` replaced it with `LOCAL WIDTH 1.3847` (frame 89 → 208 pt, undo "Resize Parts List"); dragging a step with no constraint inserted `LOCAL WIDTH 3.2933`, drawn clamped to the viewport (this was before a drag stopped at the viewport's share and at one shelf); clicking a local height pin removed the line ("Reset Parts List Size"); Escape mid-drag left the step untouched. Not observed: the cursors themselves, including the switch from up-down to left-right where the two edges meet, and a click on the interior reaching the model.

*Resizing previews, it does not write.* The controller keeps the dragged size in memory and repacks from it, so the frame repacks as the pointer moves with the document untouched; mouse-up turns the preview into exactly one edit, and Escape drops it. The edit is `Nothing` when the size did not really change — including when it changed by less than the four decimals the meta records — so a drag that ends where it started leaves no entry in the undo menu.

Routes 1 (click the pin), 3 (Escape) and 4 (delete the directive in the outline, which needs no code) are in. Route 2, the contextual menu with its reset commands, is Phase 6 along with the rest of the menu. A drag let go on the snap to the inherited size also removes the step's line (see *What gets written*).

---

### Phase 6 — `pli_polish` (optional)

- Stud-dimension annotations on cells (`1x32`), derived from `modelBounds`.
- **Marker for entries whose parts are hidden in the viewport** — dimmed icon or an eye-slash badge. Explains why a listed part isn't visible; optionally clicking it unhides. The entry would have to collect the hidden state again.
- Marker for unresolved (missing/moved) references, from the `isMissing` flag.
- Right-click menu on the frame: sort key, include submodels, parts size, hide for this step (writes `PLI SHOW LOCAL FALSE`, built from text since SHOW is read-only). The reset commands ship in Phase 5.
- `COLS` / `SQUARE` / `AREA` selectable from that menu.
- Color-name text under the multiplier for color-blind accessibility.
- Per-entry compact projection and two-scale rendering (Phase 2, options 6–7).

---

## Risks

| Risk | Mitigation |
|------|------------|
| A second GPU surface per document (nested `LDrawView`) costs memory/perf, or composites badly over `NSOpenGLView` | Create lazily, only while visible. `addOverlayView:` uses a child window, the one mechanism that reliably composites over a GL surface, and `FocusRingView` already proves it. If it misbehaves on the GL target, fall back to Phase 3 option (B) |
| Bounding-box cells waste space on angled parts | Accepted; same limitation as every other tool. Per-entry compact projection is the escape hatch |
| Inch↔point mapping is a convention, not a round-trip | Documented constant, clamped ranges, and a display clamp so an LPub3D-authored value never breaks the viewport |
| Regressing files that use the other ~30 PLI metas | Generic `LPubCommand` already round-trips unknown lines verbatim; add an explicit round-trip test with a realistic LPub3D-authored file |
| Overlay left attached to a viewport that gets removed by `ViewportArranger` | Detach on `viewportArranger:willRemoveViewports:` when the host is among the removed viewports, and re-resolve `main3DViewport` after any arrangement change |
| Layout thrash while the user scrubs steps | Cache packed layouts keyed by (step identity, constraint, scale); invalidate on the change notifications listed in Phase 3 |
| AppKit creeps into the packages, silently costing the iOS reuse | The iOS smoke build is the gate — run it every phase, not at the end. Any `NSRect`/`NSColor`/`NSFont` in a package header is a review failure; use `MatrixMath` geometry, RGBA floats, and point sizes |
| Over-splitting makes the chrome view an awkward puppet of the policy class | Draw the line at *decisions vs. drawing*: the policy answers "where, how big, which edge, what text"; the view only strokes, fills, and blits. If a method needs a graphics context, it belongs in the view |

## Tests

**Tests live beside the code they exercise, inside the owning package.** This repository already does that: `Packages/LDrawCore/Tests/LDrawCoreTests/` holds `LDrawStepGhostingTests.swift`, `LDrawGroupSuppressionTests.swift` and friends, next to `Sources/LDrawCore`. The root `Package.swift` declares them as the `LDrawCoreTests` and `LDrawFeaturesTests` test targets, so `swift test` at the repo root runs them. The Xcode `UnitTests` target also compiles the same files, and references each package's `Tests` directory as a group. Code coverage stays off.

So each new test file goes in its own module's `Tests` directory, and is added to the Xcode `UnitTests` target as it is created. `LDrawEditing` has no `Tests` directory yet. Create it on the same pattern (`Packages/LDrawEditing/Tests/LDrawEditingTests/`) and add a matching test target to the root `Package.swift`, rather than parking its tests in LDrawCore or in the app target. Swift + the Testing framework, matching the existing files.

| File | Module | Covers |
|------|--------|--------|
| `LPubPliMetaTests.swift` | LDrawCore | every `CONSTRAIN` / `SHOW` / `BEGIN IGN` grammar variant, optional scope keyword, write-out round-trip (canonical for `CONSTRAIN`, as read for the read-only metas), a read-only meta keeps its text and gets its properties back through retyping, copy and archive, malformed lines don't crash the parser, unknown `PLI …` variants stay a generic `LPubCommand` |
| `LPubPliRoundTripTests.swift` | LDrawCore | fixture MPD carrying a spread of real LPub3D PLI metas: open, save, assert byte-identical output |
| `LDrawStepPartListTests.swift` | LDrawFeatures | grouping by design + color; quantity accumulation; **hidden parts included**; `REMOVE GROUP` parts excluded; `PLI BEGIN IGN` range excluded; parts inside a texture listed; submodel policy; previous steps excluded; deterministic ordering |
| `LDrawStepPartListLayoutTests.swift` | LDrawFeatures | the five constrain modes; oversized entry gets its own row at reduced scale; `COLS` row count; `SQUARE`/`AREA` beat a fixed width on their own metric; scale floor honored and overflow reported rather than clipped; a count beside its part sits on the bottom line of the icon's box and slides in until the part stops it, also for a many-cornered outline; one crowded count puts the whole shelf's counts in strips; a badge is not held up by a count drawn in the strip; a `WIDTH` wraps the shelves and the box closes up to the widest, also past the parts; the one-row width holds every part on one shelf with none drawn smaller, a wide part included; `HEIGHT` packs one shelf below the one-row height and the same packing above the tallest; those three stops do not depend on the constraint or the height budget; layout is a pure function of (entries, constraint) |
| `LDrawStepPartListPolicyTests.swift` | LDrawFeatures | frame origin and clamps, off the page and on it at any zoom; the height budget from the padding it is given, and on the page the page less its margins and padding; on the page, LPub3D's padding, square border and page outline; inch↔point conversion at 150 dpi; edge and pin hit-testing, with the nearer edge winning where the edges meet; drag delta → size, measured from the grab so a closed-up frame does not jump, stopping at the band (its top off the page only), the room on the host (a 0.6 share off the page, the page less its margins on it), one shelf for a width, and one shelf or the tallest packing for a height; snapping to the inherited size within 6 screen points, a stop winning over an inherited size past it, and a drag let go on the snap removing the step's line; whether each axis is pinned — a step's own `WIDTH` or `HEIGHT` is, a bare step, `AREA`, `SQUARE`, `COLS` or a `GLOBAL` or unscoped line is not (these live in `LDrawStepPartListResizeTests.swift`); which line is in force: carry-forward, `LOCAL` for one step, `GLOBAL` outside the header, submodels starting from their first placement, `PART BEGIN IGN` placements, loops, the inherited width and the step's own line |
| `LDrawStepPartListEditTests.swift` | LDrawFeatures | insert when absent, after the step's last `CONSTRAIN`; a line that carries on is left alone; update in place when present (never two directives); remove when the value equals the inherited one, whatever the step's line pins, or is explicitly reset; `resetsAxis` marks a reset for the pins during a drag; `WIDTH` and `HEIGHT` replace each other; distinct undo keys for set vs. reset |
