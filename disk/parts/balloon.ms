//----------------------------------------------------------------------
// Balloon: an object that provides lift (in air), and can be popped.
//
// The art is two images: a flat gray balloon, which we tint to whatever
// color the spec asks for, and a highlight to lay over it.  The tint goes
// on the sprite rather than into a drawn image, so every balloon shares the
// two Images however many colors are in play.
//
// The highlight is where the light is, not where the balloon is facing, so
// it gets a sprite of its own that never turns: a balloon swinging on its
// string keeps its shine in the same corner, the way a real one does.
//
// POPPING is two questions asked of the skin, which is the traced outline
// below and its mirror image -- every vertex of the shape the physics uses.
// Something sharp inside it bursts it at once (see Part.sharpPoints: the
// blades of a pair of scissors are art and not shapes, so nothing in the
// physics knows they are there and the balloon has to ask).  Or any one
// point of it warms past its kindling point, which is heat.ms's arrangement
// exactly as a fuse uses it -- a warmth per sample point, cleared on Stop --
// except that what happens at the end of it is a bang rather than a flame.
//
// What is left is a half-faded picture of a burst for a moment and then
// nothing, the way a spent explosive lingers for its smoke: the sound and the
// picture are the whole of the effect, so the part has to outlive its own
// bodies for a moment.  The string is let go rather than deleted with us --
// see Rope.releaseFrom -- because whatever the balloon was lifting should
// fall, not vanish along with it.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "artUtil", "util", "heat"]

baseImg = file.loadImage("/usr/pics/balloon.png")
shineImg = file.loadImage("/usr/pics/balloon_shine.png")
burstImg = file.loadImage("/sys/pics/Burst.png")
popSnd = file.loadSound(config.balloon.popSound)

// The burst is drawn half solid, so that it reads as a flash over whatever
// the balloon was in front of rather than as another part.  It is a wash
// like the editor's, multiplied into the tint, since the sprite's tint is
// the only thing there is to say it with.
burstWash = color.fromList([255, 255, 255,
  floor(config.balloon.burstAlpha * 255)])

// The balloon's extent within the square art, in source pixels, measured out
// from the middle of the image so that the drawing is centered on the part's
// own center.  spec.width and spec.height say what that extent becomes on
// screen, and everything else here is a fraction of those.
//
// The default spec is these very numbers, so that a balloon draws its art
// pixel for pixel: artScale comes out at 1, and nothing is resampled.  A
// balloon authored at some other size still works, and will be scaled.
artWidth = 44
artHeight = 60

// The right-hand side of the balloon's outline, traced from the art, as
// fractions of width and height from the center: the bulb, then the taper
// down to the knot.  edgeLocals mirrors it and hands the lot to addPolygon,
// which takes the convex hull -- which a teardrop already is.
outline = [[0.102, 0.458], [0.250, 0.417], [0.352, 0.350], [0.420, 0.267],
  [0.477, 0.125], [0.443, 0.017], [0.386, -0.067], [0.307, -0.150],
  [0.239, -0.233], [0.159, -0.317], [0.068, -0.400], [0.034, -0.492]]

globals.Balloon = new Part
Balloon.typeName = "balloon"
Balloon.displayName = "Balloon"
// A balloon is mostly helium, which is lighter than the air it sits in, so
// it falls upwards: see preStep for how that is worked out, and how the
// damping below turns it into a steady climb rather than a launch.
Balloon.defaultSpec = Part.defaultSpec + {"width": artWidth, "height": artHeight,
  "color": "#FF4444", "density": 0.1, "airDensity": 0.6, "liftRise": 0.125,
  "restitution": 0.05, "friction": 0.7,
  "linearDamping": 16, "angularDamping": 8}

// Runtime, all of it cleared by clearRun.
Balloon.popped = false
Balloon.burstLeft = 0               // seconds the burst is still drawn for
Balloon.warmth = null               // per-instance: one per skin point

Balloon.init = function
	super.init
	self.clearRun
end function

Balloon.clearRun = function
	self.popped = false
	self.burstLeft = 0
	self.warmth = []
	for i in range(0, outline.len * 2 - 1, 1)
		self.warmth.push 0
	end for
end function

Balloon.size = function
	return [self.spec.width, self.spec.height]
end function

// What the art must be scaled by to come out at the part's size.
Balloon.artScale = function
	s = self.spec
	return [s.width / artWidth, s.height / artHeight]
end function

// The tie point on bottom: the knot, which is where a string goes.  A burst
// balloon has none, the way a spent explosive has none.
Balloon.tieLocals = function
	if self.popped then return []
	return [[0, -self.spec.height / 2]]
end function

// The skin: the traced outline and its mirror image, at the part's own size,
// in the part's own frame.  It is both the shape the physics sees and the
// line the popping is asked about, which is the point of having it in one
// place -- what bursts a balloon is something at its surface.
Balloon.edgeLocals = function
	s = self.spec
	pts = []
	for p in outline
		pts.push [p[0] * s.width, p[1] * s.height]
		pts.push [-p[0] * s.width, p[1] * s.height]
	end for
	return pts
end function

// The same points, wherever the balloon has got to.
Balloon.edgeWorld = function
	if not self.bodies then return []
	b = self.bodies[0]
	c = cos(b.angle); sn = sin(b.angle)
	o = b.position
	out = []
	for p in self.edgeLocals
		x = p[0] - b.localX; y = p[1] - b.localY
		out.push [o[0] + x * c - y * sn, o[1] + x * sn + y * c]
	end for
	return out
end function

Balloon.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addPolygon(self.edgeLocals, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

//----------------------------------------------------------------------
// Lift
//----------------------------------------------------------------------

// Where the gas that does the lifting has its center, in the part's own
// frame: up in the bulb, a few pixels above the center of mass of the
// balloon as a whole.  That gap is what keeps a balloon upright -- lift
// above weight is a pendulum hung the right way up -- and it is real: the
// helium is all in the bulb, while the skin and the knot hang below it.
Balloon.liftLocal = function
	return [0, self.spec.height * self.spec.liftRise]
end function

// Buoyancy: the air a balloon pushes aside weighs airDensity/density times
// what the balloon itself does, and that weight, pushing up, is the lift.
// So the net acceleration is (airDensity/density - 1) * gravity, upward,
// and spec.linearDamping is what it climbs against -- a balloon reaches the
// speed where the two balance (about 300 px/s, three meters per second,
// which is what a released helium balloon really does) in a fraction of a
// second, and holds it.  What it can carry is the difference between the
// two densities over its area: about 78 grams as authored above.
Balloon.preStep = function(dt)
	super.preStep dt
	s = self.spec
	for b in self.bodies
		f = s.airDensity / s.density * b.mass * config.gravity
		l = self.liftLocal
		a = b.angle
		c = cos(a); sn = sin(a)
		o = b.position
		b.applyForce 0, f, o[0] + l[0] * c - l[1] * sn,
		  o[1] + l[0] * sn + l[1] * c
	end for
end function

//----------------------------------------------------------------------
// Popping
//----------------------------------------------------------------------

Balloon.onPlay = function
	super.onPlay
	self.clearRun
end function

Balloon.onStop = function
	// Popping took our bodies out of the world.  Usually the reload puts them
	// back -- something was removed, so Stop reads the snapshot -- but a Stop
	// pressed while the burst is still on screen has nothing else to do it.
	if not self.bodies and self.world != null then
		self.makeBodies
		self.ties = null
		self.terms = null
	end if
	self.clearRun
	super.onStop
	self.showWhole
end function

Balloon.update = function(dt)
	super.update dt
	if self.popped then
		self.burstLeft = self.burstLeft - dt
		if self.burstLeft <= 0 then self.world.defer self, "sweep"
		return
	end if
	edge = self.edgeWorld
	if not edge then return
	// Both questions are asked, not just the first: a balloon may well be
	// held over a flame by the scissors that are about to close on it.
	hot = self.tooHot(edge, dt)
	if hot or self.prickedBy then self.world.defer self, "pop"
end function

// Is anything sharp inside our skin?  The point is put to the narrowphase
// rather than to the outline here, so that it is the shape the physics
// actually has -- the convex hull of those points -- that answers.
Balloon.prickedBy = function
	w = self.world
	for p in w.parts
		if util.sameRef(p, self) then continue
		for s in p.sharpPoints
			for sh in w.phys.shapesAt(s[0], s[1])
				if not sh.body.hasIndex("part") then continue
				if util.sameRef(sh.body.part, self) then return true
			end for
		end for
	end for
	return false
end function

// Has any one point of the skin taken enough heat?  Each keeps its own
// warmth, so a flame has to stay by the same patch of rubber rather than be
// waved along the side of the balloon.  See heat.ms.
Balloon.tooHot = function(edge, dt)
	out = false
	for i in edge.indexes
		if i >= self.warmth.len then break
		self.warmth[i] = heat.warm(self.warmth[i],
		  heat.at(self.world, edge[i][0], edge[i][1]), dt)
		if self.warmth[i] >= config.balloon.kindle then out = true
	end for
	return out
end function

Balloon.applyDeferred = function(what, arg)
	if what == "pop" then
		self.pop
	else if what == "sweep" then
		if self.world != null then self.world.removePart self
	else
		super.applyDeferred what, arg
	end if
end function

// Burst.  Queued rather than done on the spot, because letting the string go
// adds and removes parts: see GameWorld.defer.
Balloon.pop = function
	w = self.world
	if w == null or self.popped or not self.bodies then return
	b = self.bodies[0]
	x = b.x; y = b.y
	// Before the bodies go, since a rope works out where it has been cut from
	// where its tie points currently are.  Over a copy of the list, because
	// cutting rewrites it.
	for r in w.ropes[:]
		if r.dependsOn(self) then r.releaseFrom self
	end for
	self.popped = true
	self.burstLeft = config.balloon.burstTime
	for bd in self.bodies
		w.phys.removeBody bd
	end for
	self.bodies = []
	self.ties = null
	self.terms = null
	self.showBurst x, y
	if popSnd != null then
		pan = x / config.fieldWidth * 2 - 1
		if pan < -1 then pan = -1
		if pan > 1 then pan = 1
		popSnd.play config.balloon.popVolume, pan
	end if
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

// Three sprites on the one body: the balloon, tinted and turning with it;
// the highlight, which only ever moves; and the burst, which has no image
// until there is a burst to draw.
Balloon.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sc = self.artScale
	for img in [baseImg, shineImg]
		sp = new Sprite
		sp.image = img
		sp.scale = sc
		self.sprites.push sp
		self.spriteDisp.sprites.push sp
	end for
	sp = new Sprite
	bs = self.spec.width * config.balloon.burstScale / burstImg.width
	sp.scale = [bs, bs]
	self.sprites.push sp
	self.spriteDisp.sprites.push sp
	// Later sprites draw on top, so the shine is the second one.
	self.tintSprites
end function

// The balloon's own color is a tint, so anything the editor lays over it has
// to be multiplied in rather than assigned; the shine is white light and
// takes the wash alone.  The burst is white art, and takes the balloon's own
// color for the same reason the balloon does: it is what is left of it --
// half faded, see burstWash.
Balloon.tintSprites = function(wash="#FFFFFF")
	if self.sprites.len < 3 then return
	c = artUtil.multiply(self.spec.color, wash)
	self.sprites[0].tint = c
	self.sprites[1].tint = wash
	self.sprites[2].tint = artUtil.multiply(c, burstWash)
end function

Balloon.syncSprites = function
	if not self.bodies or self.sprites.len < 3 then return
	b = self.bodies[0]
	for sp in self.sprites
		sp.x = b.x
		sp.y = b.y
	end for
	self.sprites[0].rotation = b.angle * 180 / pi
	self.sprites[1].rotation = 0
end function

// The burst is left where the balloon was: it has no body to follow, and
// syncSprites does nothing once the bodies are gone.
Balloon.showBurst = function(x, y)
	if self.sprites.len < 3 then return
	self.sprites[0].image = null
	self.sprites[1].image = null
	self.sprites[2].image = burstImg
	self.sprites[2].x = x
	self.sprites[2].y = y
end function

Balloon.showWhole = function
	if self.sprites.len < 3 then return
	self.sprites[0].image = baseImg
	self.sprites[1].image = shineImg
	self.sprites[2].image = null
end function

Balloon.imageKey = function
	s = self.spec
	return "balloon:" + s.width + "x" + s.height + ":" + s.color
end function

// The palette icon: the same two images, baked into one at half size, since
// a balloon at full size would tower over the other rows.
Balloon.makeImage = function
	sc = self.artScale
	w = baseImg.width * sc[0] / 2; h = baseImg.height * sc[1] / 2
	g = artUtil.canvas(w, h)
	g.drawImage baseImg, 0, 0, w, h, 0, 0, baseImg.width, baseImg.height,
	  self.spec.color
	g.drawImage shineImg, 0, 0, w, h
	return g.getImage
end function
