# Parts limitation

**Overview:** Let a model use only the parts its builder can get: the parts LEGO makes now, or the parts of chosen LEGO sets. With a limit on, the Part Browser lists only the parts the limit allows, the Colors window does not offer a color the part is not made in, and the model marks the parts that break the limit: not available, not made in that color, or more copies than the sets hold. The part data comes free from Rebrickable. The data, the matching and the checking live in the packages, so another host gets them by writing only its views.

## Plan status

| ID | Phase | Status |
|----|-------|--------|
| `limit_data` | Phase 0: inventory and availability types, identity maps, the store on disk (new package LDrawInventory) | completed |
| `limit_rebrickable` | Phase 1: Rebrickable downloads, set import, LDraw matching (new package LDrawRebrickable) | completed |
| `limit_check` | Phase 2: count what the model uses and work out each part's status (LDrawFeatures) | not started |
| `limit_settings` | Phase 3: the app-wide limit, the Parts pop-up, Settings → Parts, Import Set Parts, Inventories window | not started |
| `limit_browser` | Phase 4: Part Browser: filter, SETS group, Count column, color strip, color filter | not started |
| `limit_colors` | Phase 5: Colors window: allowed colors only, Randomize Color | not started |
| `limit_marks` | Phase 6: marks in the 3D view and File Contents, inspector line, Piece Count columns | not started |
| `limit_assemblies` | Phase 7: assemblies, minifigure parts and prints matched across LDraw and LEGO numbering | not started |
| `limit_polish` | Phase 8 (optional): wanted-list export, BrickLink XML import, Rebrickable "My Parts", Brickset "on sale" | not started |

Phases 0–2 land entirely in the packages. Phases 3–6 add AppKit views, and even there the policy (which rows, which colors, which text, which mark) stays in the packages. The iOS smoke build must keep passing after every phase.

## Goals

- Two kinds of limit:
  - **Available now.** A part in a color is allowed when it came in a LEGO set released in the last two years. The span can be changed, or set to any year, which then only rules out colors a part was never made in.
  - **From sets.** The parts of one or more sets, each set counted once or more, plus loose parts. Spare parts in or out.
- The limit is an editor setting, not part of the model: nothing is written into the file. One limit holds for the whole app. Every window's Parts pop-up and the Parts pane in Settings show it and change it, as they do for the LPub3D Page switch.
- With a limit on:
  - The Part Browser lists only allowed parts. A set's parts show how many the model uses and how many the sets hold, as `5 / 10`, and the row turns red past the count.
  - A color the part is not made in cannot be picked for it.
  - Parts that break the limit are marked in the 3D view and in File Contents, and the reason is a hover away.
- No account and no key are needed. A free Rebrickable API key of the user's own only fetches a set fresh, with Rebrickable's own LDraw links for its parts.
- Works offline once the data is downloaded.
- Most of the code is in the packages, Foundation only, and unit-tested without a view.

## Non-goals

- Prices, stores, buying parts.
- Whether the model is stable or its parts really connect.
- A full collection manager. Sets and loose part lists are enough here; Rebrickable's "My Parts" may come in Phase 8.
- Changing part files or the LDraw library.

---

## Part 1 — Where the data comes from

A limit needs three things: each set's parts, with counts and spares; which parts come in which colors, in which sets, and when; and a way from LEGO's numbers to LDraw's file names and color codes. Checked on 2026-10-25.

### The sources compared

| Source | A set's parts | Years per part and color | LDraw ids | Access | Terms |
|--------|---------------|--------------------------|-----------|--------|-------|
| **Rebrickable downloads**, `cdn.rebrickable.com/media/downloads/<name>.csv.gz`, about 18 MB gzipped, updated daily | Yes: `inventories`, `inventory_parts` (with `is_spare`), `inventory_minifigs`, `inventory_sets` | From `sets.year` through the inventories. `colors.csv` has the first and last year of each color (`y1`, `y2`) | None | Public, no account. Automated downloads at most once a day | Any use, commercial too, with credit to Rebrickable |
| **Rebrickable API v3** | `lego/sets/{set_num}/parts/`, with `is_spare`, `inc_minifig_parts`, `inc_part_details` | `lego/parts/{part}/colors/{color}/` has `year_from`, `year_to` | `external_ids.LDraw` on parts and colors | Free account and key. About one call a second; past that a 429, and a ban if ignored. The docs say the API is overloaded and that full lists must come from the downloads | Any use; credit appreciated |
| BrickLink API | `items/{type}/{no}/subsets`, with extras, alternates and counterparts | Known colors, no years | No | A store API: OAuth 1.0, tokens bound to one registered IP | Personal license. Data may not be passed to anyone else |
| Brickset API v3 | No | No, but sets have launch, exit and LEGO.com dates | No | Key after sign-in; 100 set calls a day | No copycat sites |
| BrickOwl API | Partly | No | No | Key | Not for marketplaces; must link back |
| LEGO Pick a Brick | No public API | — | — | — | Personal, non-commercial use only |

### What we pick

**Rebrickable, mostly through its downloads.**

- The downloads build the availability catalog and the list of sets, and import any set offline, with no key and no account. Their terms allow this with a credit, and Bricksmith fetches them at most once a day; in practice monthly, or when asked.
- The API is for the user who adds a free key of their own. It fetches one set fresh, with Rebrickable's exact LDraw links for that set's parts: one or two calls a set, and no bulk crawls, which the docs ask apps not to make. Nothing needs the API to work.
- BrickLink is out: its API is for stores, its tokens are bound to an IP, and its terms forbid passing its data on. Brickset, BrickOwl and LEGO have no part lists, or forbid reuse. Brickset's on-sale dates stay a Phase 8 option for users with a Brickset key.

### Matching to LDraw

- **Parts.** Rebrickable follows LDraw's numbers where it can. A third-party count over every set inventory found that 94% of pieces match by the same number and 2.6% more through an LDraw alias. Prints differ: LDraw names them with `p` codes, Rebrickable with `pr` codes. But the LDraw library names the other number itself. The Parts Tracker writes `0 !KEYWORDS … Rebrickable 2431pr0014` when the numbers differ, and 9,147 of the 24,735 parts in the local library carry it. Bricksmith's part catalog already reads keywords, so this costs no download.
- **Colors.** Rebrickable's color ids are not LDraw codes. Many agree, but some clash: Rebrickable 326 is Olive Green, LDraw 326 is Yellowish Green. Colors map only through Rebrickable's `external_ids.LDraw`. There are 275 colors, so the table ships with LDrawRebrickable, made from one API call at release time and checked against the `// LEGOID` comments in LDConfig.ldr. A user's key can refresh it. Color 9999 means any color, and -1 unknown.
- **Assemblies.** Rebrickable lists a minifigure's torso with its arms and hands, and its hips with its legs, as one part each. LDraw splits them. Phase 7 deals with that.

### What "available now" can mean

- No free source says what LEGO sells today. Rebrickable has years only: the year of each set, and a first and last year for each color.
- So *Available now* means the part came in that color in a set from this year or last year, counting minifigure parts and sets inside sets, spares included. Release years run ahead (black already shows 2027), which is harmless here.
- Rebrickable's *Database Sets* theme holds lists like Pick-a-Brick-2024, parts not yet in any set. They are left out by default, with an option to count them.

### How other programs show it

- **BrickLink Studio** comes closest. Its color menu can hide colors BrickLink has no prices for, and its building palette can hide the parts not made in the selected color. Its step list puts a yellow mark on an unavailable part color, and the search `=warning()` lists them. A Color Validator tab groups the problem parts, proposes colors with an Apply button, and has Autofix to the nearest color. A set imported as a palette shows counts on its thumbnails that go down as you build. A part disappears when it is used up, and nothing warns when more are used.
- **Rebrickable's Build** compares owned sets with a model: colors exact, similar or ignored; prints, molds and alternates ignored or not; minifigures and non-LEGO parts ignored or not; spares of owned sets counted unless left out.
- **LDCad** has no color availability. Its author said it would need a file of the colors each part comes in. Nothing was found for LeoCAD or Mecabricks.

### Ideas worth stealing

1. Rebrickable's Build options as the limit's options: spares; prints, molds and alternates; exact or any color, with similar colors later.
2. Studio's palette that shows only a part's colors. Here it is the Colors window's *For Selected Part*.
3. Studio's counts on a set's parts, but a used-up part stays in the list, and using more is marked, which Studio does not do.
4. Studio's Color Validator: the problems in a list, a proposed color for each, and one click to use the nearest allowed color. Here it goes into the problems popover and Piece Count.
5. Every imported set keeps LEGO's ids next to LDraw's, so a better map can match it again.

The Parts pane and the Inventories window credit the data: *Parts data from Rebrickable.com*.

---

## Part 2 — What we build

### Words used below

- **Limit**: what a model may use. *All Parts* (no limit), *Available now*, or an *inventory*. A limit has options: spares in or out, how strictly prints and colors must match, and for *Available now*, how many years back.
- **Inventory**: a list of part, color, count and spare count. One set, or a mix: sets with a count each, plus loose parts.
- **Availability catalog**: for each part and color, the first and last year it came in a set, and in how many sets.
- **Pool**: the parts that count as one. A part, its mold variants and its alternates are one pool. With *any print* on, a printed part joins the pool of its plain part.
- **Status** of a part in the model: *allowed*, *not in this color*, *not available*, *too many* (past the count), or *no data*.

### How it looks

#### Choosing the limit, and the settings

Three places, each with one job.

**The document window shows and switches the limit.** A **Parts:** pop-up goes into the scope bar, after View: All/Steps and LPub3D Page. It switches the one app-wide limit, so every open window's pop-up and the Parts pane follow, as they do for the LPub3D Page switch.

```
Parts: [All Parts             ▾]  ⚠ 12
        All Parts
        Available Now
        ─────────────
        42115-1 Lamborghini Sián FKP 37
        Technic shelf (3 sets + loose parts)
        ─────────────
        Limit Options…
        Import Set Parts…
        Manage Inventories…
```

- The button after it shows how many parts of this window's model break the limit, and hides at zero. It opens a popover with the count of each kind, a **Select** button for each, and **Show Piece Count**.
- The same choices are in **View → Parts Limit**, with **Mark Limit Problems** to turn the marks on and off.
- **Limit Options…** opens a sheet: include spare parts (on, as Rebrickable's Build counts them); prints must match, or any print of a part will do; mold variants and alternates count as one (on); colors must match (on), or any color will do; how many years back *Available now* reaches (1, 2, 3, 5, or any year), and whether parts sold only through Pick a Brick count (off); and **Warn only**, which lets a color the part is not made in be picked, and only marks it.
- The limit and its options are kept in the app's defaults. Switching it is not an edit: it does not touch the file, mark the document changed, or go on the undo stack.

**The Inventories window keeps the library.** It is app-wide, under Window → Inventories.

- On the left, the imported sets and the inventories made from them.
- On the right, for an inventory: its sets with a count each, its loose parts (part, color, count), and **Add Set…**, **Add Parts from File…** (Bricksmith's own piece count export, Rebrickable CSV, BrickLink XML), **Remove**.
- For a set: name, year, theme, picture, part count, spare count, minifigures, the date it was fetched, and **Refresh**.
- An **Unmatched** list: the inventory parts with no LDraw part, and the model's parts with no LEGO match, so gaps in the matching can be seen and fixed by hand (Phase 7).
- **File → Import Set Parts…** opens the Add Set sheet at once: type a set number or a name, pick from the matches (number, name, year, picture), **Import**. It then offers **Use as the Limit**.

**Settings get a Parts pane**, for app-wide defaults and the data.

| Section | Rows |
|---------|------|
| Parts Data | Source: Rebrickable, updated *date*, **Update Now**. Update automatically: weekly, monthly, never. Rebrickable API key (optional), with a **Get a free key** link. The footer says what a key adds and credits the data |
| Limit | The same choices as the Parts pop-up, and **Limit Options…** |
| Part Browser | Parts the limit does not allow: Hide, Show dimmed |
| Marks | Mark parts that break the limit (switch). Highlight with: Stripes, Tint, Outline. A color well each for *not available* (red) and *too many* (orange). Dim allowed parts (switch) |

The LSynth pane's *Highlight with* pop-up and color well are the precedent for the Marks section.

#### The Part Browser

With **no limit**, the browser stays as it is, plus a **SETS** group in the category list, below Part Categories, with the imported sets and inventories. A set can be browsed at any time, and a **+** at the group's heading imports one.

With **Available now**:

- Every category and every search lists only the parts made now in at least one color. A bar over the list says so:

  ```
  Parts made in 2025–2026 · Show All
  ```

  Show All, or the *Show dimmed* preference, lists everything, with the parts the limit does not allow in gray. Primitives and Subparts are not filtered: they are for making parts, not models.
- A **color strip** goes under the preview: one chip for each color the selected part is made in now, in the Colors window's order. The current color's chip has a ring, and clicking a chip makes it the current color. When the current color is not among them, a struck-through chip of it comes first, and **Insert** is disabled with the tooltip *Not made in Sand Blue now. Pick a color below.* Past two rows, a **+12** chip opens a grid with the rest.
- A **color filter** button goes into the bottom bar. Its menu: **Any Color**, **Current Color (Red)**, then every color some part is made in now. Picking a color lists only the parts made now in that color, and the button shows its swatch while it is on. *Current Color* follows the Colors window, so every part in the list can be inserted as it is.

With an **inventory** as the limit, and whenever a set is selected under SETS:

- Rows are the inventory's items: one row per part *and color*. The columns are a color swatch, Part, Description and **Count**. Categories and search still filter them, by the LDraw part's category.
- **Count** reads `used / owned`: `5 / 10` in the normal color, `10 / 10` in gray when all are used, `11 / 10` with the whole row in red. With spares included, the tooltip says *10 + 1 spare*. Sorting by Count sorts by what is left.
- Insert, double-click and drag use the row's color, not the Colors window's.
- The color strip shows the selected part's other colors in the inventory, each chip with what is left. A click selects that row.
- An item with no LDraw part shows its LEGO number in gray and cannot be inserted.

One row per part and color, not per part, because a part can be over its count in one color and under it in another. A row per part would add the two up and hide the problem.

Every browser shows the one limit. The counts come from a model: the browser in a document window counts its own, and the shared Part Browser panel counts the main window's.

#### Colors

- With a limit on, the Colors window's material pop-up gets two items at the top: **For Selected Part**, and **In *inventory*** or **Made Now**. For Selected Part is the default.
- The selected part is the document's selection when it has parts. Otherwise it is the part selected in the Part Browser, the one the next insert makes. With several parts selected, a color must suit all of them.
- Under the other filters, the colors the selected part is not made in are dimmed and struck through, and they cannot be selected, by click, arrow key or a typed color code. **Warn only** in Limit Options lifts that, and the part is then marked instead.
- A line at the bottom says why the list is short: *Colors for Brick 2 x 4 (3001): 14 of 92*.
- **Randomize Color** picks only among each part's allowed colors.
- The inspector's color well uses the same window, so the same rule holds there.
- Parts that come in some other way are not stopped: paste, drag from another file, a typed part name, Insert Related, the Minifigure Generator. They are marked.

#### Marks in the model

**3D view.** A part that breaks the limit is drawn with diagonal stripes in its mark color, and its edges are drawn in that color too:

- red for *not available* and *not in this color*;
- orange for *too many*;
- nothing for *no data*. File Contents shows it.

Stripes show on a part of any color, red ones included, and look like neither a selected part (a wireframe) nor a ghost (see-through). The two kinds of stripes lean opposite ways, so they differ for someone who cannot tell red from orange. Tint and Outline are the other styles in Settings. **Dim allowed parts** draws every allowed part as a ghost, so the marked ones stand out in a big model. In Steps mode a step shows the marks of the parts it draws. The icons of the step's parts list are never marked: they are drawn from parts of their own.

*Too many* marks the copies past the count, in build order. If the sets hold 10 red 2 x 4 bricks, the 11th one built and those after it are marked, which shows where the bricks ran out. A part inside a submodel stands for every copy of the submodel, so it is marked when any of its copies is past the count.

**File Contents.** A marked part gets a badge at the end of its row:

| Status | Badge | Tooltip |
|--------|-------|---------|
| Not available | red `nosign` | *Not made now in any color.* / *Not in 42115-1.* |
| Not in this color | red `exclamationmark.circle.fill` | *Not made in Sand Blue now. Made in Black, Red, Light Bluish Gray and 11 more.* |
| Too many | orange `plus.circle.fill` | *The model uses 11 red Brick 2 x 4; 42115-1 holds 10.* |
| No data | gray `questionmark.circle` | *Bricksmith cannot match this part to a LEGO part.* |

A step or model row that holds marked parts shows how many, in the color of the worst one, so a collapsed tree still shows where to look.

**Elsewhere.**

- The part inspector gets a line: *Not made in Sand Blue now*, or *Uses 11 of 10 in 42115-1*.
- With a limit on, the Piece Count window adds **Owned** and **Status** columns, sorts the problems first, and gets a **Problems only** switch. Phase 8 adds **Export Missing Parts…**.
- A color problem can be fixed in one step, as Studio's Color Validator does: the popover and Piece Count offer **Use Nearest Allowed Color** for one row or for all, picking the allowed color nearest in RGB. It is one undoable edit.
- **Edit → Select Parts with Limit Problems**.
- No alert when a file opens. The count after the Parts pop-up is enough, and its popover selects.

#### Where the request's ideas went

| Idea | In this plan |
|------|--------------|
| Preferences → Parts → Highlight unavailable parts | The Marks section of the new Parts pane |
| A filter button with a color list in the Part Browser's bottom bar | The color filter button: Any Color, Current Color, then the colors made now |
| A settings page, tool or Part Browser extension for imported sets, set combinations, sets plus parts | The Inventories window keeps them; the SETS group shows them in the Part Browser |
| SETS in the Part Browser's left list; File → Import Set Parts | Both, with a **+** on the SETS heading too |
| Buttons for the selected part's colors in the bottom bar | The color strip under the preview, with what is left on each chip for a set |
| A selected set appears in the Colors window's pop-up | **In 42115-1** in the material pop-up |
| A Count column like `5 / 10`, a red line at `11 / 10` | The Count column, gray when all are used, a red row past the count |

### What counts as used

`LDrawPartUsage` walks the model the way it is built:

- It starts at the main model, the first in the file. A submodel reference is walked in place, once per reference, so a submodel used three times counts its parts three times. A submodel that no model references is checked for availability and colors, but not counted.
- Color 16 takes the color of the reference that brings the part in. A part in color 16 at the top of the main model has no real color, so its status is *no data*.
- Hidden parts count, since hiding is only a view. A part in a removed group counts once, in the step that adds it.
- Parts inside `PLI BEGIN IGN` and `PART BEGIN IGN` ranges do not count. LPub3D keeps them out of its bill of materials; they are alternates and helpers. A `PLI BEGIN SUB` range counts its substitute once instead of what it holds, as LPub3D lists it. A set lists it that way too: one hinge, not its two halves. `LDrawStepPartList` follows the same rules, so the range tracking moves into a helper that both use.
- An LSynth hose or band, a peer-file part, a missing part, and a part in a direct color (`0x2RRGGBB`) are *no data*.
- Copies are numbered in build order, so the copies past the count are the last ones built.

### Matching an LDraw part to a LEGO part

1. The LDraw name is normalized: lowercase, no `.dat`. An alias or a `~Moved to` part is followed to its target.
2. The LEGO part comes from, in order: a hand match; the `Rebrickable <number>` keyword in the part file, which the part catalog already holds; Rebrickable's own LDraw links, kept from any set fetched through the API; and last the same number, which holds for most plain parts.
3. Pools: a part's mold variants and alternates count as one, by default. With *any print* on, a print joins its plain part's pool. Both come from Rebrickable's part relations.
4. Colors map through the shipped table of Rebrickable's LDraw color links, never by the same number. With *any color* on, colors are not checked.
5. Phase 7 splits assemblies into their parts on both sides, so a minifigure torso with arms and hands in a set matches the torso, arms and hands an LDraw model places, and a hinge that a model builds from its halves matches the hinge in the set.

The map is built again when the LDraw library is reloaded, since the keywords come from it.

What has no match is *no data* and is listed under Unmatched. A match made there by hand is saved in `identity-overrides.json`, which wins over the map.

### Existing machinery to reuse

| Need | Existing code |
|------|---------------|
| Part records, categories and search | `LDrawPartBrowserModel` (`-reloadFilter`, `-filterPartRecords:bySearchString:excludeParts:`), `-[LDrawPartLibrary categoryHierarchy]`, `-partCatalogRecordsInCategory:` |
| Aliases and moved parts | `Category_Alias`, `Category_Moved`, `LDRAW_MOVED_DESCRIPTION_PREFIX` |
| A part's Rebrickable number | The `!KEYWORDS` of each part, kept in the catalog under `PART_KEYWORDS_KEY` and already searched by the Part Browser |
| The Colors window's filter | `+[LDrawColorPanelModel predicateForSearchString:material:]` and the `LDrawColorFilter` tags |
| Counting by part and color | `-[LDrawPartReport registerPart:]` keys by reference name and color. `LDrawStepPartList` has the IGN, SUB and color 16 rules |
| Derived per-part state kept on the part | `-[LDrawModel updateGroupSuppressionIfNeeded]` and `groupVisibility` |
| A per-part look that reaches into submodels | The `pushAlphaModulation:` stack in `LDrawCoreRenderer.h`, and the deferred ghost draws in both renderers |
| Redraw after a change of look only | `-noteNeedsDisplay` → `LDrawDirectiveDidChangeNotification` → `-[LDrawRenderer displayNeedsUpdating:]`. Selection works this way |
| Row text, icon and color in File Contents | `+[LDrawOutline outlineSyntaxColorKeyForDirective:]`, `+outlineIconNameForItem:`, `IconTextCell` |
| Once per edit | `-[LDrawDocument docChanged:]` |
| Settings pushed in by the host | `+[LDrawModel setGhostsPreviousSteps:]` from `LDrawApplication.m:392`, `+[PreferencesDialogController pushStepPartListDefaults]` |
| A preference pane in code | `PreferencesForm`; `-makeLSynthPane` has *Highlight with* and a color well |
| One setting shown and switched in every window | The LPub3D Page switch: `-[LDrawDocument lpubPageSwitchClicked:]` calls `+[PreferencesDialogController storeStepPartListFlag:forKey:]`, which stores the flag, pushes it into the packages and posts `LDrawStepPartListDidChangeNotification`. Every document and the Settings window follow |
| Selecting parts after a check | `-[LDrawDocument doMissingPiecesCheck:]` |
| Random colors | `+[LDrawSelection randomizedColorsForDirectives:]` |
| A parts list Rebrickable reads | `-[LDrawPartReport textualRepresentationWithSortDescriptors:]` |

### Module placement

**The rule, as for the parts list and callouts: everything but the AppKit chrome lives in the packages.** An iOS host should get the data, the matching, the counting, the statuses, the browser rows, the allowed colors and the mark colors for free, and write only its views.

| Module | Platforms | Contents |
|--------|-----------|----------|
| **LDrawInventory** (new) | macOS + iOS | Foundation only, depends on LDrawCore. `LDrawInventoryItem`, `LDrawSetInventory`, `LDrawCombinedInventory` (a mix of sets and loose parts), `LDrawPartAvailability` (the catalog), `LDrawPartIdentity` (LDraw ↔ LEGO parts and colors, pools, hand matches; reads the `Rebrickable` keywords and moved parts from the part catalog), `LDrawInventoryStore` (the library on disk, in a folder the host names), `LDrawPartLimit` (the setting), `LDrawPartLimitTable` (what a limit allows, for fast lookups). No network |
| **LDrawRebrickable** (new) | macOS + iOS | Foundation and `NSURLSession`, depends on LDrawInventory, links `z` for gzip. `LDrawRebrickableClient` (API v3, one call a second, retries, cancel), `LDrawRebrickableDownloads` (the CSV files, conditional GET, gzip, a streaming CSV reader), `LDrawRebrickableCatalogBuilder` (catalog, set list and part relations from the downloads), `LDrawRebrickableSetImporter` (one set, from the downloads or the API), and the color table as a resource. The host passes the API key in |
| **LDrawCore** | macOS + iOS | `LDrawPartLimitStatus` and a derived `limitStatus` on `LDrawPart`, neither archived nor copied. Host-pushed statics for marks: on or off, style, colors, dim allowed parts. `-drawSelf:` pushes the mark. `pushMark:`/`popMark` in `LDrawCoreRenderer`. Nothing in the file format changes |
| **LDrawRenderCore** | macOS + iOS | The mark stack in `LDrawShaderRenderer`, passed to `LDrawDLDraw` with each draw, like the ghost alpha |
| **LDrawRenderMetal** / **LDrawRenderOpenGL** | both / macOS | A marked draw deferred and drawn on its own, like a ghost. Stripes, tint or outline in the shaders. Edges in the mark color |
| **LDrawFeatures** | macOS + iOS | Now depends on LDrawInventory. `LDrawPartUsage`, `LDrawPartLimitCheck` (with the current table, pushed in by the host), `LDrawPartLimitReport`. `LDrawPartBrowserModel` gains the limit table, hide or dim, the color filter, inventory rows and the SETS group. `LDrawColorPanelModel` gains allowed colors and the new filter tags. `LDrawPartLimitPresentation`: count text, tooltip keys, badge and mark colors as RGBA, symbol names. Defaults in `LDrawPreferences` |
| **LDrawEditing** | macOS + iOS | `LDrawOutline` gives a row's status and a container's problem count. `LDrawSelection` gains *select parts with problems*, and random colors from an allowed list |
| **Bricksmith app** | macOS | The Parts pop-up, problem button and popover; Limit Options sheet; Import Set sheet; Inventories window; Settings → Parts pane; the Keychain item for the API key; the Part Browser's new columns, bar, color strip and filter button; the Colors window's dimmed rows and new pop-up items; the badge in `IconTextCell`; Piece Count columns; and the `LDrawDocument` wiring |

Conventions this has to respect, all already established:

- **No `standardUserDefaults` reads inside the packages.** The host pushes values in, as `LDrawApplication.m:390-393` does for the ghost settings.
- **No AppKit or UIKit types in package headers.** Colors cross as RGBA floats.
- **Strings cross as localization keys**, localized by the host.
- **The host names every place on disk.** The packages never look up Application Support or the app bundle.
- **Only LDrawRebrickable touches the network.** A host that links LDrawFeatures but not LDrawRebrickable reads a library someone else downloaded, and never makes a request.

How the parts fit together in the app:

```
LDrawInventoryStore (app-wide) ─┐
LDrawPartLimit (app defaults) ──┴─► LDrawPartLimitTable ─┬─► LDrawPartBrowserModel  (rows, counts, filter)
                                                         ├─► LDrawColorPanelModel   (allowed colors)
LDrawFile (each document) ─────────► LDrawPartLimitCheck ┴─► report ─► LDrawPart.limitStatus ─► 3D marks, File Contents
```

### Sketch of the main types

```objc
// LDrawInventory
typedef NS_ENUM(NSInteger, LDrawPartLimitKind)
{
    LDrawPartLimitKindNone          = 0,
    LDrawPartLimitKindAvailableNow  = 1,
    LDrawPartLimitKindInventory     = 2
};

@interface LDrawPartLimit : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>
@property (nonatomic, readonly)           LDrawPartLimitKind    kind;
@property (nonatomic, readonly)           NSInteger             yearsBack;              // Available now; 0 is any year
@property (nonatomic, readonly)           BOOL                  countsPickABrickParts;  // Available now
@property (nonatomic, readonly, nullable) NSString              *inventoryIdentifier;   // a set number, or an inventory's UUID
@property (nonatomic, readonly)           BOOL                  includesSpares;
@property (nonatomic, readonly)           BOOL                  matchesMoldVariants;
@property (nonatomic, readonly)           BOOL                  matchesAnyPrint;
@property (nonatomic, readonly)           BOOL                  matchesAnyColor;
@property (nonatomic, readonly)           BOOL                  warnsOnly;

// What the host keeps in its defaults. Nil or junk reads back as All Parts;
// -[LDrawInventoryStore resolvedLimit:] does the same for a removed inventory.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;
+ (LDrawPartLimit *) limitWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;
@end

// The same properties, readwrite, for a settings sheet.
@interface LDrawMutablePartLimit : LDrawPartLimit
@end

// What a limit allows, ready for lookups by LDraw name and color code.
@interface LDrawPartLimitTable : NSObject
+ (instancetype) tableForLimit:(LDrawPartLimit *)limit
                  availability:(nullable LDrawPartAvailability *)availability
                         items:(nullable NSArray<LDrawInventoryItem *> *)items
                      identity:(LDrawPartIdentity *)identity
                          year:(NSInteger)currentYear;
@property (nonatomic, readonly) BOOL hasData;                                       // NO without the catalog or items
- (LDrawPartLimitStatus) statusForPartNamed:(NSString *)partName
                                  colorCode:(LDrawColorT)colorCode;                 // never TooMany
- (BOOL) allowsPartNamed:(NSString *)partName;                                      // in some color
- (BOOL) allowsPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;
- (NSUInteger) ownedCountForPartNamed:(NSString *)partName
                            colorCode:(LDrawColorT)colorCode;                       // NSNotFound when not counted
- (nullable NSArray<NSNumber *> *) colorCodesForPartNamed:(NSString *)partName;    // nil when colors are not limited
- (nullable NSArray<NSNumber *> *) allowedColorCodes;                               // for the color filter
- (nullable NSString *) poolKeyForPartNamed:(NSString *)partName;                   // nil when there is no match
- (NSArray<LDrawInventoryItem *> *) items;                                          // an inventory's rows; empty otherwise
- (NSArray<LDrawInventoryItem *> *) unmatchedItems;
@end

// LDrawCore. A later value is worse.
typedef NS_ENUM(NSInteger, LDrawPartLimitStatus)
{
    LDrawPartLimitStatusAllowed         = 0,
    LDrawPartLimitStatusNoData          = 1,
    LDrawPartLimitStatusTooMany         = 2,
    LDrawPartLimitStatusNotInColor      = 3,
    LDrawPartLimitStatusNotAvailable    = 4
};

// LDrawFeatures
@interface LDrawPartLimitReport : NSObject
- (NSArray<LDrawPartLimitRow *> *) rows;                                            // one per pool and color: used, owned, status
- (NSUInteger) usedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;
- (LDrawPartLimitStatus) statusForPart:(LDrawPart *)part;                           // the worst over its copies
- (NSUInteger) problemCountInContainer:(LDrawContainer *)container;
@end

@interface LDrawPartLimitCheck : NSObject
+ (LDrawPartLimitReport *) reportForFile:(LDrawFile *)file table:(LDrawPartLimitTable *)table;
// Sets each part's limitStatus. Returns the parts whose status changed.
+ (NSArray<LDrawPart *> *) applyReport:(LDrawPartLimitReport *)report toFile:(LDrawFile *)file;
@end
```

### Phase 0 — `limit_data`: the data types and the store

- Add the `LDrawInventory` target and product to `Package.swift`, with a Swift Testing target `LDrawInventoryTests`. The app targets link the product in Phase 3, when the app first uses it, and LDrawFeatures gets it as a dependency in Phase 2.
- The types above, plus the store. Its folder, which the app sets to `~/Library/Application Support/Bricksmith/Parts Data/`, holds:

  | File | What |
  |------|------|
  | `Rebrickable/*.csv.gz`, `Rebrickable/downloads.json` | the downloaded files, with their dates and ETags |
  | `catalog.json` | availability: part → color → first year, last year, set count; and the date of the data |
  | `identity.json` | LEGO ↔ LDraw parts and colors, and the relations between parts |
  | `identity-overrides.json` | matches made by hand |
  | `sets/<number>.json` | one imported set, with both LEGO and LDraw ids, so a better map can match it again |
  | `inventories.json` | the user's inventories |

  Every file has a `version`. A reader skips what it does not know.
- `LDrawPartIdentity` reads the `Rebrickable <number>` keywords, the aliases and the moved parts from the part catalog, and is built again on `LDrawPartLibraryDidChangeNotification`.
- `LDrawPartLimitTable` resolves an inventory into pools and counts once, and answers every lookup from dictionaries. With spares off, spare counts are left out. With *any color* on, colors fold into one.
- Tests: mixing sets with counts; spares in and out; loose parts added; pools of mold variants and of prints; *Available now* by years and any year; the store round trip; a file of a newer version read without loss; the limit's dictionary round trip, with nil, junk and a removed inventory read as All Parts.

**As built.** `Packages/LDrawInventory`, with 54 tests; every package test passes and the target builds for the iOS Simulator. What came out differently from the sketch:

- *The mix of sets is `LDrawCombinedInventory`.* The umbrella header is `LDrawInventory.h`, so no class can take that name.
- *`LDrawPartLimitStatus` is already in LDrawCore*, in `LDrawPartLimitStatus.h`, because the table answers with it. `LDrawPart` gets no `limitStatus` until Phase 2.
- *A limit is an immutable value with a mutable subclass*, `LDrawMutablePartLimit`, as Foundation's collections are. The defaults dictionary keeps the kind as a word (`none`, `availableNow`, `inventory`). An inventory limit names a set number or a combined inventory's UUID, and the store's `-resolvedLimit:` turns one whose inventory is gone into no limit, keeping its options.
- *The table takes its data, not the store*, so it is tested without files; `-[LDrawInventoryStore tableForLimit:identity:year:]` puts them together. It answers `-statusForPartNamed:colorCode:` too, and keeps the items that match nothing in `-unmatchedItems`. `-partNamesInColor:` was dropped: the Part Browser asks about each record instead, and `-allowedColorCodes` serves the color filter.
- *Rebrickable's "any color" (9999)* counts toward every color of its pool, and an item in "unknown" (-1) is unmatched.
- *Several Rebrickable colors can share an LDraw color*, so the identity map gives a list (`-rebrickableColorIDsForColorCode:`), and a part is allowed when any of them is.
- *Moved parts are followed; alias parts are not yet.* The catalog does not record what an alias points to. Phase 2 can read it from the part file, which is loaded for drawing anyway.
- *The identity map is immutable.* The host builds it again when the library or the store changes.
- *Swift names are set with `NS_SWIFT_NAME`*, as `LDrawStepPartList` does, so another host gets a stable API: `LDrawPartLimit.availableNow()`, `LDrawPartLimitTable(limit:availability:items:identity:year:)`, `store.saveSetInventory(_:)`.

### Phase 1 — `limit_rebrickable`: getting the data

- Add the `LDrawRebrickable` target, `linkerSettings: [.linkedLibrary("z")]`, and `LDrawRebrickableTests` with fixture files, and link the product into both app targets. No test touches the network: the client takes a session configuration, and the tests stub it with an `NSURLProtocol`.
- **Downloads.** Fetch `sets`, `themes`, `inventories`, `inventory_parts`, `inventory_minifigs`, `inventory_sets`, `minifigs`, `parts`, `part_relationships` and `colors` with conditional GETs, at most once a day, inflate them, and read them a row at a time. Read columns by header name, so a column Rebrickable adds later does no harm.
- **Catalog.** Join inventory parts → inventories → sets for the year of each part and color. A set's minifigures and the sets inside it count too, through `inventory_minifigs` and `inventory_sets`, with their quantities multiplied. Use each set's latest inventory version; versions do not always start at 1. Keep the first year, the last year and the number of sets, for each part and color, and mark the parts found only in *Database Sets*.
- **Identity.** This phase adds to Phase 0's keyword map the links kept from API set fetches and the relations from `part_relationships` (`P` print, `M` mold, `A` alternate, `B` sub-part, `T` pattern, `R` pair), in the order *Matching an LDraw part to a LEGO part* gives. Colors come from the shipped table (`Resources/rebrickable-colors.json`, made by a small script at release time from `lego/colors/`). A user's key refreshes the table with that same one call.
- **Set import.** From the downloads, offline and keyless: the set's inventory, spares flagged, minifigure parts included. With a key, from the API instead, which is fresher and carries Rebrickable's own LDraw ids. Set search by number or name runs on the downloaded set list.
- The client keeps to one call a second, backs off on 429, can be cancelled, and reports progress. The catalog is built on a background queue, and the host shows the progress.
- Tests: CSV quoting (commas and quotes in names); gzip; a header with an extra column; the year join; a set's latest inventory version; minifigure parts and sets inside sets, multiplied; spares; *Database Sets* kept apart; colors 9999 and -1; API JSON with paging; a 429 then success; a keyword match preferred over the same number; a clashing color id (326) mapped through the table, not by number.

**As built.** `Packages/LDrawRebrickable`, with 28 tests on small hand-made files in Rebrickable's formats and a stub URL protocol; nothing in them reaches the network. Every package test passes and the target builds for the iOS Simulator. What came out differently, or is still open:

- *The color table is made from names for now.* `Scripts/make_color_table.py --names colors.csv.gz LDConfig.ldr` links 198 of Rebrickable's colors by name, then by an RGB value only one LDraw color has; the rest are mostly special lines (HO, Duplo, Modulex, Vintage). Run `REBRICKABLE_API_KEY=… Scripts/make_color_table.py --api` once to replace it with Rebrickable's own links. A user's key can do the same at run time, and `colors-api.json` in the downloads folder then wins.
- *One Rebrickable color can be several LDraw colors.* Black is LDraw's 0 and 256 (rubber black), so color links map an id to a list of codes. `LDrawPartIdentity` took that change.
- *`LDrawInventoryJSON.h` is public now*, so both packages read JSON the same careful way.
- *The set import reads the downloads, sets inside sets and minifigures included, each multiplied.* The API import does not fetch sets inside a set yet.
- *A set's count in the catalog can come out high* when a part is in the set and in one of its minifigures: each inventory is read on its own. Years, which are what *Available now* reads, are right.
- *On the real files* (`LDrawRebrickableLiveTests`, which runs only when `REBRICKABLE_LIVE_FOLDER` names a folder, checked on 2026-10-26):
  - The ten files came down in about a second. A second run within the day asked for nothing.
  - The catalog built in 4.2 s: 61,910 parts with records, 64,906 parts Rebrickable knows, 37,543 relations, 28,553 sets. Saved, it is 2.9 MB and reads back in 0.08 s.
  - A set imports from the files in 2.5 s, since it reads every part row. 42115-1 came to 295 items, 3,696 parts and 22 spares, Rebrickable's own count. 99.3% of its items (99.8% of its pieces) found an LDraw part in the library, and every color linked; 10295-1 did the same at 99.2%.
  - Of the library's 22,965 parts (aliases, moved parts, primitives and subparts left out), Rebrickable knows 61.8%, 59.2% were ever made, and 15.8% came in a set of 2025 or 2026; 75 colors have some part made now. Most of the rest are stickers (about 3,350; Rebrickable lists sticker sheets), LDraw prints with no keyword (1,871), shortcuts (816) and obsolete parts (815). Phase 7 can match an LDraw print to its plain part by name, since LDraw names a print as the base number, `p`, and a code.

### Phase 2 — `limit_check`: what the model uses, and each part's status

- `LDrawPartUsage` walks the file as *What counts as used* says, and records each directive's copies in build order.
- `LDrawPartLimitCheck` puts the usage against an `LDrawPartLimitTable`, gives each copy a status, and each directive the worst status of its copies. It counts the problems in each container for File Contents.
- `LDrawPart` gets `limitStatus`. `+applyReport:toFile:` sets it and returns the parts that changed, which the document then redraws with `noteNeedsDisplay`.
- The IGN and SUB range tracking in `+[LDrawStepPartList collectStep:…]` (its `LDrawStepPartListRange` stack) moves into an internal helper both walks use. The step list's tests keep passing unchanged.
- Tests: color 16 through two levels of submodels; a submodel placed three times; IGN left out; SUB counted as its substitute; the 11th copy marked and the first 10 not; a submodel in two colors; an unreferenced submodel checked but not counted; LSynth and missing parts as no data; spares on and off; a 5,000-part model checked well under 50 ms.

### Phase 3 — `limit_settings`: choosing the limit

- The app keeps the limit in its defaults under `PARTS_LIMIT_KEY`, as the dictionary `LDrawPartLimit` gives. `+[PreferencesDialogController storePartsLimit:]` stores it, builds the `LDrawPartLimitTable`, pushes it into LDrawFeatures (`+[LDrawPartLimitCheck setCurrentTable:]`), and posts `LDrawPartLimitDidChangeNotification`: the path `+storeStepPartListFlag:forKey:` takes for the LPub3D Page switch. At launch, `LDrawApplication` pushes it with the other settings. When the store changes, the table is built again and the same notification goes out.
- Every document observes the notification: it sets its Parts pop-up, runs its check again and updates its marks. It also runs the check from `-docChanged:`, at most once per edit. The report and the marks live in memory only; the file and the undo stack never see them.
- The Parts pop-up, the problem button and its popover go into the scope bar. View → Parts Limit gets the same items. The Parts pane in Settings observes the notification too.
- Limit Options sheet, Import Set sheet, Inventories window, Settings → Parts pane. The API key goes into the Keychain, never into the defaults.
- First use: when a limit is first chosen with no data on the Mac, a sheet says what is downloaded, from where, and how big it is, and asks before downloading.
- New keys go into `LDrawKeys.h` (`PARTS_LIMIT_…`), with defaults in `LDrawPreferences`, and the host pushes them into the packages at launch and on change.

### Phase 4 — `limit_browser`: the Part Browser

- `LDrawPartBrowserModel` gets a `limitTable`, a `hidesDisallowedParts` flag, a `colorFilter` and a `usageReport`. `-reloadFilter` then keeps only allowed records, or marks the others as dimmed. For an inventory it returns inventory rows, with extra keys for the color code, used, owned and status. It also adds the SETS group to the category hierarchy, from the store.
- `PartBrowserDataSource` shows the swatch and Count columns only when the rows have them, draws dimmed and red rows, adds the bar over the list, the color strip under the preview, and the color filter button. Insert and drag take the row's color when it has one.
- The shared panel listens for `LDrawPartLimitDidChangeNotification` and for the main window changing, and reloads.
- Tests, on the model only: hide and dim; a color filter; inventory rows and their counts; the SETS group; the count text and its status; sorting by what is left.

### Phase 5 — `limit_colors`: the Colors window

- `LDrawColorPanelModel` gets `+predicateForSearchString:material:allowedColorCodes:`, the two new filter tags, and `+canSelectColorCode:allowedColorCodes:warnsOnly:`.
- `LDrawColorPanelController` adds the new pop-up items when a limit is on, dims the rows it may not select (`LDrawColorCell`), refuses them in `-tableView:shouldSelectRow:`, and shows the footer line. It follows the limit, the main document's selection, and the Part Browser's selected part.
- `+[LDrawSelection randomizedColorsForDirectives:allowedColors:]` takes a block that gives each part's allowed colors.
- Tests, on the models: allowed colors for one part and for several; a typed code that is not allowed; random colors stay allowed.

### Phase 6 — `limit_marks`: marks in the model

- **Renderers.** `pushMark:`/`popMark` join the renderer protocol and keep a stack, like `pushAlphaModulation:`, so a mark reaches the parts inside a submodel and the colors baked into a printed part. `LDrawDLDraw` takes the mark with each draw. A marked draw is deferred and drawn on its own with its mark in per-draw data, the way a ghost carries its alpha. That keeps hardware instancing for the unmarked parts, which are almost all of them.
  - Metal: the fragment input gets the screen position (`[[position]]`) for stripes; the mark color and style go in a small per-draw buffer; `partVertex`, `wideLineVertex` and the transparent pipelines carry them.
  - OpenGL: a constant vertex attribute for the mark, and `gl_FragCoord` for stripes, in `LDrawDefault.glsl`.
  - *Dim allowed parts* pushes the ghost alpha for every allowed part, through the path ghosts already use.
- `-[LDrawPart drawSelf:]` pushes the mark when marks are on and the part's status calls for one.
- **File Contents.** `+[LDrawOutline outlineLimitStatusForItem:]` and `+outlineProblemCountForItem:`; `IconTextCell` draws the badge at the end of the row; the outline's tooltip gives the reason.
- Inspector line, Piece Count columns, Edit → Select Parts with Limit Problems.
- **Use Nearest Allowed Color.** `LDrawPartLimitPresentation` picks the nearest allowed color by RGB distance; the document applies it through `-setObject:toColor:` as one undo group.
- Check on both the Metal and the OpenGL app, in All and Steps modes, on LPub3D's page, with transparent parts, printed parts and ghosts.

### Phase 7 — `limit_assemblies`: assemblies, minifigures and prints

- Split assemblies into their parts on both sides before they meet: Rebrickable's sub-part relations for the inventory, and LDraw shortcuts (`!LDRAW_ORG Shortcut`) and `PLI BEGIN SUB` for the model, whichever is finer.
- Minifigure parts: torsos with arms and hands, hips with legs.
- The Unmatched list and hand matches in the Inventories window.
- Tests with real cases from a fixture library: hinge halves against a hinge, a minifigure from the Minifigure Generator against a set's minifigure.

### Phase 8 — `limit_polish` (optional)

- **Export Missing Parts…** from the Piece Count window, as a BrickLink wanted list (XML) or a Rebrickable CSV.
- Import a BrickLink inventory XML as loose parts.
- Rebrickable "My Parts" as an inventory, with the user's token.
- Mark the parts of Insert Related and the Minifigure Generator's lists.
- Brickset's *on sale now* dates for a stricter *Available now*, for those who have a Brickset key.
- A red count in the step's parts list for a part past the count.

---

## Decisions

Decided:

- **The limit is an editor setting.** It is never written into the model. One limit holds for the whole app, kept in its defaults, and every window shows and switches it.

To confirm. The plan above takes the first answer of each, and each is cheap to change before its phase starts.

1. **What "available now" means.** In a set from this year or last, adjustable; or on sale today, which needs Brickset's dates and a Brickset key (Phase 8). The years rule is free, keyless and close enough.
2. **Which copies are *too many*.** The copies past the count, in build order; or every copy of that part and color. The first shows where a part runs out.
3. **Colors a part is not made in.** Blocked, with *Warn only* as an option; or never blocked, only marked.
4. **Parts the limit does not allow, in the browser.** Hidden, with *Show All* in the bar; or shown dimmed. The request asks for hidden.
5. **The Rebrickable API key.** Optional: everything works from the downloads and the library's keywords, and a key only fetches a set fresh. Or no API at all, which is simpler still but loses fresh sets. A shipped table of every part's LDraw link would close more gaps, but making it takes a crawl the API docs ask apps not to make, so it would need Rebrickable's consent first.
6. **Browser rows for a set.** One per part and color, with a count each; or one per part, with the colors in the strip. Only the first can show `11 / 10` honestly.

## Risks

- **Matching.** LDraw and LEGO number parts differently, mostly for prints, assemblies, minifigure parts and stickers. *No data* and the Unmatched list make each gap visible, hand matches close it, and Phase 7 removes the common ones.
- **The data's terms and shape.** The download terms ask for a credit and at most one automated download a day; the plan does both. The API is overloaded and may stop taking new apps, so nothing depends on it. Rebrickable may change its files: columns are read by name, every request backs off, and Bricksmith keeps working on the data it has. Only the small color table ships in the app; each user's Bricksmith downloads the rest.
- **Community data.** Rebrickable's inventories are made by people and have mistakes, and the LDraw keywords are added by hand. Hand matches and *Refresh* on a set are the way out.
- **Size and time.** The inventory parts file has over a million rows. It is read as a stream on a background queue, the catalog is kept, and the download is asked for before it starts.
- **"Available now" is a guess from release years.** The UI says what it means ("made in 2025–2026"), not "in stock".
- **Speed.** The check runs once per edit and is timed in a test. Marked parts draw one by one like ghosts, and there are few of them. *Dim allowed parts* draws many as ghosts, as Steps mode's ghosting already does.
- **Two renderers.** The stack is shared in LDrawRenderCore, and the shader work is done and checked in both.
- **One limit for every window.** Two models meant for different sets cannot be checked against different limits at once; switching takes one click in either window. A limit per window, still kept out of the file, can come later without changing the packages: the check already takes its table as an argument.
- **Offline and errors.** Every view works from the last data. Errors say what failed and offer Retry.

## Tests

- **LDrawInventoryTests:** the types, the pools, the limit table, the store, the limit's dictionary.
- **LDrawRebrickableTests:** CSV, gzip, the catalog join, set import, the color table, the API client with a stubbed session, rate limiting. Fixtures are a few hand-cut rows of each real file, with the credit kept.
- **LDrawFeaturesTests:** usage and statuses, the browser model's rows and counts, the Colors window's allowed colors, the presentation's text and colors.
- **LDrawCoreTests:** `limitStatus` neither archived nor copied, and a file saved with marks on is the same as one saved with them off.
- **By hand, in the app:** both renderers; All and Steps; LPub3D's page; a set limit on a copy of a real model (never the original); offline; a first download; a bad API key.
