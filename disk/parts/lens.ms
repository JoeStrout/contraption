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
// The beam is a small mesh of quads in rlgl's immediate mode, with a color
// on every vertex and the GPU blending between them: brightest along the ray
// through the lens's middle and clear at the edges, and brightening along
// its length towards the focus, where the light is most concentrated.
//
// THE FOCUS IS HOT: one `heatSources` entry per cone, at the focus, gentle
// enough that a fuse or a wick has to sit in it for seconds before it
// catches (see heat.ms).  Nothing downstream knows a lens made it.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "physics", "util", "heat"]

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

// Where the beam's cross-sections are, in fractions of the way from the lens
// (0) to the focus (1).  Close together near the focus, where the beam is
// narrowing fastest and the brightness changing most.  Past the focus they
// are fractions of the afterglow instead (config.lens.afterglow).
convergeSteps = [0, 0.3, 0.55, 0.75, 0.9, 1]
divergeSteps = [0.33, 0.67, 1]
// Across the beam: fractions of its half-width, and how bright each is
// against the middle.  Three points round the profile off; two would make it
// a tent, with a crease of light down the middle.
acrossSteps = [0, 0.5, 1]
acrossLevels = [1, 0.55, 0]

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
	base = colors.toList(cfg.lens.coneColor)
	for i in range(0, 2)
		base[i] = round(base[i] * self.wash[i] / 255)
	end for
	// Culling off, because which way round a quad winds depends on which
	// side of the lens the light is coming from.
	rl.rlDisableBackfaceCulling
	rl.BeginBlendMode rl.BLEND_ADDITIVE
	for c in self.cones
		self.drawBeam c, base, ox, oy
	end for
	// Ending the blend mode flushes the batch, which has to happen before
	// culling comes back on, or the quads we just queued would be culled
	// by winding after all.
	rl.EndBlendMode
	rl.rlEnableBackfaceCulling
end function

LightCone.drawBeam = function(c, base, ox, oy)
	rl = raylib
	peak = cfg.lens.coneAlpha * c.strength * self.wash[3]
	if peak > 255 then peak = 255
	after = cfg.lens.afterglow

	// The stations along the beam, each [t, brightness].  Past the focus the
	// light fades out to nothing at the far end.
	stations = []
	for t in convergeSteps
		stations.push [t, 0.35 + 0.65 * t]
	end for
	for s in divergeSteps
		stations.push [1 + after * s, 0.7 * (1 - s)]
	end for

	// Each station's cross-section, in screen coordinates.  It is upright
	// (the lens is), centered on the ray through the lens's middle, and as
	// tall as the aperture scaled by how far t is from the focus -- the same
	// formula either side of it.  A row is [x, points], and a point is
	// [y above, y below, alpha].
	dx = c.fx - c.lx
	dy = c.fy - c.ly
	rows = []
	for st in stations
		t = st[0]
		y = oy - (c.ly + dy * t)
		h = halfAperture * abs(1 - t)
		a = peak * st[1]
		pts = []
		for j in acrossSteps.indexes
			pts.push [y - h * acrossSteps[j], y + h * acrossSteps[j],
			  round(a * acrossLevels[j])]
		end for
		rows.push [c.lx + dx * t + ox, pts]
	end for

	// One quad per band per slice per side.  rlgl draws a quad as two
	// triangles and blends the vertex colors across each; the default
	// texture is plain white, so the colors are all there is.
	r = base[0]; g = base[1]; b = base[2]
	n = acrossSteps.len - 1
	rl.rlCheckRenderBatchLimit (rows.len - 1) * n * 2 * 4
	rl.rlSetTexture rl.rlGetTextureIdDefault
	rl.rlBegin rl.RL_QUADS
	for i in range(0, rows.len - 2, 1)
		x0 = rows[i][0]
		p0 = rows[i][1]
		x1 = rows[i + 1][0]
		p1 = rows[i + 1][1]
		for j in range(0, n - 1, 1)
			for side in [0, 1]
				rl.rlColor4ub r, g, b, p0[j][2]
				rl.rlVertex2f x0, p0[j][side]
				rl.rlColor4ub r, g, b, p1[j][2]
				rl.rlVertex2f x1, p1[j][side]
				rl.rlColor4ub r, g, b, p1[j + 1][2]
				rl.rlVertex2f x1, p1[j + 1][side]
				rl.rlColor4ub r, g, b, p0[j + 1][2]
				rl.rlVertex2f x0, p0[j + 1][side]
			end for
		end for
	end for
	rl.rlEnd
	rl.rlSetTexture 0

	// The point itself.
	col = base[:]
	col[3] = round(255 * cfg.lens.spotAlpha * c.strength * self.wash[3] / 255)
	edge = base[:]
	edge[3] = 0
	rl.DrawCircleGradient round(c.fx + ox), round(oy - c.fy),
	  cfg.lens.spotRadius, col, edge
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

Lens.aim = function
	if self.cone == null then return
	self.cone.cones = self.focuses
end function

// A cone for every lit source in reach.  Each gets its own, because that is
// what a lens does with two lamps -- two points of light -- and the sources
// are few enough that there is no call to choose.
Lens.focuses = function
	cones = []
	if self.world == null or not self.bodies then return cones
	b = self.bodies[0]
	for p in self.world.parts
		for src in p.lightSources
			c = self.focus(b.x, b.y, src[0], src[1], src[2])
			if c != null then cones.push c
		end for
	end for
	return cones
end function

// Worked out afresh rather than read off the cone sprite, which is only as
// new as the last frame drawn.  Strength carries everything that dims the
// cone -- a candle instead of a lamp, distance, a slant -- into the heat.
Lens.heatSources = function
	out = []
	for c in self.focuses
		out.push heat.source(c.fx, c.fy, config.lens.heatRadius,
		  config.lens.heat * c.strength)
	end for
	return out
end function

// The cone a source at (sx, sy) makes through a lens centered at (lx, ly),
// or null if it makes none.
Lens.focus = function(lx, ly, sx, sy, brightness)
	dx = lx - sx
	dy = ly - sy
	d = abs(dx)
	f = config.lens.focalLength
	if d <= f then return null
	dist = sqrt(dx * dx + dy * dy)
	if dist > config.lens.reach then return null
	angle = atan(abs(dy), d) * 180 / pi
	if angle >= config.lens.maxAngle then return null
	far = f * d / (d - f)
	if far > config.lens.maxThrow then return null

	// The focus is on the ray through the middle, `far` further along the
	// axis than the lens -- so as far again past it as the source is short of
	// it, in the same proportion, both ways.
	k = far / d
	strength = brightness * cos(angle * pi / 180)
	// What a lens catches of a point source falls off with distance -- in a
	// flat world, as 1/d, not 1/d^2 -- and near enough it catches all it can.
	if dist > config.lens.fullDist then strength = strength * config.lens.fullDist / dist
	// Fade out over the last few degrees and the last stretch of reach, so
	// that dragging a lamp across either edge does not make the cone blink.
	fade = (config.lens.maxAngle - angle) / config.lens.angleFade
	if fade < 1 then strength = strength * fade
	fade = (config.lens.reach - dist) / (config.lens.reach * 0.15)
	if fade < 1 then strength = strength * fade
	fade = (config.lens.maxThrow - far) / (config.lens.maxThrow * 0.15)
	if fade < 1 then strength = strength * fade
	if strength <= 0 then return null
	return {"lx": lx, "ly": ly, "fx": lx + dx * k, "fy": ly + dy * k,
	  "strength": strength}
end function

Lens.paletteImage = function
	return lensImg
end function
