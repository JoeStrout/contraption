# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

Contraption is a build-a-machine puzzle game in the spirit of *The Incredible
Machine*, written in MiniScript for **Mini Micro 2**.  There is nothing to
compile.

It needs two sibling checkouts, and assumes this layout:

```
svnrepo/
  contraption/          this repo
  MiniMicro2/           the Mini Micro 2 system (see its CLAUDE.md)
  raylib-miniscript/    the host, and the source of disk/lib
```

Scripts here have the Mini Micro API (`../MiniMicro2/assets/lib`) and the `/sys`
disk (`../MiniMicro2/assets/sys`), *and* the raylib-miniscript extras: the
intrinsic `Matrix` class and the `physicsCore` intrinsics.  API references:
the MiniScript wiki at https://miniscript.org/wiki/ , and
`../raylib-miniscript/API_DOC.md` for host intrinsics.

Activate your MiniScript skill for general MiniScript language proficiency.

## Running and checking

Running it opens a window and needs a human to mount the disk, so **you cannot
drive it from a tool call.**  Ask the user to run it:

1. `../MiniMicro2/raylib-miniscript`
2. mount the `disk` folder (it becomes `/usr`)
3. `run "contraption"`

What you *can* do is syntax-check, which catches a great deal:

```bash
echo "" | miniscript disk/part.ms 2>&1 | grep -i "compiler error"
```

`/usr/local/bin/miniscript` is the command-line MiniScript.  It has no `Matrix`
intrinsic, so every module dies at the first physics call with `Undefined
Identifier: 'Matrix'` — that is expected, and means parsing succeeded.  Only
`Compiler Error` lines are real.  Imports do resolve, so the whole chain gets
parsed.

There are no tests and no lint step.

## Layout

```
disk/            mounted as /usr; the game
  contraption.ms   entry point: displays, level scenery, main loop
  config.ms        layout, tuning, colors -- all magic numbers live here
  part.ms          the Part base class
  parts.ms         the registry and the palette catalog; imports parts/
  glow.ms          the pool of light a lamp or a flame lays on the board
  heat.ms          what is alight, and what is near enough to catch
  particles.ms     the particle system, and the Flame built on it
  parts/           one module per type: balls, block, platform, lever,
                   balance, weight, balloon, basket, scissors, gears,
                   belts, tiePoint, pulleys, rope, candle, fuse; and the
                   electrical ones -- electric (the outlet), switches,
                   relay, motor, wire, lamp
  parts/rope.ms    the Rope part: its constraint, its beads, its drawing,
                   and how it comes apart when something cuts it
  torque.ms        gear trains: which wheels turn together, and how fast
  gameWorld.ms     parts, physics, modes, collision queries, save/load
  panel.ms         right-hand palette and transport buttons
  editor.ms        design-mode interaction
  artUtil.ms       procedurally drawn art, and its cache
  util.ms          identity-based list operations
  pics/            pre-rendered art: the ball sprite sheets, the balloon,
                   the basket, and the scissors' eight poses
  lib/             physics.ms, physicsFallback.ms, matrixUtil.ms
tools/updateScripts  refreshes disk/lib from ../raylib-miniscript
art-sources/     Blender sources for disk/pics (see balls/README.md), and
                 art-attribution.txt, whose CC-BY credits must reach the game
notes/           design notes: the parts eventually wanted, by category
```

**Never edit anything in `disk/lib`** — `tools/updateScripts` overwrites it from
the raylib-miniscript source tree.  Changes belong upstream, or in our own code.
They are copies rather than symlinks because the Mini Micro sandbox rejects any
path resolving outside its mount root (`[fs] rejected ... outside its mount
root`), which is deliberate.

`matrixUtil.ms` must be among them: Mini Micro's own `/sys/lib/matrixUtil.ms` is
an unrelated module that does `globals.Matrix = {}`, clobbering the intrinsic
class `physics.ms` needs.  `env.importPaths` is `[".", "/usr/lib", "/sys/lib"]`,
so our copy in `/usr/lib` shadows it.

## Architecture

### spec is the authored state

A part's design-time state lives entirely in its `spec` map — `x`, `y`, `angle`,
and whatever the type adds (`radius`, `color`, later `switchState`).  **Nothing
in the running simulation may write to `spec`.**  That one rule is what makes
Stop a matter of putting the bodies back where the spec says, and saving a
matter of writing out `{type, spec}` per part.  Runtime state (lit, powered,
charge) lives on the part itself, and `onStop` clears it.

Subclassing is `Ball = new Part`, extending `defaultSpec` with map addition.
Every mutable per-instance field is assigned fresh in `Part.make`; a list left
on the class would be shared by every instance.

`GameWorld.advance` calls `Part.preStep` on every part before each step and
`Part.update` after it.  Anything the solver must be told goes in `preStep`,
because by `update` the step has already been solved.

### Modes

`GameWorld.DESIGN / PLAY / PAUSED`.  Only PLAY steps physics, at a fixed
`config.timestep` against an accumulator capped at `maxStepsPerFrame`.  Design
mode never steps but still needs collision, to reject overlapping placements.

Play may *destroy* parts -- scissors cut a rope into two loose ones, a fuse
comes apart where it catches and burns away to nothing -- and Stop still has
to put the design back.  Putting the bodies where the spec says is no help for
a part that no longer exists, so `play` writes the whole design out with
`save`, `addPart` / `removePart` note that something changed, and `stop` reads
it back if anything did.  A part that wants to add or remove parts mid-step
must queue the work rather than do it, because `advance` is walking the very
list it would be changing.  `GameWorld.defer` is that queue: it takes the part
and a word of its own choosing, and hands both back to the part's
`applyDeferred` once the step is over.  `cutRope` is a named wrapper on it,
so the scissors need not know it is there.

### A few things about the physics engine

All of them are worked around in our code; `physics.ms` is used unmodified.

- `findPairs` discards any pair where neither body is dynamic, so two static
  parts are invisible to each other.  **Design mode therefore creates every
  body DYNAMIC** (`Part.addBody`), and `onPlay` applies each part's real
  `bodyType`.  Without this a platform could be placed straight through another.
- There is **no sleeping**, restitution is one constant per shape, and a
  circle on a flat floor has nothing to stop its spin -- so left alone, a
  bouncy ball rolls forever and never finishes bouncing.  Three things answer
  that, none of them in `physics.ms`: `linearDamping` / `angularDamping` in a
  part's spec, applied in `Part.addBody`; `Part.softenBounce`, which rewrites
  each shape's restitution every step from the part's speed, so a bounce
  fades out instead of pattering; and `Part.settle`, which crushes the
  velocity of a part that has barely moved for `config.settleDelay`.  Note
  that `settle` damps hard rather than freezing, so a part whose support is
  knocked away falls instead of hanging in the air.
- `config.restitutionThreshold` replaces the engine's default of 30, which
  assumes a different scale: gravity 980 px/s^2 makes a meter 100 pixels, so
  30 is 0.3 m/s -- slow enough that the solver's own overlap bias keeps a
  ball above it indefinitely.
- There are **no joints**.  A part that needs one keeps it itself, in
  `Part.update`, by projecting its bodies back onto the constraint after each
  step -- see `Lever`, which pins its bar to a fulcrum by putting the body
  back on the pivot and replacing its velocity with the single turn about
  that pivot carrying the same momentum in the one degree of freedom it has
  left.  That is what makes a blow to one end come out as spin rather than
  being thrown away, and it is exact rather than approximate.  `Balance`
  extends it through four hooks (`pinRiders`, `momentum`,
  `generalizedMass`, `applySpin`): its pans are held level on the ends of
  the bar and join the same one degree of freedom.
- A projected constraint is invisible to the solver, which is a problem when
  something lands on the constrained part: the solver works the impulse out
  against that one body's own mass, not against the assembly behind it.  On
  a balance pan that is a factor of nine, and it eats the impulse.  So
  `Balance.preStep` tells the solver a lie -- the pan's mass becomes the
  assembly's moment over its arm squared, which is what the assembly really
  resists with there -- and `Balance.momentum` unpicks it: what a pan was
  already carrying counts at its real mass, what the step just added to it
  counts at the mass the solver used, because that product is the impulse
  and the impulse is real.  A part whose mass is a fiction cannot also be
  given weight from it, so a pan's gravity is off and `preStep` hangs its
  real weight on the bar instead.
- The overlap query (`GameWorld.overlapping`) calls `findPairs` and
  `collidePairs` directly, with margin 0, into scratch matrices, and looks for
  `ColSep < -config.overlapTolerance`.  It deliberately does not call
  `World.step`, which bails on `dt <= 0` and would advance things anyway.  Being
  a real narrowphase, it stays correct for any shape we add later.

### Parts that name other parts

A rope is tied to two other parts; a mounted pulley is bolted to one.  So a
part has an `id`, which lives in its `spec` and therefore survives a save, and
the world keeps a `byId` index.  A reference is `{part: id, tie: index}`.
Deleting a part deletes whatever `dependsOn` it -- the ropes tied to it, the
pulleys on it.  Wires and belts, when they come, want the same machinery.

**Tie points** are where a rope may be fastened: `Part.tieLocals` gives them in
the part's own frame, and `tieList` resolves each to `[body, lx, ly]` in that
body's frame, so a tie point follows whatever it is on.  Resolution is lazy,
because a mounted pulley's tie point *is* the tie point it is bolted to -- same
body, same offset -- and the order parts are built in says nothing about which
part that is.  That also means a mounted pulley needs no joint and no body of
its own: a rope over it pulls on its host, at the right point, by construction.

### Torque: gears, wheels and belts

A gear, a wheel and a spool are all one thing: a hub on a fixed axle that
turns.  Hubs are *linked*, two ways.  Gears **mesh**, which is implicit --
their pitch circles touch, nothing is authored, you place them and they
engage.  Wheels are joined by a **belt**, which is explicit, because a belt
reaches as far as it likes and only the player knows which two were meant; so
a belt is a part that names two others, like a rope, and is run in the editor
the same way.  Either link is only a ratio.

What a belt can be fastened to is a rim or a groove -- `Gear.beltRings`, empty
for a plain gear, whose teeth would chew one.  A **gearwheel** has teeth and a
groove, which makes it the one part that is in a geared train and a belted one
at once, and the join between the two ways of building.  A **step pulley** has
three grooves, and is the only hub that takes power in at one radius and gives
it out at another: since a train's ratio is the product of `R out / R in` over
the hubs along it, and that is 1 for every single-radius hub, nothing else in
a train can trade speed for force at all.  Which groove a belt runs in is part
of what the belt records (`ra` / `rb`), and the editor picks it from where you
click.

A connected set of hubs is a *train*, and a train has exactly one degree of
freedom, so it is held the way `Lever` holds its bar: after each step, read
the train's momentum in that one coordinate, and put every hub back on its
axle turning at the one rate that carries it.  `torque.ms` owns that over a
graph of ratios, which is why the two kinds of link differ only in how the
edges are found: the solver never learns which is which.

The hub bodies are ordinary dynamic bodies between projections, which is what
makes the transmission two-way: a ball dropped on a gear turns the train, and
a turning train drags the ball along by friction.  The teeth themselves are
art -- the shape the physics sees is a circle inside the pitch circle, so
meshing gears never touch -- but they are *phased* like real teeth, at the
moment a train is built, and that happens in design mode too
(`GameWorld.alignGears`), so gears visibly snap into mesh as they are dragged.
Axles snap to the half-peg lattice, because a meshing pair's centres are
exactly the sum of its pitch radii apart and whole pegs cannot make every sum.
A belt has no teeth to line up, so a belted wheel simply stays where it is.

A **spool** is how a train gets a load: a gear with a drum, whose rope
lengthens by `drumRadius * dtheta` as it turns and whose tension is
`drumRadius` worth of torque back.  Two things about it are worth knowing.
Its rope's length is runtime state (`Rope.curLen`), not `spec.length`, since
spec is authored and this is not; and the solver does not pull on the spool
itself (`Part.ropeFixed`) -- instead the spool hands the train the tension
*and* the load's mass carried round to the rim, as a matched pair, because
handing over the tension alone makes the drum and the rope whip each other
apart inside a dozen steps.  `Spool.driveTorque` explains it in full.

`notes/torque-parts.md` has the whole plan, including belts and the rough
edges this leaves.

### Ropes

See the header of `rope.ms`; the two things to know here are that a taut rope
is a single scalar constraint (its total path length) solved by impulses after
the physics step, and that a slack rope is not physics at all but a line of
beads, run for looks and never pushing back.

`GameWorld.solveRopes` runs after `phys.step` and before the parts' `update`
hooks, so a rope pulling on a lever arrives in time for the lever's pin to
turn it into spin.  Ropes that share a body are relaxed together.  The solve
is in two passes -- impulses for the velocity, then a geometric pass for the
length -- and `rope.ms` explains why folding the second into the first (the
usual Baumgarte bias) is wrong here rather than merely inexact.

### Fire

Heat is points, not a field (`heat.ms`).  A part that is burning hands back
one or more *sources* -- a place, a reach, and how fierce it is -- from
`Part.heatSources`; a part that can catch asks `heat.at` how hot it is where
it stands.  There is no diffusion, nothing cools, and nothing has a
temperature.  That is the same ceiling `circuit.ms` puts on electricity, for
the same reason.  The one real number is `power`, because a lens will
eventually have to light things a candle cannot, and that keeps the catalogue
of what lights what down to two constants per part instead of code.

Sources are gathered once a step, in `advance`, after the physics has moved
everything and before any part asks whether it has caught.  **Design mode
never collects and never asks** -- a fuse laid against a lit candle while the
machine is being built has to sit there unburnt.

A **fuse** (`parts/fuse.ms`) is a Rope with the pull taken out (like a wire)
and the hang taken out as well: no bead chain, ever.  Its geometry is a
polyline in world coordinates in `spec.shape`, taken from its fastenings every
frame in design mode and frozen once play starts -- which is what "stiff" and
"pinned to the board" amount to, and is also what lets half a burnt fuse stay
hanging in the air exactly where the whole one was.  Burning is two numbers,
how much has gone from each end; catching is a walk along what is left,
asking `heat.at` every few pixels.  Near an end, that end lights.  Anywhere
else the fuse comes apart into two fuses, each alight at the new end.  The
front is itself a heat source, which is the whole of how a fuse lights the
next thing -- nothing in `fuse.ms` knows what a candle is.

### Light, and things that are only for the look of them

A lamp or a candle lays a **glow** on the board: one sprite, one pre-drawn
radial gradient, tinted and faded, and that is all of it (`glow.ms`).  There
is no occlusion -- nothing is shadowed and nothing is lit -- because nothing
in the game yet asks what light *reaches*.  When a lens arrives and things
start catching fire, that question gets answered with rays, in its own
module; the glow will still be the picture that says a thing is burning.
Keeping the two apart is the point.

A **particle system** (`particles.ms`) is a fixed pool of sprites, allocated
once.  A dead particle is not removed from the pool, it simply has no image,
so nothing is allocated per particle.

The pool goes on screen as **one entry**: a member of `SpriteDisplay.sprites`
may itself be a list of sprites, drawn depth first, so a whole effect holds a
single place in the draw order and nothing reordering the layer can shuffle
it apart.  A part that has one pushes the pool into its own `sprites` as that
one entry, and then `destroy`, `moveSpritesTo` and the restacking all account
for it without knowing what it is; `Candle` does that with a `Flame`, and
carries a `Glow` beside it.  So **an entry of `Part.sprites` may be a list**,
which is why `Part.tintSprites` steps over one and why the default
`Part.syncSprites` (which pairs sprites with bodies by index) is only for
parts whose sprites are all plain sprites.

Both of these move without the physics moving them, and both must keep moving
in design mode -- a lit candle burns while you build around it.  So they run
from `Part.updateEffects`, which `GameWorld.updateEffects` calls every frame
in every mode but PAUSED, off the world's own clock (`effectTime`) rather
than `time`, so a pause does not make a flame jump.  Nothing in there may
touch the physics or the spec.

### Coordinates

Mini Micro screen coordinates throughout — y up, origin lower left — so gravity
is `-config.gravity`.  `physics.ms` documents y-down but is agnostic; only the
sign of gravity matters.  Body angles are radians CCW and `Sprite.rotation` is
degrees CCW, so the conversion is just `* 180 / pi`.

Snapping quantizes a part's *bounding-box corner*, not its center, so parts
sized in multiples of `config.grid` abut exactly.  Positions stay floats;
`GameWorld.snap` is the only place that quantizes.

### Display layers

Lower slot numbers draw on top.  1: the part being dragged (above the panel, so
it does not slide under while crossing the edge).  2: the panel.  3: selection
overlay, and the tie-point guides while a rope is being run.  4: ropes and
belts, which therefore lie over the parts they are fastened to -- a belt has
to, or it disappears behind the rim it is wrapped around.  5: placed parts.
6: pegboard and scenery.  7: backdrop.

A part owns its sprites and knows which display holds them (`Part.spriteDisp`,
`moveSpritesTo`), so `destroy` always finds them wherever the editor has put
them.

All eight slots are taken, so anything that must draw over its neighbours --
or under all of them -- cannot have one of its own.  Position in the part
layer stands in for it, sprites being drawn in list order, and
`GameWorld.restackSprites` puts that order back whenever anything joins the
layer.  Three hooks ask for it: `Part.drawsInFront` keeps a whole part's
sprites at the end (a basket, so that what it carries rides inside it), and
`Part.backSprites` / `Part.frontSprites` name single sprites that belong at
one end of the layer whatever the part they belong to is doing -- a lamp's
pool of light is one, and the lamp itself stands in the ordinary order.

## Conventions

**Import with `ensureImport`, not `import`.**  `import` runs the module every
time it is called, which is correct -- but it means a module imported from
five places is five separate maps, and `globals.Part = {}` running again makes
a *new* Part that the existing subclasses do not inherit from.  Class-level
state then splits in two: `Part.nextId` resets to 1 and the next part created
collides with an id that a rope is already using to name its target.  So every
module here opens with `import "importUtil"` and then `ensureImport [...]`,
which imports once, into globals.  `importUtil` itself is the one plain
`import`, for obvious reasons.

## MiniScript gotchas hit in this codebase

- **`==` compares maps by value.**  `list.indexOf` will match two distinct parts
  that merely look alike, and parts reference the world, which references the
  parts list, so a deep compare is cyclic as well as wrong.  Anything meaning
  "this exact object" goes through `util.ms` (`indexOfRef`, `removeRef`,
  `containsRef`, `sameRef`), which wrap `refEquals`.
- **`range(a, b)` counts *down* when `b < a`**, so `range(0, n-1)` with `n == 0`
  yields `[0, -1]` rather than nothing.  Always pass the explicit step:
  `range(0, n-1, 1)` correctly gives `[]`.
- `PixelDisplay` has `line`, not `drawLine`.
- **`locals`, `globals` and `outer` cannot be parameter names.**  The error is
  `Expected parameter name`, which the syntax check above does not match.
- **`fillEllipse` drops a wedge.**  It hands the job to raylib's
  `DrawEllipse`, a fan of 36 triangles with its seam at angle 0, and one
  triangle of it does not arrive -- so every filled circle has a ten-degree
  bite out of its right side, invisible at a few pixels across and obvious at
  fifty.  `fillPoly` next door is our own triangulation and is careful about
  the culling and batch flushing that `DrawEllipse` is not, so
  `artUtil.fillCircle` / `drawCircle` go through that instead.  Worth fixing
  upstream in `PixelDisplay.ms` eventually; until then, prefer them for
  anything bigger than a bolt head.
- `super` resolves from the class the running function was *defined* in, so a
  three-deep override chain (`Balance` -> `Lever` -> `Part`) works and does not
  recurse.
- **`PixelDisplay` draws in replace mode** (GL_ONE/GL_ZERO) for everything but
  text and `drawImage`, so alpha does not blend -- it overwrites.  Filling with
  a transparent color therefore genuinely erases; and a translucent highlight
  drawn straight onto a *shared* layer (the links or overlay display) punches a
  hole through to the part below rather than shading it.  Inside a part's own
  cached image it is fine, since that is composited with `drawImage`.  For an
  opaque highlight there, see `artUtil.lighten` / `multiply`.  Prefer it over `clear` for per-frame
  erasing: `clear` reallocates the render texture when the size differs, and
  passing the wrong size silently resizes the display.

## Code Style

- Tabs for indentation
- Comments say *why*, not *what*; a module opens with a comment on its job
- No emojis unless requested
