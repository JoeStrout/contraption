# Ball sprites

`make_balls.py` renders each ball in `BALLS` as 64 frames of a full turn and
packs them into one 8x8 sprite sheet, one sheet per size the ball lists.

The game currently uses `ball-star` at 32 and 40, `ball-bowling` and
`ball-soccer` at 40, and `ball-tennis` at 20; the rest are marked `skip=True` and need `--only <name>`
or `--all`.

```sh
./render.sh                          # everything, into out/
./render.sh --only ball-star         # just one
./render.sh --frames 8 --size 128 --engine eevee --samples 32   # quick preview
```

`render.sh` just locates Blender (override with `BLENDER=...`) and runs
`make_balls.py` inside it; the script needs Blender's bundled Python and numpy,
so it will not run under the system python.

Output lands in `out/`:

* `out/<name>_8x8_<size>.png` — the sheet the game loads
* `out/<name>_<size>/frame_NN.png` — the frames (only with `--write-frames`)

Copy the sheets into `../../disk/pics/` when you want them in the game.

## The tilt

Each ball carries a `tilt`: a fixed rotation about X, Y and Z applied *before*
the spin.  Without it the pattern faces the camera dead-on in every frame and
the ball reads as a flat disc turning rather than a sphere tumbling.  The tilt
lives on the ball object; the spin is the Z rotation of an empty it is parented
to, so the spin axis stays put no matter how the ball is tilted inside it.

`--tilt X,Y,Z` overrides it for one run, which is how you find a good one: an
imported model's features sit wherever its author put them, so the useful tilt
is whatever brings them into view (the bowling ball's single hole, say).

## The frame convention

A 2D physics circle has exactly one degree of freedom, its rotation about the
axis out of the screen, so that is the axis the sphere spins about and the
camera looks straight down it.  The camera is orthographic, aimed along -Z with
+Y up, so world X/Y are screen X/Y and a positive object rotation is
counterclockwise on screen — the same sense as Mini Micro's `Sprite.rotation`.

Frame *i* is the ball turned `i * 360/64` degrees counterclockwise.  Frames run
left to right, top to bottom: frame 0 is the top-left cell.  So:

```
	// one frame of the sheet, as an Image
	degPerFrame = 360 / 64
	idx = round(body.angle * 180 / pi / degPerFrame) % 64
	if idx < 0 then idx = idx + 64
	col = idx % 8; row = floor(idx / 8)
	// sheet rows are top-down, but getImage's y is bottom-up
	img = sheet.getImage(col * size, (7 - row) * size, size, size)
```

The sphere is framed edge to edge (`MARGIN` is 0), so **the sprite's pixel size
is the ball's diameter** — a 64px sheet cell is a ball of radius 32.

The lights do not move with the ball, so the specular highlight stays put while
the pattern spins, which is what sells the 3D read.  Only the key light is
visible to glossy rays: one highlight looks like a light source, three look
like smudges on a shiny ball.

`--supersample` defaults to 0, meaning "pick one per size" -- each sprite is
rendered at about 160px and box-filtered down, so a 20px ball gets as much edge
detail as a 64px one.

## Adding a ball

Add a dict to `BALLS`: `name`, `sizes` (a list, since one ball often ships at
several pixel sizes, each of which is also its diameter), `pattern`, and the
colours `base` / `accent` / `accent2` as sRGB hex.  Optional `tilt`,
`roughness`, `metallic`, `specular`, `frames`, `skip`, plus whatever the
pattern takes.

Patterns are evaluated in 3D on the sphere's surface, not painted into UV
space, because an equirectangular image smears anything near a pole into a
sunburst.  `star` puts a stripe around the equator and a star on each pole,
which read as a rim band and the ball's face; `beach` is wedges of longitude;
`dots` scatters dots on a Fibonacci sphere; `stripe` is bands of latitude.

## Imported models

Instead of `pattern` and colours, give a ball a `model` path (relative to this
directory) and it is imported rather than generated -- `.gltf`, `.glb`, `.obj`
and `.fbx`.  It is then centred on the origin and scaled so its longest axis is
exactly 2 units, which frames it like the generated spheres, and it keeps its
own materials.  `ball-bowling`, `ball-tennis` and `ball-soccer` all come this
way; only `ball-star` and the other patterned ones are generated here.

`tennis_ball.glb` is the one model *not* in the repo: at 76 MB it is too big
to keep in history, so `.gitignore` excludes it.  Re-rendering `ball-tennis`
means downloading it again first, from https://skfb.ly/6YLwv , and saving it
as `../models/tennis_ball.glb`.  The rendered sheet in `disk/pics` is
committed, so nothing needs it until that ball is rendered again.

Everything under `../models` is CC-BY and must be credited: the required text
is in `../art-attribution.txt`, and it has to travel into the game's credits,
because the rendered sheets are derivatives.

One trap: the spin axis runs through the poles, so **a pattern that varies only
with latitude is symmetric about that axis and looks completely motionless** --
the tilt hides this a little, but not enough.  That is why `stripe` is only
useful combined with something else, as `star` does.  Every ball needs some
longitudinal variation to look like it is turning.
