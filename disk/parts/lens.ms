//----------------------------------------------------------------------
// Lens: a burning glass, fixed to the board, that gathers the light of a
// lamp or a candle and draws it down to a point on the far side.
//
// THE OPTICS are a thin lens and nothing more.  The ray through the middle
// of the lens goes straight on, and every other ray from the same source is
// bent to cross it at one place, so the focus is on the line from the source
// through the lens's middle -- above the lens if the source is below it --
// at the lens-equation distance d' = 1 / (1/f - 1/d) beyond it, where d is
// how far the source is along the axis.  A source nearer than f is never
// brought to a point, and one off to the side by more than config's
// `lensMaxAngle` is not either, a real lens smearing so steep a beam into
// nothing.  The lens never turns, so its axis is always level and d is only
// ever a difference in x.
//
// WHAT IT LOOKS LIKE is the lens's own picture and, for each source it is
// focusing, a cone of light: from the full height of the glass down to the
// focus, and out again a little way past it.  No sprite image can be that --
// the cone changes shape with every move of the lamp -- so the cone is a
// Sprite whose `draw` is overridden to go straight to raylib, drawing its
// triangles additively in screen coordinates.  Being a Sprite is what lets it
// sit in the part layer like anything else: it is in the lens's `sprites`,
// so destroy, moveSpritesTo and the restacking all account for it, and it
// goes to the back or the front of the layer with the glows (see
// config.glowInFront), since it is the same kind of thing.
//
// raylib draws a triangle in one flat color, so the beam's softness is made
// by overlap: `lensConeLayers` sheets, each narrower than the last and all
// closing on the same focus, so that the middle of the beam is covered more
// often than its edges; and each sheet cut into bands along its length that
// brighten towards the focus, where the light is most concentrated.
//
// Nothing here is heat yet -- the focus is only drawn.  When it is, it is one
// more `heatSources` entry at the focus, and nothing downstream will know a
// lens made it.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "physics", "util"]

lensImg = file.loadImage("/usr/pics/lens.png")

// LightCone.draw is called by the display system, from Mini Micro's own
// render loop, and that runs with the *host's* globals -- where none of the
// game's modules are.  What a function can always see is the scope it was
// defined in, so everything draw reaches for is pinned here, at module
// level, under a name of its own.
cfg = config
colors = color
Disp = Display

// The picture is 18 by 40, and the glass fills all but a column either side;
// its middle is the middle of the frame, which is where the optical center
// is.  The aperture is a little short of the full height, the tips of the
// glass being too thin to bend much of anything.
artWidth = 16
artHeight = 40
halfAperture = 18

// Where each band of the cone starts and ends, in fractions of the way from
// the lens to the focus.  Close together near the focus, where the beam is
// narrowing fastest and the brightness changing most.
convergeSteps = [0, 0.3, 0.55, 0.75, 0.9, 1]

//----------------------------------------------------------------------
// LightCone: the sprite that draws the beams.
//
// `cones` is worked out each frame by the lens and read here; each is a map
// of the lens center (lx, ly), the focus (fx, fy), and `strength`, 0 to 1.
//----------------------------------------------------------------------

globals.LightCone = new Sprite
LightCone.cones = null              // per-instance
LightCone.wash = null               // per-instance: the editor's wash, as a list

LightCone.make = function
	c = new LightCone
	c.cones = []
	c.wash = [255, 255, 255, 255]
	return c
end function

LightCone.draw = function(offsetX=0, offsetY=0)
	if not self.cones then return
	rl = raylib
	// Screen coordinates are y-down from the top, so a world point (x, y)
	// is at (x + ox, oy - y).  Same arithmetic as Sprite.draw.
	ox = offsetX
	oy = Disp.screenHeight - offsetY
	base = colors.toList(cfg.lensConeColor)
	for i in range(0, 2)
		base[i] = base[i] * self.wash[i] / 255
	end for
	rl.rlDisableBackfaceCulling
	rl.BeginBlendMode rl.BLEND_ADDITIVE
	for c in self.cones
		self.drawCone c, base, ox, oy
	end for
	// Ending the blend mode flushes the batch, which has to happen before
	// culling comes back on, or the triangles we just queued would be culled
	// by winding after all.
	rl.EndBlendMode
	rl.rlEnableBackfaceCulling
end function

LightCone.drawCone = function(c, base, ox, oy)
	layers = cfg.lensConeLayers
	a = cfg.lensConeAlpha * c.strength / layers * self.wash[3] / 255
	after = cfg.lensAfterglow
	for layer in range(0, layers - 1, 1)
		w = 1 - layer / layers
		// Closing on the focus, and brightening as it does.
		for i in range(0, convergeSteps.len - 2, 1)
			t0 = convergeSteps[i]
			t1 = convergeSteps[i + 1]
			self.band c, t0, t1, w, a * (0.35 + 0.65 * (t0 + t1) / 2), base, ox, oy
		end for
		// Opening out past it, and fading.
		steps = 3
		for i in range(0, steps - 1, 1)
			t0 = 1 + after * i / steps
			t1 = 1 + after * (i + 1) / steps
			self.band c, t0, t1, w, a * (1 - (i + 0.5) / steps) * 0.7, base, ox, oy
		end for
	end for
	// The point itself.
	col = base[:]
	col[3] = round(255 * cfg.lensSpotAlpha * c.strength * self.wash[3] / 255)
	edge = base[:]
	edge[3] = 0
	rl.DrawCircleGradient round(c.fx + ox), round(oy - c.fy),
	  cfg.lensSpotRadius, col, edge
end function

// One band of one sheet: the stretch of beam between t0 and t1, where 0 is
// the lens and 1 the focus.  The beam's cross-section at t is upright (the
// lens is), centered on the ray through the lens's middle, and as tall as
// the aperture scaled by how far t is from the focus -- which is the same
// formula either side of it.
LightCone.band = function(c, t0, t1, w, alpha, base, ox, oy)
	if alpha <= 0 then return
	col = base[:]
	col[3] = round(255 * alpha)
	if col[3] < 1 then return
	dx = c.fx - c.lx
	dy = c.fy - c.ly
	x0 = c.lx + dx * t0 + ox
	y0 = oy - (c.ly + dy * t0)
	h0 = halfAperture * abs(1 - t0) * w
	x1 = c.lx + dx * t1 + ox
	y1 = oy - (c.ly + dy * t1)
	h1 = halfAperture * abs(1 - t1) * w
	raylib.DrawTriangle [x0, y0 - h0], [x0, y0 + h0], [x1, y1 + h1], col
	if h1 > 0 then raylib.DrawTriangle [x0, y0 - h0], [x1, y1 + h1], [x1, y1 - h1], col
end function

//----------------------------------------------------------------------
// The part
//----------------------------------------------------------------------

globals.Lens = new Part
Lens.typeName = "lens"
Lens.displayName = "Lens"
Lens.bodyType = physics.STATIC
Lens.defaultSpec = Part.defaultSpec + {"restitution": 0.3, "friction": 0.3}

Lens.cone = null                    // per-instance: the LightCone sprite

Lens.size = function
	return [artWidth, artHeight]
end function

Lens.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(artWidth, artHeight, 0, 0, 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Lens.image = function
	return lensImg
end function

// The sprites are [lens, cone].  The default syncSprites pairs the first with
// the one body, and passes the cone by, which needs no position: it draws in
// world coordinates.
Lens.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sp = new Sprite
	sp.image = lensImg
	self.sprites.push sp
	self.cone = LightCone.make
	self.sprites.push self.cone
	for sp in self.sprites
		self.spriteDisp.sprites.push sp
	end for
	self.aim
end function

Lens.backSprites = function
	if config.glowInFront or self.cone == null then return []
	return [self.cone]
end function

Lens.frontSprites = function
	if not config.glowInFront or self.cone == null then return []
	return [self.cone]
end function

Lens.tintSprites = function(wash="#FFFFFF")
	if not self.sprites then return
	self.sprites[0].tint = wash
	if self.cone != null then self.cone.wash = color.toList(wash)
end function

// Every frame, in design mode as well as play: a lamp dragged past the lens
// should drag its focus with it.  Nothing here touches physics or spec.
Lens.updateEffects = function(dt)
	self.aim
end function

// Work out a cone for every lit source in reach.  Each gets its own, because
// that is what a lens does with two lamps -- two points of light -- and the
// sources are few enough that there is no call to choose.
Lens.aim = function
	if self.cone == null or self.world == null or not self.bodies then return
	cones = []
	b = self.bodies[0]
	for p in self.world.parts
		for src in p.lightSources
			c = self.focus(b.x, b.y, src[0], src[1], src[2])
			if c != null then cones.push c
		end for
	end for
	self.cone.cones = cones
end function

// The cone a source at (sx, sy) makes through a lens centered at (lx, ly),
// or null if it makes none.
Lens.focus = function(lx, ly, sx, sy, brightness)
	dx = lx - sx
	dy = ly - sy
	d = abs(dx)
	f = config.lensFocalLength
	if d <= f then return null
	dist = sqrt(dx * dx + dy * dy)
	if dist > config.lensReach then return null
	angle = atan(abs(dy), d) * 180 / pi
	if angle >= config.lensMaxAngle then return null
	far = f * d / (d - f)
	if far > config.lensMaxThrow then return null

	// The focus is on the ray through the middle, `far` further along the
	// axis than the lens -- so as far again past it as the source is short of
	// it, in the same proportion, both ways.
	k = far / d
	strength = brightness * cos(angle * pi / 180)
	// What a lens catches of a point source falls off with distance -- in a
	// flat world, as 1/d, not 1/d^2 -- and near enough it catches all it can.
	if dist > config.lensFullDist then strength = strength * config.lensFullDist / dist
	// Fade out over the last few degrees and the last stretch of reach, so
	// that dragging a lamp across either edge does not make the cone blink.
	fade = (config.lensMaxAngle - angle) / config.lensAngleFade
	if fade < 1 then strength = strength * fade
	fade = (config.lensReach - dist) / (config.lensReach * 0.15)
	if fade < 1 then strength = strength * fade
	fade = (config.lensMaxThrow - far) / (config.lensMaxThrow * 0.15)
	if fade < 1 then strength = strength * fade
	if strength <= 0 then return null
	return {"lx": lx, "ly": ly, "fx": lx + dx * k, "fy": ly + dy * k,
	  "strength": strength}
end function

Lens.paletteImage = function
	return lensImg
end function
