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
// CATCHING is a walk along what is left, asking heat.ms how hot it is at
// points a few pixels apart.  Near an end, that end catches.  Anywhere else
// and the fuse comes apart into two fuses, each alight at the new end --
// which is what a real one does, and is the reason the burn is two numbers
// on a frozen polyline rather than one part creeping along.
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
Fuse.canRoute = false               // it cannot bend round a pulley...
Fuse.allowsLooseEnd = false         // ...and it wants a fastening at each end
Fuse.defaultSpec = Rope.defaultSpec + {"shape": null,
  "color": config.fuseColor}

// Runtime, all of it: px eaten from each end, and whether each is alight.
Fuse.eatenHead = 0
Fuse.eatenTail = 0
Fuse.litHead = false
Fuse.litTail = false
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
end function

// Take the line from the fastenings as soon as there are any, rather than
// waiting for design mode's next frame: a fuse with no shape yet has no
// length, and the editor asks for its length the moment it is made.
Fuse.build = function(world)
	super.build world
	self.remeasure
end function

//----------------------------------------------------------------------
// Polyline arithmetic.  All of it is on plain lists of [x, y] and none of it
// knows what a fuse is; if anything else ever wants it, it belongs in util.
//----------------------------------------------------------------------

segLen = function(a, b)
	return sqrt((b[0] - a[0]) ^ 2 + (b[1] - a[1]) ^ 2)
end function

polyLength = function(pts)
	if pts == null or pts.len < 2 then return 0
	total = 0
	for i in range(1, pts.len - 1, 1)
		total = total + segLen(pts[i-1], pts[i])
	end for
	return total
end function

lerpPt = function(a, b, f)
	return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
end function

// The piece of a polyline between two distances along it, or null if that is
// nothing at all.
trimPoly = function(pts, fromS, toS)
	if pts == null or pts.len < 2 or toS <= fromS then return null
	out = []
	s = 0
	for i in range(1, pts.len - 1, 1)
		a = pts[i-1]
		b = pts[i]
		d = segLen(a, b)
		if d <= 0 then continue
		s0 = s
		s = s + d
		lo = fromS
		if lo < s0 then lo = s0
		hi = toS
		if hi > s then hi = s
		if hi <= lo then continue
		if not out then out.push lerpPt(a, b, (lo - s0) / d)
		out.push lerpPt(a, b, (hi - s0) / d)
	end for
	if out.len < 2 then return null
	return out
end function

// Where a given distance along a polyline falls.
pointAt = function(pts, s)
	if pts == null or not pts then return null
	if s <= 0 then return [pts[0][0], pts[0][1]]
	acc = 0
	for i in range(1, pts.len - 1, 1)
		d = segLen(pts[i-1], pts[i])
		if d > 0 and acc + d >= s then
			return lerpPt(pts[i-1], pts[i], (s - acc) / d)
		end if
		acc = acc + d
	end for
	last = pts[pts.len - 1]
	return [last[0], last[1]]
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

Fuse.shapePoints = function
	return self.spec.shape
end function

Fuse.shapeLength = function
	return polyLength(self.spec.shape)
end function

// What has not burnt yet.
Fuse.remaining = function
	return trimPoly(self.spec.shape, self.eatenHead,
	  self.shapeLength - self.eatenTail)
end function

// Where a burning front has got to.  `head` picks which one.
Fuse.frontAt = function(head)
	if head then return pointAt(self.spec.shape, self.eatenHead)
	return pointAt(self.spec.shape, self.shapeLength - self.eatenTail)
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
	self.setLength polyLength(shape)
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
		rest.push segLen(pts[i-1], pts[i])
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
end function

Fuse.onStop = function
	super.onStop
	self.eatenHead = 0
	self.eatenTail = 0
	self.litHead = false
	self.litTail = false
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
	if not (self.litHead and self.litTail) then self.checkCatch
end function

// Walk what is left, a few pixels at a time, and see if any of it is in
// something hot enough.  The walk starts at the head, so a fuse lying in a
// flame at one end catches at that end rather than in the middle.
Fuse.checkCatch = function
	w = self.world
	if w == null or not w.heat then return
	pts = self.remaining
	if pts == null or pts.len < 2 then return
	L = polyLength(pts)
	step = config.fuseSampleStep
	s = 0
	while true
		p = pointAt(pts, s)
		if heat.at(w, p[0], p[1]) >= config.fuseLightHeat then
			// A catch that was swallowed as "this bit is already alight" is
			// not the end of the walk: something else further along -- a
			// candle against the middle of a fuse already burning at one end
			// -- still has to be found.
			if self.catchAt(self.eatenHead + s) then return
		end if
		if s >= L then return
		s = s + step
		// The far end always gets asked, however the length divides up: it is
		// the end that will be lying in whatever this fuse is meant to light,
		// and missing it by four pixels would be missing it entirely.
		if s > L then s = L
	end while
end function

// Something caught, `s` along the whole shape.  Near an end, that end is
// alight; anywhere else the fuse comes apart there.
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
	head = trimPoly(pts, self.eatenHead, s)
	tail = trimPoly(pts, s, L - self.eatenTail)
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
	f.setLength polyLength(shape)
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
		return [self.glowHead.sprite, self.glowTail.sprite,
		  self.sparkHead.sprites, self.sparkTail.sprites]
	end if
	return [self.sparkHead.sprites, self.sparkTail.sprites]
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
	L = polyLength(pts)
	e = config.fuseEmberLength
	if e > L / 2 then e = L / 2
	spans = []
	if self.litHead then spans.push [0, e]
	if self.litTail then spans.push [L - e, L]
	for sp in spans
		em = trimPoly(pts, sp[0], sp[1])
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
