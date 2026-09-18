// heat.ms
// What is hot, and what is near enough to catch.
//
// Heat here is points, not a field.  A part that is burning says so by
// handing back one or more *sources* -- a place, how far it reaches, and how
// fierce it is -- and a part that can catch fire asks how hot it is where it
// stands.  There is no diffusion, no temperature that rises and falls, and
// nothing cools down; a thing is either in reach of something hot enough or
// it is not.  That is the same ceiling circuit.ms puts on electricity and for
// the same reason: the puzzle is in the arrangement, not in the numbers, and
// a model with numbers in it would have to be explained to the player.
//
// The one number that is real is `power`, and it is there because it will
// have to be.  A candle can light a fuse; a lens focusing a lamp will have to
// light things a candle cannot.  So a source carries how fierce it is and
// whatever might catch carries what it takes -- one comparison, and the
// catalogue of what lights what stays a matter of two constants per part
// rather than of code.
//
// Sources are gathered once a step (GameWorld.advance) and thrown away
// again, because every one of them is somewhere a part currently is.
// Nothing here is cached between steps and nothing needs to be: the list is
// a handful of entries and the query is a distance test against each.
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

// How hot it is at a point: the fiercest source that reaches it, or zero.
// The fiercest rather than the sum, because two candles side by side are not
// a blowtorch -- what decides whether a thing catches is the hottest thing
// touching it.
at = function(world, x, y)
	best = 0
	for h in world.heat
		if h[3] <= best then continue
		dx = x - h[0]
		dy = y - h[1]
		if dx * dx + dy * dy <= h[2] * h[2] then best = h[3]
	end for
	return best
end function
