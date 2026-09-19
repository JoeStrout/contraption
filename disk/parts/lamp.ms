//----------------------------------------------------------------------
// Lamp: a bulb in a porcelain socket, bolted to the board, which lights up
// when a live net reaches it.
//
// ELECTRICALLY it is the dullest load there is -- two brass binding screws,
// joined through the bulb, so it lights when either one is live and passes
// current on to whatever is wired to the other.  A real socket's screws work
// exactly that way, and it means a lamp can sit in line in a circuit rather
// than having to be the end of one.  Nothing here asks how much current, or
// notices two lamps in series, because circuit.ms has no idea what either
// would mean; see notes/electrical-parts.md for why that ceiling is where it
// is.
//
// WHAT IT LOOKS LIKE is two pre-rendered pictures, lit and unlit, and a
// third sprite for the pool of light it throws -- a Glow, steady, since a
// filament does not waver.  See glow.ms for what that is and is not.
//
// The glow does not ride in the part's own place in the layer: it is kept at
// the very back of it (or the very front -- see config.glowInFront), which
// is what `Part.backSprites` is for, so that the light lies under the whole
// board rather than only under the parts that happen to have been placed
// later.  The lamp itself stays in the ordinary order.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "artUtil", "physics", "util", "glow"]

offImg = file.loadImage("/usr/pics/bulb-off.png")
onImg = file.loadImage("/usr/pics/bulb-on.png")
glowImg = file.loadImage("/usr/pics/light-glow.png")

// The art is the authority on where everything is.  These are measured off
// the two pictures, in image pixels from the top-left corner; nothing may be
// moved here without moving it there.
imgWidth = 40
imgHeight = 56
// What the picture actually covers, which is a little less than the frame it
// is rendered in.  This is the footprint, so that a snapped lamp stands on
// the lattice line rather than a few pixels above it.
artWidth = 38
artHeight = 50
basePix = [2, 36, 37, 52]           // the porcelain socket: left, top, right, bottom
glassPix = [20, 20, 13]             // the bulb: center and radius
filamentPix = [20, 14.5]            // where the light comes from
termPix = [[5, 48], [35, 48]]       // the two binding screws

// Image pixels are y-down from the top-left; part-frame coordinates are y-up
// from the middle of the frame.
toLocal = function(x, y)
	return [x - imgWidth / 2, imgHeight / 2 - y]
end function

globals.Lamp = new Part
Lamp.typeName = "lamp"
Lamp.displayName = "Lamp"
Lamp.bodyType = physics.STATIC
Lamp.defaultSpec = Part.defaultSpec + {"restitution": 0.15, "friction": 0.6}

Lamp.lit = false                    // runtime: a live net reaches us
Lamp.glow = null                    // per-instance; see glow.ms

Lamp.size = function
	return [artWidth, artHeight]
end function

Lamp.terminalLocals = function
	out = []
	for t in termPix
		out.push toLocal(t[0], t[1])
	end for
	return out
end function

// The screws are the two ends of the same lamp, so the fill runs through it.
Lamp.conducts = function(i, j)
	return true
end function

// Two shapes on the one body, because a box around the whole thing would
// leave a ball resting on thin air out at the shoulders of the glass.
Lamp.makeBodies = function
	s = self.spec
	b = self.addBody
	p = basePix
	mid = toLocal((p[0] + p[2] + 1) / 2, (p[1] + p[3] + 1) / 2)
	sh = b.addBox(p[2] - p[0] + 1, p[3] - p[1] + 1, mid[0], mid[1], 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	mid = toLocal(glassPix[0], glassPix[1])
	sh = b.addCircle(glassPix[2], mid[0], mid[1], 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Lamp.update = function(dt)
	super.update dt
	self.setLit self.powered
end function

Lamp.setLit = function(v)
	if v == self.lit then return
	self.lit = v
	self.showState
end function

Lamp.showState = function
	if not self.sprites then return
	self.sprites[0].image = self.image
	if self.glow != null then self.glow.setLit self.lit
end function

Lamp.onStop = function
	super.onStop
	self.lit = false
	self.showState
end function

//----------------------------------------------------------------------
// Appearance: two pre-drawn pictures and the pool of light, so nothing here
// is cached -- the images themselves are the cache, loaded once when this
// module is.
//----------------------------------------------------------------------

Lamp.image = function
	if self.lit then return onImg
	return offImg
end function

// The sprites are [lamp, glow].  The glow's own sprite is spliced in here so
// that destroy, moveSpritesTo and the restacking all account for it without
// having to know what it is.
Lamp.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sp = new Sprite
	sp.image = self.image
	self.sprites.push sp
	self.glow = Glow.make(glowImg, config.lampGlowColor, config.lampGlowAlpha,
	  config.lampGlowScale)
	self.glow.setLit self.lit
	self.sprites.push self.glow.sprite
	for sp in self.sprites
		self.spriteDisp.sprites.push sp
	end for
end function

Lamp.backSprites = function
	if config.glowInFront or self.glow == null then return []
	return [self.glow.sprite]
end function

Lamp.frontSprites = function
	if not config.glowInFront or self.glow == null then return []
	return [self.glow.sprite]
end function

// The lamp is where the body is; the glow is at the filament, which is up
// inside the glass, and carried round with the part if it is turned.  It is
// not turned itself, being a round pool of light.
Lamp.syncSprites = function
	if not self.bodies or not self.sprites then return
	b = self.bodies[0]
	sp = self.sprites[0]
	sp.x = b.x
	sp.y = b.y
	sp.rotation = b.angle * 180 / pi
	if self.glow == null then return
	f = self.filamentWorld
	self.glow.moveTo f[0], f[1]
end function

Lamp.filamentWorld = function
	b = self.bodies[0]
	f = toLocal(filamentPix[0], filamentPix[1])
	c = cos(b.angle); sn = sin(b.angle)
	return [b.x + f[0] * c - f[1] * sn, b.y + f[0] * sn + f[1] * c]
end function

// The light comes from the filament.  See Part.lightSources.
Lamp.lightSources = function
	if not self.lit or not self.bodies then return []
	f = self.filamentWorld
	return [[f[0], f[1], config.lampLight]]
end function

// The glow carries a tint of its own -- its color, and the alpha that is the
// whole of whether it is showing -- so the editor's wash is handed to it to
// multiply in rather than laid over it.  Compare Balloon.tintSprites.
Lamp.tintSprites = function(wash="#FFFFFF")
	if not self.sprites then return
	self.sprites[0].tint = wash
	if self.glow != null then self.glow.setWash wash
end function

// The palette shows the lamp, not its light.
Lamp.paletteImage = function
	return offImg
end function
