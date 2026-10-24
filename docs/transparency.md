# Transparent parts

**Overview:** The Metal renderer puts every fragment of every transparent part into a list for its pixel, then sorts each pixel's list by depth and blends it in one pass over the whole surface, as "How the layers blend" tells. Parts can be drawn in any order, a part's faces show through each other whichever is drawn first, and parts that sit inside each other blend in their true order.

## What it replaced

Transparent parts used to be sorted by their origins and blended far to near, each with depth writes on. Two things went wrong:

- Inside one part, the faces were blended in the order of the part file. A face drawn early wrote depth and hid the faces behind it that came later, so one triangle of a face could show the walls behind it while the next one did not. That is why half of a tile's top looked darker than the other half.
- Parts that sit inside each other, like stacked cones, have no right order by origin. The part drawn first hid the other one's walls behind it, so from some angles one part looked solid.

## How it works

All of it is in `Packages/LDrawRenderMetal`.

1. Opaque parts draw as before.
2. When the drawing finds transparent parts, it gets the lists ready, and a tile shader (`clearTransparentLists`) empties each tile's lists inside the render pass. A tile's later fragments come after it, so no list is emptied late. The lists are made only when a frame has transparent parts, with no guess from the frame before.
3. Transparent parts draw with depth testing against the opaque ones, but without depth writes. Their fragment shader (`transparentFragmentShader`, `transparentWideLineFragmentShader`) writes no color. It adds the fragment to its pixel's list: color, depth, the MSAA samples it covers, and for a line, line bits (see below). Thin lines draw with the faces' pipeline, and their vertices carry a normal as a face's do, so the drawing tells the shader when thin lines come. The samples take 4 bits, so the lists need 4 samples or fewer; the renderer uses 4.
4. A triangle over the whole surface (`transparencyResolveFragmentShader`) runs once per MSAA sample. It reads its pixel's list, keeps the nearest 16 fragments that cover its sample in order, and blends them over what is drawn in that sample, as the next section tells. Fragments past the nearest 16 are blended as one layer of their average color, behind the others. Each fragment is passed down all 16 places, swapping where it is nearer, so the 16 stay in registers. Blending each sample on its own keeps edges right where a transparent edge crosses an opaque one: a sample the transparent part does not cover keeps the opaque color.
5. Ghosts, drag handles and the marquee draw after, as before.

All of this happens in the frame's one render pass, so the multisample targets stay in tile memory on Apple GPUs.

`LDrawTransparentLists` keeps the buffers: one list head per pixel, a buffer of fragments, and 32 counters that hand out room in it. A frame takes counters that a finished frame gave back, or new ones, and sets them to 0, so a frame still on the GPU keeps its own. They are read after the frame to learn how much room it needed, and then given back. The heads and fragments are one buffer each, shared by the frames in flight. Metal tracks them, so a frame does not empty or fill them before the frame before it has blended them. Three copies would triple the memory.

## How the layers blend

Plastic lets some colors through and stops the rest. Think of a channel as a band of colors: a layer lets some of the band through and stops the others. Two layers of one hue let the same colors through, so the one behind stops little more. Two layers of different hues each stop their own, so red behind blue looks dark, as real plastic does. The usual "over" blend, used before, made it a gray purple.

So in each channel the layers still blend front to back as with "over": each adds its color by its alpha and passes on 1 - alpha of what is behind it. Only the order changes:

- Layers of one hue go in depth order, so a part of one color blends exactly as before, its shading included. A face in a darker shade has the same hue: its channels are in the same proportions. Rounding to 8 bits is allowed for. Shading may have cut a channel off at full brightness, so a pair of channels with one is left out of the test. When that leaves no pair, as for a brightly lit yellow face, one color must be the other scaled up, with its cut-off channels at least as bright as the scale makes them: bright yellow, (1, 0.88, 0.20), then matches dim yellow, but not (0.83, 1, 0), whose blue is 0 against 0.20. If no channel is left to scale by, as for two lit faces of (1, 1, 0), both must be cut off in the same channels and dark in the others.
- A gray layer, such as trans-clear, has no hue and goes in depth order with every layer, so it looks as before.
- A line takes the hue of the face behind it, which it is drawn on, and goes in depth order with that hue. It is not plastic of its own: going first by its own dark color, the edges inside a part would show as if they were in front, and staying in place, it would leave a light line wherever another hue goes first.
- The average layer behind the 16 sorted fragments goes in depth order with every layer. An average has no one hue, and where it holds a line it is dark.
- Where two hues differ, the hue with less of the channel goes first, all its layers together. A hue's value in a channel is its brightest layer's, so its shading does not change its place. Of two layers, the one with less first always gives less light, so this order takes away what the other layer stopped, and adds nothing.
- A sample keeps 4 hues apart. Layers of any further hue go in depth order with every layer.
- The layers that go in depth order with every layer split a sample into stretches, and a hue goes first only within its stretch. Otherwise trans-red in front of trans-clear in front of trans-blue would put the blue before the red in the red channel but keep the clear after the red, and the orders would go round in a circle: the red would darken while the clear stayed put.

Each layer is compared with the first layer of each hue found so far, not with every other layer, and then blends with running products of the light: one for the layers before its stretch, and for each hue, one for its nearer layers in the stretch and one for all of them, found by looking ahead once at the start of the stretch. Comparing every pair of layers, as first written, cost two to three times as much GPU time on the stress model. The depth sort is still needed: for the layers that keep their place, and for lines that lie on each other.

What is drawn behind the layers, opaque parts or the background, shows through what no plastic covers, as before, and is not filtered by channel. Filtering it the same way would let a dark part stop the glass's own light in a channel, so a red light on a black brick would look almost black. An opaque face in the lists, of a part that is also transparent, blends last in the same way and hides the layers behind it.

So one layer looks exactly as before over anything, and so does a part of one color. The shader still returns a premultiplied color with how much of what is drawn gets through, so the fixed blend and pictures with a clear background are unchanged.

## What the GPU does, and why the code looks the way it does

These were measured on an M3 and drive the design:

- **A fragment shader that writes to memory runs once per covered MSAA sample**, not once per pixel, and only for samples that pass the early depth test. Its `[[sample_mask]]` input is the triangle's coverage, not what passed the depth test. So the shader asks for `[[sample_id]]`, and the runs for the samples of one pixel find each other: they get the same color and depth, so the first one adds a fragment and the others add their sample to it. Without that, there would be four times as many fragments. The depth is taken at the pixel's center, in case a GPU puts each run's position at its sample, and depths one step apart still match, since they can round apart. It is the clip z over the clip w, both interpolated with perspective. That ratio is the rasterizer's depth: in a perspective test it was within 2 of 2^24 steps of `[[position]].z`, the same for all samples of a pixel. A fragment that already has the sample is never shared: it is another face, even one of the same color touching this one, like the faces where two bricks of one color are stacked.
- **One global counter is slow.** Every new fragment takes room from a counter with an atomic add. With one counter, the adds waited on each other and the lists cost about twice as much. The counters are picked by 8-pixel tile, and each owns an equal slice of the fragment buffer.
- **SIMD group functions are not reliable in these shaders.** Taking room for a whole SIMD group at once gave duplicate indices, so each fragment takes its own.
- **A fragment goes into its list with a compare and exchange**, so that a sample that loses the race to another sample of the same face can then share that sample's fragment. Each failed try means another fragment got in first, so a few tries are almost always enough. A compare and exchange may also fail for no reason, so after 16 tries the fragment goes in at the head with a plain exchange, which cannot fail. Other samples of the face can still join it there.
- **Raster order groups** let the blend pass read what earlier draws of the same pass wrote for its pixel, and a **tile dispatch** empties the lists inside the pass. A test that filled the heads with garbage before each of 200 passes found every list emptied in time. In a tile dispatch the grid position is the pixel in the render target, not in the tile; on surfaces that are not a whole number of tiles, every head was emptied. The lists need both, so only an Apple GPU gets them.

## Ties and depth bias

Stacked LEGO parts have faces that lie exactly on each other, such as the top of one brick and the bottom of the brick on it. Their depths differ only by rounding.

- Fragments are first sorted by depth. Then fragments within 16 of 2^24 steps of the first fragment of their run count as one surface, and go by color. Without it, the order flips from pixel to pixel and the surface speckles. A run spans no more than 16 steps, so a chain of close surfaces, each within 16 steps of the next, does not become one surface. The runs are worked out from the sorted depths, so the order does not depend on the order the fragments came in.
- A transparent face that lies on an opaque face is pushed back by 16 steps of depth bias, so the opaque face hides it everywhere. An example is the inside of a transparent plate resting on the studs below it. The bias does not scale with slope: a face seen almost edge on would go behind what is just behind it. Metal applies depth bias only to triangles, so thin edge lines keep their depth: the bottom outline of a transparent brick on an opaque plate stays.
- With outlines, faces also get a bias that scales with slope, up to a limit set as a depth. A face steeper than 45 degrees to the eye reaches that limit by its slope alone, so the limit for transparent faces is 16 steps higher. Without that, a transparent face lying on an opaque one got the same bias as it and fought it for depth, as on the studs under a transparent plate in a 3/4 view.
- A transparent face sorts a little behind the lines on its edges: twice the tie. It does not scale with slope either, so a face seen almost edge on does not sort behind a part that is really behind it. On such a face a line can sort behind it, as it can on an opaque face.
- Lines that lie on each other blend once, as the depth test does for opaque lines. Examples are an edge that two subparts both draw, and the overlapping ends of two wide lines at a corner. A line is skipped when one of the last 4 lines blended has the same color and is within the depth leeway of either; faces blended between them do not count. The leeway matters at corners: a wide line's quad keeps the depth of its ends, so where two lines' ends overlap, each one's depth follows its own slope, and on an edge that recedes from the eye they can be thousands of steps apart. So a wide line's leeway is how much its depth changes along it over two line widths, two for corners sharper than square. A thin line's is a tie. Faces that lie on each other still blend twice, since they are two layers of plastic.
- The line bits sit beside the samples, below the depth: a mark that the fragment is a line, and its leeway as a tie times a power of 4, rounded up, in 3 bits. Colors are kept exactly, so a face at full alpha stays opaque.

## Room for fragments

The first frame with transparent parts has room for a fragment for every other pixel. A frame that needs more drops some fragments and asks for another frame, which gets room for what it needed and half as much again. A frame that uses over seven eighths of the room also grows it, so a view that zooms in rarely runs out. After 30 frames in a row that use under a third, it shrinks. A view that stops drawing gets no such frames, so 2 to 4 seconds after its last frame its lists let go of the fragment buffer if that frame needed under half of it; the next frame makes one that fits. On the stress model, a close-up took the lists to 821 MB; back at the whole model they went down to the heads' 13 MB, and the next frame made the 475 MB it needs. The fragment buffer never goes past 1 GB.

A counter keeps counting past its slice, which tells how much a frame needed. But a fragment that found no room was counted once for each of its samples, since there was no fragment for the other samples to share. So the count past the slice is divided by the samples in a pixel.

When the lists already have the most room they can, a frame on screen that runs out keeps the fragments that fit and does not ask for another frame, which would run out the same way. A picture is drawn again until its fragments fit; if even the most room is too little, it is drawn once more with the parts blended one at a time, rather than returned with some missing.

A surface bigger than 8192 x 8192 pixels gets no lists: its heads alone would take over 256 MB. Neither does a frame whose buffers cannot be made. Both blend their transparent parts one at a time.

A view lets go of its list buffers after a frame with no transparent parts. Pictures keep theirs for the next picture while they take 64 MB or less, so a run of parts list pictures does not make them anew; bigger ones are let go. Either way the room the last frame needed is kept, per pixel, so the next frame or picture makes buffers that fit its size at once instead of running out first.

## Without the lists

On a GPU without the lists, transparent parts are still sorted by their origins and blended far to near with "over", but without depth writes and with the same depth bias. A part no longer hides its own faces or the parts behind it. Parts that sit inside each other can still blend in the wrong order, and lines that lie on each other blend twice, which shows as darker spots at the corners of outlines. Letting the lines write depth was tried: each line then hid the faces drawn after it, which left a light seam along every line.

## Cost

On an M3 at 2243 x 1414 pixels, the Porsche (16 transparent parts among about 2000) took about 2.3 ms more GPU time per frame: 0.4 ms to clear the heads and blend, the rest for shading the transparent surfaces once per sample. A frame with no transparent parts costs nothing extra. When a close-up fills the view with several layers of transparent walls, the fragment buffer can reach a few hundred MB.

The cost grows with the number of transparent fragments, not parts. A stress model of about 1050 transparent parts, glass towers ten bricks high and a field of small parts, put 17 to 25 million fragments in a frame, about 8 per pixel. In a Release build it took 73 to 110 ms of GPU time per frame, depending on the angle and the launch, against 11 to 13 ms for the sorted blending. The CPU took about 2 ms; drawing all 1047 transparent parts one at a time took 0.6 ms of it. Of the GPU time:

| Stage | GPU time |
|---|---|
| Opaque parts and the transparent geometry, with no fragment work | 8 ms |
| Shading each transparent sample | about 10 ms |
| Putting the fragments into the lists | about 50 ms, 10 of it for the extra runs of the shader for the samples of a pixel |
| Blending the lists, per sample | 8 to 12 ms, mostly following the lists through memory |
| Blending lines that lie on each other once | about 5 ms more |

With outlines on, the lines are quads a few pixels wide, so the same model put 25 to 33 million fragments in the lists. Blending lines that lie on each other once then added about 6% to the frame. Each line is checked only against the last 4 lines blended. Checking it against every nearer fragment, as first written, added 15 to 20%, and as much again when faces were checked too.

The same build varies by 15 to 30% from one launch to the next, so a difference of a few ms needs several launches, taking turns, to show. Raster order groups cost nothing measurable, and the 32 counters fill within 1% of each other. A much faster design would keep the layers in tile memory, out of main memory.

These times were taken with the "over" blend. Blending by channel adds 10 to 27%. On the stress model, in pictures of 2243 x 1414 pixels in a Release build, it took a frame's GPU time from 37 to 46 ms in a side view and from 126 to 160 ms in a view from above, and with outlines from 60 to 72 ms and from 206 to 227 ms. That is the median of 7 pictures in each of 3 launches, taking turns.

## Limits

- Only transparent layers filter each other. An opaque part behind them shows through as with "over", so a red part in front of a blue brick still looks a gray purple.
- Colors filter in three channels, not by their spectra, and in the stored color values rather than in linear light.
- A face lit so brightly that two of its channels are cut off has only one channel left to tell its hue by. Lit neon green, (1, 1, 0.57), then matches any color that, scaled up until its third channel is 0.57, cuts off the other two, such as (0.4, 0.4, 0.2) or trans-red, whose green and blue are small but not 0. It does not match (0.4, 0, 0) or (0.4, 0.4, 0). A matched pair blends in depth order.
- Trans-clear still lays a white haze over a colored transparent part behind it, as with "over". Real clear plastic would hardly change it.
- The fragments past the nearest 16 blend as one average layer in depth order, so they do not filter by channel.
- Without the lists, parts blend with "over", so red behind blue looks a gray purple there.
- A ghost is drawn after the lists are blended, so it shows over a transparent part even where it is behind it.
- A part with both opaque and transparent faces goes into the lists as a whole. Its opaque faces do not write depth, so ghosts and drag handles drawn later are not hidden by them.
