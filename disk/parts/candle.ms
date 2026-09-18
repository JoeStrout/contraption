//----------------------------------------------------------------------
// Candle: a candle in a holder, which may be authored lit or unlit.
//
// Whether it is burning is *authored* state, not runtime state: it lives in
// `spec.lit`, a click in the editor flips it (see the note on states in
// part.ms), and Stop puts it back to however the design says.  So a level can
// start with the candle already going, or with it dark and a puzzle about how
// to light it.  The runtime `lit` is a separate field, because one day
// something will blow this out mid-run and that must not touch the design.
//
// It burns with two effects, and they are different kinds of thing:
//
//   the glow    a pool of light on the board, flickering.  See glow.ms.
//   the flame   particles, born at the wick and rising.  See particles.ms.
//
// The flame is drawn from the same radial gradient the glow is, shrunk right
// down: a candle flame at this size is a soft blob of light and not a shape,
// and a dozen overlapping blobs make the bright core by themselves.
//
// It is DYNAMIC and can be knocked over, with the weight in the metal foot
// -- density 4 against the wax's 1 -- so that it rights itself from a nudge
// and goes over properly from a shove.  Nothing yet puts it out when it
// falls, which it should; that wants the flame to know which way is up, and
// it already does (see Flame), so it is a matter of deciding what the rule
// is rather than of machinery.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "artUtil", "physics", "util", "glow",
  "particles", "heat"]

offImg = file.loadImage("/usr/pics/candle-off.png")
onImg = file.loadImage("/usr/pics/candle-on.png")
glowImg = file.loadImage("/usr/pics/light-glow.png")

// The art is the authority.  Image pixels, y-down from the top-left corner.
imgWidth = 36
imgHeight = 56
// What the picture actually covers.  The holder's finger loop is off to the
// left, so the candle's own column is *not* in the middle of the frame, and
// the part's origin is the middle of what is drawn rather than of the frame.
artPix = [1, 0, 34, 53]             // left, top, right, bottom
basePix = [1, 48, 34, 53]           // the foot of the holder
stemPix = [15, 3, 25, 47]           // the wax and the cup under it
wickPix = [19.5, 0]                 // the tip of the wick
glowRise = 6                        // px above it that the flame is brightest
originX = (artPix[0] + artPix[2] + 1) / 2
originY = (artPix[1] + artPix[3] + 1) / 2

// Part-frame coordinates: y-up, from that origin.
toLocal = function(x, y)
	return [x - originX, originY - y]
end function

// Where the picture's own middle falls in that frame, which is what the
// sprite has to be offset by.
spriteOff = toLocal(imgWidth / 2, imgHeight / 2)

// A rect given as [left, top, right, bottom] in image pixels, as
// [width, height, centerX, centerY] in the part's frame.
toBox = function(r)
	mid = toLocal((r[0] + r[2] + 1) / 2, (r[1] + r[3] + 1) / 2)
	return [r[2] - r[0] + 1, r[3] - r[1] + 1, mid[0], mid[1]]
end function

globals.Candle = new Part
Candle.typeName = "candle"
Candle.displayName = "Candle"
Candle.defaultSpec = Part.defaultSpec + {"restitution": 0.05, "friction": 0.7,
  "linearDamping": 0.02, "angularDamping": 0.05, "lit": false}

Candle.lit = false                  // runtime: burning right now
Candle.glow = null                  // per-instance
Candle.flame = null

Candle.init = function
	super.init
	self.lit = self.spec.lit
end function

// The wick is the one place worth fastening anything to, and it is where a
// fuse wants to end: run one from a lit candle's wick to a dark one's and the
// flame is already touching it.
Candle.tieLocals = function
	return [toLocal(wickPix[0], wickPix[1])]
end function

// Where the wick has got to, which is where the fire is.  Worked out from the
// body rather than from the tie list so that syncSprites can use it before
// anything has asked for a tie point.
Candle.wickWorld = function
	if not self.bodies then return null
	b = self.bodies[0]
	w = toLocal(wickPix[0], wickPix[1])
	c = cos(b.angle); sn = sin(b.angle)
	return [b.x + w[0] * c - w[1] * sn, b.y + w[0] * sn + w[1] * c]
end function

// A lit candle is hot a little above its wick, where the flame is, and that
// is the whole of how it lights a fuse.  See heat.ms.
Candle.heatSources = function
	if not self.lit then return []
	w = self.wickWorld
	if w == null then return []
	return [heat.source(w[0], w[1] + glowRise, config.candleHeatRadius,
	  config.candleHeat)]
end function

// ...and an unlit one catches from anything hot enough at that same place,
// which is what the far end of a fuse is by the time it gets there.  This is
// runtime state and never touches spec: Stop puts the candle back to however
// the design left it.
Candle.update = function(dt)
	super.update dt
	if self.lit or self.world == null then return
	w = self.wickWorld
	if w == null then return
	if heat.at(self.world, w[0], w[1]) >= config.candleLightHeat then
		self.setLit true
	end if
end function

Candle.size = function
	return [artPix[2] - artPix[0] + 1, artPix[3] - artPix[1] + 1]
end function

// Lit or not is the one thing there is to author, so a click in the editor
// walks between the two.
Candle.stateSpecs = function
	return [{"lit": false}, {"lit": true}]
end function

Candle.applyState = function
	self.setLit self.spec.lit
	super.applyState
end function

// Heavy foot, light wax: what keeps it standing.
Candle.makeBodies = function
	s = self.spec
	b = self.addBody
	for r in [[basePix, 4], [stemPix, 1]]
		box = toBox(r[0])
		sh = b.addBox(box[0], box[1], box[2], box[3], 0, r[1])
		sh.setRestitution s.restitution
		sh.setFriction s.friction
	end for
end function

Candle.setLit = function(v)
	if v == self.lit then return
	self.lit = v
	self.showState
end function

Candle.showState = function
	if not self.sprites then return
	self.sprites[0].image = self.image
	t = 0
	if self.world != null then t = self.world.effectTime
	if self.glow != null then self.glow.setLit self.lit, t
	// Blown out, what is already in the air burns out on its own rather than
	// vanishing, so nothing is cleared here.
	if self.flame != null then self.flame.emitting = self.lit
end function

// Stop restores the design, and being alight is part of the design.
Candle.onStop = function
	super.onStop
	self.setLit self.spec.lit
end function

Candle.updateEffects = function(dt)
	if self.world == null then return
	t = self.world.effectTime
	if self.glow != null then self.glow.update t
	if self.flame != null then self.flame.update dt
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

Candle.image = function
	if self.lit then return onImg
	return offImg
end function

// The sprites are [candle, glow, flame pool] -- three entries, the last of
// them a list, which a SpriteDisplay draws depth first.  Putting the pool in
// the part's own list is what makes destroy, moveSpritesTo and the restacking
// account for it; the flame system only ever owns the particles' motion.  The
// pool goes last, so the flame is drawn over the candle.
Candle.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sp = new Sprite
	sp.image = self.image
	self.sprites.push sp

	self.glow = Glow.make(glowImg, config.candleGlowColor,
	  config.candleGlowAlpha, config.candleGlowScale, config.candleGlowFlicker)
	self.sprites.push self.glow.sprite

	self.flame = Flame.make(glowImg, config.flameCount)
	f = self.flame
	f.rate = config.flameRate
	f.life = config.flameLife
	f.lifeVar = config.flameLifeVar
	f.speed = config.flameSpeed
	f.speedVar = config.flameSpeedVar
	f.dir = pi / 2
	f.spread = config.flameSpread
	f.spawnRadius = config.flameWidth
	f.accelY = config.flameRise
	f.taper = config.flameTaper
	f.startScale = config.flameStartScale
	f.endScale = config.flameEndScale
	f.startTint = config.flameHotColor
	f.endTint = config.flameCoolColor
	self.sprites.push f.sprites

	for sp in self.sprites
		self.spriteDisp.sprites.push sp
	end for
	self.showState
end function

Candle.backSprites = function
	if config.glowInFront or self.glow == null then return []
	return [self.glow.sprite]
end function

Candle.frontSprites = function
	if not config.glowInFront or self.glow == null then return []
	return [self.glow.sprite]
end function

// The candle's picture sits a pixel below the part's origin, the origin being
// the middle of what is drawn rather than of the frame it is drawn in.  The
// wick goes wherever the candle is tipped to; the flame off it does not,
// since fire goes up whatever is holding it.
Candle.syncSprites = function
	if not self.bodies or not self.sprites then return
	b = self.bodies[0]
	c = cos(b.angle); sn = sin(b.angle)
	sp = self.sprites[0]
	sp.x = b.x + spriteOff[0] * c - spriteOff[1] * sn
	sp.y = b.y + spriteOff[0] * sn + spriteOff[1] * c
	sp.rotation = b.angle * 180 / pi

	w = self.wickWorld
	wx = w[0]
	wy = w[1]
	if self.flame != null then self.flame.moveTo wx, wy
	// The pool of light hangs where the bright part of the flame is, which is
	// a little above the wick rather than on it.
	if self.glow != null then self.glow.moveTo wx, wy + glowRise
end function

Candle.tintSprites = function(wash="#FFFFFF")
	if not self.sprites then return
	self.sprites[0].tint = wash
	if self.glow != null then self.glow.setWash wash
	// The particles are left alone: their tint is their age, and the wash is
	// gone again the moment the part is dropped.
end function

Candle.paletteImage = function
	return offImg
end function

// Carried across the board, a candle would otherwise leave a trail of fire
// hanging in the air behind it: particles are in world coordinates and know
// nothing of the part that made them.  So a move takes the flame with it.
Candle.setPose = function(x, y, angle=null)
	super.setPose x, y, angle
	if self.flame != null then self.flame.clear
end function
