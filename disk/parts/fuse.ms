//----------------------------------------------------------------------
// Fuse: a cord between two fastenings, which burns.
//
// It is a Rope, for everything a Rope already knows how to be -- run from
// tie point to tie point in the editor, drawn on the links layer, cut by
// scissors, deleted along with whatever it is fastened to -- and it takes
// two things out.  It never pulls (`buildJacobian`, as a wire does), and it
// never hangs: there is no bead chain, ever.
//
// STIFF is the point of the part.  A rope and a wire droop, and a fuse that
// drooped could only ever light things lying on the floor.  So a fuse is
// pinned to the board along the line it was run: its geometry is a polyline
// in world coordinates (`spec.shape`), and while the machine is being built
// that line is taken from the fastenings every frame, so dragging a candle
// drags the fuse with it.  When play starts, nothing takes it from the
// fastenings any more and it simply stays where it is -- which is also what
// makes a burning fuse behave, since half a fuse still has to hang in the
// air exactly where the whole one was.
//
// BURNING is two numbers: how much has been eaten from the head end, and how
// much from the tail.  What is left is the shape trimmed by both, and when
// they meet, the fuse is gone.  Either end may be alight; a fuse tied
// between two lit candles burns from both.
//
// CATCHING is a walk along what is left, warming points a few pixels apart
// by however hot heat.ms says it is at each, and catching where one of them
// reaches its kindling point.  Near an end, that end catches.  Anywhere else
// and the fuse comes apart into two fuses, each alight at the new end --
// which is what a real one does, and is the reason the burn is two numbers
// on a frozen polyline rather than one part creeping along.
//
// ITS POINTS are of two kinds.  One is a tie point on a part, as a rope's
// are.  The other is a place on the board, pinned there in the editor with a
// shift-click, which only a stiff link can have: a rope fastened to thin air
// would simply fall off it, while a fuse pinned there stays.  That is what
// lets a run turn a corner in mid air and go wherever the puzzle needs it,
// rather than only from part to part.
//
// The front is itself a heat source, which is the whole of how a fuse lights
// the next thing: nothing here knows what a candle is.
//
// Splitting and burning away both add or remove parts, so both are queued
// rather than done where they are noticed -- see GameWorld.defer.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "artUtil", "util", "heat", "glow",
  "particles"]

glowImg = file.loadImage("/usr/pics/light-glow.png")

globals.Fuse = new Rope
Fuse.typeName = "fuse"
Fuse.displayName = "Fuse"
Fuse.canRoute = false               // it cannot bend round a pulley
Fuse.allowsLooseEnd = true
Fuse.allowsFreePoints = true        // ...but it may be pinned to the board
Fuse.defaultSpec = Rope.defaultSpec + {"shape": null,
  "color": config.fuseColor}

// Runtime, all of it: px eaten from each end, and whether each is alight.
Fuse.eatenHead = 0
Fuse.eatenTail = 0
Fuse.litHead = false
Fuse.litTail = false
Fuse.warmth = null                  // per-instance: sample index -> warmth
Fuse.hotSpot = null                 // runtime: [x, y, warmth] of the warmest
                                    // point, which is where it smokes
Fuse.smolder = null                 // per-instance; see makeSprites
Fuse.sparkHead = null               // per-instance; see makeSprites
Fuse.sparkTail = null
Fuse.glowHead = null
Fuse.glowTail = null

Fuse.init = function
	super.init
	self.eatenHead = 0
	self.eatenTail = 0
	self.litHead = false
	self.litTail = false
	self.warmth = {}
	self.hotSpot = null
end function

// Take the line from the fastenings as soon as there are any, rather than
// waiting for design mode's next frame: a fuse with no shape yet has no
// length, and the editor asks for its length the moment it is made.
Fuse.build = function(world)
	super.build world
	self.remeasure
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// A point is {part, tie} or {x, y}; see the header.  This replaces the base
// class's walk, which knows only the first kind.
Fuse.path = function
	out = []
	for p in self.spec.points
		if p.hasIndex("part") then
			part = self.world.partById(p.part)
			if part == null then return null
			w = part.tieWorld(p.tie)
			if w == null then return null
			out.push w
		else
			out.push [p.x, p.y]
		end if
	end for
	if out.len < 2 then return null
	return out
end function

// ...and a fuse is only deleted along with a part it is actually fastened to.
Fuse.dependsOn = function(other)
	for p in self.spec.points
		if p.hasIndex("part") and p.part == other.id then return true
	end for
	return false
end function

Fuse.shapePoints = function
	return self.spec.shape
end function

Fuse.shapeLength = function
	return util.polyLength(self.spec.shape)
end function

// What has not burnt yet.
Fuse.remaining = function
	return util.trimPoly(self.spec.shape, self.eatenHead,
	  self.shapeLength - self.eatenTail)
end function

// Where a burning front has got to.  `head` picks which one.
Fuse.frontAt = function(head)
	if head then return util.pointAt(self.spec.shape, self.eatenHead)
	return util.pointAt(self.spec.shape, self.shapeLength - self.eatenTail)
end function

// Design mode, every frame: take the line from the fastenings, so that the
// fuse follows what it is tied to.  A piece of a burnt one is fixedLength and
// keeps the shape it was cut with.
//
// The list is replaced rather than written into, because spec is what a save
// copies and what Stop restores, and nothing may edit one of those from
// underneath the other.
Fuse.remeasure = function
	if self.spec.fixedLength then return
	path = self.path
	if path == null or path.len < 2 then return
	shape = []
	for p in path
		shape.push [p[0], p[1]]
	end for
	self.spec.shape = shape
	self.setLength util.polyLength(shape)
end function

Fuse.measure = function
	return self.shapeLength
end function

// Stiff: it never hangs, so there are never any beads.
Fuse.updateVisual = function(dt)
	self.chain = null
end function

// It never pulls on anything, the same way a wire never does.
Fuse.buildJacobian = function
	self.jac = null
	self.tension = 0
	return false
end function

// What is left of it, in the form the scissors and the editor expect.
Fuse.polyline = function
	pts = self.remaining
	if pts == null or pts.len < 2 then return null
	rest = []
	for i in range(1, pts.len - 1, 1)
		rest.push util.segLen(pts[i-1], pts[i])
	end for
	return {"pts": pts, "pins": [0, pts.len - 1], "rest": rest}
end function

//----------------------------------------------------------------------
// Burning
//----------------------------------------------------------------------

Fuse.onPlay = function
	super.onPlay
	self.eatenHead = 0
	self.eatenTail = 0
	self.litHead = false
	self.litTail = false
	self.warmth = {}
	self.hotSpot = null
end function

Fuse.onStop = function
	super.onStop
	self.eatenHead = 0
	self.eatenTail = 0
	self.litHead = false
	self.litTail = false
	self.warmth = {}
	self.hotSpot = null
	if self.smolder != null then self.smolder.clear
	if self.sparkHead != null then self.sparkHead.clear
	if self.sparkTail != null then self.sparkTail.clear
end function

Fuse.update = function(dt)
	super.update dt
	L = self.shapeLength
	if L <= 0 then return
	if self.litHead then self.eatenHead = self.eatenHead + config.fuseBurnRate * dt
	if self.litTail then self.eatenTail = self.eatenTail + config.fuseBurnRate * dt
	if self.eatenHead + self.eatenTail >= L then
		self.world.defer self, "spent"
		return
	end if
	// Both ends alight: there is nothing left that could catch that is not
	// already burning.
	// Cleared here rather than in the walk, so that a fuse which returns
	// early from it -- nothing hot anywhere, or both ends already alight --
	// stops smoking rather than smoking on at the last place it was warm.
	self.hotSpot = null
	if not (self.litHead and self.litTail) then self.checkCatch dt
end function

// Walk what is left, a few pixels at a time, warming each point by however
// hot it is there and catching where one gets to config.fuseKindle.  The
// walk starts at the head, so a fuse lying in a flame at one end catches at
// that end rather than in the middle.
//
// The points are fixed along the whole shape -- the kth is k * fuseSampleStep
// from the head end as it was run -- rather than along what is left, so a
// point keeps its warmth while the fronts eat in from either end.  The far
// end is a point of its own (key -1), whatever the length divides into: it
// is the end that will be lying in whatever this fuse is meant to light, and
// missing it by four pixels would be missing it entirely.
//
// Only points that are warm at all are kept, and the map is rebuilt every
// step from those still on the fuse, so what has burnt away is forgotten.
Fuse.checkCatch = function(dt)
	w = self.world
	if w == null then return
	if not w.heat and not self.warmth then return
	shape = self.spec.shape
	if shape == null or shape.len < 2 then return
	a = self.eatenHead
	b = self.shapeLength - self.eatenTail
	if b <= a then return
	step = config.fuseSampleStep
	keys = []
	k = ceil(a / step)
	while k * step <= b
		keys.push k
		k = k + 1
	end while
	if not keys or keys[-1] * step < b then keys.push -1

	old = self.warmth
	self.warmth = {}
	caught = false
	for k in keys
		if k < 0 then pos = b else pos = k * step
		v = 0
		if old.hasIndex(k) then v = old[k]
		h = 0
		p = null
		if w.heat then
			p = util.pointAt(shape, pos)
			h = heat.at(w, p[0], p[1])
		end if
		if h == 0 and v == 0 then continue
		v = heat.warm(v, h, dt)
		// The warmest point is where the smoke comes off.  Worked out here
		// rather than kept sorted: the walk is already visiting every point.
		if self.hotSpot == null or v > self.hotSpot[2] then
			if p == null then p = util.pointAt(shape, pos)
			self.hotSpot = [p[0], p[1], v]
		end if
		// One catch a step.  A catch that was swallowed as "this bit is
		// already alight" does not count: something else further along -- a
		// lens on the middle of a fuse already burning at one end -- still
		// has to be found.
		if v >= config.fuseKindle and not caught then
			if self.catchAt(pos) then caught = true
		end if
		if v > 0.001 then self.warmth[k] = v
	end for
end function

// Something caught, `s` along the whole shape.  Near an end, that end is
// alight; anywhere else the fuse comes apart there.  False if the point was
// already on fire and there was nothing to do.
//
// A front burning within reach of `s` IS the fire that was found there: its
// own source is at the front and reaches `fuseHeatRadius` back down the cord
// it has already eaten.  Without this the walk, which starts at the head,
// finds a tail-burning fuse's own front a few pixels short of the end, calls
// that the middle, and splits the fuse behind its own flame -- every step,
// so a fuse burning tailwards ate itself several times faster than one
// burning headwards.  The same guard covers the two halves of a fresh split,
// whose fronts start out on top of each other.
Fuse.catchAt = function(s)
	slop = config.fuseEndSlop
	reach = config.fuseHeatRadius
	if self.litHead and s <= self.eatenHead + reach then return false
	if self.litTail and s >= self.shapeLength - self.eatenTail - reach then
		return false
	end if
	if s <= self.eatenHead + slop then
		self.litHead = true
		return true
	end if
	if s >= self.shapeLength - self.eatenTail - slop then
		self.litTail = true
		return true
	end if
	self.world.defer self, "split", s
	return true
end function

Fuse.applyDeferred = function(what, arg)
	if what == "spent" then
		if self.world != null then self.world.removePart self
	else if what == "split" then
		self.splitAt arg, true
	else
		super.applyDeferred what, arg
	end if
end function

// Cut by the scissors, between vertices i and i+1 of what is left.  The same
// coming-apart as a catch, except that a cut end is not on fire.
Fuse.cutAt = function(i, t)
	pl = self.polyline
	if pl == null or i >= pl.rest.len then return []
	s = pl.rest[i] * t
	for k in range(0, i - 1, 1)
		s = s + pl.rest[k]
	end for
	self.splitAt self.eatenHead + s, false
	return []
end function

// Two fuses where there was one, each keeping whatever fastening was at its
// own far end, and each alight at the new end if it was fire that parted
// them.
Fuse.splitAt = function(s, lightCut)
	w = self.world
	if w == null or w.partById(self.id) == null then return
	pts = self.spec.shape
	L = self.shapeLength
	head = util.trimPoly(pts, self.eatenHead, s)
	tail = util.trimPoly(pts, s, L - self.eatenTail)
	sp = self.spec.points
	headTie = []
	tailTie = []
	if sp != null and sp.len >= 1 then headTie = [{} + sp[0]]
	if sp != null and sp.len >= 2 then tailTie = [{} + sp[sp.len - 1]]
	litHead = self.litHead
	litTail = self.litTail
	col = self.spec.color
	w.removePart self
	if head != null then
		p = makeFusePiece(w, head, headTie, col)
		p.litHead = litHead
		p.litTail = lightCut
	end if
	if tail != null then
		p = makeFusePiece(w, tail, tailTie, col)
		p.litHead = lightCut
		p.litTail = litTail
	end if
end function

// A piece is fixedLength -- its shape is what it is and nothing recomputes it
// -- and freeEnd, which for a fuse means only that it is no longer fastened
// at both ends.
makeFusePiece = function(w, shape, ties, col)
	f = Fuse.make({"points": ties, "shape": shape, "freeEnd": true,
	  "fixedLength": true, "color": col})
	w.addPart f
	f.setLength util.polyLength(shape)
	return f
end function

// The front is what lights the next thing.  Nothing here knows what it might
// be lighting: see heat.ms.
Fuse.heatSources = function
	out = []
	for head in [true, false]
		if head then lit = self.litHead else lit = self.litTail
		if not lit then continue
		p = self.frontAt(head)
		if p == null then continue
		out.push heat.source(p[0], p[1], config.fuseHeatRadius, config.fuseHeat)
	end for
	return out
end function

//----------------------------------------------------------------------
// Appearance: sparks off each front, and a little light at it.  Both are
// the part's own sprites, so destroy and the layer restacking account for
// them; the fuse's line itself is drawn on the links layer like any rope's.
//----------------------------------------------------------------------

makeSparks = function
	ps = ParticleSystem.make(glowImg, config.sparkCount)
	ps.rate = config.sparkRate
	ps.life = config.sparkLife
	ps.lifeVar = config.sparkLifeVar
	ps.speed = config.sparkSpeed
	ps.speedVar = config.sparkSpeedVar
	ps.dir = pi / 2
	ps.spread = config.sparkSpread
	ps.accelY = config.sparkGravity
	ps.drag = config.sparkDrag
	ps.startScale = config.sparkStartScale
	ps.endScale = config.sparkEndScale
	ps.startTint = config.sparkHotColor
	ps.endTint = config.sparkCoolColor
	return ps
end function

Fuse.makeSprites = function
	self.spriteDisp = self.world.partDisp
	self.smolder = Smolder.make(glowImg)
	self.sprites.push self.smolder.sprites
	self.sparkHead = makeSparks
	self.sparkTail = makeSparks
	self.glowHead = Glow.make(glowImg, config.fuseGlowColor,
	  config.fuseGlowAlpha, config.fuseGlowScale, config.candleGlowFlicker)
	self.glowTail = Glow.make(glowImg, config.fuseGlowColor,
	  config.fuseGlowAlpha, config.fuseGlowScale, config.candleGlowFlicker)
	self.sprites.push self.glowHead.sprite
	self.sprites.push self.glowTail.sprite
	self.sprites.push self.sparkHead.sprites
	self.sprites.push self.sparkTail.sprites
	for sp in self.sprites
		self.spriteDisp.sprites.push sp
	end for
end function

// The two little pools of light go wherever every other pool of light goes,
// and the sparks go over everything: they are thrown into the air, not laid
// on the board.
Fuse.backSprites = function
	if config.glowInFront or self.glowHead == null then return []
	return [self.glowHead.sprite, self.glowTail.sprite]
end function

Fuse.frontSprites = function
	if self.sparkHead == null then return []
	if config.glowInFront then
		return [self.glowHead.sprite, self.glowTail.sprite, self.smolder.sprites,
		  self.sparkHead.sprites, self.sparkTail.sprites]
	end if
	return [self.smolder.sprites, self.sparkHead.sprites, self.sparkTail.sprites]
end function

// The sparks and the little light at each front are driven from the flags
// every frame, rather than switched on at the moment a flag changes.  That
// matters: a fuse that comes apart hands its two halves their fronts from
// outside (see splitAt), so a half that was born already alight never has a
// change to notice -- it would burn, and draw its ember, and throw no sparks
// at all.  Assigning what is already assigned costs nothing, and there is
// then no way for the two to drift apart.
Fuse.updateEffects = function(dt)
	if self.world == null or self.glowHead == null then return
	t = self.world.effectTime
	// The wisp off wherever the cord is warmest, which says the aim is good
	// before there is anything else to see.
	if self.smolder != null then
		if self.hotSpot == null then
			self.smolder.setHeat 0
		else
			self.smolder.moveTo self.hotSpot[0], self.hotSpot[1]
			self.smolder.setHeat self.hotSpot[2] / config.fuseKindle
		end if
		self.smolder.update dt
	end if
	for head in [true, false]
		if head then
			lit = self.litHead; ps = self.sparkHead; g = self.glowHead
		else
			lit = self.litTail; ps = self.sparkTail; g = self.glowTail
		end if
		ps.emitting = lit
		g.setLit lit, t
		if lit then
			p = self.frontAt(head)
			if p != null then
				ps.moveTo p[0], p[1]
				g.moveTo p[0], p[1]
			end if
		end if
		g.update t
		ps.update dt
	end for
end function

//----------------------------------------------------------------------
// Drawing
//----------------------------------------------------------------------

Fuse.drawWidth = function
	return config.fuseWidth
end function

Fuse.draw = function(disp)
	pts = self.remaining
	if pts == null then return
	c = self.drawColor
	w = self.drawWidth
	for i in range(0, pts.len - 2, 1)
		disp.line pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1], c, w
	end for
	// The last inch before a front, glowing.  Drawn over the cord rather than
	// instead of it, so the join never shows a gap.
	if not (self.litHead or self.litTail) then return
	L = util.polyLength(pts)
	e = config.fuseEmberLength
	if e > L / 2 then e = L / 2
	spans = []
	if self.litHead then spans.push [0, e]
	if self.litTail then spans.push [L - e, L]
	for sp in spans
		em = util.trimPoly(pts, sp[0], sp[1])
		if em == null then continue
		for i in range(0, em.len - 2, 1)
			disp.line em[i][0], em[i][1], em[i+1][0], em[i+1][1],
			  config.fuseEmberColor, w
		end for
	end for
end function

//----------------------------------------------------------------------
// Editor odds and ends.  The base class answers these out of `path` and the
// bead chain; a fuse has neither, only what is left of its line.
//----------------------------------------------------------------------

Fuse.designBounds = function
	pts = self.remaining
	if pts == null then return [self.spec.x, self.spec.y, 1, 1]
	x0 = pts[0][0]; y0 = pts[0][1]; x1 = x0; y1 = y0
	for p in pts
		if p[0] < x0 then x0 = p[0]
		if p[0] > x1 then x1 = p[0]
		if p[1] < y0 then y0 = p[1]
		if p[1] > y1 then y1 = p[1]
	end for
	return [x0 - 2, y0 - 2, x1 - x0 + 4, y1 - y0 + 4]
end function

Fuse.hitTest = function(x, y)
	pts = self.remaining
	if pts == null then return false
	for i in range(0, pts.len - 2, 1)
		if util.distToSegment(x, y, pts[i], pts[i+1]) < self.drawWidth + 3 then
			return true
		end if
	end for
	return false
end function

Fuse.imageKey = function
	return "fuse:" + self.spec.color
end function

// The palette icon: a length of cord, alight at one end.
Fuse.makeImage = function
	w = config.grid * 2
	h = config.grid * 2
	g = artUtil.canvas(w, h)
	pts = []
	for i in range(0, 16, 1)
		f = i / 16
		pts.push [2 + f * (w - 4), h / 2 + sin(f * 3 * pi) * 4]
	end for
	for i in range(0, pts.len - 2, 1)
		g.line pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1],
		  self.spec.color, config.fuseWidth
	end for
	for i in range(pts.len - 4, pts.len - 2, 1)
		g.line pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1],
		  config.fuseEmberColor, config.fuseWidth
	end for
	last = pts[pts.len - 1]
	artUtil.fillCircle g, last[0], last[1], 3, config.sparkHotColor
	return g.getImage
end function
