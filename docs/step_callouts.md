# Step callouts

**Overview:** A callout takes a submodel out of the step that places it and shows how to build it in a box of its own, with an arrow to where it goes. LPub3D writes one as `0 !LPUB CALLOUT BEGIN` … `0 !LPUB CALLOUT END` around the line that places the submodel. Bricksmith reads those lines, draws the box over the main 3D viewport with the step parts list, and writes a moved, added or removed callout back in a form LPub3D reads.

It builds on the step parts list. Read [step_part_list_frame.md](step_part_list_frame.md) first: the overlay, the packer, the page and the way a meta line is found in force are all described there.

## Plan status

| ID | Phase | Status |
|----|-------|--------|
| `callout_metas` | Phase 1: typed CALLOUT metas, and the parts list rule | completed |
| `callout_summary` | Phase 2: the summary box, its arrows, click to enter and a way back | completed |
| `callout_page` | Phase 3: on LPub3D's page, the step strip, `PLACEMENT`, and dragging a box | completed |
| `callout_style` | Colors, borders, margins and fonts from the file | completed |
| `callout_centering` | The step centered on the page as LPub3D 2.4.3 and later does it, and `ASSEM PLACEMENT` | completed |
| `callout_editing` | Adding a callout from the parts list, and removing one from its box | completed |
| `callout_dividers` | Adding and removing a divider from the menu of a step in a box | completed |
| `callout_direction` | Turning the steps of one callout, down or across, from its box's menu | completed |
| `callout_follow` | A box moves with its submodel while the model is turned on the page | completed |
| `callout_automatic` | A preference that has the callouts placed automatically, with the file's placement of them not read | completed |

## What a callout is in the file

```
0 !LPUB CALLOUT BEGIN
1 0 90 -40 -10 1 0 0 0 1 0 0 0 1 seat left arm.ldr
1 0 -30 -40 -10 1 0 0 0 1 0 0 0 1 seat left arm.ldr
0 !LPUB CALLOUT POINTER TOP_LEFT 0.367 0.656 0
0 !LPUB CALLOUT POINTER TOP 0.392 0.521 0.399 0
0 !LPUB CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE -0.00452592 0.032123
0 !LPUB CALLOUT END
```

Everything below was read from LPub3D's source (`traverse.cpp`, `meta.cpp`, `callout.cpp`, `ranges.cpp`, `step.cpp`, `placement.cpp`, `calloutpointeritem.cpp`) and checked against a printed LPub3D instruction book for the same model.

- **The bracket.** `BEGIN` takes nothing, `ASSEMBLED` or `ROTATED`. With nothing, the box shows the submodel's steps. `ASSEMBLED` shows it finished from the default view, and `ROTATED` finished as it sits in the step. A part between the two lines that places no submodel is an ordinary part of the step. LPub3D does not nest brackets in one file.
- **Instances.** A second line placing the same submodel adds no steps, only a count.
- **`CALLOUT DIVIDER`** sits in the called-out submodel, between two of its steps. The steps after it start a new column, or a new row. LPub3D writes it as the first line of the step that starts one, and all 12 in the Porsche are there. It reads the model line by line, though, and the line ends the column or row of the step it is reading. So a `DIVIDER` counts for a step when it comes anywhere between the first thing built in the step shown before and the first thing built in the step itself: after a part of the step before, in a step between the two that builds nothing, or at the top of the step (`+[LDrawStepCallout dividerLinesBeforeStep:]`). `CALLOUT DIVIDER STEPS` is another thing, a line between two steps of one column, and is not read.
- **`CALLOUT ALLOC (HORIZONTAL|VERTICAL)`** says which way the steps run. Vertical is the default: steps run down a column, and columns follow each other to the right.
- **`CALLOUT PLI PER_STEP (TRUE|FALSE)`.** `TRUE`, the default, gives each step in the box a parts list of its own. `FALSE` hands the parts to the list of the step that holds the callout, once for each instance.
- **Step numbers** are drawn only when the box has more than one step, and not at all under `ASSEM SHOW_STEP_NUMBER FALSE`.
- **The count** goes in the bottom right corner. When it would cover a picture the box grows sideways or downward, whichever adds less area.
- **`CALLOUT PLACEMENT <position> [<justification>] <relative to> (INSIDE|OUTSIDE) [[OFFSET] x y]`.** Outside, a side puts the box past that edge, a margin away, and the second word says where along the side. A corner puts it diagonally past the corner. Inside, the box sits against the edge from within. The offset is a share of the size of the thing the box is placed against. With no line the box goes `RIGHT CENTER ASSEM OUTSIDE`.
- **`CALLOUT POINTER <position> [<location>] x y [base]`.** For a straight arrow, `x y` is the tip as a share of the step's assembly picture, from its top left. Where the arrow leaves the box is not read from the line: LPub3D works it out from the tip, as the point of the box's edge nearest to it. The position and location in the line are that result written down. LPub3D draws only the arrows the file lists.
- **Scale.** A callout's assembly is drawn at `CALLOUT ASSEM MODEL_SCALE`, 1.0 unless the file says otherwise. `ASSEM MODEL_SCALE` does not reach into the box.
- **How the box looks.** `CALLOUT BORDER`, `BACKGROUND`, `SUBMODEL_BACKGROUND_COLOR`, `MARGINS`, `ASSEM MARGINS`, `PLI MARGINS`, `SEPARATOR`, and `FONT` and `FONT_COLOR` under `STEP_NUMBER` and `INSTANCE_COUNT`. Lengths are in the file's unit, inches unless `RESOLUTION` is in `DPCM`. A border's radius is in dots at the file's resolution.
- **Where the assembly goes.** `ASSEM PLACEMENT [LOCAL] CENTER PAGE INSIDE x y` moves the step on its page by a share of the page. See *Where the step goes on the page* below.

### Which lines are in force for a callout

LPub3D reads the lines between a callout's `BEGIN` and `END` into that callout alone (`traverse.cpp` gives each callout a copy of the metas and parses its lines into the copy). So for one callout:

1. a line between its own two lines wins;
2. then a line of the step that comes before its `BEGIN` and is in no other callout;
3. then what earlier steps carry.

A line inside another callout of the same step does not count. A line inside a callout of an *earlier* step does, unless it says `LOCAL`: LPub3D finds a page by reading every line before it into one set of metas. In the Porsche an unscoped `CALLOUT ALLOC HORIZONTAL` inside one callout turns the callouts of later pages horizontal, and the printed book shows it. `-[LDrawStepCallout directiveInForceMatching:]` is that rule, on top of `+[LDrawStepPartListPolicy directiveInForceForStep:excluding:matching:]`.

### The parts list rule

A submodel a callout shows the steps of is built in the box from loose parts, so the step's list takes the parts and not the submodel:

- The called-out submodel is **not** a row of the step's list, whatever the submodel preference says.
- Its parts are rows of the step's list when `CALLOUT PLI PER_STEP FALSE` is in force, once for each instance, and a part in the main color takes the color the submodel is placed in. Otherwise the box lists them.
- A submodel shown finished (`ASSEMBLED`, `ROTATED`) is built on pages of its own, so it stays a row like any other placed submodel, and none of its parts are listed.
- `PLI BEGIN IGN` and `PART BEGIN IGN` around the placing line keep everything out, and the submodel's own ranges still apply inside it.

One point is taken from LPub3D's printed pages, not its source. `traverse.cpp` reads as if a called-out submodel were also a row under `PLI INCLUDE_SUBMODELS TRUE`, in every release from 2.4.3 on. The printed book for the Porsche never lists one, on any of its callout pages, while it does list the submodels placed with no callout. The pages won, and the rule is also the one that counts each part once.

## What Bricksmith draws

The overlay is the parts list's. `LDrawStepPartListPresentation` gives the host a list of `LDrawStepCalloutBox`, and `StepPartListView` draws them. A box is made of pictures, labels and divider lines, so the two forms below are drawn by the same code.

The boxes and their arrows are on top of everything else in the overlay, the parts list included. LPub3D stacks them the same way: a callout's background has z value 98 and the parts list's has 0 (`declarations.h`), so a box that reaches over the list shows whole. The list's icons are a 3D view of their own, with the counts in another view above it, and what the overlay itself draws lies under both. So the callouts, and the button that leads back, are drawn in one more view above those two, `StepPartListTopView`, which covers the overlay. In it every arrow comes first and the boxes after, in the callouts' order: a box covers the place its arrows leave from, a later box covers an earlier one, and a click goes to the box on top.

### Off the page: the summary

Bricksmith is an editor, and a strip of steps takes room the model needs. So off the page a box is a summary:

- each submodel finished, in the view of its last step, packed like a small parts list, with `2×` under one placed twice;
- the parts the box lists itself, when the step's list does not have them;
- a badge on the top edge that says how many steps build it;
- an arrow to each placement.

The boxes stack down the left edge under the list, and start a new column when there is no room below. A box is no bigger than 35% of the view each way; a bigger submodel is drawn smaller.

The arrows are worked out, not read. The file's tip is a place on LPub3D's picture of the step, which means nothing in a view that can be turned, panned and zoomed. Each arrow is aimed at the middle of a placement, projected on every camera change, and there are as many arrows as the callout has `POINTER` lines, up to one for each placement. A callout with no such line points nowhere, as in LPub3D.

An arrow does not run all the way to that middle, and it does not start at a corner of the box. Both are taken from LPub3D's pages.

It leaves the box at the point of an edge nearest the middle, kept clear of that edge's two corners. On the page the room kept is the border's corner radius plus half its margin, which puts the start just past the rounded corner: 0.12 inch in the Porsche. The two corner arrows of page 8 of its book leave their boxes 0.18 and 0.19 inch from the corner, the radius plus the whole margin, and that read as too far along the edge here. The room is never less than the space two arrows keep between them, so a square box with no margin keeps its arrows off its corners as well. Off the page it is 7 points. A placement past a corner is past two edges, and the arrow leaves the one it is further past. An edge too short to keep clear of both corners is left at its middle.

Two arrows never leave an edge closer together than a small space: 0.08 inch on the page, 6 points off it. Placements past the same corner would all be reached from the same point of the edge, so the box works out the arrows of an edge together (`-[LDrawStepCalloutBox arrowsToMiddles:outlines:]`, with `PlaceStarts()` for one edge):

1. Each arrow's place is the one it would have alone. In order along the edge, each place is moved clear of the one before it, then back from the far corner. So the first arrow at a corner keeps the place a lone arrow has, and the others go further from the corner. An edge with more arrows than room for them shares itself out evenly.
2. The places are handed out from the low end of the edge. Each goes to the arrow whose placement is furthest round toward that end, seen from the place. Of two placements in one direction the nearer one gets it.

The second step is what keeps arrows from crossing. Every other placement is then on the far side of the arrow just placed, and so is every place still to hand out, so no later arrow can cross it. Arrows on different edges of a box cannot cross either: the edge an arrow leaves is the one its placement is further past, which keeps the two on opposite sides of the diagonal out of the corner. Arrows of two different boxes are not looked at.

From there the arrow keeps the line to the middle, and stops a little short of where the line first meets the edge of the placed submodel. The space left is 0.05 inch on the page, LPub3D's margin, and 4 points off it. An arrow drawn to the middle covered the very thing it points at. The edge is taken from the same outline points the assembly is measured by: the submodel's points, placed as the part places it, are projected by the host (`-[LDrawView viewPointsForModelPoints:]`), and `-[LDrawStepCalloutBox arrowsToMiddles:outlines:]` finds where the line crosses the outline around them. That outline has no dents, so on a submodel with a hollow side the tip can stop a little short of what is drawn. With nothing to measure, and for an arrow whose start is already inside the outline, the tip is the middle.

### On LPub3D's page: the steps

With *Draw on LPub3D's page* on, a box is laid out the way LPub3D prints it:

- one picture for each step of the submodel that builds something, showing everything built up to that step, in that step's own rotation, at the callout's scale;
- steps running down or across by `ALLOC`, in groups split at `DIVIDER`, with a line between two groups; a group shorter than the longest spreads its steps over that length;
- step numbers and the count as described above. The count is written `×2`, the sign first, as LPub3D prints it;
- each step's own parts above its picture when `PER_STEP` is `TRUE`;
- a callout that shows its submodel finished gets one picture.

The box goes where its `PLACEMENT` line says, `CALLOUT MARGINS` away. `PAGE` is the page, `PLI` the parts list frame, and anything else stands for the assembly, since Bricksmith draws one step at a time and has no step number or step group to place against. A box is not kept on the page: LPub3D lets one hang off the paper, and a file that does that should show it.

The arrows are the worked-out ones, as off the page. An earlier version drew the file's tips here, but they are shares of LPub3D's picture of the step, and Bricksmith's picture is not the same picture: the camera, the cropping and the scale all differ a little, and the tips landed beside the parts. So the `POINTER` lines only say how many arrows there are. On the page an arrow is drawn in the color of the box's outline and as thick as it, with a head 5/16 inch long and 1/8 inch wide, which are LPub3D's sizes. A `BORDER HIDDEN` box gets arrows with no head.

The box, the step's center and the arrows all need to know where the step's assembly is drawn. The host measures it: `+[LDrawStepPartListPolicy assemblyOutlinePointsInModel:]` gives the points to project and `-[LDrawView viewRectForModelPoints:]` the box around them. A part is measured by its real shape, not by its box: for 26 fixed directions, the corner of the part that reaches furthest along each. A box around a round or a sloped part is bigger than the part. The points of a part are kept for as long as the catalog keeps the part.

### How the box looks on the page

`LDrawStepCalloutStyle` works out one callout's look from the lines in force for it, with LPub3D's own choice where the file says nothing (`CalloutMeta` in `meta.cpp`, `declarations.h`). Everything comes out in page inches, so the host only multiplies by the page inch.

| What | From | With no line |
|------|------|--------------|
| Outline: shape, dashes, color, thickness, corner radius | `CALLOUT BORDER` | square, solid, black, 1/32 in |
| Room inside the outline | the `MARGINS` at the end of a `BORDER` line | 0.05 in |
| Fill | `CALLOUT BACKGROUND` | the submodel color |
| The submodel colors | `CALLOUT SUBMODEL_BACKGROUND_COLOR` | white, `#FFFFCC`, `#FFCCCC`, `#CCCCFF` |
| Room between the box and what it is placed against | `CALLOUT MARGINS` | 0.05 in |
| Room between two steps | `CALLOUT ASSEM MARGINS` | 0.05 in |
| Room around a step's parts list, its number and the count | `CALLOUT PLI MARGINS`, `STEP_NUMBER MARGINS`, `INSTANCE_COUNT MARGINS` | 0.05 in |
| The line between two groups, and the room on each side | `CALLOUT SEPARATOR` | black, 1/32 in, 0.05 in |
| Step number text | `CALLOUT STEP_NUMBER FONT`, `FONT_COLOR` | Arial 36 bold, black |
| Count text | `CALLOUT INSTANCE_COUNT FONT`, `FONT_COLOR` | Arial 24 bold, black |

How the numbers are used, each read from `callout.cpp` and `step.cpp` and checked against the book:

- **The box** is its content plus, on each side, the border's margin and its thickness (`Callout::sizeIt`).
- **Two steps** of a group are one `ASSEM MARGINS` apart, not two: LPub3D keeps the larger of two neighbors' margins. There is no such margin at the box's edge.
- **A divider** takes its thickness and the separator's margin on each side.
- **A border line with no `MARGINS`** keeps the margins LPub3D had, so they come from the last `BORDER` line in force that has them.
- **The submodel color** is picked by depth. A callout takes the color one level deeper than the model it is in, so a callout in the top model is the second color, cream. A depth past the list takes the last color. A picture or a gradient cannot be drawn here and gets the submodel color.
- **A color** is `#rgb`, `#rrggbb`, `#aarrggbb` or an SVG color name, the forms Qt reads. One that cannot be read is black, as in LPub3D.
- **A font** is Qt's description, `"Arial,48,-1,5,50,0,0,0,0,0"`: family, point size, pixel size, style hint, weight, slant. LPub3D hands it to Qt unscaled and paints at one dot per pixel, so 48 comes out as 48 dots at the file's resolution, which is 48/170 inch in the Porsche. The book confirms it: its 48 point count is 0.32 inch tall at 150 DPI. Weight is bold from 63 on Qt 5's scale and from 600 on Qt 6's, which writes more than ten values. A family the Mac does not have is drawn in the system font.
- **Text room** is an estimate, since the package cannot measure a font: 0.56 of the size for each character, 1.15 of it for the line, and the 4 dots Qt keeps clear around a text item. The host draws the text in the middle of that room and does not cut it short.

Off the page a box keeps Bricksmith's own look, the parts list's frame. The file's colors are chosen for LPub3D's page background, which is not drawn there.

### Where the step goes on the page

LPub3D does not center the assembly alone on its page. It centers one box around the assembly and what is placed against it (`Placement::placeRelativeBounding` in `placement.cpp`, called for the single step page in `formatpage.cpp`), and `ASSEM PLACEMENT ... CENTER PAGE INSIDE x y` then moves that box by `x` and `y` shares of the page.

Which callouts are in that box depends on the version. Up to 2.4.2 every callout placed against the assembly is, so a tall callout above the assembly pushes the assembly down, and dragging a callout moves the assembly. From 2.4.3 on a callout that has been dragged, that is one whose `PLACEMENT` has an offset that is not zero, is left out (`Placement::relativeTo`, with a comment that calls it a hack), so dragging a callout moves nothing else. Bricksmith follows 2.4.3 and later:

- a callout placed against `ASSEM` with no offset, or with no `PLACEMENT` line at all, is centered with the assembly;
- a callout with an offset is not, and neither is one placed against the page, the parts list, or anything Bricksmith does not draw;
- a parts list placed against the assembly is, offset or not. See [step_part_list_frame.md](step_part_list_frame.md), *Where the list goes*.

The Porsche was laid out under the older rule, and it shows. Its printed book has a callout half a page tall above the assembly of step 17, with the assembly far below the middle to make room. Under the newer rule the assembly sits in the middle and most of that callout is above the page, until an `ASSEM PLACEMENT` moves the assembly down. 52 of the file's 106 callouts are dragged ones on pages of one step.

`LDrawStepPartListPresentation` works out the same thing: `stepCenterInView` is where the middle of the page has to be for the box around the measured assembly and the callouts centered with it to sit where LPub3D puts it. The presentation still draws the page where the host keeps it, so the answer does not depend on where the page is now.

The host keeps the page's place as a model point, the *page center* in `LDrawStepPartListPageAnchor`, next to the anchor that the page is sized by. `StepPartListController` sets it by unprojecting `stepCenterInView` at the anchor's depth. It does that:

- when another step is on display;
- when one of the step's `PLACEMENT` lines changes, which covers a dropped box, undo and redo, and an edit of the line's text;
- when a box that is centered with the assembly changes size, whatever line did it: `placementKey` has the size of each such box in page inches, so it is the same at every zoom;
- when the step can be measured and could not be when it was centered, as before the part catalog is there;
- when the anchor is measured again: a new Steps session, another model, Zoom to Fit;
- when the document asks, after a change that turns the camera or changes what is on display.

It does not do it for any other edit. Moving a part changes the box around the assembly, and centering again on every such change would move the page under the pointer. The step is centered again the next time one of the things above happens.

The paper stays where it is on screen, at the same size, and the model moves on it. `-[LDrawDocument holdLPubPageDuringChange:]` notes where the page center is drawn and how many points an inch of the page covers, runs the change, zooms so the page has that size again, has the controller center the step, and scrolls the new page center to the noted point. The zoom makes up for how big the new step is drawn beside the page anchor at its own angle, and for a `LOCAL` `ASSEM MODEL_SCALE`: at a step that sets 1.2 the model grows on paper that stays put. So the zoom the view shows changes a little from step to step. When the controller centers on its own it does the same. A page with no place yet, at the start of a Steps session, is left where the centering puts it. Zoom to Fit centers the step and then puts the page center in the middle of the viewport.

A pan or a zoom needs none of this: the page center is a model point, the assembly's box and the callouts scale together, and the step stays centered.

**Turning the model** keeps the page still, and moves each callout with its submodel. A hand rotation, a trackpad twist or another orientation changes the outline of the assembly on screen with every move, and callouts placed against that outline jumped about while the model turned. The page slid too, because the model point it is pinned to moves on screen in a turn. So a turn is treated as the reader looking at the model, not as a new layout:

- The page stays where it was drawn. After a turn the presenter takes the page center again from under the page's middle (`-keepPageInPlaceThroughTurn`).
- Each callout starts from where the file puts it, against the box the assembly had on the page when the step was laid out. `LDrawStepPartListPageAnchor` keeps that box from the middle of the page, in page inches, so it follows a pan and a zoom. The presenter measures the assembly live only while the camera is at the angle the step was laid out at (`-assemblyRectForHost:`).
- From there a box goes as far as its submodel has moved on the page. See *Moving with the submodel through a turn*.
- The arrows follow the model, since their tips are places in it.

Turning back to the angle the step was laid out at measures live again, and gives the same layout. A step change, Zoom to Fit and the document's own turns (a `ROTSTEP`, an edit of one) lay the step out afresh for the angle the camera then has.

### Moving with the submodel through a turn

While the camera is turned away from the angle the step was laid out at, a callout's box moves with its submodel, so the box and its arrows stay beside what they show. At the angle of the layout nothing is moved: the boxes are where the file puts them.

**What a box follows** is the middle of what its callout places: the mean of the middles of its placements (`-[LDrawStepCalloutBox placementsMiddle]`). It is one model point, so it moves evenly as the camera turns. The outline of the placements would change shape with every move, and a box kept a set distance from it would shake.

**How far it goes.** At the angle of the layout the presenter keeps where each of these points is drawn: its place from the middle of the assembly's box, in page inches, by the callout's `BEGIN` line. The assembly's box stays on the page through a turn, follows a pan and a zoom, and moves with the step when the page is centered again, so a kept place holds through all of them. In a turned view a box is to move by where its point is drawn now less where it was drawn then (`-moveCalloutsWithSubmodelsInPresentation:aroundAssembly:`). A callout that is new in a turned view is kept as it is drawn then, and moves from there. The box around each placement an arrow goes to is kept the same way, for the arrows below.

**What stops it.** `LDrawStepCalloutFollower` moves each box that far where there is room:

- A box stays on the page, and clear of the parts list and of the other boxes.
- A box the file puts off the page stays where it is, and is in the way of the others as the list is. It is a place that went wrong, such as a box dragged under LPub3D 2.4.2 (see *Limits*), and moving it would only draw the eye to it. Off the page is more than a tenth of an inch over an edge. A box is not drawn to LPub3D's exact size, so one that is put at the edge may reach a few points over it, and that one still moves.
- Where the file leaves less room than the margin, or has a box a little over the edge, the box may go back there. Two things the file puts over each other do not keep clear of each other.

**The room it keeps** is LPub3D's. Every element there has a `MARGINS` value, 0.05 inch each way when the file gives none (`DEFAULT_MARGIN`), and when LPub3D places one thing against another it puts the larger of the two things' margins between them (`Placement::placeRelative`). So a box keeps the larger of its own `CALLOUT MARGINS` and 0.05 inch to the page's edge and to the parts list, and two boxes keep the larger of their two margins. The margins are taken for x and y each. LPub3D itself uses a margin only where it places one thing against another. It keeps nothing else apart, so two of its boxes can lie over each other.

**Arrows.** A box also keeps off the arrows where it can, since an arrow under a box says nothing.

- *Another box's arrow.* Where the file has a box to one side of another box and of everything that box's arrows go to, it stays to that side of both. An arrow lies between its box and where it goes, so the box is then clear of the whole arrow. Where an arrow goes moves as the camera turns, so the box gives way to it. The room is the margin and 1/16 inch more, half the width of an arrow's head. A box the file has over that area keeps to its side of each place an arrow goes to instead, which keeps it off the tip.
- *Its own arrow.* A box stays half an inch from the placement its arrow goes to, on the side of it that it is on. That is room for the head, 5/16 inch, and some of the line. Where the file has the box nearer, it keeps that, so that it starts from where the file puts it. Once it has taken a side of its own (see *Changing places*) it keeps the head's 5/16 inch at least: the box around a placement is another in every view, and what the file leaves may be nothing there.
- *Where an arrow goes* is the box around the outline of its placement, as the camera draws it. The side of it a box keeps to is taken from where it was drawn when the step was laid out, so it does not change through a turn.

The page, the list and the other boxes count for more than the arrows. A box that is at the edge of the page stays there when a placement comes under it, and between two arrows that leave it no room it goes half way.

The model is not something to keep clear of, but for the placements the arrows go to. A box goes over the rest of it when its submodel does.

**No jumps while the boxes keep their sides.** A smooth move counts for more than a set distance to the submodel. A box that kept its distance would have to jump over whatever is in its way, and to choose a side of it, and a choice that flips while the camera turns is a jump. So there is no choice to make. Two things keep the order they are in, along x or along y, whichever has the wider gap between them: a box to the right of the list stays to the right of it, and slides along its edge. With that each box has a range to move in on x and one on y:

1. The range starts as the page less its margin, and what stays takes its room from it.
2. Boxes in order take room from each other's ranges, so the first of two boxes in a row stops early enough for the second to fit before the edge of the page.
3. Each box goes as far as its submodel did.
4. It is moved to its side of the arrows, and then back into its range.
5. Two boxes that are then too close for their order are moved apart, each as far as the other, within their ranges.

Steps 4 and 5 are done sixteen times, since a box moved off an arrow may meet another box, and each time halves what is left. The order comes last, so it holds where both cannot be had.

Each of these changes little when the camera turns a little, so a box moves about as far in one move of the camera as the submodels do.

**Changing places.** Sides that never change leave boxes stuck. When a turn takes two submodels past each other, or one to the edge of the page, a box cannot be beside its submodel and off the arrows on the side the file has it on. So the boxes may take other sides, and an `LDrawStepCalloutArrangement` keeps which from one layout to the next.

- *The sides to choose from.* A box may be on four sides of its submodel: the file's, and that place mirrored about the middle of its placements, across, up and down, and both. With each box on one of them, the side every box is on of the others and of the arrows is read as it is from the file's layout, but from where that puts the boxes and where the arrows go now. Two boxes that would lie over each other there are put in the order of their middles, so the boxes still never lie over each other, and a box that would lie over a placement an arrow goes to moves off it, to the side its middle is on. Sides that leave a box no place on the page are left out.
- *What a way of putting the boxes costs*, in page inches: 1 for each inch a box is from its place beside its submodel, 0.75 for a box that is not on the file's side of it, 4 for each inch of an arrow under a box or the list, 2 for each inch a box reaches over a placement another box's arrow goes to, 2 for each inch an arrow is short of its room, 4 for an arrow whose placement is under its own box, and a half for two arrows that cross. An arrow is taken to run from the point of its box nearest the middle of its placement to the box around the placement. So the file's side wins while it is good, and a box held an inch or more from its submodel by the page's edge goes to another side of it.
- *When they change.* Boxes that cost 0.3 or less are let be. Others are worked out on the file's sides and on every way of the four sides, for up to four boxes every way together and for more a box at a time. The cheapest way is taken when it takes off 0.3 and a quarter of the cost. That gap keeps two ways that cost about the same from taking turns.
- *The move.* A change of sides would be a jump. So the boxes are drawn as far from their new places as they were, and close that distance over 0.3 seconds, slowly at first and at the end. The camera may go on turning in that time: the place moves with it, and the box closes on it. A box that has not been drawn yet has nowhere to come from, and is on its side at once. The presenter says `isMovingCallouts` while a box is on its way, and the controller then lays the step out again a sixtieth of a second later. That reload, and the one a move of the camera asks for, are due in every run loop mode: a drag or a gesture that turns the camera keeps the run loop in its tracking mode, and the overlay has to keep up with it.
- *Back at the angle of the layout* the boxes go to where the file puts them, by the same move. Boxes that are on another side, or still on their way somewhere, set out from where they are drawn, once, in the first layout there. The sides taken are forgotten when another step is laid out.

With sides that change, the same angle no longer always gives the same page: which sides the boxes have depends on how the camera got there. The angle of the layout always gives the file's.

A box that keeps its side can be stopped by something that is no longer beside it: a box below the list stays below the list's lower edge all the way across the page. It gets past when another side costs enough less.

**A drag in a turned view** moves the box from where it is drawn, and the offset written is for the step's own view, on the file's side of the submodel: the place the box is dropped at, less how far its submodel has moved on the page since the step was laid out (`-getPlacementOffset:forOrigin:`). Beside its submodel the box is then where it was dropped, and it is that far from there at the angle of the layout.

- What had held the box away from beside its submodel does not count: not the page's edge or another box, not another side of its submodel, and not a move it was still on. So a box the page's edge had stopped stays where it is dropped, and is not drawn back to the edge.
- A box that is picked up ends its move. While it is held nothing is arranged: the other boxes are drawn where they were drawn last, so nothing moves but the box in hand (`+holdBoxes:…`). Once it is let go the boxes start from the file's sides, which is where the drop puts the box, and each sets out from where it was drawn: the others from where they stood, and the dropped one from under the pointer when the file could not have it there.
- A box picked up on the far side of its submodel is put on the file's side by the drop. The file then has it on that side of the assembly: at the angle of the layout the box may be on another side of the assembly than it was.
- Where the file then puts the box cannot be seen in a turned view. So a box dropped on the page gets a place in the file that is in nothing's way: on the page, and clear of the parts list and of the other boxes as the file has them, by the larger of the two margins (`-findFileObstaclesOfBoxes`). It goes the shortest way off whatever it would lie over, and the box then lands that much short of where it was dropped. Off the page it would follow nothing any more. A box dropped at the angle of the layout goes where it is put, over the list too, as in LPub3D.

### Placing the callouts automatically

The preference *Place callouts automatically* (Settings, Steps, Callouts; `Step Callouts Placed Automatically`, off by default) has Bricksmith put the boxes on LPub3D's page by itself. It is for a file whose callouts are placed badly or not at all, and for looking at a model from every side without the boxes being in the way.

- **What is not read** is a callout's `PLACEMENT` line, with its offset. Everything else is read as before: what a box shows, how it looks, its margins, the way its steps run, its dividers, and how many arrows it has. Nothing is written to the file.
- **Where a box goes.** Beside the step's assembly as the camera draws it now, past one of its four sides by the box's `MARGINS`, and level with what the box calls out: the middle of where its arrows go, or of what it places when it has no arrow. It is also half an inch from where its arrows go, when the side of the assembly is nearer than that, so the arrow has room. Four more places are beside what the box calls out, half an inch from it on each side, wherever the assembly's sides are. They are for a page that leaves no room beside the assembly.
- **Which place.** The one that costs least, by the costs under *Changing places*, with two more: 0.5 for each inch from the box to what it calls out, and 1 for each inch the box reaches over the assembly. So a box goes beside the assembly on the side nearest its submodel, unless the page has no room there or another box or an arrow is in the way. Two boxes are tried in every pair of places. With more, each box in turn takes its cheapest place, twice round.
- **The rest is as for a box that follows its submodel.** It stays on the page, clear of the parts list and of the other boxes, and off the arrows. It keeps its side until another is better by enough, and moves there over 0.3 seconds. This is done at every angle: there is no layout of the file's to come back to.
- **The step is centered without the callouts**, as LPub3D centers it without the ones that have been dragged. An `ASSEM PLACEMENT` line still moves the assembly.
- **A box cannot be dragged.** A drag writes a `PLACEMENT` line, which would not be read. `isPlacedByFile` is NO for every box, so the tracker picks none up. A click still shows the submodel's steps, and the menus are as before.
- **Turning the preference on or off** puts the boxes afresh, at once and with no move. The sides the boxes had are forgotten (`-useSidesPlacedAutomatically:`): a side means one of eight places around the assembly when the boxes are placed automatically, and one of four around the submodel when the file places them. The presenter keeps where each submodel is drawn at the angle of the layout whichever way the boxes are placed. So with the preference turned off in a turned view, the boxes are where they would have followed their submodels to from the file's places.

The presenter calls `-placeCalloutBoxesAroundAssembly:places:arrangement:` with the box around the assembly measured through the camera for each layout, where it otherwise moves the boxes from the file's places. `LDrawStepCalloutFollower` does both: for a box with an assembly beside it, the four sides are the sides of the assembly, the file's sides are never tried, and every box may move.

### Following a callout

A click on a box shows the submodel's own steps, starting at the first, and a button in the bottom left corner leads back to the step it was called out in. A box of several submodels shows the one that was clicked: the one whose step is under the pointer, or whose row is, off the page. A click between two of them, or in the box's padding, takes the nearest (`-[LDrawStepCalloutBox submodelAtPoint:]`). When that one cannot be shown, because it is no model of this file or is the one on display, it is the callout's first that can be. The document keeps the way back as a path, so a callout inside a called-out submodel works too. The path is dropped when the active model is changed any other way.

On the page the paper stays where it is through the change of model, and keeps its size. A change of model is more than a change of step. The camera sits further from a bigger model, the new model has its own rotation center, and it may have another `ASSEM MODEL_SCALE`. Left alone, the submodel's page came out smaller and in another place, and the parent's page came back in a third.

`-[LDrawDocument holdLPubPageDuringModelChange:]` does for a model what `-holdLPubPageDuringChange:` does for a step:

1. It notes where the middle of the page is drawn, and how many points an inch of the page covers.
2. It runs the change.
3. It zooms so the new model's page has that scale (`-[LDrawStepPartListPageFitter showPageOfModel:inView:atPointsPerPageInch:]`). The page's size is the zoom times the scale measured beside the new model's anchor, so one change of zoom is exact.
4. It has the controller center the step on the page, and scrolls the page's middle back to the noted point.

Every change of the model on display goes through `-setActiveModel:`, which uses the hold, so choosing a model in the Models menu keeps the page too. The zoom the view shows does change: the paper is the same size, but in a perspective view a submodel is not as deep in the scene as its parent.

The way back also puts back the step's viewing angle. Steps mode starts a model at its first step, and going from there to a step with no rotation of its own leaves the camera at the first step's angle. So `-showModel:atStepIndexOnCalloutPath:` sets the angle of the step it arrives at.

With no pan or zoom in between, the step that was left is drawn as it was. A pan or a zoom inside the submodel moves the paper, and the parent's page comes back where the paper is then.

### Dragging

On the page a box can be dragged. Nothing is written until the drag is let go, and Escape drops it. A press that does not move is still a click.

A box whose `PLACEMENT` names something Bricksmith does not draw cannot be dragged. Its offset is a share of that thing's size, and the assembly that stands in for it here is another size, so the number written would put the box somewhere else in LPub3D. The line can be typed.

A dragged box rewrites the offset of its `PLACEMENT` line and keeps the rest as typed. A callout with no line gets `CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE x y`, just before its `END`. `LDrawStepCalloutEdit` decides what is written and the document applies it, as one undoable edit named *Move Callout*. Offsets are written with four decimals, as LPub3D writes them.

A box stays where it is let go, and what is on screen after the drop is what LPub3D prints.

A box that already has an offset is not part of what is centered, so dropping it moves nothing else. The first drag of a box is different. Until then the box was centered with the assembly, and with an offset it no longer is. LPub3D then puts the assembly in the middle without it, so the assembly has to move on the page, and a box placed against the assembly moves with it. Written as the plain distance dragged, the offset would leave the box that far from where it was dropped.

So the offset allows for the move. The presentation works out, for each box placed against the assembly, how far the assembly will go when that box is left out and the step is centered again with the page where it is (`assemblyShiftAfterDrag`). `-[LDrawStepCalloutBox getPlacementOffset:forOrigin:]` measures the offset from where the box will go with no offset after that move. The drop then centers the step like any other change of the line: the paper stays, the assembly goes to its place once, and the box is where it was dropped. The same sum keeps a box under the pointer when the step was due to be centered again for another reason, such as parts moved since it was last centered.

The arrows cannot be dragged, since their tips are not read from the file.

### Adding and removing a callout

Both are on a right click, or a click with Control, in the overlay. `LDrawStepCalloutEdit` decides what is written and the document applies it as one undoable edit.

**Call Out** is in the menu of a submodel's row of the step's parts list, so it needs submodels to be listed. It writes, in LPub3D's own order:

```
0 !LPUB CALLOUT BEGIN
1 0 90 -40 -10 1 0 0 0 1 0 0 0 1 seat left arm.ldr
1 0 -30 -40 -10 1 0 0 0 1 0 0 0 1 seat left arm.ldr
0 !LPUB CALLOUT POINTER LEFT 0.500 0.389 0.575 0
0 !LPUB CALLOUT POINTER LEFT 0.500 0.512 0.349 0
0 !LPUB CALLOUT END
```

- Every placement the row counts goes in one callout: a row marked 2× gives one box with two arrows. LPub3D has one count for a callout and only raises it for the submodel it saw last, so a callout is for one submodel.
- A placement that is already in a callout, inside `PLI BEGIN IGN` or `PART BEGIN IGN`, or in another color is no part of the row and is left alone.
- Placements with other lines between them are moved to follow the first, so that nothing else ends up inside the callout.
- There is one `POINTER` line for each placement, since LPub3D draws no arrow without one. The tip is the middle of the placement as a share of the box around the step's assembly, seen straight on from the step's own angle (`+tipForModelPoint:inOutline:view:`). So it does not depend on how the view is turned, and it is close to where LPub3D's picture has the part, not exact. With no part catalog the tip is the middle of the assembly. The arrow is written as leaving the left side of the box, which is where a new box is: LPub3D works the real place out from the tip.
- No `PLACEMENT` line is written. The box starts to the right of the assembly, in the middle, and counts toward the step's center until it is dragged.

The submodel then stops being a row of the list, and its parts are listed by the step or by the box as `PER_STEP` says.

**Remove Callout** is in the menu of a callout's box. It takes out `BEGIN`, `END` and the lines between them that hold for that callout alone: its arrows, its `PLACEMENT`, any `POINTER_ATTRIBUTE` line, and a styling line that says `LOCAL`. The parts stay where they are. A styling line with no `LOCAL` stays too, now outside any callout: LPub3D carries such a line to the callouts after it, and the Porsche relies on that for `ALLOC`, so taking it out would turn the callouts of later pages. `CALLOUT DIVIDER` lines in the submodel are left alone as well, since another step may call the same submodel out.

### Adding and removing a divider

Both are in the menu of a step inside a callout's box, on the page, above *Remove Callout*. Off the page a box shows its submodel finished, so there is no step to click.

- **Add Divider Before Step N** is offered on a step that starts no column or row yet. That step and those after it move to a new one.
- **Remove Divider Before Step N** is offered on the step after a divider, and on the line itself with the room on each side of it.
- The first step shown of a submodel has neither. It starts a column or row whatever the file says, and so does the first step of each submodel of a callout that holds several: the line between two submodels is no `DIVIDER` line.

A box knows its steps for this (`-[LDrawStepCalloutBox steps]`, `-stepAtPoint:`). Each step has a share of the box: its picture, number and parts, and the room around them up to the next step. The shares of a column fill it, so a click anywhere in a column lands on a step.

Add writes one line, `0 !LPUB CALLOUT DIVIDER`, first in the step, which is right after the `STEP` line of the step before. Remove takes out every `DIVIDER` line that counts for the step, wherever it is, and with them the `DIVIDER_POINTER` and `DIVIDER_POINTER_ATTRIBUTE` lines there, which give a divider its arrows. LPub3D deletes those with the divider too. Each is one step of undo.

The line is in the submodel, not in the step that calls it out. So the edit names the step its lines go into (`targetStep`), and every callout of that submodel changes with it: 13 of the 92 submodels the Porsche calls out are called out twice. That is how LPub3D has it.

A divider makes the box taller or wider, and the box is centered on the page with the assembly. So the step is centered again after the edit, with the paper kept where it is, as after a dropped box: the presentation's `placementKey` says which steps of each box follow a divider.

### Turning the steps of a callout

*Arrange Steps Horizontally* and *Arrange Steps Vertically* are in the menu of a callout's box on the page, whichever the box is not doing now. A box that shows one picture has neither, since nothing would change.

The item turns that callout alone, and that decides what is written. LPub3D's own menu writes `0 !LPUB CALLOUT ALLOC HORIZONTAL`, with no `LOCAL`, between the callout's two lines. Such a line turns the callout it is in, and it also stays in the metas LPub3D reads a later page with, so the callouts of every later step turn with it until one of them says otherwise. The Porsche has 23 `ALLOC` lines for that reason. A `LOCAL` line ends with its step, so `+[LDrawStepCalloutEdit editArrangingStepsOfCallout:vertically:]` writes that:

- A callout with no `ALLOC` line of its own, or whose last one has no `LOCAL`, gets `0 !LPUB CALLOUT ALLOC LOCAL HORIZONTAL` (or `VERTICAL`) just before its `END`. A line with no `LOCAL` is left as it is, since later steps may go by it, and the new line wins because it comes last. LPub3D applies a line anywhere between `BEGIN` and `END` to the callout: its own lines sit after the submodel's line.
- A callout whose last `ALLOC` line is a `LOCAL` one has that line taken out, when the callout then runs the way wanted without it. So turning a box and turning it back leaves the file as it was. Otherwise the line's text is changed.
- A `LOCAL` line ends more than itself with the step: LPub3D drops every `ALLOC` line that follows it in the step too. So when a line further down the step, in a later callout, is one that later steps go by, the line written has no `LOCAL`. The later line still carries on in place of it, so nothing after the step changes, and the new line is taken out again when the box is turned back. For the same reason a `LOCAL` line with such a line after it is changed and not taken out.

The step is centered on the page again afterwards, as after a divider: `placementKey` carries the way each box's steps run.

### Fixes after review

- **`PER_STEP` is read for each callout**, through the lines in force for that callout (`-listsOwnParts`). It was one answer for the whole step, taken from every `PER_STEP` line of the step: two callouts of one step could not differ, and a `FALSE` after a callout's `END` still moved that callout's parts into the step's list.
- **A short arrow is drawn.** An arrow shorter than its head, 5/16 inch on the page, was left out altogether. Its head is now as long as the arrow, in the same shape.
- **On the page a step change sets the step's own angle**, also for a step with no rotation of its own (`-setCurrentStep:`). The step is laid out at the angle the camera has, so a camera left turned on the step before became the new step's layout.
- **A `ROTATED` callout turns each row by a placement of that row.** One submodel placed in two colors is two rows, and both took the turn of the first placement. Its steps are also counted once for the steps badge, not once for each row.
- **Turning the steps of one callout leaves later steps alone** when a second callout of the step has the `ALLOC` line they go by. The `LOCAL` line written into the first callout ended that line with the step too, and the callouts of later steps turned. See *Turning the steps of a callout*.
- **LPub3D's own border and separator are in inches in a `DPCM` file.** With no `BORDER` or `SEPARATOR` line the sizes LPub3D starts from were taken for centimeters, and the outline and its margins came out 2.54 times too small.
- **A box placed against something that is not drawn is not dragged.** The offset written was a share of the assembly's size under a line that still named the other thing. See *Dragging*.
- **A click on a box is known by the callout's `BEGIN` line.** The callouts are collected again on every reload, so a reload between the press and the release made the click do nothing.
- **A click with Control opens the menu with Caps Lock on.** Caps Lock counted as another key, and the click entered the callout.
- **A step is centered again when a centered box changes size, and when it can first be measured.** Only `PLACEMENT`, `ALLOC` and `DIVIDER` lines were looked at, and a step centered before anything could be measured stayed on the page anchor. See *Where the step goes on the page*.
- **A zoom does not draw every picture again at each step it takes.** A picture is kept under its size, so every step of a zoom asked for all of them anew. The picture on show is now stretched while the zoom changes, and drawn at the new size 0.15 seconds after it settles (`subjectKey`, `-[LDrawStepCalloutPictureStore makePicturesForBoxes:waitingForZoom:]`).
- **A change to the model on display keeps the pictures.** Every change to the file dropped them all, so moving a part of the step drew each callout's pictures again. They show the called-out submodels, which such a change does not touch. They are dropped when another model is put on display, and for a change anywhere else.
- **A submodel placed several times in a callout is measured once.** Each placement measured it again, only to find its row.
- **A submodel placed in two colors shows its steps once.** It is two rows, and the strip added its steps for each row: twice the pictures, with the numbers starting again at 1. The steps now go with the submodel's first row, and the count beside the last picture is every placement of it, in any color. A callout that shows its submodels finished, `ASSEMBLED` or `ROTATED`, still has a picture for each row, since each is another color or another turn.
- **A box stays where it is dropped the first time too.** The first drop of a box that was centered with the assembly moved the assembly to the middle, and the box went with it, out from under the pointer. The offset written now allows for that move. See *Dragging*.
- **The overlay keeps up while the camera is being turned.** A move of the camera queued its reload for the default run loop mode only, and took the one for a box's move, which is due in every mode, out of the queue. A drag or a gesture keeps the run loop in its tracking mode, so nothing was laid out until it ended, and the boxes then jumped the whole turn. Both are now due in every mode.
- **A box that is on its way does not jump when the camera comes to the angle of the layout.** Only boxes on a side of their own set out from where they were drawn. One on the file's side that was still on its way somewhere had what was left of that move added to the file's place.
- **A drop does not count a move the box is still on.** How far the box had followed its submodel was taken from where it was drawn, which has what is left of a move in it, so the line was written that much off and the box left the pointer as the move went on. A drop is now measured by how far the submodel has moved, and picking a box up ends its move.
- **A box on the far side of its submodel stays where it is dropped.** It is drawn mirrored about its submodel, so the line that was written moved it the other way. Such a box now comes to the file's side when it is picked up, and the drop is written for that side.
- **The other boxes stand still while a box is held.** Picking a box up put the boxes back on the file's sides, so the others moved away under the drag. They are now arranged again only once the box is let go.
- **A box dropped in a turned view is not put over the parts list by the file.** The file's place was only kept on the page, so a box dropped from the far side could lie over the list once the model was turned back. It is now kept clear of the list and of the other boxes as well.
- **Turning *Place callouts automatically* off forgets the sides the boxes had.** A side kept from the automatic placing was read as a side of the submodel, so the file's box could be drawn mirrored, and stay so while that cost little. In a turned view the boxes were also laid out as if the view were the step's own, since nothing had been kept of where the submodels were drawn at the angle of the layout. See *Placing the callouts automatically*.
- **A box that is first drawn in a turned view is on its side at once.** It set out from the file's side, where it had never been drawn. The first layout after the preference changes is such a one.
- **A callout of several submodels is followed to the one that was clicked.** The first one in the file was taken, wherever the click was, and when that was the model on display nothing was shown, though the callout held another. See *Following a callout*.

## The packages

The code for callouts is meant for other apps too, so the app keeps only what is AppKit. There are two packages on top of LDrawFeatures, and a host that only shows callouts links the first alone.

**LDrawStepRendering** shows a step's parts list and callouts over a model. It uses CoreGraphics and CoreText, and no AppKit or UIKit.

| Class | What it does | What the host gives it |
|-------|--------------|------------------------|
| `LDrawStepOverlayPresenter` | Lays the visible step out against a camera, works out the arrows, puts each step in its place on the page, keeps the page still through a turn, and has each callout move with its submodel then. Says whether a box is still on its way to a new place, so the host lays the step out again. Says what a change to the file or the camera means: lay out again, discard the pictures, or only draw the arrows. | The model, the size of the view, and a camera: `LDrawStepOverlayCamera`, six calls that turn model points into view points and back, on top of the four the page fitter needs. |
| `LDrawStepOverlayRenderer` | Draws the page, the list's frame and pins, a list's labels, the callouts and the button that leads back, into a `CGContext` whose origin is the view's top left corner. | The fill of the frame and the color of a pin as `CGColor`, two localized formats, and the title of the button. |
| `LDrawStepCalloutPictureStore` | Keeps the pictures of the called-out submodels, and waits for a zoom to settle before drawing them at a new size. | A picture source, which draws a model off screen as a `CGImage`. |
| `LDrawStepCalloutPath` | Remembers the steps left through callouts, for the way back. | Which models can be put on display. |

**LDrawStepEditing** changes callouts. It draws nothing.

| Class | What it does | What the host gives it |
|-------|--------------|------------------------|
| `LDrawStepCalloutEdit` | Says what each change writes, and makes it through the host with `-applyToStep:host:`. | `LDrawStepCalloutEditHost`: put a directive into a container, take one out, and keep one's state for undo. |
| `LDrawStepCalloutMenuItem` | What a menu offers at a point: each item has the key of its title, the step it names, and its edit. | Its own menu, and the localized titles. |
| `LDrawStepCalloutTracker` | Follows a press on a box or on the button: a click that follows it, a drag that moves the box as a preview, Escape. | The points of the events, and after each layout the boxes on show. |

The callouts' model and layout (`LDrawStepCallout`, `LDrawStepCalloutBox`, `LDrawStepCalloutStyle`) stay in LDrawFeatures with the parts list. The presentation of a step builds the boxes, and the boxes use the list's packer, so the two cannot be in different packages.

The off-screen picture is drawn by `+[LDrawRenderer newImageOfDirective:center:zoomPercentage:size:scale:]` in LDrawRenderMetal.

What is left in Bricksmith:

- `StepPartListView` stacks the views, has the renderer draw into them, and is the picture source.
- `StepPartListChromeView` is the view above the 3D icons that the list's labels are drawn in.
- `StepPartListController` attaches the overlay, watches the notifications and the window's events, builds the `NSMenu`, and sets the cursors.
- `LDrawView` is the camera. It already had the calls, so it conforms with an empty category.
- `LDrawDocument` is the edit host with the three methods it already had. It owns the undo manager and which model is on display, and holds the page through a change of step or model.

### Drawing without AppKit

The renderer puts every pixel where the AppKit drawing put it. Three things were needed for that:

- **Curves** are flattened to 0.6 pixel, which is what `NSBezierPath` sets. CoreGraphics' own value gives a round corner slightly different edge pixels.
- **A round corner and an oval** are built from the same points, in the same order, as AppKit builds them. The order also decides where the dashes of a dashed outline fall.
- **A line of text** is as tall as AppKit measures it: the ascent rounded, plus the descent rounded. For the system font below 21 points AppKit rounds the descent up instead. The baseline is the rounded ascent under the top of the line.

Text that does not fit its rectangle is the one difference: it is cut short by CoreText, which may end it a letter sooner or later than AppKit did.

## Where the code is

| What | Where |
|------|-------|
| The metas | `LPubCallout`, `LPubCalloutPointer`, `LPubPlacement` (a callout's and an assembly's), `LPubCalloutAlloc`, `LPubCalloutPliPerStep`, `LPubAssemShowStepNumber` (LDrawCore) |
| The style metas | `LPubCalloutBorder`, `LPubCalloutBackground`, `LPubCalloutSubmodelColor`, `LPubCalloutMargins`, `LPubCalloutSeparator`, `LPubCalloutFont`, and the color reader in `LPubColor` (LDrawCore). The border, background, margins and font also read the same lines under `PLI` for the step's parts list; the callout reads only those whose `branch` is `LPubStyleBranchCallout` |
| What a step calls out, and the lines in force for a callout | `LDrawStepCallout` (LDrawFeatures) |
| The parts list rule | `+[LDrawStepPartList collectStep:…]` (LDrawFeatures) |
| How a box looks | `LDrawStepCalloutStyle` (LDrawFeatures) |
| The box, its place and its arrows | `LDrawStepCalloutBox` (LDrawFeatures) |
| The summary and the strip | `LDrawStepCalloutContent` (LDrawFeatures, private) |
| Where the step goes on the page | `LDrawStepPartListPresentation` (`stepCenterInView`, `placementKey`), `LDrawStepPartListPageAnchor` (the page center, the assembly's box on the page) (LDrawFeatures) |
| The offset a dragged box needs | `-[LDrawStepCalloutBox getPlacementOffset:forOrigin:]`, with the assembly's move from `-[LDrawStepPartListPresentation findStepCenterForModel:host:]` (LDrawFeatures) |
| Moving the boxes with their submodels through a turn | `-[LDrawStepOverlayPresenter moveCalloutsWithSubmodelsInPresentation:aroundAssembly:]` (LDrawStepRendering), `-[LDrawStepPartListPresentation moveCalloutBoxesFrom:to:arrangement:]`, `-restCalloutBoxesWithArrangement:`, `LDrawStepCalloutFollower` (LDrawFeatures, private) |
| The sides the boxes have taken in a turn, and the moves under way | `LDrawStepCalloutArrangement` (LDrawFeatures), kept by `LDrawStepOverlayPresenter` |
| Drawing a box that is on its way again | `-[StepPartListController reload]`, while `-[LDrawStepOverlayPresenter isMovingCallouts]` (app) |
| Placing the boxes automatically | `+[LDrawStepPartList placesCalloutsAutomatically]`, `-[LDrawStepPartListPresentation placeCalloutBoxesAroundAssembly:places:arrangement:]`, `+[LDrawStepCalloutFollower placeBoxes:aroundAssembly:…]` (LDrawFeatures), and the switch in `PreferencesDialogController` (app) |
| Which lines put a divider before a step | `+[LDrawStepCallout dividerLinesBeforeStep:]`, `+stepShownBeforeStep:` (LDrawFeatures) |
| The steps a box shows, and the step and the submodel at a point | `LDrawStepCalloutStep`, `-[LDrawStepCalloutBox steps]`, `-stepAtPoint:`, `-submodelAtPoint:` (LDrawFeatures) |
| The box and the row of the parts list under a point | `-[LDrawStepPartListPresentation calloutBoxAtPoint:]`, `-entryAtPoint:` (LDrawFeatures) |
| The scale of the page in a view, and the zoom that gives a page a scale | `LDrawStepPartListPageFitter` (LDrawFeatures) |
| Measuring the assembly, centering the page, keeping it through a turn, where each submodel is drawn, the arrows in the view | `LDrawStepOverlayPresenter` (LDrawStepRendering) |
| Drawing | `LDrawStepOverlayRenderer` (LDrawStepRendering) |
| Keeping the pictures | `LDrawStepCalloutPictureStore` (LDrawStepRendering) |
| The way back | `LDrawStepCalloutPath` (LDrawStepRendering) |
| Pictures drawn off screen | `+[LDrawRenderer newImageOfDirective:center:zoomPercentage:size:scale:]` (LDrawRenderMetal) |
| What a drag, an added and a removed callout, an added and a removed divider, and turned steps write, and writing it | `LDrawStepCalloutEdit` (LDrawStepEditing) |
| What the two menus offer | `LDrawStepCalloutMenuItem` (LDrawStepEditing) |
| A click on a box or on the button, and a drag | `LDrawStepCalloutTracker` (LDrawStepEditing) |
| The views, and the picture source | `StepPartListView`, `StepPartListChromeView` (app) |
| Events, the `NSMenu`, cursors | `StepPartListController` (app) |
| Undo, which model is on display, holding the page through a step and through a change of model | `LDrawDocument` (app) |

Everything that decides something is in the packages and runs with no part catalog, so the package tests cover it.

## How it was checked

- `swift test`: the grammar and write-back of every meta, the colors, what a step calls out, the lines in force for a callout, the list rule, the summary, the strip and its spacing, the style and its defaults, placement, where the arrows leave a box and stop, that no two arrows of a box cross for 200 made-up sets of placements, the step's center and which callouts count toward it, the row under a point, the edits that move, add and remove a callout, which lines put a divider before a step, the steps a box shows and the step at a point, the edits that add and remove a divider, the edit that turns the steps of one callout and leaves the others, and the drag preview. For the two packages: an edit made through a host, with the old line kept before it is changed and a divider going into its own step, what the menu offers on each kind of step and on a row, a click, a drag, a drop and an abandoned drag in the tracker, the way back and what ends it, when a picture is drawn again and when the one on show stands in, where the button and a list's labels are drawn, what a change to a file means for the overlay, and against a made-up camera that the page is pinned to its model point, moves with a pan and stays put through a turn.
- On `10274-1 Porsche RSR.ldr`, which has 106 callouts: every line is written back as it was read, 4416 of 4416. The typed lines are 224 brackets, 108 pointers, 114 placements (12 of them `ASSEM PLACEMENT`), 23 `ALLOC`, 10 borders, 10 backgrounds, 3 margins, a separator and 2 fonts.
- Against the printed book for that model: the lists of the callout steps, the strips (same pictures, same columns and dividers), the cream and blue boxes with no visible outline, the count beside the last picture, and the arrow heads.
- Arrow starts: at step 15 the two arrows that leave an edge near a corner leave it 10.5 points from the corner, which is 0.118 inch at 89 points to the page inch. The two that leave the middle of an edge are where they were.
- Arrows from one corner: with the first box of step 15 dragged 100 points to the right, both its placements are past its top left corner. The arrows leave the top edge 10.5 and 17.6 points from the corner, 0.08 inch apart, the one to the placement further left nearer the corner, and they do not cross. As the file places its boxes, four of them have two arrows, at steps 15, 27 and 72, and in none do the two cross.
- Arrow tips: at step 15 the four placements' outline points were projected and drawn over a picture of the overlay. Each tip sits just outside the edge of its placement's points, on the line from the box to the placement's middle, with 4.4 points between the tip and the edge at 89 points to the page inch.
- Turning: three hand rotations left the page rectangle where it was, while the assembly's outline grew from 870 to 928 points wide and the arrow tips followed the parts. A pan then moved the page and the boxes together. Turning back to the step's angle gave the first layout again, and a step change in a turned view centered the new step for that view.
- Boxes that follow, in the running app with the page fitted at 89 points to the page inch: at steps 15, 42, 55 and 64 the camera was turned by 5, 20, 45, 90, 135 and 180 degrees about the upright axis, to two tilted angles, and back, and each view was read after its moves had ended. The page rectangle and the parts list did not move at all. The box of step 64 went 28.9, 106.5, 194.5, 192.1 and 12.5 points to the left and then 238.5 to the right with its submodel, and was back at its place exactly at the step's angle. At one tilted angle its submodel went lower than the page leaves the box room for, and the box went to above it. The first box of step 15 went up to 114.1 points. The second, which the file puts 32 points over the top of the page, stayed, and so did the box of step 42 and the second box of step 55, each half over the right edge. The first box of step 55 reaches 6 points over the bottom edge, so it moved: at 45 degrees it stopped 10.5 points from the left edge, which is the file's `CALLOUT MARGINS` of 0.118 inch, and further round it went to the other side of its submodel. It went no lower than the file puts it.
- No jumps: at steps 15, 55 and 64 the camera went once round the upright axis and once round a tilting one, in 180 moves of two degrees, and each view was read after its moves had ended. A box that kept its side went no further in one move than its submodel did: 3.1 points at step 15 and 12.7 at step 64, which is what the submodels went. The first box of step 55 went to another side of its submodel 2 and 3 times in the two turns, and the box of step 64 twice in the tilting one, each where the page's edge had held it away from its submodel. After the turn round the upright axis each box was back at its place to a thousandth of a point, and the three boxes off the page had not moved in any of the 1086 layouts.
- Arrows and changing places, on `7347-4 Roadster +31003.ldr` at step 6, which has two boxes with an arrow each and `CALLOUT MARGINS` of 0.118 inch. Seen from 40, 60, −120 degrees the two submodels have changed places up and down. With nothing kept off the arrows the two boxes lay against each other there, over both placements, with next to nothing of either arrow to see. Kept off the arrows on the file's sides they were 284 points apart, with arrows 114 and 217 points long that ran past each other. Now they change places: each is beside its own submodel, with arrows 62 and 61 points long and nothing over them. The camera then went once round the upright axis, once round the level one and once round a tilting one, in 360 moves of a degree each, and each view was read after its moves had ended. In none of the 1083 views did a box lie over the other's arrow, where on the file's sides one did in 72 views of the turn round the level axis. An arrow's placement was under its own box in 9 views, where it was in 42, and an arrow was shorter than 8 points in 34, where it was in 315. The boxes changed places 4, 7 and 7 times in the three turns. Back at the step's angle they were where the file puts them.
- The reload while the camera is being turned: with the run loop run in its event tracking mode only, a reload queued for the default mode alone did not run, and the one the controller queues now did.
- A drag from the far side, through the event code at step 64 seen tilted 20 and turned 45 degrees, where the box is above its submodel and the file has it below the assembly. Dragged 40 points right and 60 up, and in another run 40 right and 30 down, it stayed where it was let go to 0.06 points each time, as one edit named *Move Callout*. It was the first drop of that box, so the assembly moved to the middle as well. Back at the step's angle the box was above the assembly, 478 and 388 points higher than before. Undo gave the first line and place again. At 45 degrees, where the box is on the file's side, the same drag left it where it was let go too, and 40 points right of and 60 above its old place at the step's angle.
- The file's place after a drop in a turned view, on the roadster at step 6 seen turned 40 degrees: the second box was dragged to where the file would have had it 40 points inside the corner of the parts list. After the drop the file has it 10.5 points to the right of the list, which is the file's `CALLOUT MARGINS`, in the turned view and back at the step's angle. Undo gave the first line and place again.
- The other box during a drag, on the roadster at step 6 seen from 40, 60, −120 degrees, where the two boxes have changed places: the first box was picked up and held 30 points right of and 20 below its place. The second box was where it had been, to a hundredth of a point, at once and half a second later, and after the drop. The first stayed where it was let go to 0.03 points. Undo gave the first line and place again.
- Placing the callouts automatically, with the preference on in the running app. The Steps pane of the settings shows the section *Callouts* with the switch and its note. On the roadster at step 6 the two boxes are below and above the assembly at the step's angle, each level with its submodel, with arrows 41 and 157 points long, whatever their `PLACEMENT` lines say. In the three full turns of 360 moves no box lay over the other's arrow or over the other box in any of the 1083 views. An arrow's placement was under its own box in 8 views, and an arrow was shorter than 8 points in 31. The boxes changed places 4, 11 and 12 times. On the Porsche at steps 15, 42, 55 and 64, at ten angles each, all 60 boxes laid out were on the page, also the four the file puts off it, and none lay over the parts list or another box. With the preference off the 22 scenarios are the same as before.
- The page's scale, on the roadster at `ASSEM MODEL_SCALE 1.0` with the page fitted at 89 points to the inch, going through steps 1, 50, 51, 52, 72 and 73 and back to 1, with a Zoom to Fit at step 73. The page stayed at the same place and size throughout, and the camera stood 3123 LDU back on every step, the distance for the finished car. The model's middle was drawn at exactly the page's scale on every step, and at 1.2 times it at step 51, which sets `LOCAL 1.2`. The zoom went from 136.5% to 164.6% at step 51 and back to 137.2% at step 52. The finished car was 9.74 inches wide in its three-quarter view at step 72 and 10.33 inches seen from the side at step 73, on a page 12.05 inches wide; with step 73 straight on, so drawn orthographically, 10.19 inches. A brick added 1500 LDU from the car at step 73 moved the camera from 3123 to 10441 LDU back, with the page at the same place and size and the model's middle still at the page's scale; the zoom went from 138.65% to 138.94%. Undo put the camera and the zoom back.
- Turning the preference on and off in a turned view, on the roadster at step 6 seen from 40, 60, −120 degrees, with the preference set in the running app and not in the stored settings. Placed by the file, the two boxes had followed to (533.7, 197.5) and (471.7, 463.2). With the preference on they were at (759.9, 90.8) and (332.6, 560.3), at once and half a second later. With it off again they were back at the first two places to a tenth of a point, at once, with no move under way. In each of the layouts both boxes were on the page and off the list and each other.
- A drag in a turned view, through the event code at step 64: with the camera turned 45 degrees the box was drawn 194.5 points left of its place. Dragged 60 points right and 80 up it stayed there when let go, to 0.02 points, with the page where it was. The line written is `CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE 0.0418 -0.2146`, as one edit named *Move Callout*. Back at the step's angle the box was 60 points right of and 80 above where the file had it before. Undo gave the first line and place again.
- In the running app, with the page fitted: stepping from 15 to 16, 17, 51, 55 and back to 3 left the page rectangle where it was to a tenth of a point, with the assembly in the middle of the page at 15, 16, 17 and 3. At steps 51 and 55 it was off the middle by 0.0481, 0.0621 and −0.0120, 0.0963 of the page, which are the numbers of the two `ASSEM PLACEMENT` lines. At step 17 the dragged callout reaches 3.1 inches above the page, as the newer rule has it. A pan moved the page with the model, and a zoom scaled both, with the step still centered.
- Following a callout on the page: at step 21 the page was drawn at (24.61, −0.50), 1072.27 by 712.00 points. It kept that rectangle to a thousandth of a point through *rear-right chassis*, a step change in it, *back wheel stop* called out from its second step, and the two ways back. In the main model again the assembly's outline, the first callout's box and the zoom of 165.08% were what they had been. Before the hold the same click at step 15 drew the submodel's page at (20.75, 18.48), 1045.81 points wide, and brought the parent's back at (−25.62, −133.51), 1097.47 wide. After a pan and a zoom of 1.25 inside the submodel the parent's page came back on the moved paper, with 1.25 times its zoom. Changing the model as the Models menu does kept the page as well. A click and its way back take about 100 and 160 milliseconds at that step, as before.
- Stacking: at step 21 the callout's box reaches 39 points over the right end of the parts list, and 53 points down it. After the app has drawn once, the overlay's layers are, from the bottom: its own drawing, the icons' Metal layer, the counts, and the top view with the callouts. A picture of the overlay leaves the Metal layer out, so the order was read from the layers. In such a picture a box dragged 120 points down covered the list's border and its last count, where the list's views used to be drawn over the box. A right click in the overlap offers *Remove Callout*.
- Dividers, through the menu code at step 21, whose box shows the four steps of *rear-right chassis* in two rows: the menu on step 1 and in the box's padding is *Remove Callout* alone, on step 2 it starts with *Add Divider Before Step 2*, and on step 3 and on the line with *Remove Divider Before Step 3*. Adding before step 2 wrote `0 !LPUB CALLOUT DIVIDER` as the first line of that step of the submodel, ahead of the `CALLOUT BEGIN` that was first, and the box had three rows. Undo gave two rows again. Removing the divider before step 3 put the four steps in one row, 747 points wide, and undo gave the two rows back. A right click sent as an event on step 3 was taken by the overlay. At step 59 the box is centered with the assembly: a divider before its second step made it 171 points wide where it was 90, the assembly moved 41 points to the left, the page did not move, and the middle of the two together was on the middle of the page before, after, and after undo.
- Turning the steps, through the menu code at step 21: the callout has LPub3D's own `CALLOUT ALLOC HORIZONTAL`, and the callout of step 22 runs across as well. *Arrange Steps Vertically* wrote `CALLOUT ALLOC LOCAL VERTICAL` before `END` and left the first line: the box's two rows of two became two columns of two, the page did not move, and step 22's callout still ran across. The menu then offered *Arrange Steps Horizontally*, which took the `LOCAL` line out and gave the step's lines and the box's frame back as they were.
- With mouse events: a box dragged by (60, −40) points followed the pointer, and letting go wrote `… OUTSIDE 0.0644 -0.0602` and left the box, the assembly and the page where they were. Undo put the line and the box back, and redo did it again.
- The first drop of a centered box, with mouse events: at step 64 the box sits under the assembly with no offset. Dragged by (60, 30) points and let go, it stayed at the pointer to 0.02 point, which is the rounding of the offset to four decimals. The page rectangle did not move, and the assembly went to the middle of the page. The line written was `CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE 0.0418 -0.0341`, where the plain distance dragged is `0.0418 0.0492`: the difference is the 50.8 points the assembly moved. Asking for LPub3D's centering after the drop changed nothing, so the layout on screen is the one LPub3D prints. Undo gave the first layout back to a hundredth of a point. The 22 saved scenarios are unchanged, since their dragged box already had an offset.
- A callout of two submodels, with mouse clicks: the Porsche has none, so in a copy of it the first callout of step 15, of *seat left arm*, was given a placement of *seat right arm* as well. Its box then showed a step of each. A click on the second step put *seat right arm* on display, and after the way back a click on the first put *seat left arm* on display. The page kept its rectangle through both.
- The move into the two packages: 22 scenarios were saved before it, as the numbers of each layout and a picture of the overlay. They are steps 15, 21, 27, 55, 59 and 97 on the page and 15 and 21 off it, following a callout and coming back by call and by click, the menus at step 21, a divider added and undone, the steps turned and undone, and a box dragged with mouse events, dropped and undone. After the move every number is the same to a hundredth of a point, and no pixel of any picture differs by more than 24 of 255. Both apps build, and the two new packages and LDrawRenderMetal build for iOS. The same 22 were the same again once the boxes followed their submodels, and once they changed places, since none of them turns the camera.
- Adding and removing, through the menu code: *Remove Callout* on the first box of step 15 took out its `BEGIN`, `END`, two arrows and `PLACEMENT`, and the list gained the row *seat left arm* 2×. *Call Out* on that row wrote the six lines shown above and the row went again. Undo gave the step's lines back as typed.

The book was printed from an older state of the file: 150 DPI and scale 1.0, where the file now says 170 DPI and 1.15. Its page has the same number of pixels, so its layout holds, but its sizes do not: the assembly is now 1.3 times as big on the same page, and a callout's own contents 1.13 times. Some offsets have been dragged since, too. So the book shows how LPub3D lays a page out, not where each box is today. With today's numbers several steps do not fit their page, in LPub3D as here: at step 17 the callout and the assembly together are taller than the page.

The book also confirms the page scale: a stud in it measures 46.7 pixels of a 2048 pixel page, and one LDU to 1/64 inch at 150 DPI gives 46.9.

## Limits

- **A file laid out under LPub3D 2.4.2 or older** has its dragged callouts where the older centering put them, and some of them are off the page under the newer rule. See *Where the step goes on the page*.
- **Adding needs the submodel's row.** With submodels not listed there is no row to click, and no other way to call one out.
- **A new callout shows its steps.** `ASSEMBLED` and `ROTATED` are not offered, and neither is a reset of the box's place. They can be typed.
- **Turning the steps is for one callout.** There is no item that turns the callouts of later steps too, as LPub3D's own does. A line with no `LOCAL` can be typed for that.
- **An arrow cannot be added to or taken from a callout** that exists. Removing the callout and calling the submodel out again gives one for each placement.
- **A divider cannot be dragged** to another step. Removing it and adding one before the other step does the same in two steps of undo.
- **`CALLOUT DIVIDER STEPS`**, LPub3D's line between two steps of one column, is not read, drawn or offered. Neither are a divider's arrows, `DIVIDER_POINTER`: they are kept as typed, and go when their divider is removed.
- **Only callouts are counted with the assembly.** LPub3D also counts a parts list, a step number, a rotate icon or a submodel preview placed against the assembly. Bricksmith always draws the parts list in the page's corner and has none of the others.
- **Steps of a step group.** LPub3D prints the steps of a `MULTI_STEP` together on one page. Bricksmith shows one step at a time and centers each as a page of its own.
- **`ASSEM MARGINS`** is not read, and **`PAGE MARGINS`** only for the step and the parts list. The room between a box and what it is placed against is the callout's margin alone, where LPub3D takes the larger of the two.
- **An assembly placed anywhere but `CENTER PAGE INSIDE`** uses LPub3D's default margin, and a line that places it against anything but the page is read as none.
- **`CALLOUT ASSEM MODEL_SCALE`** is not read. The callout's assembly is drawn at 1.0.
- **`PLI INCLUDE_SUBMODELS`** is still Bricksmith's own preference, not read from the file.
- **Pictures and gradients** as a background are not drawn.
- **The parts list in a step of a box** keeps Bricksmith's look. `CALLOUT PLI` styling beyond its margins is not read, and neither is the styling of the step's own parts list.
- **Fonts** are sized as LPub3D sizes them on a Mac, where Qt makes a point one dot. Windows makes it 96/72 of one, so a file laid out there may have its text a third bigger than it is drawn here.
- **A perspective view** has the page's scale only at the middle of the whole model, the page anchor. Parts nearer the camera are drawn bigger than that and parts further away smaller, more than LPub3D draws them, so the box around the assembly is not exactly LPub3D's. The camera stands 6.5 times the size of the whole model from its center of rotation, so for the roadster a part 100 LDU nearer than the middle is drawn about 3% bigger. While the camera is turned by hand the model may come nearer or go further on a page that keeps its size, until the next step is laid out.
- **A turned view starts from the layout of the unturned one.** The boxes move with their submodels from where the file puts them, and are not placed against the outline the model has now. Zoom to Fit lays the step out for the view as it is.
- **A box that follows its submodel may cover the model.** It keeps clear of the page's edge, the parts list, the other boxes and the placements the arrows go to, and not of the rest of the model.
- **A box may still lie over an arrow** where no side of its submodel leaves room for both. That happens when a turn takes the placements to the edge of the page or off it.
- **Four sides of its submodel** are all a box can take, each as far from the middle of its placements as the file has it. It does not go nearer, further or to a corner to find room.
- **A box on its way** may lie over another box or an arrow for the 0.3 seconds its move takes.
- **Placed automatically, a box is beside the box around the assembly**, not beside the model's outline. A long model seen from a corner leaves much of that box empty, and the callouts still stay outside it where the page has room. Where it has none, they lie over the assembly's box.
- **A drop in a turned view is written for the file's side of the submodel.** A box picked up on the far side comes to the file's side, so the step's own layout may then have it on another side of the assembly than before. Where the file's place would be off the page, or over the parts list or another box, it is moved clear, and the box lands that much short of where it was dropped. The file's place may still be over the assembly.
- **A box off the page does not follow.** It stays where the file puts it until its line is put right, by a drag or by hand.
- **A submodel moved in a turned view** takes its box along, as a turn does. The box is where the file puts it again once the view is back at the angle the step was laid out at.
- **Callouts inside a strip.** A callout in a called-out submodel is not drawn as a box inside the outer box. Its submodel is part of the step's picture, and it gets its own box once the outer submodel is on display.
- **A `PLACEMENT` outside a callout.** Only the line between a callout's two lines is read. LPub3D clears the placement at each `END`, so a line in one callout does not reach the next, but a line written outside every callout is not read here.
- **Arrows** are straight, are aimed at the middle of a placement, and cannot be moved. A `POINTER` line is counted and written back as typed.
- **The tips Call Out writes** are still the middle of each placement, not its edge. The edge depends on where the box is, and the line in the file would go stale as soon as the box is dragged.
- **Earlier steps are not faded** in a strip, as LPub3D can do.
- **OpenGL** draws no pictures off screen, so a callout's box has no pictures there. `+[LDrawView imageOfModel:…]` returns nil in that build: the OpenGL renderer has nothing that draws into an image, where Metal has `-newImageWithPixelSize:transparent:`.
- An arrow can pass under another box, and the arrows of two different boxes can cross.
