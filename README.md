# Contraption

A build-a-machine puzzle game in the spirit of *The Incredible Machine*,
written in MiniScript for [Mini Micro 2](https://github.com/JoeStrout/MiniMicro2).

Arrange balls, blocks and platforms on a pegboard, then hit play and watch
physics do the rest.

## Running

Contraption needs the Mini Micro 2 host, which supplies both the Mini Micro
API and the `physicsCore` intrinsics the physics engine runs on.  It expects
`MiniMicro2` and `raylib-miniscript` to be checked out alongside this repo:

    some-folder/
      contraption/
      MiniMicro2/
      raylib-miniscript/

Then:

1. `./tools/updateScripts` — refresh the shared libraries in `disk/lib` from
   the raylib-miniscript source tree.  (They are committed, so this is only
   needed when upstream changes.)
2. Launch the host: `../MiniMicro2/raylib-miniscript`
3. Mount the `disk` folder as `/usr`.
4. `run "contraption"`

## Controls

| | |
|---|---|
| drag from the palette | place a new part |
| drag a placed part | move it — it turns red where it will not fit |
| click a part | select it |
| Backspace / Delete | delete the selected part |
| wheel over the panel | scroll the palette |
| play / pause / stop | run, hold, and reset the simulation |
| Esc | quit |

## How it is put together

| file | |
|---|---|
| `disk/contraption.ms` | entry point: displays, level scenery, main loop |
| `disk/config.ms` | layout, tuning constants, colors |
| `disk/part.ms` | the `Part` base class |
| `disk/parts.ms` | Ball, Block, Platform, and the palette catalog |
| `disk/gameWorld.ms` | parts, physics, modes, collision queries, save/load |
| `disk/panel.ms` | the right-hand palette and transport buttons |
| `disk/editor.ms` | design-mode interaction |
| `disk/artUtil.ms` | procedurally drawn art, and its cache |
| `disk/util.ms` | identity-based list operations |
| `disk/lib/` | copies of shared libraries; see `tools/updateScripts` |

A part's authored state lives entirely in its `spec` map — position, angle,
and whatever else the type needs.  Nothing in the running simulation writes to
`spec`, which is what makes Stop a matter of putting the bodies back where the
spec says, and saving a design a matter of writing out each part's type name
and its spec.

The world runs in two modes.  Design mode never steps the simulation, but it
still needs collision detection so that parts cannot be placed overlapping;
that query runs the physics broadphase and narrowphase directly, without the
solver.  Play mode steps at a fixed 1/60s against an accumulator.
