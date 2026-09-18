# Electrical parts: outlets, wires, switches and relays

The plan for the wired half of the machine.  Nothing here is built yet.

## The idea

Electricity is the only domain on the board that acts **at a distance,
instantly, with no geometry**.  A rope transmits force at a distance, but
only along its path and only in tension; a belt only between two rims; wind
and light are local and directional.  A wire is how the machine says "when
*that* happens over there, *this* happens over here", and that job is done
in full by one bit.

So: **a net is either live or dead.**  No voltages, no currents, no component
values.  Each frame, flood-fill outward from every live source through every
closed switch; whatever the fill reaches is powered.  This is the same shape
of code as `torque.ms` walking the link graph to find a train, minus the
solver -- there is no momentum to conserve and nothing to project, because
the answer is a boolean.

Two things follow, and they are the whole design:

- What makes a net live is **mechanical**.  The interesting work moves out of
  the electrics and into what closes the switch: a ball on a pressure plate,
  a lever throwing a knife switch, a rope on a pull chain, a solar panel lit
  through a lens, a generator on a gear train.
- What a live net does is **leave the domain again**.  A motor is already a
  hub in `torque.ms`; a bulb feeds the light domain; a fan feeds wind; a
  buzzer makes the loud noise that wakes the cat.  Electricity is plumbing
  between the other domains, not a domain to play in by itself.

## Why not the alternatives

**R-C analog.**  Every other part in this game is legible by looking at it:
you can see the lever is off centre, see the gears mesh, see the rope go
taut.  A time constant is a number the player can neither see nor estimate.
It also drags in component values everywhere -- once resistors have numbers,
so must bulbs, motors and outlets -- and that is a catalogue to balance, in a
game whose parts are otherwise balanced by shape.

**Logic levels and gates.**  A gate array on the pegboard is a second,
disconnected game glued to the side of this one: it does not touch the
physics, and wiring it with a mouse on a peg lattice is miserable.  We get
the same expressive power from the relay below, as a consequence of a part
you can watch click.

**Two-conductor cords and nothing else** -- the thin end -- is right about
the UX and wrong about the ceiling: all you can ever do with it is put a
switch in the line.

## One terminal, and the board is ground

The open question in `contraption-Ideas.md` was how to tell a two-conductor
power cable from a single-conductor wire.  The answer is not to have both.

Every part has **one terminal**, and the pegboard frame is the return path --
chassis ground, which is real-world plausible and halves the clutter on
screen.  Only parts that are *in line* need two: a switch, a fuse, a relay's
contacts.  A load and a source need one each.

This costs nothing, because series circuits are exactly the thing that wants
component values.  Two bulbs in series should be dim, and dimness is a
number; with no numbers, series has no meaning beyond "with a switch in it",
and that is the case the two-terminal parts cover.

## A wire is a rope that never pulls

A wire reuses the rope and belt machinery as it stands: a part that names two
others as `{part: id, tie: index}`, found in the editor through the existing
`LINKING` state and `linkTarget`, indexed by `byId`, deleted by `dependsOn`
when either end goes, drawn in layer 4 over the parts it is fastened to.
Scissors should cut one, and the demon should love doing so.

What it does *not* reuse is the constraint.  A wire is never taut: it is the
bead chain from `rope.ms` and nothing else, hanging under gravity, draping
over ledges one way, never pushing back.  That is most of `rope.ms` deleted
rather than anything new written.

**Wires hang loose on purpose**, which is the one place the editor should
differ from a rope.  A rope takes its length from the layout every frame
(`Rope.remeasure`) so that it is exactly taut and stays taut as things move.
A wire instead takes `config.wireSlack` times that length -- try **1.10** --
so a new connection sags a little, and goes on sagging when either end is
dragged.  A wire pulled *straight* would read as a rope, and a wire that
looks like a rope will be expected to pull like one.  Note this is not
`Rope.fixedLength`, which keeps one length forever; it is remeasure with a
factor, so the sag is proportional and a long run across the board droops
like one.

## The relay is the part worth having

A **relay** is a switch actuated by its own net: energise the coil and the
contacts move.  It is physically legible -- you can watch it click, and hear
it -- and it is the one part that buys real depth, because on its own it
gives:

- **NOT**, from normally-closed contacts;
- **AND**, from two relays in series;
- **OR**, from two in parallel;
- **memory**, from a relay wired through its own contacts to hold itself on
  until something else breaks the line.

A player who wants a latch can build one.  A player who does not need never
meet the word.  That is the whole argument for this level of complexity
rather than the one above it: digital behaviour *emerging* from a mechanical
part, instead of a digital vocabulary imposed on the board.

## The capacitor is a delay, not an ODE

Worth keeping, because puzzles want sequencing and this is the legible way to
get it: a capacitor charges while its net is live and keeps that net live for
`N` seconds after the source is cut, with the charge drawn on its face as a
meter so the player can watch the clock run down.  No R, no exponential, one
number the player can see.

The **resistor** should be cut.  With no values anywhere on the board it has
no job to do.

## Order of work

1. **The net solver and the first slice**: outlet, wire, pressure plate,
   motor, bulb.  Five parts, and they already reach two other domains --
   the motor is a `Gear` and needs only a `powered` gate on its torque, and
   the bulb is the light domain's first source.  Build the flood fill in a
   module of its own (`circuit.ms`, beside `torque.ms`) and call it from
   `GameWorld.advance` before the parts' `preStep` hooks, since a motor must
   know whether it is powered before the step it drives.

   The **outlet** is the source: a wall socket bolted to the board, drawn
   with two sockets like a real one, so it takes two cords without any part
   of the UI having to explain that a net may branch.  Always live.

2. **Switches**: the knife switch (thrown by anything that hits its handle),
   the pressure plate (closed while something rests on it), the pull chain
   (closed while the rope tied to it is taut -- which the rope solve already
   knows, since it is the tension clamp).  Each of these is a two-terminal
   in-line part and they differ only in what sets `closed`.

3. **Relay**, and with it whatever art says "this is a coil and those are
   contacts" at pegboard scale.  Normally-open and normally-closed as one
   part with a spec flag, since the difference is one boolean in the solve.

4. **Capacitor**, **buzzer**, **electromagnet**, **fan**, **solar panel**,
   **generator** -- each of which is a load or a source and adds nothing to
   the solver.  The generator is the interesting one: it is a hub, so it
   wants `torque.ms` to hand it the train's speed and the circuit to ask for
   power back, and that is the first two-way coupling between the two graphs.

## Known rough edges, in advance

- **Runtime state must not touch spec.**  A switch's `closed`, a relay's
  armature, a capacitor's charge and every part's `powered` live on the part
  and are cleared in `onStop`; what a switch is *authored* closed or open as
  is `spec.switchState`, exactly as the architecture note in `CLAUDE.md`
  already anticipates.
- **Feedback within one frame.**  A relay wired to break its own coil is a
  buzzer, and the flood fill will oscillate every frame.  Real ones do too,
  and it should sound like it -- but the fill must be a single pass over the
  graph as it stood at the start of the frame, not a fixed-point iteration,
  or a self-breaking relay will hang the solve.
- **Nets change when parts do.**  Cutting a wire changes the graph mid-play,
  the same way cutting a rope does; it should go through the existing
  `cutRope` / `applyRopeCuts` queue rather than editing the parts list from
  inside `advance`.
- A wire has no collision, so nothing can rest on one and a wire cannot hold
  anything up.  That is deliberate -- it is what keeps a wire from being
  mistaken for a rope -- but it means a wire draped over a moving part will
  pass through whatever else is in the way at the far end.
