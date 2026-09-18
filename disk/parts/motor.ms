//----------------------------------------------------------------------
// Motor: a case bolted to the board, a gearwheel turning on the front of
// it, and one terminal to power it.
//
// The gearwheel half is a Gearwheel and nothing more, so a motor drives a
// geared train or a belted one with equal ease, and torque.ms never learns
// that this hub is any different from the rest.  What is different is where
// the turning comes from.
//
// Its torque falls off in a straight line with speed, from `torque` at a
// standstill to nothing at `freeSpin` -- which is a real motor's curve, and
// is also the only thing that gives this one a speed at all: gears weigh
// almost nothing at our scale, so constant torque alone would take even a
// weak motor to a blur in a step or two.
//
// What that curve buys is the behavior under load.  Hang more on it than its
// torque can hold and it does not simply give up: it slows, which raises its
// torque, until the two meet -- so it stalls under exactly its rated load,
// creeps under a little more, and pays out faster the heavier the load gets,
// bearing down harder all the way.  A winch with no brake, which is what it
// is.
//
// ELECTRICALLY it is the simplest thing there is: one terminal, grounded
// through the pegboard like everything else, and nothing at all from either
// half of that curve unless circuit.ms has found a live net that reaches it.
// Both halves, because both of them are the same electromagnetism: an open
// circuit carries no current, so it makes no torque to drive with and none
// to resist with either.  Gating only the drive would leave an unwired motor
// dragging on `torque / freeSpin`, which at our scale is ten times the
// moment of the gears it sits among -- so a motor dropped into a train and
// not plugged in would quietly seize the whole thing.  What is left when it
// is off is ordinary bearing friction, which is what `angularDamping` is
// here for, and which is why this one has the same damping a plain gear has
// rather than none.
//
// THE TWO BODIES are the hub and the case, in that order, because everything
// torque.ms asks of a Gear is answered out of `bodies[0]`.  They need a good
// deal of keeping apart:
//
//   - they overlap, and so does a gear meshed with this one, so hubs and
//     cases are filtered against each other wholesale (config.catHub /
//     catCase), on the same reasoning as the lever's pieces.
//   - `spec.angle` on a gear is its *tooth phase*, and changes whenever a
//     train is built.  The case must not be placed from it or it would spin
//     with the gearwheel, so it has a placeBody of its own.
//   - the sprites are in the opposite order from the bodies, since the case
//     is drawn behind the wheel that turns on it.
//----------------------------------------------------------------------

globals.Motor = new Gearwheel
Motor.typeName = "motor"
Motor.displayName = "Motor"
Motor.defaultSpec = Gearwheel.defaultSpec + {"teeth": 12, "ringRadius": 10,
  "color": config.gearMotorColor,
  // Newton-meters.  What it means in play is the load it stalls at, which is
  // this over the drum radius it is pulling on: 3 N-m on a spool's 10 cm drum
  // is 30 N, so it walks away with a kilogram, labors at two, and is held by
  // three.
  "torque": 3,
  "freeSpin": 3,      // radians/second with nothing to carry
  "dir": 1,           // 1 turns counterclockwise, -1 clockwise
  // Bearing friction: what slows an unpowered motor, since with no current
  // there is nothing else left to.  See the header.
  "angularDamping": 0.5,
  "caseWidth": 60, "caseHeight": 44, "caseColor": config.motorCaseColor}

// Which body is which.  The hub has to be first; see the header.
Motor.HUB = 0
Motor.CASE = 1

//----------------------------------------------------------------------
// Geometry.  The case hangs below the axle with its top edge on it, so the
// gearwheel stands proud above the box and the lower band of the box stays
// clear for the terminal -- which is a motor seen from the front, and also
// the only arrangement in which both halves are visible at once.
//----------------------------------------------------------------------

Motor.caseCenter = function
	return [0, -self.spec.caseHeight / 2]
end function

// Where the terminal post sits on the case, in the case's own frame.  The
// art and the geometry both work from this, because a terminal drawn
// anywhere but where a wire actually fastens is worse than no terminal at
// all.
Motor.terminalOffset = function
	return [-self.spec.caseWidth / 2 + 7, -self.spec.caseHeight / 2 + 13]
end function

Motor.terminalLocals = function
	c = self.caseCenter
	t = self.terminalOffset
	return [[c[0] + t[0], c[1] + t[1], Motor.CASE]]
end function

Motor.size = function
	s = self.spec
	w = s.caseWidth
	if self.outerRadius * 2 > w then w = self.outerRadius * 2
	return [w, s.caseHeight + self.outerRadius]
end function

// The footprint is not centered on the axle the way a plain gear's is: the
// case is all below it.  Everything that asks where a part sits goes through
// here, so the asymmetry only has to be said once.
Motor.designBounds = function
	sz = self.size
	return [self.spec.x - sz[0] / 2, self.spec.y - self.spec.caseHeight,
	  sz[0], sz[1]]
end function

Motor.makeBodies = function
	super.makeBodies                // the hub, as bodies[0]
	s = self.spec
	c = self.caseCenter
	b = self.addBody(c[0], c[1])
	sh = b.addBox(s.caseWidth, s.caseHeight, 0, 0, 0, 1)
	sh.setFilter config.catCase, config.maskCase
	sh.setRestitution 0.1
	sh.setFriction 0.7
	b.setGravityScale 0
end function

// The case is bolted to the board facing one way, and stays there while the
// gearwheel phases round; see the header on spec.angle.
Motor.placeBody = function(b)
	if self.bodies.len > Motor.CASE and refEquals(b, self.bodies[Motor.CASE]) then
		s = self.spec
		b.setAngle 0
		b.setPosition s.x + b.localX, s.y + b.localY
		b.setVelocity 0, 0
		b.setAngularVelocity 0
		return
	end if
	super.placeBody b
end function

// Play: the hub turns, the case does not.  Part.onPlay has just made both of
// them the part's own bodyType, which is the hub's.
Motor.onPlay = function
	super.onPlay
	self.bodies[Motor.CASE].setType physics.STATIC
end function

//----------------------------------------------------------------------
// What torque.ms asks of us
//----------------------------------------------------------------------

Motor.driveTorque = function(dt)
	if not self.powered then return 0
	s = self.spec
	return s.torque * s.dir * config.torqueUnit
end function

// Off with the drive, and for the same reason: see the header.
Motor.dragTorque = function(dt)
	if not self.powered then return 0
	s = self.spec
	if s.freeSpin <= 0 then return 0
	return s.torque * config.torqueUnit / s.freeSpin
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

// The sprites are [case, hub] where the bodies are [hub, case], so that the
// wheel draws over the box it turns on.
Motor.spriteBody = [1, 0]

Motor.makeSprites = function
	self.spriteDisp = self.world.partDisp
	for img in [self.caseImage, self.image]
		sp = new Sprite
		sp.image = img
		self.sprites.push sp
		self.spriteDisp.sprites.push sp
	end for
end function

Motor.syncSprites = function
	for i in self.sprites.indexes
		b = self.bodies[Motor.spriteBody[i]]
		sp = self.sprites[i]
		sp.x = b.x
		sp.y = b.y
		sp.rotation = b.angle * 180 / pi
	end for
end function

Motor.imageKey = function
	return super.imageKey + ":" + self.spec.dir
end function

// The gearwheel, with the arrow that says which way it drives, drawn on the
// hub so that it stays put while the teeth go round.
Motor.makeImage = function
	img = super.makeImage
	g = artUtil.canvas(img.width, img.height)
	g.drawImage img, 0, 0
	self.drawArrow g, img.width / 2, img.height / 2
	return g.getImage
end function

Motor.drawArrow = function(g, cx, cy)
	r = self.pitchRadius * 0.55
	d = self.spec.dir
	c = config.gearArrowColor
	// Three quarters of a turn, leaving room for the head.
	prev = null
	for i in range(0, 12, 1)
		a = d * (i / 12 * 1.5 * pi - 0.4)
		p = [cx + r * cos(a), cy + r * sin(a)]
		if prev != null then g.line prev[0], prev[1], p[0], p[1], c, 2
		prev = p
	end for
	// The head, tangent to the arc at the end of it.
	a = d * (1.5 * pi - 0.4)
	tip = [cx + r * cos(a + d * 0.5), cy + r * sin(a + d * 0.5)]
	back = r * 0.45
	left = [cx + (r + back / 2) * cos(a), cy + (r + back / 2) * sin(a)]
	right = [cx + (r - back / 2) * cos(a), cy + (r - back / 2) * sin(a)]
	g.fillPoly [tip, left, right], c
end function

// The case gets its own cache entry, since it is a second sprite rather than
// part of the picture that turns.
Motor.caseImage = function
	s = self.spec
	key = "motorCase:" + s.caseWidth + "x" + s.caseHeight + ":" + s.caseColor
	if not artUtil.cache.hasIndex(key) then
		artUtil.cache[key] = self.makeCaseImage
	end if
	return artUtil.cache[key]
end function

Motor.makeCaseImage = function
	s = self.spec
	w = s.caseWidth; h = s.caseHeight
	g = artUtil.canvas(w, h)
	artUtil.fillRoundRect g, 0, 0, w, h, 5, s.caseColor
	g.fillRect 3, h - 4, w - 6, 3, "#FFFFFF30"
	g.fillRect 3, 2, w - 6, 3, "#00000035"
	g.drawRect 1, 1, w - 2, h - 2, "#00000050", 1
	// Cooling fins down the exposed lower band, which is the part of the case
	// the gearwheel does not cover.
	x = 18
	while x < w - 8
		g.line x, 6, x, h / 2 - 3, config.motorVentColor, 2
		x = x + 6
	end while
	// The terminal post, drawn last so it stands over the fins, and at the
	// one spot terminalOffset names.
	t = self.terminalOffset
	self.drawTerminal g, w / 2 + t[0], h / 2 + t[1]
	return g.getImage
end function

Motor.drawTerminal = function(g, cx, cy)
	artUtil.fillCircle g, cx, cy, 4.5, "#00000060"
	artUtil.fillCircle g, cx, cy, 3.5, config.termPostColor
	g.line cx - 2, cy, cx + 2, cy, "#403020", 1
end function

// The palette needs the whole motor in one picture; the part itself is two
// sprites, because only one of them turns.
Motor.paletteImage = function
	s = self.spec
	key = self.imageKey + ":palette"
	if artUtil.cache.hasIndex(key) then return artUtil.cache[key]
	ro = self.outerRadius
	sz = self.size
	g = artUtil.canvas(sz[0], sz[1])
	// The axle sits one gear radius down from the top of the picture.
	cx = sz[0] / 2
	cy = sz[1] - ro
	ci = self.caseImage
	g.drawImage ci, cx - ci.width / 2, cy - ci.height
	hi = self.image
	g.drawImage hi, cx - hi.width / 2, cy - hi.height / 2
	artUtil.cache[key] = g.getImage
	return artUtil.cache[key]
end function
