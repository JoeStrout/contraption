// particles.ms
// Sprites that live briefly and then are born again: smoke, sparks, flame.
//
// A particle system is a fixed *pool* of sprites, allocated once and never
// added to or taken from after that.  A dead particle is not removed -- it
// simply has no image, which Sprite.draw returns on at once -- so nothing is
// allocated per particle, which at sixty frames a second is the cost that
// would matter.
//
// The pool is the system's `sprites`, and it goes on screen as *one entry*:
// a member of a SpriteDisplay's sprite list may itself be a list of sprites,
// drawn depth first, so the whole effect occupies a single place in the draw
// order and cannot be shuffled apart by anything reordering the layer.  That
// is also what makes the bookkeeping cheap: a standalone effect calls `addTo`
// and `removeFrom`, and an effect belonging to a part pushes `sprites` into
// the part's own sprite list as one entry, after which `Part.destroy`,
// `moveSpritesTo` and the layer restacking all account for it without
// knowing what it is.  The candle does that.
//
// WHAT A PARTICLE IS is an ordinary Sprite with a few more fields on it:
// `alive`, `age`, `life`, and a velocity.  The base class flies it on a
// straight ballistic arc and interpolates its scale and tint from one end of
// its life to the other, which covers most of what an effect wants.  A
// subclass that needs more overrides `spawn` and `step`; Flame, below, does
// both, because a flame is not ballistic -- it rises faster the hotter it
// is, and the hot part is where it started.

import "importUtil"
ensureImport ["config", "util"]

globals.ParticleSystem = {}

ParticleSystem.image = null         // what every particle is drawn with
ParticleSystem.sprites = null       // per-instance: the pool, live and dead
ParticleSystem.emitting = false     // whether new ones are being born
ParticleSystem.x = 0                // ...and where
ParticleSystem.y = 0
ParticleSystem.pending = 0          // fractional particles owed; see emit

// The shape of a particle's life.  All of it is per-instance and meant to be
// assigned after `make`; a subclass that wants something these cannot say
// overrides `spawn` and `step` instead of adding more knobs here.
ParticleSystem.rate = 20            // born per second while emitting
ParticleSystem.life = 1             // seconds, and how much that varies
ParticleSystem.lifeVar = 0
ParticleSystem.speed = 40           // px/sec at birth, and how much that varies
ParticleSystem.speedVar = 0
ParticleSystem.dir = pi / 2         // which way, in radians, and the half-angle
ParticleSystem.spread = 0           // of the cone it is scattered through
ParticleSystem.accelX = 0           // px/sec^2, applied for the whole life
ParticleSystem.accelY = 0
ParticleSystem.drag = 0             // fraction of speed shed per second
ParticleSystem.spawnRadius = 0      // born this far off the emitter, at random
ParticleSystem.startScale = 1       // scale and tint at birth...
ParticleSystem.endScale = 1         // ...and at the end, interpolated across
ParticleSystem.startTint = "#FFFFFFFF"
ParticleSystem.endTint = "#FFFFFF00"
// The tints between those two, worked out once and then looked up.  Mixing
// two colors means a call into raylib and a string built from the result,
// which is nothing once and a few thousand times a second here; sixteen
// steps is more than the eye can find in something that lives half a second.
// Assigning either tint above means clearing this.
ParticleSystem.tintSteps = 16
ParticleSystem.tints = null

// `count` is the ceiling on how many may be alive at once, which is also the
// number of sprites this costs forever.  rate * life is the number a steady
// emitter settles at, so a little over that is the right size.
ParticleSystem.make = function(image, count=24)
	ps = new self
	ps.image = image
	ps.sprites = []
	ps.pending = 0
	ps.tints = null
	for i in range(1, count, 1)
		p = new Sprite
		p.image = null
		p.alive = false
		p.age = 0
		p.life = 0
		p.vx = 0
		p.vy = 0
		ps.sprites.push p
	end for
	return ps
end function

//----------------------------------------------------------------------
// Getting on screen
//----------------------------------------------------------------------

// The pool goes on as one entry, and comes off as one.
ParticleSystem.addTo = function(disp)
	disp.sprites.push self.sprites
end function

ParticleSystem.removeFrom = function(disp)
	util.removeRef disp.sprites, self.sprites
end function

// Where new particles are born.  A part moves this to wherever the effect
// comes out of it -- a candle's wick -- every frame.
ParticleSystem.moveTo = function(x, y)
	self.x = x
	self.y = y
end function

//----------------------------------------------------------------------
// Running
//----------------------------------------------------------------------

ParticleSystem.update = function(dt)
	for p in self.sprites
		if not p.alive then continue
		p.age = p.age + dt
		if p.age >= p.life then
			self.kill p
		else
			self.step p, dt
		end if
	end for
	if self.emitting then self.emit dt
end function

// Hand out the whole life's worth at once: a puff of smoke, a spray of
// sparks.  Emitting need not be on, and nothing is owed afterwards.
ParticleSystem.burst = function(n)
	for i in range(1, n, 1)
		p = self.freeParticle
		if p == null then return
		self.spawn p
	end for
end function

// New particles for one frame's worth of time.  The fraction owed is carried
// rather than rounded, or a rate below one a frame would never fire at all.
ParticleSystem.emit = function(dt)
	self.pending = self.pending + self.rate * dt
	while self.pending >= 1
		self.pending = self.pending - 1
		p = self.freeParticle
		if p == null then
			// The pool is full: forget what is owed rather than let it pile
			// up, or the effect would fire a burst the moment it has room.
			self.pending = 0
			return
		end if
		self.spawn p
	end while
end function

ParticleSystem.freeParticle = function
	for p in self.sprites
		if not p.alive then return p
	end for
	return null
end function

ParticleSystem.kill = function(p)
	p.alive = false
	p.image = null      // ...which is what keeps it off the screen
end function

// Every particle, everywhere, at once: what a part does when it is stopped
// or taken out of the world.
ParticleSystem.clear = function
	for p in self.sprites
		self.kill p
	end for
	self.pending = 0
end function

//----------------------------------------------------------------------
// What one particle does.  These two are the subclass hooks.
//----------------------------------------------------------------------

ParticleSystem.spawn = function(p)
	p.alive = true
	p.age = 0
	p.image = self.image
	p.life = self.life + self.lifeVar * (rnd * 2 - 1)
	if p.life <= 0 then p.life = 0.01
	a = self.dir + self.spread * (rnd * 2 - 1)
	v = self.speed + self.speedVar * (rnd * 2 - 1)
	p.vx = v * cos(a)
	p.vy = v * sin(a)
	p.x = self.x
	p.y = self.y
	if self.spawnRadius > 0 then
		a = rnd * 2 * pi
		r = self.spawnRadius * sqrt(rnd)   // even over the disc, not the radius
		p.x = p.x + r * cos(a)
		p.y = p.y + r * sin(a)
	end if
	p.rotation = 0
	p.scale = self.startScale
	p.tint = self.startTint
end function

ParticleSystem.step = function(p, dt)
	p.vx = p.vx + self.accelX * dt
	p.vy = p.vy + self.accelY * dt
	if self.drag > 0 then
		k = 1 - self.drag * dt
		if k < 0 then k = 0
		p.vx = p.vx * k
		p.vy = p.vy * k
	end if
	p.x = p.x + p.vx * dt
	p.y = p.y + p.vy * dt
	self.shade p, p.age / p.life
end function

// How a particle looks a fraction `t` of the way through its life.  Split
// out from `step` so that a subclass can keep the look and change the
// flight, or the other way about.
ParticleSystem.shade = function(p, t)
	p.scale = self.startScale + (self.endScale - self.startScale) * t
	if self.tints == null then self.buildTints
	i = floor(t * self.tintSteps)
	if i < 0 then i = 0
	if i >= self.tintSteps then i = self.tintSteps - 1
	p.tint = self.tints[i]
end function

ParticleSystem.buildTints = function
	self.tints = []
	n = self.tintSteps
	for i in range(0, n - 1, 1)
		self.tints.push color.lerp(self.startTint, self.endTint, i / (n - 1))
	end for
end function

//----------------------------------------------------------------------
// Smolder: the thin wisp off something that is heating up and has not caught
// yet -- a fuse or a wick under a lens's focus.  It is the only sign the
// player gets that the aim is good and the waiting is worth it, so it starts
// well before the thing lights and thickens as it gets closer.
//
// It is an ordinary ballistic system with the numbers of smoke rather than
// of fire: slow, gray, spreading as it goes, and drifting up rather than
// climbing the way a flame does.
//----------------------------------------------------------------------

globals.Smolder = new ParticleSystem

Smolder.make = function(image)
	ps = super.make(image, config.smolder.count)
	ps.rate = config.smolder.rate
	ps.life = config.smolder.life
	ps.lifeVar = config.smolder.lifeVar
	ps.speed = config.smolder.speed
	ps.speedVar = config.smolder.speedVar
	ps.dir = pi / 2
	ps.spread = config.smolder.spread
	ps.accelY = config.smolder.rise
	ps.drag = config.smolder.drag
	ps.startScale = config.smolder.startScale
	ps.endScale = config.smolder.endScale
	ps.startTint = config.smolder.startColor
	ps.endTint = config.smolder.endColor
	return ps
end function

// How hard to smoke, given a warmth as a fraction of the kindling point.
// Nothing shows below the threshold; above it the trickle thickens, so that
// a fuse about to go is visibly closer than one merely warm.
Smolder.setHeat = function(frac)
	if frac < config.smolder.threshold then
		self.emitting = false
		return
	end if
	self.emitting = true
	f = (frac - config.smolder.threshold) / (1 - config.smolder.threshold)
	if f > 1 then f = 1
	self.rate = config.smolder.rate * (0.3 + 0.7 * f)
end function

//----------------------------------------------------------------------
// Flame: the one every fire in the game is built from.
//
// A flame is not a spray of debris and does not behave like one.  What makes
// it the shape it is, is that the gas is hottest where it started and cools
// as it goes: it is *buoyant*, so it accelerates upward the whole way rather
// than slowing under gravity, and it narrows as it rises because the hot
// column draws air in behind it.  So particles are born across the width of
// the wick and steer back toward its centerline as they climb, which is the
// taper, and they are born a lively yellow and end a dull red, which is the
// cooling.
//
// `dir`, `speed` and the accelerations are in world terms and stay upright
// no matter what the part holding the flame is doing.  A candle knocked on
// its side still burns straight up, which is correct and also the only thing
// that looks right.
//----------------------------------------------------------------------

globals.Flame = new ParticleSystem
Flame.taper = 6                     // how hard a particle is drawn inward

Flame.step = function(p, dt)
	// Toward the centerline, harder the further out it has drifted: the
	// column pinches closed above the wick.
	p.vx = p.vx + (self.x - p.x) * self.taper * dt
	p.vy = p.vy + self.accelY * dt
	p.x = p.x + p.vx * dt
	p.y = p.y + p.vy * dt
	self.shade p, p.age / p.life
end function
