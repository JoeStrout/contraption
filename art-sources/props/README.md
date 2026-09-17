# Prop sprites

`make_props.py` renders each prop in `PROPS` as a strip of frames running from
wide open to shut, and packs them into one row.  A prop with no `joints` is a
single still frame instead, written as one sprite rather than a strip.

```sh
./render.sh                          # everything, into out/
./render.sh --only scissors          # just one
./render.sh --engine eevee --samples 8 --size 192 96 --frames 4   # quick look
./render.sh --as-modelled            # keep the model's own materials
./render.sh --only scissors --open 0.75   # try a different gape
./render.sh --only basket --yaw 25 --pitch 18   # try a view, for a still prop
```

`render.sh` just locates Blender (override with `BLENDER=...`) and runs
`make_props.py` inside it; the script needs Blender's bundled Python and numpy,
so it will not run under the system python.

Output lands in `out/`:

* `out/<name>_<frames>x1_<w>x<h>.png` — the strip the game loads
* `out/<name>_<w>x<h>.png` — a jointless prop, which is one frame, not a strip
* `out/<name>_<w>x<h>/frame_NN.png` — the frames (only with `--write-frames`)

Copy the strip into `../../disk/pics/` when you want it in the game.

## Why not just play the model's animation

The scissors model ships with an open-shut-open animation, easing included.
Sampling that evenly in *time* bunches the frames up at the ends, where the
easing is slow, and wastes half of them on the return trip.  So the script
reads only which nodes turn and how far, and drives them itself: frame 0 is
fully open, the last frame is shut, evenly spaced **in angle**.

## The frame convention

Frame *i* is the prop at openness `1 - i/(frames-1)`, so frame 0 is open and
the last frame is shut.  Frames run left to right in a single row:

```
	// one frame of the strip, as an Image
	idx = round(openness * (frames - 1))   // 0 = open
	img = strip.getImage(idx * w, 0, w, h)
```

The camera is orthographic, fixed, and framed once from the union of every
frame's bounds, so **a fixed point of the model stays on the same pixel in
every frame** — for the scissors, the pivot screw.  A part can therefore pin
its body at the pivot and let the sprite swap underneath it.

Unlike the balls, which are framed edge to edge so the sprite size *is* the
diameter, props get a little air around them (`MARGIN`): the silhouette
changes shape as the prop opens, and a blade tip landing on the last pixel
column looks clipped.

## Standing props: the basket

`basket` has no `joints`, so it is a single frame and the joint machinery --
`check_axis`, the angle sweep, the measured orientation below -- sits out.
What it needs instead is `view`: `yaw` spins the prop about its own upright
axis, `pitch` tips its top toward the camera.  Both are zero for the basket,
because the playfield is seen dead on, and any pitch looks down into the
basket from a camera the rest of the game does not have.  `--yaw` and
`--pitch` override them for one run, which is how to find a view.

There is nothing to measure an orientation *from* on a prop like this -- no
shut pose, no tapering working end -- but there is glTF's own up axis, which
the importer turns into Blender's +Z, so standing it up on screen is all the
orientation it needs.

Nothing scales a prop the way `make_balls.py` scales a ball, so a prop carries
the model's own units, and this basket is 18 of them deep.  That is why the
camera stands off by the model's depth and takes its clip range from it: at a
fixed distance it ends up *inside* a model this big, and the near clip plane
slices the front off the basket -- which reads as a hole in the weave rather
than as an error.

## Orientation is measured, not configured

A new prop does not need Euler angles dialled in by hand.  The script looks at
the model and works out that the thinnest axis of the silhouette is the one to
look down, the longest is the one to run across the screen, and the end of
that long axis that *tapers* is the working end, which it points right.

That last test is taken with the prop **shut**.  Open, both ends are spread —
the handles most of all, being the longer arms — and the taper test reads that
as the pointed end and renders the whole thing mirrored.

## The hinge axis

`axis` is the joints' rotation axis **as Blender holds it after import**, which
is not what the glTF file says.  The scissors' hinge is local Z in the file;
Blender's importer converts the model from Y-up to Z-up, and the hinge comes
out on -Y.

Getting this wrong is quiet rather than loud: the joint swings the prop out of
its own flat plane, and every frame still renders, just all looking much alike.
`check_axis` therefore fails the run if opening the prop makes it thicker.

## Picking a cell size

The cell is whatever shape the prop actually makes, not a round number chosen
up front: the shut pose sets the width, the widest-open pose sets the height,
and the script fits the union of every frame into the cell without distorting
it.  Give it a cell of the wrong aspect and the prop shrinks to fit the
tighter axis, leaving a band of empty pixels down the other one — the scissors
at 48x24 used 21 columns of 48.

So render once at a guess, look at how much of the frame the art covers, and
size the cell to that.  The scissors came out 3:2 (48x32) at a 36-degree gape,
which `open=0.6` sets; the model's own animation opens twice that far, which
is dramatic but small on screen.

## Adding a prop

Add a dict to `PROPS`: `name`, `size` as `[width, height]`, `frames`, `model`
(a path relative to this directory), `joints` mapping glTF node names to the
angle each is turned at frame 0, and `axis`.  Optional `open` scales every
joint angle, for opening wider or less wide than the model does; `skip` leaves
it out of a plain run; `materials` recolours it (below); `pivot` names the node
to measure the blade/handle split from.

A prop that does not move leaves out `joints` and `axis`, sets `frames` to 1,
and gives `view` instead.

### Recolouring

Models come with whatever materials their author gave them, and a prop that is
one flat white — as these scissors are — vanishes at this size against the
playfield's `#E7D2C1`.  `materials` replaces them with a `blade` colour and a
`handle` colour, split along the long axis at `split`, a fraction of the
model's length measured from the pivot (negative reaches back behind it, so
the steel shank stays steel).

The split is geometric rather than per-object because each half of a scissors
is a single mesh running handle to tip: there is no object boundary at the
grip, only a place along its length where steel becomes plastic.

`--as-modelled` skips this, for checking what the model actually looks like.

## Models

Everything under `../models` is CC-BY and must be credited: the required text
is in `../art-attribution.txt`, and it has to travel into the game's credits,
because the rendered strips are derivatives.
