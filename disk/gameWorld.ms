// gameWorld.ms
// The world: the parts in it, the physics that moves them, and the mode that
// says whether it is moving at all.

import "importUtil"
ensureImport ["config", "physics", "part", "parts", "torque", "circuit",
  "json", "util"]

// physicsCore is a native intrinsic where the host has one, and the
// MiniScript fallback (reachable through the physics module) where it does
// not.  We call into it directly for the design-mode overlap query.
if physics.hasIndex("physicsCore") then
	core = physics.physicsCore
else
	core = physicsCore
end if

globals.GameWorld = {}

GameWorld.DESIGN = 0
GameWorld.PLAY = 1
GameWorld.PAUSED = 2

GameWorld.make = function(partDisp)
	w = new GameWorld
	w.phys = physics.World.make(0, -config.gravity)
	w.phys.restitutionThreshold = config.restitutionThreshold
	w.parts = []
	w.byId = {}             // part id -> part, for the references ropes hold
	w.ropes = []            // the parts with a constraint to solve
	w.belts = []            // ...and the ones that are only drawn
	w.wires = []            // ...and the ones that carry current
	w.mode = GameWorld.DESIGN
	w.partDisp = partDisp
	// Scratch matrices for the overlap query, reused so that dragging does
	// not allocate a pair of matrices on every mouse move.
	w.pairScratch = Matrix.ofSize(0, 2)
	w.contactScratch = Matrix.ofSize(0, core.ContactColumns)
	w.leftover = 0      // unconsumed real time, carried between frames
	w.ropeCuts = []     // cuts asked for mid-step; see cutRope
	w.snapshot = null   // the design as it was when play began
	w.partsChanged = false
	w.trains = []       // the gear trains, rebuilt whenever the design changes
	w.torqueDirty = true
	w.circuitDirty = true   // ...and the nets, likewise; see solveCircuit
	return w
end function

//----------------------------------------------------------------------
// Parts
//----------------------------------------------------------------------

GameWorld.addPart = function(p)
	self.parts.push p
	self.byId[p.id] = p
	if p.isRope then self.ropes.push p
	if p.isBelt then self.belts.push p
	if p.isWire then self.wires.push p
	if self.mode != GameWorld.DESIGN then self.partsChanged = true
	if p.turns or p.isBelt then self.torqueDirty = true
	self.circuitDirty = true
	p.build self
	self.raiseFrontParts
	return p
end function

// Sprites on one display draw in list order, so the only way a part can be
// made to draw over the others is to keep its sprites at the end of the
// list.  There is no display slot left to give it instead: all eight are
// spoken for, and the ones above the parts (the drag layer, the panel, the
// selection overlay) are all things that must stay above it.
//
// So a part that draws in front is pushed back to the end whenever anything
// new is added to the layer, which is the only moment the order can change.
GameWorld.raiseFrontParts = function
	for p in self.parts
		if not p.drawsInFront or p.spriteDisp == null then continue
		if not refEquals(p.spriteDisp, self.partDisp) then continue
		for sp in p.sprites
			util.removeRef self.partDisp.sprites, sp
			self.partDisp.sprites.push sp
		end for
	end for
end function

// Take a part out, and with it anything that only made sense while it was
// there: the ropes tied to it, the pulleys bolted to it.
GameWorld.removePart = function(p)
	idx = util.indexOfRef(self.parts, p)
	if idx == null then return
	doomed = []
	for other in self.parts
		if not util.sameRef(other, p) and other.dependsOn(p) then doomed.push other
	end for
	p.destroy
	self.parts.remove idx
	self.byId.remove p.id
	if p.isRope then util.removeRef self.ropes, p
	if p.isBelt then util.removeRef self.belts, p
	if p.isWire then util.removeRef self.wires, p
	if p.turns or p.isBelt then self.torqueDirty = true
	self.circuitDirty = true
	if self.mode != GameWorld.DESIGN then self.partsChanged = true
	for d in doomed
		self.removePart d
	end for
end function

// Redraw whatever rides on `p`, now that `p` has moved.  One level deep: a
// pulley on a weight is the case this is for.
GameWorld.syncDependents = function(p)
	for other in self.parts
		if not util.sameRef(other, p) and other.dependsOn(p) then
			other.syncSprites
		end if
	end for
end function

GameWorld.partById = function(id)
	if not self.byId.hasIndex(id) then return null
	return self.byId[id]
end function

// The topmost part whose actual shape covers (x, y), or null.
GameWorld.partAt = function(x, y)
	shapes = self.phys.shapesAt(x, y)
	// shapesAt returns them topmost (highest shape id) first.
	for sh in shapes
		if sh.body.hasIndex("part") then return sh.body.part
	end for
	// Parts the physics cannot answer for: a rope has no shapes at all, and
	// a mounted pulley has no body of its own.  Last placed wins.
	for i in range(self.parts.len - 1, 0, -1)
		if self.parts[i].hitTest(x, y) then return self.parts[i]
	end for
	return null
end function

//----------------------------------------------------------------------
// Design-mode collision
//----------------------------------------------------------------------

// The parts whose shapes genuinely interpenetrate `p`'s.
//
// This runs the broadphase and narrowphase only -- no integration, no solver
// -- so it is exact for any shape we will ever add, and cheap enough to call
// on every mouse move.  World.step is no use here: it bails out on dt <= 0,
// and we do not want it advancing anything anyway.
//
// Note that this is only correct because design-mode bodies are all DYNAMIC
// (see Part.addBody): findPairs discards any pair of non-dynamic bodies.
GameWorld.overlapping = function(p)
	ph = self.phys
	if not ph.bodies or not p.bodies then return []
	ph.refreshGeometry
	pairCount = core.findPairs(ph.shapeData, ph.invMass, 0, self.pairScratch)
	if pairCount == 0 then return []
	core.collidePairs self.pairScratch, ph.shapeData, ph.vertData, 0, null,
	  self.contactScratch
	cm = self.contactScratch
	if cm.rows == 0 then return []

	mine = {}
	for b in p.bodies
		mine[b.index] = true
	end for
	bodyA = cm.getColumn(core.ColBodyA)
	bodyB = cm.getColumn(core.ColBodyB)
	sep = cm.getColumn(core.ColSep)
	hits = []
	for r in range(0, cm.rows - 1, 1)
		if sep[r] >= -config.overlapTolerance then continue
		ia = bodyA[r]; ib = bodyB[r]
		other = null
		if mine.hasIndex(ia) and not mine.hasIndex(ib) then
			other = ib
		else if mine.hasIndex(ib) and not mine.hasIndex(ia) then
			other = ia
		end if
		if other == null then continue
		b = ph.bodies[other]
		if not b.hasIndex("part") then continue
		if not util.containsRef(hits, b.part) then hits.push b.part
	end for
	return hits
end function

// Would `p` be legal where it now sits?  The part decides; this is the rule
// for the ordinary sort, which has a footprint and must keep it clear.
GameWorld.placementOK = function(p)
	return p.placementOK(self)
end function

GameWorld.footprintOK = function(p)
	bounds = p.designBounds
	if bounds[0] < 0 or bounds[1] < 0 then return false
	if bounds[0] + bounds[2] > config.fieldWidth then return false
	if bounds[1] + bounds[3] > config.fieldHeight then return false
	return self.overlapping(p).len == 0
end function

// Where a part dropped at (x, y) lands.  Again the part decides -- a mounted
// pulley snaps to a tie point rather than to the grid.
GameWorld.snap = function(p, x, y)
	return p.snapPose(self, x, y)
end function

// Snap a proposed center position so the part's footprint lands on the grid.
// Positions stay floats; this is the only place that quantizes them.
GameWorld.gridSnap = function(p, x, y)
	sz = p.size
	g = config.grid
	left = round((x - sz[0] / 2) / g) * g
	bottom = round((y - sz[1] / 2) / g) * g
	return [left + sz[0] / 2, bottom + sz[1] / 2]
end function

// Snap a proposed center position onto the pegboard lattice itself, instead
// of lining the part's footprint up with it.  For a part whose whole point is
// the single spot at its middle -- a tie point is one -- that middle is what
// has to land on a peg, and gridSnap would leave it half a footprint off, so
// that ropes run between pegs rather than along them.  `step` is for parts
// that need a finer lattice than the pegs themselves: a gear's axle lands
// between two pegs as readily as on one, because what it has to line up with
// is the next gear, not the board.
GameWorld.pegSnap = function(p, x, y, step=0)
	if step <= 0 then step = config.grid
	return [round(x / step) * step, round(y / step) * step]
end function

//----------------------------------------------------------------------
// Modes
//----------------------------------------------------------------------

GameWorld.play = function
	if self.mode == GameWorld.DESIGN then
		// Play may destroy parts -- scissors cut a rope in two, and a balloon
		// will one day pop -- and Stop has to be able to put them back.
		// Nothing else can restore a part that no longer exists, so the whole
		// design is written out here and read back if anything went.
		self.snapshot = self.save
		self.partsChanged = false
		self.torqueDirty = true
		self.circuitDirty = true
		for p in self.parts
			p.onPlay
		end for
	end if
	self.mode = GameWorld.PLAY
end function

GameWorld.pause = function
	if self.mode == GameWorld.PLAY then self.mode = GameWorld.PAUSED
end function

GameWorld.stop = function
	if self.mode == GameWorld.DESIGN then return
	self.mode = GameWorld.DESIGN
	self.ropeCuts = []
	self.torqueDirty = true
	self.circuitDirty = true
	for p in self.parts
		p.onStop
	end for
	// Mode is DESIGN again first, so that rebuilding does not itself look
	// like a change made during play.
	if self.partsChanged and self.snapshot != null then
		self.load self.snapshot
		self.partsChanged = false
	end if
	// A second pass, because a part that rides on another can only be put
	// back once the part underneath it has been.
	for p in self.parts
		p.syncSprites
	end for
end function

//----------------------------------------------------------------------
// Simulation
//----------------------------------------------------------------------

// Advance by `elapsed` seconds of real time, in fixed steps.  The leftover is
// carried, and a backlog past maxStepsPerFrame is dropped rather than chased,
// so a hitch cannot spiral into a slideshow.
GameWorld.advance = function(elapsed)
	if self.mode != GameWorld.PLAY then return
	dt = config.timestep
	self.leftover = self.leftover + elapsed
	steps = floor(self.leftover / dt)
	if steps > config.maxStepsPerFrame then steps = config.maxStepsPerFrame
	self.leftover = self.leftover - steps * dt
	if self.leftover > dt then self.leftover = dt
	for i in range(1, steps, 1)
		// Who is live, before anything reads it: a motor's drive torque is
		// the first thing preStep and the train solver ask about.
		self.solveCircuit
		// Parts first: preStep is where they set up what the step about to
		// run must see -- the restitution a bounce will use, the inertia a
		// lever's pan presents to something landing on it.
		for p in self.parts
			p.preStep dt
		end for
		self.phys.step dt
		self.solveRopes dt
		self.solveTorque dt
		for p in self.parts
			p.settle dt
			p.update dt
		end for
		if self.ropeCuts then self.applyRopeCuts
	end for
	for p in self.parts
		p.syncSprites
	end for
end function

// Work out which parts a live net reaches.  Cached like the trains are, and
// for the same reason: it only changes when the design does -- or, once
// there are switches and relays, when one of them moves, which is what
// setting circuitDirty from a part's own update will mean.  See circuit.ms.
GameWorld.solveCircuit = function
	if not self.circuitDirty then return
	self.circuitDirty = false
	circuit.solve self
end function

// Turn the gear trains through one step.  Each train is one degree of
// freedom held by projection, exactly as a lever's bar is, so like the rope
// solve this runs after the step whose contacts it has to answer for, and
// before the parts' own update hooks.  See torque.ms.
GameWorld.solveTorque = function(dt)
	if self.torqueDirty then
		self.trains = torque.build(self)
		self.torqueDirty = false
	end if
	for t in self.trains
		t.solve dt
	end for
end function

// Design mode: stand every gear at the angle that has its teeth meshing with
// its neighbors'.  Called when one is moved, because moving a gear can put it
// in mesh with one thing and out of mesh with another, and the phases of a
// whole train follow from wherever its first gear stands.
GameWorld.alignGears = function
	if self.mode != GameWorld.DESIGN then return
	self.trains = torque.build(self)
	self.torqueDirty = false
	for t in self.trains
		t.applyPhase
	end for
end function

// Cut a rope in two, between vertices i and i+1 of the line it is drawn
// along (see Rope.polyline), `t` of the way along that link.
//
// Queued rather than done on the spot, because whoever asks for it is a part
// in the middle of its own update hook, and cutting adds and removes parts --
// which would shift the very list advance is walking.
GameWorld.cutRope = function(rope, i, t)
	self.ropeCuts.push [rope, i, t]
end function

GameWorld.applyRopeCuts = function
	cuts = self.ropeCuts
	self.ropeCuts = []
	for c in cuts
		c[0].cutAt c[1], c[2]
	end for
end function

// Rope tension, solved after the step the contacts were solved in.
//
// Each rope is a single scalar constraint, but ropes that share a body pull
// on each other, so they are relaxed together: one pass to work out each
// rope's geometry and hand back the tension it was carrying, then a round of
// iterations over the lot.  It runs before the parts' own update hooks, so
// that a rope pulling on a lever arrives in time for the lever's pin to turn
// it into spin.
GameWorld.solveRopes = function(dt)
	if not self.ropes then return
	for r in self.ropes
		r.beginSolve dt
	end for
	for i in range(1, config.ropeIterations, 1)
		for r in self.ropes
			r.solveOnce dt
		end for
	end for
	// And then put the length right, by moving things rather than by asking
	// the impulses to do two jobs at once.
	for i in range(1, config.ropePosIterations, 1)
		for r in self.ropes
			r.solvePosition
		end for
	end for
end function

// Ropes are drawn from their own simulation, not from sprites, and it runs
// in every mode.  In design mode it also keeps each rope's length in step
// with the layout, so that moving something a rope is tied to shortens or
// lengthens the rope instead of leaving it slack.  Paused, nothing moves:
// the length is part of the run by then, and must not be touched.
GameWorld.updateRopes = function(dt)
	if self.mode == GameWorld.PAUSED then return
	designing = self.mode == GameWorld.DESIGN
	for r in self.ropes
		if designing then r.remeasure
		r.updateVisual dt
	end for
end function

// Ropes and belts are drawn from their own geometry rather than from sprites,
// onto the one layer above the parts -- so a rope lies over whatever it is
// tied to, and a belt is visibly wrapped around its wheels rather than
// vanishing behind their rims.
GameWorld.drawLinks = function(disp)
	disp.fillRect 0, 0, config.fieldWidth, config.fieldHeight, color.clear
	for b in self.belts
		b.draw disp
	end for
	for r in self.ropes
		r.draw disp
	end for
end function

// Every tie point in the world, as [part, index, x, y].  The editor shows
// these while a rope is being run.
GameWorld.tiePoints = function
	out = []
	for p in self.parts
		tl = p.tieList
		for i in tl.indexes
			w = p.tieWorld(i)
			if w != null then out.push [p, i, w[0], w[1]]
		end for
	end for
	return out
end function

// The wheel under (x, y), as [part, 0, cx, cy] -- the same shape a tie point
// comes back as, since running a belt is the same act as running a rope -- and
// the index is which of the hub's grooves was picked, so a step pulley is run
// exactly like anything else.  Only a hub with somewhere to put a belt
// answers; see Gear.beltRings.
GameWorld.hubAt = function(x, y)
	best = null
	bestD = 0
	for p in self.parts
		if not p.turns then continue
		rings = p.beltRings
		if not rings then continue
		c = p.hubWorld
		d = sqrt((c[0] - x) ^ 2 + (c[1] - y) ^ 2)
		// Anywhere on the part will do, since the grooves of a step pulley
		// are a few pixels apart and the outermost is its rim: what the click
		// has to choose is which one, not whether.
		lim = p.outerRadius
		if rings[rings.len - 1] > lim then lim = rings[rings.len - 1]
		if d > lim + 4 then continue
		if best == null or d < bestD then
			best = p
			bestD = d
		end if
	end for
	if best == null then return null
	// Which groove: the one the click is nearest to, measured out from the
	// axle.  Near the middle is the smallest, out at the rim the largest.
	rings = best.beltRings
	pick = 0
	for i in rings.indexes
		if abs(bestD - rings[i]) < abs(bestD - rings[pick]) then pick = i
	end for
	c = best.hubWorld
	return [best, pick, c[0], c[1]]
end function

// Every terminal in the world, as [part, index, x, y] -- the same shape a
// tie point comes back as, since running a wire is the same act as running a
// rope.  The editor shows these while a wire is being run.
GameWorld.terminals = function
	out = []
	for p in self.parts
		tl = p.terminalList
		for i in tl.indexes
			w = p.terminalWorld(i)
			if w != null then out.push [p, i, w[0], w[1]]
		end for
	end for
	return out
end function

GameWorld.terminalAt = function(x, y, range)
	best = null
	bestD = range * range
	for t in self.terminals
		d = (t[2] - x) ^ 2 + (t[3] - y) ^ 2
		if d <= bestD then
			bestD = d
			best = t
		end if
	end for
	return best
end function

// The tie point nearest (x, y) within `range` px, or null.  `skip` leaves a
// part's own tie points out: a mounted pulley's tie point sits exactly on top
// of the one it is mounted on, and would otherwise hide it.
GameWorld.tieAt = function(x, y, range, skip=null)
	best = null
	bestD = range * range
	for t in self.tiePoints
		if skip != null and util.sameRef(t[0], skip) then continue
		d = (t[2] - x) ^ 2 + (t[3] - y) ^ 2
		if d <= bestD then
			bestD = d
			best = t
		end if
	end for
	return best
end function

//----------------------------------------------------------------------
// Saving and loading
//----------------------------------------------------------------------

GameWorld.save = function
	out = []
	for p in self.parts
		if p.fixed then continue
		out.push p.save
	end for
	return json.toJSON(out)
end function

GameWorld.load = function(jsonString)
	doomed = []
	for p in self.parts
		if not p.fixed then doomed.push p
	end for
	for p in doomed
		self.removePart p
	end for
	for saved in json.parse(jsonString)
		self.addPart parts.fromSaved(saved)
	end for
end function
