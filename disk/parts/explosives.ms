//----------------------------------------------------------------------
// Explosives: a firecracker, which lies on its side, and a stick of
// dynamite, which stands up.  One base class, because the two differ only in
// their numbers and their picture.
//
// THE FUSE is the part's own, and it is drawn art rather than a Fuse.  It
// has to be: a Fuse is a line pinned to the board between two fastenings,
// and this one is a two-inch pigtail that must ride around with whatever it
// is stuck in.  So it is a polyline in the part's frame (`fuseLocals`, tip
// first), and burning it is one timer walked along that line.  What it buys
// is the delay: light a firecracker off a candle and you still have a second
// and a bit to be somewhere else, which is the whole of what makes an
// explosive a puzzle piece rather than a trap.
//
// Catching and chaining both go through heat.ms and neither knows what the
// other end is.  The cap asks how hot it is at the fuse *tip*, so a Fuse run
// to the tie point there lights it; the burning fuse is itself a source, so
// one explosive lights the next; and the fireball is a source too, briefly
// and over the whole blast radius, so a stick of dynamite sets off the fuses
// around it.
//
// THE BLAST is one instant, worked out in `detonate`.  Every body within
// reach takes an impulse falling off with the square of how far in it is,
// applied at the point of that body *nearest* the blast rather than at its
// middle -- which is where the pressure actually arrives, and is what tips a
// post over instead of sliding it.  Distance is measured to each shape's
// world bounding box, so a blast beside the end of a long platform is near
// it, which measuring to its center would get badly wrong.
//
// WHAT IT BREAKS is heat's arrangement over again: the blast carries a
// `power` and a part carries the power it takes to break it
// (`Part.breakPower`).  Only dynamite has any, which is what makes it the
// one thing in the game that destroys a block or a platform.  Nothing fixed
// is ever broken -- the level floor is not a puzzle piece.
//
// AFTERWARDS the part does not vanish, because the smoke and the sparks are
// its own sprites and would go with it.  It goes `spent` instead: its bodies
// are taken out of the world, its picture is blanked, and it lingers just
// long enough for the smoke to clear before asking to be removed.  Stop puts
// it back, the way it puts back a rope the scissors cut, because `play`
// wrote the design out before any of this happened.
//
// Taking bodies out and removing the part both change the list `advance` is
// walking, so both are queued -- see GameWorld.defer.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "artUtil", "physics", "util", "glow",
  "particles", "heat"]

glowImg = file.loadImage("/usr/pics/light-glow.png")

// Loaded once and shared by every stick on the board: raylib restarts a
// sound that is already playing, which for a blast is exactly right.
sounds = {}
soundFor = function(path)
	if not sounds.hasIndex(path) then sounds[path] = file.loadSound(path)
	return sounds[path]
end function

//----------------------------------------------------------------------

globals.Explosive = new Part
Explosive.typeName = "explosive"
Explosive.displayName = "Explosive"

// Tuning, all of it from config and all of it overridden by the two real
// types below.  These are class fields rather than spec, because they are
// what the *type* is rather than anything the player authors.
Explosive.fuseTime = 1.5            // seconds of fuse, once it catches
Explosive.blastRadius = 100
Explosive.blastImpulse = 300        // kg*px/s at ground zero; see config
Explosive.blastPower = 0            // what it is able to break
Explosive.breakRadius = 0           // ...and how close that has to be
Explosive.sparkCount = 24           // particles in the spray
Explosive.smokeCount = 0            // ...and in the cloud, 0 for none
Explosive.flashAlpha = 0.8
Explosive.flashScale = 0.3
Explosive.soundPath = null
Explosive.volume = 1
Explosive.fuseEnd = "boom"          // what the end of the fuse asks for: a
                                    // rocket's lights its motor, not its charge

// Runtime, all of it, and all of it cleared by onStop.
Explosive.lit = false               // the fuse is burning
Explosive.burnt = 0                 // px of it gone
Explosive.warmth = 0                // how near its tip is to catching; see heat.ms
Explosive.spent = false             // it has gone off
Explosive.blastX = 0                // where it went off, since the bodies are
Explosive.blastY = 0                // taken away at that moment
Explosive.fireTime = 0              // seconds the fireball is still hot
Explosive.lingerLeft = 0            // ...and until the wreck is swept up
Explosive.flashLeft = 0
Explosive.capSparks = null          // per-instance; see makeSprites
Explosive.smolder = null            // the wisp off a tip that is warming
Explosive.blastSparks = null
Explosive.smoke = null
Explosive.flash = null

Explosive.init = function
	super.init
	self.clearRun
end function

Explosive.clearRun = function
	self.lit = false
	self.warmth = 0
	self.burnt = 0
	self.spent = false
	self.fireTime = 0
	self.lingerLeft = 0
	self.flashLeft = 0
end function

//----------------------------------------------------------------------
// The fuse
//----------------------------------------------------------------------

// The fuse is a polyline in the part's own frame, the tip first and the
// point it enters the charge last -- measured off the drawn pixels, so the
// fire creeps along exactly the cord the picture shows.  See `art` below.
Explosive.fuseLength = function
	return util.polyLength(self.fuseLocals)
end function

// A rope or a Fuse is fastened at the tip, which is also where the cap asks
// whether it has caught: run a fuse there and the fire arrives where the
// fire should arrive.
Explosive.tieLocals = function
	if self.spent then return []
	f = self.fuseLocals
	if not f then return []
	return [[f[0][0], f[0][1]]]
end function

// A point of the part's own frame, wherever the part has been knocked to.
Explosive.localToWorld = function(lx, ly)
	if not self.bodies then return null
	b = self.bodies[0]
	c = cos(b.angle); sn = sin(b.angle)
	o = b.position
	x = lx - b.localX
	y = ly - b.localY
	return [o[0] + x * c - y * sn, o[1] + x * sn + y * c]
end function

// Where the fire on the fuse has got to: the tip before it is lit, creeping
// down toward the charge after.
Explosive.frontWorld = function
	p = util.pointAt(self.fuseLocals, self.burnt)
	if p == null then return null
	return self.localToWorld(p[0], p[1])
end function

//----------------------------------------------------------------------
// Heat: what it catches from, and what it lights in turn
//----------------------------------------------------------------------

Explosive.heatSources = function
	// The fireball, over the part of the blast radius that was fire rather
	// than pressure.  This is what sets off the fuses lying around a stick.
	if self.spent then
		if self.fireTime <= 0 then return []
		return [heat.source(self.blastX, self.blastY,
		  self.blastRadius * config.explosionHeatFrac, config.explosionHeat)]
	end if
	if not self.lit then return []
	f = self.frontWorld
	if f == null then return []
	return [heat.source(f[0], f[1], config.explosiveFuseHeatRadius,
	  config.explosiveFuseHeat)]
end function

//----------------------------------------------------------------------
// Running
//----------------------------------------------------------------------

Explosive.onPlay = function
	super.onPlay
	self.clearRun
end function

Explosive.onStop = function
	// Going off took our bodies out of the world, and Stop has to put the
	// whole design back.  Usually the reload does it -- something was broken,
	// so the snapshot comes back -- but a blast that broke nothing leaves the
	// design unchanged, and then this is the only thing that would.
	if not self.bodies and self.world != null then
		self.makeBodies
		self.ties = null
		self.terms = null
	end if
	// Before the base class, which puts the bodies back and redraws: our own
	// syncSprites does nothing while we are still spent.
	self.clearRun
	super.onStop
	if self.smolder != null then self.smolder.clear
	if self.capSparks != null then self.capSparks.clear
	if self.blastSparks != null then self.blastSparks.clear
	if self.smoke != null then self.smoke.clear
	if self.sprites then self.sprites[0].image = self.image
end function

Explosive.update = function(dt)
	super.update dt
	if self.spent then
		self.fireTime = self.fireTime - dt
		self.lingerLeft = self.lingerLeft - dt
		if self.lingerLeft <= 0 then self.world.defer self, "sweep"
		return
	end if
	if self.lit then
		// The fuse burns at the same rate everything else in the game does,
		// scaled so that its whole length is fuseTime -- which is the number
		// worth authoring, the drawn pigtail being only a few pixels long.
		L = self.fuseLength
		if self.fuseTime <= 0 then
			self.burnt = L
		else
			self.burnt = self.burnt + L / self.fuseTime * dt
		end if
		if self.burnt >= L then self.world.defer self, self.fuseEnd
		return
	end if
	self.checkCatch dt
end function

// Has the tip of the fuse soaked up enough heat to light?  See heat.ms.  Its
// own hook, so that a type which is busy -- a rocket in the air -- can
// decline to catch again without having to repeat the rest of `update`.
Explosive.checkCatch = function(dt)
	f = self.fuseLocals
	if not f then return
	t = self.localToWorld(f[0][0], f[0][1])
	if t == null then return
	self.warmth = heat.warm(self.warmth, heat.at(self.world, t[0], t[1]), dt)
	if self.warmth >= config.explosiveKindle then self.lit = true
	if self.smolder != null then self.smolder.moveTo t[0], t[1]
end function

Explosive.applyDeferred = function(what, arg)
	if what == "boom" then
		self.detonate
	else if what == "sweep" then
		if self.world != null then self.world.removePart self
	else
		super.applyDeferred what, arg
	end if
end function

//----------------------------------------------------------------------
// The blast
//----------------------------------------------------------------------

// The nearest point of a body's shapes to (x, y), as [distance, px, py], or
// null for a body with no shapes.  Shape.bounds is the world box the
// broadphase already keeps, so this costs nothing and is honest about a long
// platform, whose center is nowhere near its ends.
nearestOn = function(b, x, y)
	best = null
	for sh in b.shapes
		bd = sh.bounds
		px = x
		if px < bd[0] then px = bd[0]
		if px > bd[2] then px = bd[2]
		py = y
		if py < bd[1] then py = bd[1]
		if py > bd[3] then py = bd[3]
		d = sqrt((px - x) ^ 2 + (py - y) ^ 2)
		if best == null or d < best[0] then best = [d, px, py]
	end for
	return best
end function

Explosive.detonate = function
	w = self.world
	if w == null then return
	ch = self.chargeLocal
	c = self.localToWorld(ch[0], ch[1])
	if c == null then c = [self.spec.x + ch[0], self.spec.y + ch[1]]
	self.blastX = c[0]
	self.blastY = c[1]

	R = self.blastRadius
	// Stated in kg*px/s; engine mass is density times area in pixels, so a
	// kilogram of it is pxPerMeter^2.  See Weight.density.
	J = self.blastImpulse * config.pxPerMeter ^ 2
	doomed = []
	for p in w.parts
		if util.sameRef(p, self) or p.fixed then continue
		nearest = null
		for b in p.bodies
			n = nearestOn(b, c[0], c[1])
			if n == null then continue
			if nearest == null or n[0] < nearest then nearest = n[0]
			if n[0] >= R then continue
			// Square falloff: a blast is over almost at once, and a linear
			// one reaches much too far for how it looks.
			f = (1 - n[0] / R) ^ 2
			// Away from the blast, but delivered where the pressure arrives:
			// off-center, so the thing tumbles.
			m = b.centerOfMass
			u = util.unit(m[0] - c[0], m[1] - c[1])
			if u == null then u = [0, 1]
			b.applyImpulse J * f * u[0], J * f * u[1], n[1], n[2]
		end for
		if nearest != null and self.breakRadius > 0 and
		   nearest <= self.breakRadius and p.breakPower > 0 and
		   self.blastPower >= p.breakPower then
			doomed.push p
		end if
	end for
	for p in doomed
		w.removePart p
	end for

	self.spent = true
	self.lit = false
	self.fireTime = config.explosionFireTime
	self.lingerLeft = config.explosionLinger
	self.flashLeft = config.explosionFlashTime
	// The bodies go now: what is left is a cloud, and a cloud does not hold
	// anything up.  The part itself stays until the smoke has cleared.
	for b in self.bodies
		w.phys.removeBody b
	end for
	self.bodies = []
	self.ties = null
	self.terms = null

	if self.sprites then self.sprites[0].image = null
	if self.capSparks != null then self.capSparks.emitting = false
	if self.blastSparks != null then
		self.blastSparks.moveTo c[0], c[1]
		self.blastSparks.burst self.sparkCount
	end if
	if self.smoke != null then
		self.smoke.moveTo c[0], c[1]
		self.smoke.burst self.smokeCount
	end if
	self.playSound c[0]
end function

// Panned to where it happened, which costs one line and is most of what
// tells you which of three firecrackers has just gone.
playAt = function(path, vol, x)
	if path == null then return
	snd = soundFor(path)
	if snd == null then return
	pan = x / config.fieldWidth * 2 - 1
	if pan < -1 then pan = -1
	if pan > 1 then pan = 1
	snd.play vol, pan
end function

Explosive.playSound = function(x)
	playAt self.soundPath, self.volume, x
end function

//----------------------------------------------------------------------
// Effects
//----------------------------------------------------------------------

makeCapSparks = function
	ps = ParticleSystem.make(glowImg, config.capSparkCount)
	ps.rate = config.capSparkRate
	ps.life = config.capSparkLife
	ps.lifeVar = config.sparkLifeVar
	ps.speed = config.capSparkSpeed
	ps.speedVar = config.capSparkSpeedVar
	ps.dir = pi / 2
	ps.spread = pi
	ps.accelY = config.sparkGravity
	ps.drag = config.sparkDrag
	ps.startScale = config.capSparkStartScale
	ps.endScale = config.capSparkEndScale
	ps.startTint = config.sparkHotColor
	ps.endTint = config.sparkCoolColor
	return ps
end function

makeBlastSparks = function(count)
	ps = ParticleSystem.make(glowImg, count)
	ps.life = config.blastSparkLife
	ps.lifeVar = config.blastSparkLifeVar
	ps.speed = config.blastSparkSpeed
	ps.speedVar = config.blastSparkSpeedVar
	ps.dir = pi / 2
	ps.spread = pi
	ps.accelY = config.blastSparkGravity
	ps.drag = config.blastSparkDrag
	ps.startScale = config.blastSparkStartScale
	ps.endScale = config.blastSparkEndScale
	ps.startTint = config.sparkHotColor
	ps.endTint = config.sparkCoolColor
	return ps
end function

makeSmoke = function(count)
	ps = ParticleSystem.make(glowImg, count)
	ps.life = config.smokeLife
	ps.lifeVar = config.smokeLifeVar
	ps.speed = config.smokeSpeed
	ps.speedVar = config.smokeSpeedVar
	ps.dir = pi / 2
	ps.spread = pi
	ps.accelY = config.smokeRise
	ps.drag = config.smokeDrag
	ps.startScale = config.smokeStartScale
	ps.endScale = config.smokeEndScale
	ps.startTint = config.smokeStartColor
	ps.endTint = config.smokeEndColor
	return ps
end function

// The sprites are [picture, flash, cap sparks, blast sparks, smoke] -- the
// last three lists, which a SpriteDisplay draws depth first.  They go in the
// part's own list so that destroy, moveSpritesTo and the layer restacking
// account for them without knowing what they are; see particles.ms.
Explosive.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sp = new Sprite
	sp.image = self.image
	self.sprites.push sp

	self.flash = Glow.make(glowImg, config.sparkHotColor, self.flashAlpha,
	  self.flashScale)
	self.sprites.push self.flash.sprite

	self.smolder = Smolder.make(glowImg)
	self.sprites.push self.smolder.sprites
	self.capSparks = makeCapSparks
	self.blastSparks = makeBlastSparks(self.sparkCount)
	self.sprites.push self.capSparks.sprites
	self.sprites.push self.blastSparks.sprites
	if self.smokeCount > 0 then
		self.smoke = makeSmoke(self.smokeCount)
		self.sprites.push self.smoke.sprites
	end if

	for sp in self.sprites
		self.spriteDisp.sprites.push sp
	end for
end function

// Fire and smoke are thrown into the air, not laid on the board, so all of
// it goes over everything.
Explosive.frontSprites = function
	if self.flash == null then return []
	out = [self.flash.sprite, self.smolder.sprites, self.capSparks.sprites,
	  self.blastSparks.sprites]
	if self.smoke != null then out.push self.smoke.sprites
	return out
end function

Explosive.updateEffects = function(dt)
	if self.world == null or self.flash == null then return
	// Driven from the state every frame rather than switched at the moment it
	// changes, for the reason Fuse.updateEffects gives: nothing can then
	// drift out of step with what the part is actually doing.
	// The wisp while the cap is warming, and nothing once it has caught.
	if self.lit or self.spent then
		self.smolder.setHeat 0
	else
		self.smolder.setHeat self.warmth / config.explosiveKindle
	end if
	self.smolder.update dt
	self.capSparks.emitting = self.lit and not self.spent
	if self.capSparks.emitting then
		f = self.frontWorld
		if f != null then self.capSparks.moveTo f[0], f[1]
	end if
	self.capSparks.update dt
	self.blastSparks.update dt
	if self.smoke != null then self.smoke.update dt

	// The flash: brightest at once, spreading as it dies, gone in a fifth of
	// a second.  Glow has no fade of its own, so this drives its alpha and
	// scale directly and re-applies them.
	if self.flashLeft > 0 then
		self.flashLeft = self.flashLeft - dt
		t = self.flashLeft / config.explosionFlashTime
		if t < 0 then t = 0
		self.flash.setLit true
		self.flash.moveTo self.blastX, self.blastY
		self.flash.alpha = self.flashAlpha * t
		self.flash.scale = self.flashScale *
		  (config.explosionFlashGrowth - (config.explosionFlashGrowth - 1) * t)
		self.flash.apply 0
	else
		self.flash.setLit false
	end if
end function

// One sprite on one body -- until there is no body, at which point the
// picture is gone anyway and the effects run off the blast point.  The
// picture's own middle is not the part's origin (the origin is the middle of
// what is *drawn*, and the frame has margins), so it carries an offset.
Explosive.syncSprites = function
	if self.spent or not self.bodies or not self.sprites then return
	b = self.bodies[0]
	off = self.spriteOffset
	c = cos(b.angle); sn = sin(b.angle)
	sp = self.sprites[0]
	sp.x = b.x + off[0] * c - off[1] * sn
	sp.y = b.y + off[0] * sn + off[1] * c
	sp.rotation = b.angle * 180 / pi
end function

Explosive.tintSprites = function(wash="#FFFFFF")
	if not self.sprites then return
	self.sprites[0].tint = wash
	if self.flash != null then self.flash.setWash wash
end function

// Carried across the board, the sparks would otherwise stay where they were
// born: they are in world coordinates and know nothing of the part.
Explosive.setPose = function(x, y, angle=null)
	super.setPose x, y, angle
	if self.capSparks != null then self.capSparks.clear
end function

//----------------------------------------------------------------------
// The art, and the geometry taken from it.
//
// The picture is the authority, exactly as it is for the candle: the boxes
// the physics uses and the line the fuse burns along are both measured off
// the drawn pixels, in image coordinates (y-down from the top-left corner),
// and converted here.  A part's origin is the middle of what is *drawn*
// rather than of the frame it is drawn in, which is why the sprite carries an
// offset at all.
//----------------------------------------------------------------------

// Image pixels to the part's own frame: y-up, from that origin.
toLocal = function(origin, x, y)
	return [x - origin[0], origin[1] - y]
end function

// A rect given as [left, top, right, bottom] in image pixels, as
// [width, height, centerX, centerY] in the part's frame -- which is what
// Body.addBox wants.
toBox = function(origin, r)
	mid = toLocal(origin, (r[0] + r[2] + 1) / 2, (r[1] + r[3] + 1) / 2)
	return [r[2] - r[0] + 1, r[3] - r[1] + 1, mid[0], mid[1]]
end function

// The middle of a rect of image pixels, which is where a part's origin goes.
originOf = function(r)
	return [(r[0] + r[2] + 1) / 2, (r[1] + r[3] + 1) / 2]
end function

sizeOf = function(r)
	return [r[2] - r[0] + 1, r[3] - r[1] + 1]
end function

toPoly = function(origin, pts)
	out = []
	for p in pts
		out.push toLocal(origin, p[0], p[1])
	end for
	return out
end function

// Everything a type needs off one picture, as one map, so that re-exporting
// the art means changing the pixel rects here and nothing else.
measure = function(img, frame, artPix, chargePix, fusePix, boxesPix=null)
	o = originOf(artPix)
	// The charge is the one box most things are, so it stands in when a type
	// does not say otherwise; a rocket is a tube and a stick and needs two.
	if boxesPix == null then boxesPix = [chargePix]
	boxes = []
	for r in boxesPix
		boxes.push toBox(o, r)
	end for
	return {"img": img, "size": sizeOf(artPix), "origin": o,
	  "charge": toBox(o, chargePix), "boxes": boxes,
	  "fuse": toPoly(o, fusePix),
	  "off": toLocal(o, frame[0] / 2, frame[1] / 2)}
end function

// Subclass hook: the one map a type has to hand back.  Everything else --
// its footprint, its body, its fuse, where the blast comes from -- falls out
// of it, so a type is its picture plus its numbers and nothing besides.
Explosive.art = function
	return null
end function

Explosive.size = function
	return self.art.size
end function

Explosive.spriteOffset = function
	return self.art.off
end function

Explosive.fuseLocals = function
	return self.art.fuse
end function

Explosive.chargeLocal = function
	a = self.art.charge
	return [a[2], a[3]]
end function

Explosive.image = function
	return self.art.img
end function

Explosive.makeBodies = function
	s = self.spec
	b = self.addBody
	for a in self.art.boxes
		sh = b.addBox(a[0], a[1], a[2], a[3], 0, s.density)
		sh.setRestitution s.restitution
		sh.setFriction s.friction
	end for
end function

//----------------------------------------------------------------------
// Firecracker: a paper tube on its side, and a small sharp pop.
//----------------------------------------------------------------------

globals.Firecracker = new Explosive
Firecracker.typeName = "firecracker"
Firecracker.displayName = "Firecracker"
Firecracker.defaultSpec = Part.defaultSpec + {"density": 0.8,
  "restitution": 0.15, "friction": 0.6, "linearDamping": 0.02,
  "angularDamping": 0.1}

Firecracker.fuseTime = config.firecrackerFuseTime
Firecracker.blastRadius = config.firecrackerBlastRadius
Firecracker.blastImpulse = config.firecrackerImpulse
Firecracker.blastPower = config.firecrackerPower
Firecracker.breakRadius = config.firecrackerBreakRadius
Firecracker.sparkCount = config.firecrackerSparks
Firecracker.smokeCount = config.firecrackerSmoke
Firecracker.flashAlpha = config.firecrackerFlashAlpha
Firecracker.flashScale = config.firecrackerFlashScale
Firecracker.soundPath = config.firecrackerSound
Firecracker.volume = config.firecrackerVolume

// The tube lies along the frame with its pigtail waving off to the right, so
// the fuse is measured right to left: the tip first, as fuseLocals wants.
fcArt = measure(file.loadImage("/usr/pics/firecracker_40x12.png"), [40, 12],
  [1, 1, 38, 10],                     // all of it, pigtail included
  [1, 1, 27, 10],                     // the tube the physics sees
  [[38.5, 5.5], [36, 4.5], [32, 4.5], [28, 5.5]])

Firecracker.art = function
	return fcArt
end function

//----------------------------------------------------------------------
// Dynamite: a bundle standing on end, and a blast that takes the wall out.
//----------------------------------------------------------------------

globals.Dynamite = new Explosive
Dynamite.typeName = "dynamite"
Dynamite.displayName = "Dynamite"
Dynamite.defaultSpec = Part.defaultSpec + {"density": 1.5,
  "restitution": 0.05, "friction": 0.7, "linearDamping": 0.02,
  "angularDamping": 0.1}

Dynamite.fuseTime = config.dynamiteFuseTime
Dynamite.blastRadius = config.dynamiteBlastRadius
Dynamite.blastImpulse = config.dynamiteImpulse
Dynamite.blastPower = config.dynamitePower
Dynamite.breakRadius = config.dynamiteBreakRadius
Dynamite.sparkCount = config.dynamiteSparks
Dynamite.smokeCount = config.dynamiteSmoke
Dynamite.flashAlpha = config.dynamiteFlashAlpha
Dynamite.flashScale = config.dynamiteFlashScale
Dynamite.soundPath = config.dynamiteSound
Dynamite.volume = config.dynamiteVolume

// The bundle stands upright with its fuse out of the top, so the fuse is
// measured downward: the tip first.  The binding at its foot (rows 11-13 of
// the picture) is part of the fuse, not of the charge.
dyArt = measure(file.loadImage("/usr/pics/dynamite_36x56.png"), [36, 56],
  [1, 2, 34, 53],                     // all of it, fuse included
  [1, 14, 34, 53],                    // the three sticks the physics sees
  [[17.5, 2.5], [18.5, 5], [18, 9], [17.5, 13]])

Dynamite.art = function
	return dyArt
end function

//----------------------------------------------------------------------
// Rocket: an explosive that goes somewhere first.
//
// Its fuse lights the MOTOR rather than the charge.  For rocketFlightTime it
// climbs under a thrust applied along its own axis, at its center of mass --
// so the motor drives it without ever turning it, and where it is pointed is
// where it goes -- and then it goes off like a small stick of dynamite,
// wherever it has got to.  The exhaust is thrown out of the nozzle in world
// coordinates and left behind, which is what draws the trail, and it is hot,
// so a rocket lights fuses as it passes them.
//
// Until then it is PINNED: it stands on the board and neither falls over nor
// falls down.  There is no joint in the engine to do that with, so it is the
// same projected constraint Lever uses -- the body stays DYNAMIC and is put
// back on its authored pose after every step -- and that is also what makes
// the pin breakable.  What the step left in the body's velocity is exactly
// what the collision or the blast was worth; over rocketFreeSpeed (or
// rocketFreeSpin) the rocket is let go instead of put back.  A STATIC body
// would hold it just as still and could tell us none of that: impulses do
// not touch one, so a blast beside it would register as nothing at all.
//
// It is aimed straight up, because there is nothing in the editor yet that
// would let a player aim it.  Nothing here assumes that: the thrust, the
// exhaust and the pin are all in the part's own frame, so an angle in the
// spec is all it will take.
//----------------------------------------------------------------------

globals.Rocket = new Explosive
Rocket.typeName = "rocket"
Rocket.displayName = "Rocket"
Rocket.defaultSpec = Part.defaultSpec + {"density": 0.5,
  "restitution": 0.2, "friction": 0.6, "linearDamping": 0.02,
  "angularDamping": 0.4}

Rocket.fuseTime = config.rocketFuseTime
Rocket.fuseEnd = "launch"           // the fuse reaches the motor, not the charge
Rocket.blastRadius = config.rocketBlastRadius
Rocket.blastImpulse = config.rocketImpulse
Rocket.blastPower = config.rocketPower
Rocket.breakRadius = config.rocketBreakRadius
Rocket.sparkCount = config.rocketSparks
Rocket.smokeCount = config.rocketSmoke
Rocket.flashAlpha = config.rocketFlashAlpha
Rocket.flashScale = config.rocketFlashScale
Rocket.soundPath = config.rocketSound
Rocket.volume = config.rocketVolume

Rocket.pinned = true                // runtime: held to the board
Rocket.flying = false               // ...or under power
Rocket.flightLeft = 0               // seconds of motor left
Rocket.exhaust = null               // per-instance; see makeSprites

// The picture: nose, tube and guide stick, with the fuse out of the nozzle.
// The physics sees the tube (and the lower part of the cone, which is the
// same width) and the stick, as two boxes; the cone's point is art, the way
// a gear's teeth are.
rkArt = measure(file.loadImage("/usr/pics/rocket_40x129.png"), [40, 129],
  [7, 9, 32, 128],                    // all of it, stick included
  [9, 32, 28, 74],                    // the motor: where the blast comes from
  [[19, 81.5], [19, 78], [19.5, 75.5]],
  [[9, 22, 28, 74], [9, 75, 11, 128]])
// The mouth of the nozzle: where the thrust is aimed from and the fire comes
// out.  It is on the rocket's own axis, which is what keeps the trail
// straight behind it.
rkArt.tail = toLocal(rkArt.origin, 19.5, 76)

Rocket.art = function
	return rkArt
end function

Rocket.clearRun = function
	super.clearRun
	self.pinned = true
	self.flying = false
	self.flightLeft = 0
end function

// A rocket in the air has a fuse that is already gone and a motor that is
// already lit; without this the tip would sit in its own exhaust and light
// the thing a second time.
Rocket.checkCatch = function(dt)
	if self.flying then return
	super.checkCatch dt
end function

Rocket.applyDeferred = function(what, arg)
	if what == "launch" then
		self.launch
	else
		super.applyDeferred what, arg
	end if
end function

Rocket.launch = function
	self.lit = false
	self.pinned = false
	self.flying = true
	self.flightLeft = config.rocketFlightTime
	if self.capSparks != null then self.capSparks.emitting = false
	t = self.localToWorld(rkArt.tail[0], rkArt.tail[1])
	x = self.spec.x
	if t != null then x = t[0]
	playAt config.rocketLaunchSound, config.rocketLaunchVolume, x
end function

Rocket.detonate = function
	self.flying = false
	super.detonate
end function

// The thrust, before the step rather than after it, because it is something
// the solver has to be told.
Rocket.preStep = function(dt)
	super.preStep dt
	if not self.flying or not self.bodies then return
	b = self.bodies[0]
	f = b.mass * config.rocketThrust
	a = b.angle
	b.applyForce -sin(a) * f, cos(a) * f
end function

Rocket.update = function(dt)
	super.update dt
	if self.spent then return
	if self.flying then
		self.flightLeft = self.flightLeft - dt
		if self.flightLeft <= 0 then self.world.defer self, "boom"
		return
	end if
	if self.pinned then self.holdStill
end function

// Neither a rocket held to the board nor one under power is *resting*, and
// settling either is wrong -- but only the second is a disaster.  Being
// pinned means its velocity is zeroed every step, so it counts as settled
// within settleDelay of the run starting; the motor then adds about ten
// px/sec per step, which is under settleSpeed, so settle crushes each step's
// thrust to a fifth and the rocket creeps off the pad at a steady couple of
// pixels a second and never gets above the threshold at all.
Rocket.settle = function(dt)
	if self.pinned or self.flying then
		self.settleTime = 0
		return
	end if
	super.settle dt
end function

// The pin: put the body back where the design says, unless the step left it
// moving hard enough to have torn it loose.  What is in the velocity is what
// the blow was worth, gravity included -- which is why the two thresholds
// have to sit well above one step of gravity alone.
Rocket.holdStill = function
	if not self.bodies then return
	b = self.bodies[0]
	v = b.velocity
	if v[0] * v[0] + v[1] * v[1] > config.rocketFreeSpeed ^ 2 or
	   abs(b.angularVelocity) > config.rocketFreeSpin then
		self.pinned = false
		return
	end if
	self.placeBody b
end function

// A flying rocket is a flame on the end of a stick: it lights what it passes.
Rocket.heatSources = function
	if not self.flying then return super.heatSources
	t = self.localToWorld(rkArt.tail[0], rkArt.tail[1])
	if t == null then return []
	return [heat.source(t[0], t[1], config.rocketExhaustHeatRadius,
	  config.rocketExhaustHeat)]
end function

//----------------------------------------------------------------------

makeExhaust = function
	ps = ParticleSystem.make(glowImg, config.rocketExhaustCount)
	ps.rate = config.rocketExhaustRate
	ps.life = config.rocketExhaustLife
	ps.lifeVar = config.rocketExhaustLifeVar
	ps.speed = config.rocketExhaustSpeed
	ps.speedVar = config.rocketExhaustSpeedVar
	ps.spread = config.rocketExhaustSpread
	ps.drag = config.rocketExhaustDrag
	ps.startScale = config.rocketExhaustStartScale
	ps.endScale = config.rocketExhaustEndScale
	ps.startTint = config.sparkHotColor
	ps.endTint = config.sparkCoolColor
	return ps
end function

Rocket.makeSprites = function
	super.makeSprites
	self.exhaust = makeExhaust
	self.sprites.push self.exhaust.sprites
	self.spriteDisp.sprites.push self.exhaust.sprites
end function

Rocket.frontSprites = function
	out = super.frontSprites
	if self.exhaust != null then out.push self.exhaust.sprites
	return out
end function

Rocket.updateEffects = function(dt)
	super.updateEffects dt
	if self.exhaust == null then return
	self.exhaust.emitting = self.flying
	if self.flying then
		t = self.localToWorld(rkArt.tail[0], rkArt.tail[1])
		if t != null then self.exhaust.moveTo t[0], t[1]
		// Straight out of the tail, wherever the tail is pointed.
		if self.bodies then self.exhaust.dir = self.bodies[0].angle - pi / 2
	end if
	self.exhaust.update dt
end function

Rocket.onStop = function
	super.onStop
	if self.exhaust != null then self.exhaust.clear
end function

Rocket.setPose = function(x, y, angle=null)
	super.setPose x, y, angle
	if self.exhaust != null then self.exhaust.clear
end function
