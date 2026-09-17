
//----------------------------------------------------------------------
// Lever: a rigid bar that turns on a fixed fulcrum.
//
// The engine has no joints, so the pin is ours to keep, and `update` does it
// once per step.  A pinned lever has exactly one degree of freedom -- the
// bar's angle -- so the job is to take whatever free-body state the step
// produced and project it back onto that one motion: put the bar's origin
// back on the pivot, and replace its velocity with the single turn about the
// pivot carrying the same momentum in that degree of freedom.
//
// That projection is not an approximation.  For an impulse J struck at a
// point q, it gives the bar (q - P) x J of momentum about the pivot P, which
// is exactly what a real pin would, because the part of the blow the pin
// swallows is the part that would have moved P.  So a ball landing on one
// end comes out as spin rather than being thrown away, and the weight of an
// off-center bar becomes the torque that tips it.
//
// Two bodies: the bar, which is the only part of a plain lever that moves,
// and the fulcrum, which is static scenery that happens to travel with the
// part.  Both have their origin at the pivot -- the bar so that holding it
// still is the whole of the constraint, the fulcrum so that its outline is
// written relative to the same point.
//
// The bar's travel stops where its descending end reaches the bottom of the
// part's footprint, which is the ground the fulcrum stands on.  Its rising
// end does sweep above the footprint; parts want headroom over a lever.
//----------------------------------------------------------------------

globals.Lever = new Part
Lever.typeName = "lever"
Lever.displayName = "Lever"
Lever.defaultSpec = Part.defaultSpec + {"length": 160, "thickness": 10,
  "fulcrumHeight": 30, "pivotFrac": 0, "color": "#C08A4A",
  "fulcrumColor": "#7A8894", "restitution": 0.1, "density": 1.2,
  "friction": 0.6, "angularDamping": 0.4}

Lever.bar = null            // per-instance, see makeBodies
Lever.fulcrum = null
Lever.barSprite = null      // per-instance, see makeSprites
Lever.fulcrumSprite = null
Lever.spin = 0              // runtime: the turn rate we last solved for

Lever.init = function
	self.bar = null
	self.fulcrum = null
	self.barSprite = null
	self.fulcrumSprite = null
	self.spin = 0
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// Subclass hook: footprint the part needs above the top of the bar, for
// whatever the bar carries up there.
Lever.headroom = function
	return 0
end function

Lever.size = function
	s = self.spec
	return [s.length, s.fulcrumHeight + s.thickness + self.headroom]
end function

// The pivot in the part's own frame: on the bar's midline, which is the
// headroom and half the bar's thickness down from the top of the footprint,
// and `pivotFrac` of the way from the bar's center to its end.
Lever.pivotLocal = function
	s = self.spec
	return [s.pivotFrac * s.length / 2,
	  self.size[1] / 2 - self.headroom - s.thickness / 2]
end function

// The pivot in world coordinates.  Nothing but spec decides this: the pin
// does not move, which is the whole point of it.
Lever.pivotWorld = function
	s = self.spec
	pv = self.pivotLocal
	c = cos(s.angle); sn = sin(s.angle)
	return [s.x + pv[0] * c - pv[1] * sn, s.y + pv[0] * sn + pv[1] * c]
end function

// How far the bar may turn from the authored angle, in radians: the tilt at
// which the lower corner of the longer arm reaches the bottom of the
// footprint.  With the arm half-length A, the half-thickness B and the drop
// C from pivot to footprint bottom, that corner is C low when
// sin(t)*A + cos(t)*B = C, which is the identity below.  (C works out to the
// same fulcrumHeight + B whatever the headroom above: the headroom raises
// the pivot and the footprint's top edge by equal amounts.)
Lever.maxTilt = function
	s = self.spec
	a = s.length / 2 * (1 + abs(s.pivotFrac))
	b = s.thickness / 2
	c = s.fulcrumHeight + b
	h = sqrt(a * a + b * b)
	if c >= h then return config.leverMaxTilt
	t = asin(c / h) - atan(b, a)
	if t > config.leverMaxTilt then return config.leverMaxTilt
	if t < 0 then return 0
	return t
end function

// Half the width of the fulcrum's base.  Its sides are flared out from the
// bar's steepest tilt, so there is always daylight between the underside of
// the bar and the slope beneath it.
Lever.fulcrumHalfWidth = function
	s = self.spec
	h = s.fulcrumHeight + s.thickness / 2
	hw = h / tan(self.maxTilt + config.leverFulcrumFlare)
	if hw > s.length / 4 then hw = s.length / 4
	return hw
end function

//----------------------------------------------------------------------
// Physics bodies
//----------------------------------------------------------------------

Lever.makeBodies = function
	s = self.spec
	pv = self.pivotLocal
	self.bar = self.addBody(pv[0], pv[1])
	sh = self.bar.addBox(s.length, s.thickness, -pv[0], 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	sh.setFilter config.catDefault, config.maskBar

	self.fulcrum = self.addBody(pv[0], pv[1])
	hw = self.fulcrumHalfWidth
	base = -(s.fulcrumHeight + s.thickness / 2)
	fsh = self.fulcrum.addPolygon([[0, 0], [hw, base], [-hw, base]])
	fsh.setRestitution s.restitution
	fsh.setFriction s.friction
	fsh.setFilter config.catFulcrum, config.maskFulcrum
end function

// Only the bar moves; the fulcrum is as static as the floor.
Lever.onPlay = function
	self.bar.setType physics.DYNAMIC
	self.fulcrum.setType physics.STATIC
end function

//----------------------------------------------------------------------
// Holding the pin.  The four hooks below are what a variant extends when it
// hangs something else off the bar: what else to put back in place, what
// momentum it carries, what inertia it adds, and how it moves once the one
// remaining degree of freedom has been solved for.
//----------------------------------------------------------------------

Lever.update = function(dt)
	stop = self.pinBar
	self.pinRiders
	spin = self.momentum / self.generalizedMass
	// Sitting against a stop: it may leave, but it may not lean harder.
	if spin * stop > 0 then spin = 0
	self.applySpin spin
end function

// Put the bar back on its pivot, stopping it at the end of its travel.
// Returns 1 or -1 if it is up against a stop, 0 if it swings free.
Lever.pinBar = function
	s = self.spec
	b = self.bar
	p = self.pivotWorld
	a = b.angle
	lim = self.maxTilt
	stop = 0
	if a > s.angle + lim then
		a = s.angle + lim
		stop = 1
	else if a < s.angle - lim then
		a = s.angle - lim
		stop = -1
	end if
	if stop then b.setAngle a
	b.setPosition p[0], p[1]
	return stop
end function

// Subclass hook: put whatever else the bar carries back where the bar's
// pose, now pinned, says it belongs.
Lever.pinRiders = function
end function

// The bar's arm: its center of mass relative to the pivot.  Zero for a bar
// hung at its middle, which is why a seesaw sits wherever you leave it.
Lever.barArm = function
	p = self.pivotWorld
	com = self.bar.centerOfMass
	return [com[0] - p[0], com[1] - p[1]]
end function

// The assembly's momentum in its one degree of freedom, out of the step just
// taken: the angular momentum about the pivot of everything the pin holds.
Lever.momentum = function
	b = self.bar
	r = self.barArm
	return b.inertia * b.angularVelocity + b.mass * (r[0] * b.vy - r[1] * b.vx)
end function

// And the inertia that momentum has to turn: the assembly's moment about the
// pivot.
Lever.generalizedMass = function
	b = self.bar
	r = self.barArm
	return b.inertia + b.mass * (r[0] * r[0] + r[1] * r[1])
end function

// Everything the pin holds now turns about the pivot at `spin`, and at
// nothing else.
Lever.applySpin = function(spin)
	b = self.bar
	r = self.barArm
	b.setAngularVelocity spin
	b.setVelocity -spin * r[1], spin * r[0]
	// Kept because a rider whose mass the solver has been told to lie about
	// cannot have its own momentum read back off it; see Balance.momentum.
	self.spin = spin
end function

Lever.onStop = function
	super.onStop
	self.spin = 0
end function

// The pin already holds the bar still, so there is no resting jitter to
// crush -- and settling would stall a bar that is tipping slowly under a
// load, which is a lever doing its job rather than a part at rest.  Angular
// damping is what quiets this one.
Lever.settle = function(dt)
end function

//----------------------------------------------------------------------
// Appearance.  A lever is several pictures, not one: the bar turns and the
// fulcrum does not.  The composite that `image` builds is for the palette.
//----------------------------------------------------------------------

Lever.barImageKey = function
	s = self.spec
	return "lever-bar:" + s.length + "x" + s.thickness + ":" + s.pivotFrac +
	  ":" + s.color
end function

Lever.barImage = function
	key = self.barImageKey
	if not artUtil.cache.hasIndex(key) then artUtil.cache[key] = self.drawBar
	return artUtil.cache[key]
end function

Lever.drawBar = function
	s = self.spec
	w = s.length; h = s.thickness
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.color
	g.fillRect 0, h - 2, w, 2, "#FFFFFF38"
	g.fillRect 0, 0, w, 2, "#00000038"
	g.drawRect 0, 0, w, h, "#00000070", 2
	// The bolt, drawn where the bar actually turns: on an off-center lever
	// it is the only thing that says which arm is the long one.
	d = h * 0.7
	bx = w / 2 + s.pivotFrac * w / 2 - d / 2
	g.fillEllipse bx, (h - d) / 2, d, d, "#404850"
	g.drawEllipse bx, (h - d) / 2, d, d, "#00000090", 1
	return g.getImage
end function

Lever.fulcrumImageKey = function
	s = self.spec
	return "lever-fulcrum:" + self.fulcrumHalfWidth + "x" + s.fulcrumHeight +
	  ":" + s.thickness + ":" + s.fulcrumColor
end function

Lever.fulcrumImage = function
	key = self.fulcrumImageKey
	if not artUtil.cache.hasIndex(key) then
		artUtil.cache[key] = self.drawFulcrum
	end if
	return artUtil.cache[key]
end function

Lever.drawFulcrum = function
	s = self.spec
	hw = self.fulcrumHalfWidth
	h = s.fulcrumHeight + s.thickness / 2
	g = artUtil.canvas(hw * 2, h)
	// Inset by the pen width, so the outline lands inside the canvas.
	pts = [[hw, h - 1], [hw * 2 - 1, 1], [1, 1]]
	g.fillPoly pts, s.fulcrumColor
	g.drawPoly pts, "#00000070", 2
	g.line 1, 1, hw * 2 - 1, 1, "#00000040", 2
	return g.getImage
end function

Lever.imageKey = function
	return "lever:" + self.barImageKey + "/" + self.fulcrumImageKey
end function

// The palette icon: the whole assembly at rest, laid out exactly as the
// sprites sit in the world.
Lever.makeImage = function
	sz = self.size
	g = artUtil.canvas(sz[0], sz[1])
	self.drawAssembly g
	return g.getImage
end function

// Subclass hook: draw the part at rest into `g`, whose origin is the bottom
// left corner of the footprint.
Lever.drawAssembly = function(g)
	s = self.spec
	sz = self.size
	pv = self.pivotLocal
	// Where the pivot lands in a picture of the footprint.
	px = sz[0] / 2 + pv[0]
	py = sz[1] / 2 + pv[1]
	f = self.fulcrumImage
	g.drawImage f, px - f.width / 2, py - f.height
	g.drawImage self.barImage, 0, py - s.thickness / 2
end function

// Fulcrum first, so that the bar draws over it.
Lever.makeSprites = function
	self.spriteDisp = self.world.partDisp
	self.fulcrumSprite = new Sprite
	self.fulcrumSprite.image = self.fulcrumImage
	self.barSprite = new Sprite
	self.barSprite.image = self.barImage
	for sp in [self.fulcrumSprite, self.barSprite]
		self.sprites.push sp
		self.spriteDisp.sprites.push sp
	end for
end function

// No sprite here is centered on its body's origin -- the bar and the fulcrum
// are both pinned at the pivot -- so each one is placed by hand, from its own
// center's offset in the body's frame.
Lever.syncSprites = function
	if not self.bodies then return     // destroyed
	s = self.spec
	pv = self.pivotLocal

	// The bar's picture is centered on the bar, which is `pivotFrac` of an
	// arm away from the origin it turns about.
	o = self.bar.position
	a = self.bar.angle
	self.barSprite.x = o[0] - pv[0] * cos(a)
	self.barSprite.y = o[1] - pv[0] * sin(a)
	self.barSprite.rotation = a * 180 / pi

	// The fulcrum's is centered half its height below the apex.
	o = self.fulcrum.position
	a = self.fulcrum.angle
	h = (s.fulcrumHeight + s.thickness / 2) / 2
	self.fulcrumSprite.x = o[0] + h * sin(a)
	self.fulcrumSprite.y = o[1] - h * cos(a)
	self.fulcrumSprite.rotation = a * 180 / pi
end function

