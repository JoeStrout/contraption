// heat.ms
// What is hot, and how near the things around it are to catching.
//
// Heat here is points, not a field.  A part that is burning says so by
// handing back one or more *sources* -- a place, how far it reaches, and how
// fierce it is -- and a part that can catch fire asks how hot it is where it
// stands.  There is no diffusion: heat goes from a source straight into
// whatever is in its reach, and nowhere else.
//
// What a thing that can catch does with that is WARM UP.  Each place that
// might catch -- a wick, a fuse's tip, a point every few pixels along a fuse
// -- carries a `warmth`, and a source's `power` is how fast it adds to the
// warmth of whatever is in reach, per second.  Warmth leaks away all the
// time, in proportion to how much there is (config.heatCoolTime), and when
// it reaches what the thing takes to catch -- its kindling point, one
// constant per part -- it is alight.  So:
//
//   A flame, which is fierce, lights a fuse in a tenth of a second or so:
//   near enough at once, as it always was.
//
//   A lens's focus, which is gentle, takes seconds -- and a fuse pulled out
//   of it before then cools off again rather than keeping what it had.
//
//   Anything too gentle never gets there at all, however long it is left,
//   because warmth stops rising where the leak matches the supply: at
//   power * heatCoolTime.  That is the one comparison the old model made,
//   and it is still what says a candle through a lens will not light a
//   fuse and a lamp through one will.
//
// Sources are gathered once a step (GameWorld.advance) and thrown away
// again, because every one of them is somewhere a part currently is.  The
// warmth is the only thing that lasts, and it belongs to the part that is
// warming, which keeps it as runtime state and clears it on Stop.
//
// Design mode never collects and never asks.  A fuse laid against a lit
// candle while the machine is being built must sit there unburnt, or the
// design would consume itself before it was finished.

import "importUtil"
ensureImport ["config"]

// A source is [x, y, radius, power].
source = function(x, y, radius, power)
	return [x, y, radius, power]
end function

// Ask every part what it has got that is hot.
collect = function(world)
	out = []
	for p in world.parts
		for h in p.heatSources
			out.push h
		end for
	end for
	world.heat = out
end function

// How fast it is warming at a point: every source that reaches it, added up,
// since two lenses focused on the one spot heat it twice as fast.
//
// A source does not stop at its rim.  It is at full power over the inner
// part of its reach and fades to nothing at the edge (config.heatFalloff),
// which is what gives the player room to work: parts land on grid lines and
// a focus lands wherever the optics put it, so "near enough" has to count
// for something.  Near enough warms more slowly, and far enough out never
// gets there at all, which is the right way round.
at = function(world, x, y)
	total = 0
	for h in world.heat
		dx = x - h[0]
		dy = y - h[1]
		d2 = dx * dx + dy * dy
		if d2 >= h[2] * h[2] then continue
		f = (h[2] - sqrt(d2)) / (h[2] * config.heatFalloff)
		if f > 1 then f = 1
		total = total + h[3] * f
	end for
	return total
end function

e = 2.718281828459045       // MiniScript has no exp

// A warmth, `dt` later, under `power`.  Solved exactly rather than stepped,
// so it neither overshoots nor depends on the timestep: warmth heads for
// power * coolTime -- where the leak would balance the supply -- and closes
// the gap by the same fraction every second.
warm = function(warmth, power, dt)
	tau = config.heatCoolTime
	target = power * tau
	return target + (warmth - target) * e ^ (-dt / tau)
end function
