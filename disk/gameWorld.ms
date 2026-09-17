// gameWorld.ms
// The world: the parts in it, the physics that moves them, and the mode that
// says whether it is moving at all.

import "importUtil"
ensureImport ["config", "physics", "part", "parts", "json", "util"]

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
	w.mode = GameWorld.DESIGN
	w.partDisp = partDisp
	// Scratch matrices for the overlap query, reused so that dragging does
	// not allocate a pair of matrices on every mouse move.
	w.pairScratch = Matrix.ofSize(0, 2)
	w.contactScratch = Matrix.ofSize(0, core.ContactColumns)
	w.leftover = 0      // unconsumed real time, carried between frames
	return w
end function

//----------------------------------------------------------------------
// Parts
//----------------------------------------------------------------------

GameWorld.addPart = function(p)
	self.parts.push p
	self.byId[p.id] = p
	if p.isRope then self.ropes.push p
	p.build self
	return p
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

//----------------------------------------------------------------------
// Modes
//----------------------------------------------------------------------

GameWorld.play = function
	if self.mode == GameWorld.DESIGN then
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
	for p in self.parts
		p.onStop
	end for
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
		// Parts first: preStep is where they set up what the step about to
		// run must see -- the restitution a bounce will use, the inertia a
		// lever's pan presents to something landing on it.
		for p in self.parts
			p.preStep dt
		end for
		self.phys.step dt
		self.solveRopes dt
		for p in self.parts
			p.settle dt
			p.update dt
		end for
	end for
	for p in self.parts
		p.syncSprites
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

GameWorld.drawRopes = function(disp)
	disp.fillRect 0, 0, config.fieldWidth, config.fieldHeight, color.clear
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
