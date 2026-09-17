// gameWorld.ms
// The world: the parts in it, the physics that moves them, and the mode that
// says whether it is moving at all.

import "config"
import "physics"
import "part"
import "parts"
import "json"
import "util"

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
	p.build self
	return p
end function

GameWorld.removePart = function(p)
	idx = util.indexOfRef(self.parts, p)
	if idx == null then return
	p.destroy
	self.parts.remove idx
end function

// The topmost part whose actual shape covers (x, y), or null.
GameWorld.partAt = function(x, y)
	shapes = self.phys.shapesAt(x, y)
	// shapesAt returns them topmost (highest shape id) first.
	for sh in shapes
		if sh.body.hasIndex("part") then return sh.body.part
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

// Would `p` be legal where it now sits?  Off the playfield counts as not.
GameWorld.placementOK = function(p)
	bounds = p.designBounds
	if bounds[0] < 0 or bounds[1] < 0 then return false
	if bounds[0] + bounds[2] > config.fieldWidth then return false
	if bounds[1] + bounds[3] > config.fieldHeight then return false
	return self.overlapping(p).len == 0
end function

// Snap a proposed center position so the part's footprint lands on the grid.
// Positions stay floats; this is the only place that quantizes them.
GameWorld.snap = function(p, x, y)
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
		for p in self.parts
			p.settle dt
			p.update dt
		end for
	end for
	for p in self.parts
		p.syncSprites
	end for
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
