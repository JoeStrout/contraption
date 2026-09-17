# Torque parts: gears, belt wheels, and motors

The plan for the rotating half of the machine.  Gears are implemented; belts
are designed here and not yet built.

## The idea

A gear, a belt wheel, and a motor are all the same kind of thing: a **hub**,
bolted to the pegboard, that turns.  Hubs are **linked** to each other, and a
set of linked hubs turns as one: every wheel's angular velocity is a fixed
multiple of every other's.  So a connected set of hubs -- a **train** -- has
exactly one degree of freedom, the same as a lever, and is held the same way:
by projection, after each physics step, since the engine has no joints.

Two kinds of link, both giving a ratio and nothing else:

- **mesh** (gear to gear): implicit.  Two toothed hubs mesh when their pitch
  circles touch -- centre distance within a couple of pixels of `R1 + R2`.
  Nothing is authored; you place them and they engage.  The ratio is
  `-N1/N2`: meshed gears turn opposite ways.
- **belt** (wheel to wheel): explicit, because a belt can reach across the
  board and only the player knows which wheels they meant.  A belt is a part
  that names two hubs, like a rope names two tie points.  The ratio is
  `+R1/R2` for an open belt and `-R1/R2` for a crossed one.

A **gearwheel** has both teeth and one or more belt rings, so it is a node
that can take either kind of link.  Nothing in the solver has to know: it
already works on a graph of ratios.

## What the solver does, once per step

`torque.ms` owns this; `GameWorld.solveTorque` calls it after `solveRopes`.

1. Trains are found by walking the link graph (breadth-first).  Each part in
   a train gets a **ratio** `r` relative to the train's reference hub, and a
   **phase** -- the angle it stands at when the train's own angle is zero.
2. If a cycle disagrees about a ratio (three gears in a triangle whose teeth
   do not divide out), the train is marked **locked** and does not turn at
   all.  Real gears jam the same way.
3. The step just taken has left each hub's body with whatever angular
   velocity the contacts gave it.  The train's momentum in its one
   coordinate is `P = sum(I_i * r_i * w_i)`, its moment is
   `M = sum(I_i * r_i^2)`, and driving torque contributes `sum(tau_i * r_i)`.
   Then `w = (P + gen * dt) / M`, capped by the lowest free-running speed
   any motor in the train imposes.
4. Each hub is put back on its axle -- position restored, linear velocity
   zeroed -- and given `angle = phase_i + r_i * theta` and
   `w_i = r_i * w`.

This is the lever's projection generalised, and it is two-way for the same
reason: a ball dropped on a gear spins the train, and a spinning train drags
a ball along by friction, because the hub bodies are ordinary dynamic bodies
between the projections.

## Teeth that actually line up

Teeth are art, not physics, but they have to look meshed.  When a train is
built, each child's phase is chosen so that a tooth of the parent lands in a
gap of the child at the point where the pitch circles touch.  With `u` the
fraction of a tooth the contact falls at on the parent, the child must sit at
`u' = 0.5 - u`, which fixes its angle to within a whole tooth; the whole
tooth left over is chosen to be the one nearest where the child already
stands, so nothing visibly jumps.

Since this is also done in design mode (`GameWorld.alignGears`, from
`Gear.setPose`), gears snap into mesh as you drag them, and Play changes
nothing.

## Units

Engine mass is density times area in pixels, so one kilogram is
`pxPerMeter^2` of it and one newton-metre of torque is `pxPerMeter^4`:
`config.torqueUnit`.  A motor's `torque` is authored in newton-metres, which
is the number that means something: divided by the radius it pulls on, it is
the load the motor stalls at.  3 N-m on a spool's 10 cm drum is 30 N, so the
motor lifts a kilogram at 20 px/s, two at 10, is held by three, and is walked
backwards by four.

Gears are light (a 40 cm gear weighs 150 g), so torque alone would take even
a weak motor to a blur in a step or two.  What gives it a speed is the other
half of the curve: its torque falls in a straight line from `torque` at a
standstill to nothing at `freeSpin`.  That is also what makes it behave under
load, since slowing down raises its torque until the two meet.

## Order of work

1. **Gears** (done): `Gear` and `Motor` in `parts/gears.ms`, the train solver
   in `torque.ms`, procedurally drawn art.  Three sizes -- 12, 18 and 24
   teeth, pitch radii 20, 30 and 40 px -- bolted to the board on a half-peg
   lattice.  Half, because a pair meshes at exactly the sum of its pitch
   radii (40, 50, 60, 70 or 80 px) and whole pegs cannot make 50 at all, in
   any direction; on halves every pair meshes straight across, and 12 against
   18 also meshes diagonally on the 30-40-50 triangle.
2. **Spool** (done): a `Gear` with a `drumRadius`, which is the only way a
   train can do work on anything that is not lying on top of it.  The rope
   solve needed two things for it: a runtime length (`Rope.curLen`) that a
   spool can wind, and a length *rate* in the velocity solve, so that a rope
   being taken in asks the load to move rather than to stand still.

   What stops a winch is `Spool.minLength`: the length may run ahead of the
   path it is measured along by a hair and no further, because a drum cannot
   take in rope the load is not giving it.  That covers the rope running out
   at the drum, the load reaching the drum, the load reaching anything else,
   and a rope tied to a fixed point, all with one rule -- and when it binds,
   `Train.applyStops` stops the whole train dead, in that direction only, so
   a stalled hoist still lowers.
3. **Belt wheels** (done): `Wheel` is a gear with no teeth, so nothing meshes
   with it and a belt is the only way in or out; `Belt` is a part that names
   two hubs.  The editor runs one exactly as it runs a rope, which is why
   that state is now `LINKING` rather than `ROPING` and picks its target
   through `linkTarget`.  `torque.ms` gained `beltPairs` and one more case
   where a link's ratio comes from, and the solver gained nothing at all.

   Drawing is the two lines that touch both wheels plus the wrap at each end.
   Both radii to such a line point the same way, so the tangent points are at
   `alpha +/- phi` from either centre with `cos(phi) = (Ra - Rb) / d` -- one
   angle rather than two.
4. **Gearwheels** (done): teeth and a belt groove on one part, and so the one
   part that is in a geared train and a belted one at once.  It did fall out
   of the two before it -- a `beltRadius` and a ring drawn on the face -- but
   it also settled a question they had left open: a plain gear now has *no*
   belt radius, because it is teeth the whole way round and teeth would chew a
   belt.  What takes a belt is a rim or a groove, which is what tells a wheel
   and a gearwheel from a gear.
5. **Step pulley** (done): three grooves on one hub, and the first part able
   to trade speed for force -- see the header of `parts/belts.ms` for why
   nothing before it could, and why this is a pulley rather than the compound
   gear a real gearbox would use.  A belt now records which groove it runs in
   at each end, since that is what the ratio is made of.

   It takes a gearwheel at each end to get from the motor into belt-land and
   back out to the spool, which is five parts for a reduction.  A compound
   gear would do it in one, and is the obvious thing to look at next: the
   difficulty is that whatever meshes its small half overlaps its big half, so
   it needs both a collision category of its own (as `Lever` has) and an
   editor that knows to allow the overlap.

6. **Belt slip**: a belt carries a limited tension, and past it the two ends
   turn at different rates -- which means a belt is not one train but two,
   coupled by a torque.  Worth having (it is how you stop a jammed train from
   stalling the whole machine), but only after belts work at all.

## Known rough edges

- A hub body is dynamic between projections, so a heavy part landing on a
  gear pushes it off its axle for one step before being put back, and sinks a
  little.  The lever has the same flaw.  If it shows, the fix is `Balance`'s:
  tell the solver the hub's inertia is the whole train's, and unpick the lie
  when reading the momentum back.
- A train is rebuilt from scratch when parts come or go during play, which
  resets its angle bookkeeping.  Only rope cuts and (later) popping balloons
  do that, and the wheels are put back where they already were, so the seam
  is invisible -- but it would not survive a part being added every step.
- The rope's path ends at the drum's *axle*, not at the tangent point on its
  rim, so a wound rope is up to `drumRadius` longer than it is drawn (the
  drawing trims it to the rim; `Rope.trimEnds`).  At a 10 px drum this is
  nothing; it would matter for a big one.
