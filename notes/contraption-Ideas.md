# Contraption

These are notes for a "The Incredible Machine" type game, where you arrange parts on a wall (pegboard) in addition to fixed parts for each puzzle, in order to complete some objective.

## Physics (Dynamics)

Virtually all objects participate in the physics collision/dynamics system.  Most objects are either fixed (static) or moveable.

+ fixed platforms
- ramps (or adjustable platforms that can be made into ramps)
+ various balls (different size, weight, and elasticity)
+ various blocks (like balls but rectangular instead of round)
+ balloons (bouyant, burst under too much heat or when poked)
+ levers (a rigid bar on a fixed fulcrum; seesaws, and off-center levers that trade travel for force)
+ balances (a lever carrying a level pan at each end; a ball rides a pan until the other end is loaded)
- ballternator -- flips back or forth on each ball drop, alternating which way it sends the ball

## Ropes and Pulleys

Taut ropes transfer force direction.  Loose ones are decorative.

+ rope
+ free pulley
+ fixed/mounted pulley
+ scissors
+ basket

## Electricity

A net is simply live or dead: no voltages, no currents, no component values.
Every part has one terminal and the pegboard frame is the return path, so
there is only one kind of connection and no cable/wire distinction to make.
Parts that sit *in line* -- switches, relays, fuses -- have two.  A wire is a
rope that never pulls, and hangs with 10% slack so it does not read as one.
See `notes/electrical-parts.md` for the whole plan.

- power outlet (the source; a wall socket, always live)
- wire
- switch (knife switch, pressure plate, pull chain)
- relay -- the part that buys the depth: NOT, AND, OR and memory fall out of it
- capacitor (a visible delay, not an R-C time constant)
- light bulb
- motor
- fan
- buzzer, electromagnet, solar panel, generator

## Wheels/Gears/Belts

Wheels can be connected with belts (which automatically resize to fit).  Gears are connected just by positioning them the right distance from each other.  Each gear/wheel has a *rotation* with speed and torque, transmitted through the connections.

+ wheels (various sizes), joined by belts; step pulleys, for the ratios; and a
  spool, to put a load on a train
+ gears (12, 18 and 24 teeth; they mesh by being placed next to each other)
- fan
+ motor (constant torque, stalls under a heavier load; see notes/torque-parts.md)
- generator (or maybe motor/generator is one?)

## Wind

Fans and bellows produce wind, which acts on flames and on very light objects that are nearby and in the right direction.  A windmill converts that to rotation.

- fan
- bellows
- sail car
- windmill

## Light

The room is normally lit (though it'd be cool if we could turn the room lights off).  But light sources (bulbs and candles) produce extra light within a small area, which can produce power in solar panels, and be focused through a lens to produce heat.

- light bulb
- candle
- solar panel
- lens

## Flame

Flammable things ignite when exposed to sufficient heat (unless the room air is set to vacuum).  Flames produce light and heat.  A few other things can also light flammables, e.g., we might have flint & steel, an explicit lighter, or a magic effect.

- candle
- fuse (burns slowly)
- rocket
- boiler

## Steam

The main elements here are a boiler (which produces pressure when heated) and pipes, which transmit pressure.

- boiler
- pipes
- valve
- piston (extends when pressurized)
- engine (converts pressure to rotation)

## Creatures

We'll have a handful of creatures with complex behaviors, following their own utility functions to move around and interact with other objects.

- mouse hole: emits one mouse if things have been quiet for several seconds, and there is cheese nearby.  Runs to the cheese.  Upon any threat (cat, loud noise, high heat), runs back to its hole.
- cat: starts asleep, wakes upon contact or loud noise.  Chases mouse and clockwork mouse; pushes things off of platforms and ledges.
- demon: adorable little guy like Beastie the BSD Daemon.  Appears in the Pentagram when all five candles have been lit; runs around the board causing mischief.  Loves to pop balloons, cut ropes, and light flammables.  Disappears if any of the 5 candles are extinguished, or if it can find no more mischief to do.

## Magic

There are lots of ways we could go here, but a simple one is:

- magic wand: a gloved hand holding a wand, which can be rotated in standard increments to point in various directions.  When tapped, the wand shoots a projectile of sparks which have various effects: ignite flammables, cause movable objects to levitate for a while, and cause static objects to briefly disappear.  Include fun animations like the cat freaking out when it levitates.  Consider some materials that the projectile bounces off of, allowing puzzles with banked shots.
