// circuit.ms
// Which parts are live.
//
// Electricity here is one bit.  A net is live or it is dead; there are no
// voltages, no currents and no component values, and nothing in the game
// ever asks how much of anything is flowing.  That is a deliberate ceiling
// -- see notes/electrical-parts.md -- and what it buys is that the whole
// solve is a flood fill.
//
// The graph is over *terminals*, not parts.  A wire is an edge between the
// two terminals it was run between; a part with more than one terminal says
// for itself which of them it joins up inside (`Part.conducts`), which is
// what a switch is and, later, what a relay's contacts are.  A part whose
// `liveSource` is set -- an outlet -- seeds the fill at every terminal it
// has.  Everything the fill reaches is powered.
//
// Nothing here has a return path, because the pegboard frame is the return
// path: every load and every source has one terminal and grounds through the
// board.  Two terminals are for the parts that sit in line.  That is why
// there is only one kind of wire and no cable/conductor distinction to draw.
//
// This runs once per design change rather than once per step (see
// GameWorld.solveCircuit), which is all that is needed while nothing changes
// state mid-run.  A relay does change state mid-run, and the way it will ask
// for another fill is to set world.circuitDirty -- a single pass over the
// graph as it stood, never a fixed-point iteration, because a relay wired to
// break its own coil is a buzzer and must be allowed to chatter rather than
// hang the solve.

import "importUtil"
ensureImport ["config", "util"]

// A terminal's name in the graph.  Part ids are unique and survive a save,
// which is exactly what a key has to be.
nodeKey = function(part, i)
	return part.id + ":" + i
end function

addEdge = function(adj, a, b)
	if not adj.hasIndex(a) then adj[a] = []
	if not adj.hasIndex(b) then adj[b] = []
	adj[a].push b
	adj[b].push a
end function

// Work out what is live, and set `powered` on every part and wire.
solve = function(world)
	for p in world.parts
		p.powered = false
		p.liveTerms = []
	end for

	adj = {}
	seeds = []
	for p in world.parts
		n = p.terminalList.len
		if n == 0 then continue
		for i in range(0, n - 1, 1)
			for j in range(i + 1, n - 1, 1)
				if p.conducts(i, j) then addEdge adj, nodeKey(p, i), nodeKey(p, j)
			end for
			if p.liveSource then seeds.push nodeKey(p, i)
		end for
	end for
	for w in world.wires
		e = w.endpoints
		if e == null then continue
		addEdge adj, nodeKey(e[0][0], e[0][1]), nodeKey(e[1][0], e[1][1])
	end for

	live = {}
	queue = []
	for k in seeds
		if live.hasIndex(k) then continue
		live[k] = true
		queue.push k
	end for
	while queue
		k = queue.pull
		if not adj.hasIndex(k) then continue
		for m in adj[k]
			if live.hasIndex(m) then continue
			live[m] = true
			queue.push m
		end for
	end while

	// Per terminal as well as per part: a relay's coil has to be told apart
	// from its contacts, which are on the same part and on other nets
	// entirely.  See Part.termLive.
	for p in world.parts
		n = p.terminalList.len
		for i in range(0, n - 1, 1)
			on = live.hasIndex(nodeKey(p, i))
			p.liveTerms.push on
			if on then p.powered = true
		end for
	end for
	// A wire shows what it is carrying, which is the one piece of feedback
	// that says a connection took.  Both its ends are the same net, so
	// either one answers.
	for w in world.wires
		e = w.endpoints
		w.powered = e != null and live.hasIndex(nodeKey(e[0][0], e[0][1]))
	end for
end function
