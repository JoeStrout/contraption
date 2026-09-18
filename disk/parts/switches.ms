//----------------------------------------------------------------------
// Switches: the parts that decide whether a net is live.
//
// All the interesting work in this half of the game is mechanical.  A switch
// is electrically the dullest thing there is -- two terminals, joined or not
// (`conducts`) -- and everything that makes one worth placing is what closes
// it: something resting on a plate, something knocking a blade over.  So the
// base class here is four lines, and the two parts below share nothing but
// those four lines.
//
// `closed` is runtime state and lives on the part, never in spec; what goes
// in spec is how the switch is *authored* to start.  Changing it sets
// world.circuitDirty, which is how a switch asks circuit.ms for another
// flood fill -- see the note there about why that is a single pass and not
// an iteration to a fixed point.
//----------------------------------------------------------------------

globals.Switch = new Part
Switch.typeName = "switch"          // abstract: no catalog entry names it
Switch.displayName = "Switch"
Switch.closed = false               // runtime

Switch.conducts = function(i, j)
	return self.closed
end function

Switch.setClosed = function(v)
	if v == self.closed then return
	self.closed = v
	self.showState
	if self.world != null then self.world.circuitDirty = true
end function

// Subclass hook: the switch has just moved, so look like it.
Switch.showState = function
end function

// Subclass hook: the state the design authors, which is what Stop restores.
Switch.startClosed = function
	return false
end function

Switch.init = function
	self.closed = self.startClosed
end function

Switch.makeSprites = function
	super.makeSprites
	self.showState
end function

Switch.onStop = function
	super.onStop
	self.closed = self.startClosed
	self.showState
end function

//----------------------------------------------------------------------
// Pressure plate: closed while anything is resting on it.
//
// It does not actually move, and it does not need to.  What tells us
// something is on it is a row of point queries in a thin band just above its
// face: a ball sitting on the plate occupies that band, and so does the
// bottom edge of a block, while a part merely standing alongside does not.
// `shapesAt` is a real query against the world's shapes, so this stays
// correct for any shape we add later, and it costs a handful of point tests
// a step.
//
// The band is sampled across the plate rather than at its middle because a
// ball parked near one end is still on the plate; seven samples over 60
// pixels catches anything as wide as the smallest ball we have.
//----------------------------------------------------------------------

globals.PressurePlate = new Switch
PressurePlate.typeName = "pressurePlate"
PressurePlate.displayName = "Pressure Plate"
PressurePlate.bodyType = physics.STATIC
PressurePlate.defaultSpec = Part.defaultSpec + {"width": 60, "height": 20,
  "color": "#7A8894", "plateColor": "#B0BCC8",
  "restitution": 0.05, "friction": 0.8}

PressurePlate.senseHeight = 3       // how far above the face to look
PressurePlate.senseCount = 7        // ...and at how many points across it
PressurePlate.travel = 3            // how far the face visibly sinks

PressurePlate.size = function
	return [self.spec.width, self.spec.height]
end function

// One terminal at each end, on the body of the plate.
PressurePlate.terminalLocals = function
	s = self.spec
	return [[-s.width / 2 + 6, -s.height / 2 + 5],
	  [s.width / 2 - 6, -s.height / 2 + 5]]
end function

PressurePlate.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

PressurePlate.update = function(dt)
	super.update dt
	self.setClosed self.loaded
end function

// Anything in the band above the face, other than ourselves.
PressurePlate.loaded = function
	if self.world == null or not self.bodies then return false
	s = self.spec
	c = cos(s.angle); sn = sin(s.angle)
	n = PressurePlate.senseCount
	ly = s.height / 2 + PressurePlate.senseHeight
	for i in range(0, n - 1, 1)
		lx = -s.width / 2 + 4 + (s.width - 8) * i / (n - 1)
		x = s.x + lx * c - ly * sn
		y = s.y + lx * sn + ly * c
		for sh in self.world.phys.shapesAt(x, y)
			if not sh.body.hasIndex("part") then continue
			if util.sameRef(sh.body.part, self) then continue
			return true
		end for
	end for
	return false
end function

PressurePlate.showState = function
	if not self.sprites then return
	self.sprites[0].image = self.stateImage(self.closed)
end function

PressurePlate.imageKey = function
	s = self.spec
	return "plate:" + s.width + "x" + s.height + ":" + s.color + ":" +
	  s.plateColor
end function

// Up and down are two pictures of the same size, so the sprite never moves:
// what sinks is the face drawn inside it.
PressurePlate.stateImage = function(down)
	key = self.imageKey + ":" + down
	if not artUtil.cache.hasIndex(key) then
		artUtil.cache[key] = self.drawPlate(down)
	end if
	return artUtil.cache[key]
end function

PressurePlate.image = function
	return self.stateImage(self.closed)
end function

PressurePlate.drawPlate = function(down)
	s = self.spec
	w = s.width; h = s.height
	g = artUtil.canvas(w, h)
	// The housing: a shallow box with the face riding in it.
	g.fillRect 0, 0, w, h - 4, s.color
	g.drawRect 0, 0, w, h - 4, "#00000060", 1
	// The springs at each end, which is what says this one gives.
	coil = artUtil.multiply(s.color, "#808898")
	for x in [7, w - 7]
		for k in [0, 1, 2]
			y = 4 + k * 3
			g.line x - 4, y, x + 4, y + 1.5, coil, 1
		end for
	end for
	drop = 0
	if down then drop = PressurePlate.travel
	g.fillRect 2, h - 6 - drop, w - 4, 6, s.plateColor
	g.fillRect 2, h - 2 - drop, w - 4, 2, "#FFFFFF50"
	g.drawRect 2, h - 6 - drop, w - 4, 6, "#00000070", 1
	// The terminals, at the spots terminalLocals names.
	for t in self.terminalLocals
		artUtil.fillCircle g, w / 2 + t[0], h / 2 + t[1], 3.5,
		  config.termPostColor
	end for
	return g.getImage
end function

//----------------------------------------------------------------------
// Blade switch: a knife switch, thrown by whatever hits it.
//
// The blade is a bar on a pin, which is a Lever -- so this is one, and it
// inherits the projection that makes a blow to the blade come out as spin
// about the hinge rather than being thrown away.  What it does not inherit
// is any of the geometry: the pivot is at one end of the bar instead of
// under its middle, the travel runs from level to `openAngle` rather than
// symmetrically either way, and the fulcrum is a base with a post at each
// end, which are the two terminals.
//
// It is a Lever and not a Switch, MiniScript having one parent per class, so
// the four lines of Switch are repeated below rather than inherited.  The
// pin is the part worth sharing; `conducts` is three words.
//
// A real knife switch snaps over center and stays where it is put, and this
// one does too, from a detent torque that points at whichever end of the
// travel the blade is nearer.  Make that torque bigger than the blade's own
// weight can ever be (`detent` is in units of exactly that) and the switch
// is bistable about the halfway point: nudge it past the middle and it
// slams the rest of the way by itself, which is what a switch should feel
// like and also what keeps it from hovering half-closed and chattering.
//----------------------------------------------------------------------

// Near enough to level to count as made: a couple of degrees, which is well
// inside where the detent will have carried it anyway.
closeTilt = 3 * pi / 180

globals.BladeSwitch = new Lever
BladeSwitch.typeName = "bladeSwitch"
BladeSwitch.displayName = "Blade Switch"
BladeSwitch.defaultSpec = Lever.defaultSpec + {"length": 48, "thickness": 7,
  "fulcrumHeight": 12, "pivotFrac": -1,
  "color": "#C8CED6", "fulcrumColor": "#3A4450",
  "density": 2, "friction": 0.5, "restitution": 0.05,
  // Stiff, so a thrown blade stops rather than bouncing in its jaw.
  "angularDamping": 6,
  "openAngle": 65 * pi / 180,
  // The detent, as a multiple of the torque the blade's own weight makes.
  // Over 1 at every angle it can stand at, so both ends hold.
  "detent": 1.4,
  "startOpen": true}

BladeSwitch.closed = false

BladeSwitch.init = function
	super.init
	self.closed = self.startClosed
end function

BladeSwitch.startClosed = function
	return not self.spec.startOpen
end function

BladeSwitch.startTilt = function
	if self.spec.startOpen then return self.spec.openAngle
	return 0
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// The blade sweeps up and to the right of the hinge, so the part needs the
// height of that sweep above the bar, and a little width past each post.
BladeSwitch.headroom = function
	return self.spec.length * sin(self.spec.openAngle)
end function

BladeSwitch.size = function
	sz = super.size
	return [sz[0] + 12, sz[1]]
end function

// The base runs the whole footprint, not a triangle under the pivot.
BladeSwitch.fulcrumHalfWidth = function
	return self.size[0] / 2
end function

// Where the blade stands now, measured from the closed position.
BladeSwitch.tilt = function
	if self.bar == null then return self.startTilt
	return self.bar.angle - self.spec.angle
end function

//----------------------------------------------------------------------
// Bodies
//----------------------------------------------------------------------

BladeSwitch.makeBodies = function
	s = self.spec
	pv = self.pivotLocal
	self.bar = self.addBody(pv[0], pv[1])
	sh = self.bar.addBox(s.length, s.thickness, -pv[0], 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	sh.setFilter config.catDefault, config.maskBar

	// The base is centered on the footprint, which is not where the pivot is,
	// so its shape is offset back along the bar.
	self.fulcrum = self.addBody(pv[0], pv[1])
	hw = self.fulcrumHalfWidth
	h = s.fulcrumHeight + s.thickness / 2
	fsh = self.fulcrum.addBox(hw * 2, h, -pv[0], -h / 2, 0, 1)
	fsh.setRestitution s.restitution
	fsh.setFriction s.friction
	fsh.setFilter config.catFulcrum, config.maskFulcrum
end function

// A post at each end of the base, on the base's own body.
BladeSwitch.terminalLocals = function
	s = self.spec
	pv = self.pivotLocal
	return [[pv[0], pv[1], 1], [pv[0] + s.length, pv[1], 1]]
end function

// The blade starts wherever the design says, which is not the part's angle.
BladeSwitch.placeBody = function(b)
	if self.bar != null and refEquals(b, self.bar) then
		p = self.pivotWorld
		b.setAngle self.spec.angle + self.startTilt
		b.setPosition p[0], p[1]
		b.setVelocity 0, 0
		b.setAngularVelocity 0
		return
	end if
	super.placeBody b
end function

//----------------------------------------------------------------------
// The pin, and the detent that makes it a switch
//----------------------------------------------------------------------

// Lever's travel is symmetric about the authored angle; this one runs from
// level to openAngle and no further either way.
BladeSwitch.pinBar = function
	s = self.spec
	b = self.bar
	t = self.tilt
	stop = 0
	if t < 0 then
		b.setAngle s.angle
		stop = -1
	else if t > s.openAngle then
		b.setAngle s.angle + s.openAngle
		stop = 1
	end if
	p = self.pivotWorld
	b.setPosition p[0], p[1]
	return stop
end function

// Toward whichever end of the travel the blade is nearer, and hard enough to
// beat its own weight there.  See the header.
BladeSwitch.detentTorque = function
	s = self.spec
	dir = -1
	if self.tilt > s.openAngle / 2 then dir = 1
	return dir * s.detent * self.bar.mass * config.gravity * s.length / 2
end function

BladeSwitch.update = function(dt)
	stop = self.pinBar
	spin = (self.momentum + self.detentTorque * dt) / self.generalizedMass
	// Sitting against a stop: it may leave, but it may not lean harder.
	if spin * stop > 0 then spin = 0
	self.applySpin spin
	// Closed means home in the jaw, which is the stop at the bottom.
	self.setClosed self.tilt < closeTilt
end function

BladeSwitch.setClosed = function(v)
	if v == self.closed then return
	self.closed = v
	if self.world != null then self.world.circuitDirty = true
end function

BladeSwitch.conducts = function(i, j)
	return self.closed
end function

BladeSwitch.onStop = function
	super.onStop
	self.closed = self.startClosed
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

BladeSwitch.barImageKey = function
	s = self.spec
	return "blade:" + s.length + "x" + s.thickness + ":" + s.color
end function

BladeSwitch.drawBar = function
	s = self.spec
	w = s.length; h = s.thickness
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.color
	g.fillRect 0, h - 2, w, 2, "#FFFFFF60"
	g.fillRect 0, 0, w, 2, "#00000030"
	g.drawRect 0, 0, w, h, "#00000070", 1
	// The handle, at the end you throw it by, and the hinge bolt at the other.
	artUtil.fillCircle g, w - 4, h / 2, h * 0.8, "#D8442C"
	artUtil.drawCircle g, w - 4, h / 2, h * 0.8, "#00000070", 1
	artUtil.fillCircle g, 4, h / 2, h * 0.35, "#404850"
	return g.getImage
end function

BladeSwitch.fulcrumImageKey = function
	s = self.spec
	return "bladeBase:" + self.fulcrumHalfWidth + "x" + s.fulcrumHeight +
	  ":" + s.thickness + ":" + s.fulcrumColor
end function

BladeSwitch.drawFulcrum = function
	s = self.spec
	w = self.fulcrumHalfWidth * 2
	h = s.fulcrumHeight + s.thickness / 2
	g = artUtil.canvas(w, h)
	artUtil.fillRoundRect g, 0, 0, w, h, 3, s.fulcrumColor
	g.fillRect 2, h - 3, w - 4, 2, "#FFFFFF20"
	g.drawRect 0, 0, w, h, "#00000070", 1
	// The two posts, at the ends of the blade's travel: the hinge on the left
	// and the jaw the blade lands in on the right.  These are the terminals.
	// The base picture is centered on the footprint, and so are the
	// part-frame coordinates the terminals are given in.
	for t in self.terminalLocals
		artUtil.fillCircle g, w / 2 + t[0], h - 2, 4, config.termPostColor
		artUtil.drawCircle g, w / 2 + t[0], h - 2, 4, "#00000070", 1
	end for
	return g.getImage
end function

BladeSwitch.imageKey = function
	return "bladeSwitch:" + self.barImageKey + "/" + self.fulcrumImageKey
end function

// Both sprites are pinned at the pivot, which is not the middle of either
// picture, so each is placed from its own center's offset in the body frame.
BladeSwitch.syncSprites = function
	if not self.bodies then return
	s = self.spec
	pv = self.pivotLocal
	o = self.bar.position
	a = self.bar.angle
	self.barSprite.x = o[0] - pv[0] * cos(a)
	self.barSprite.y = o[1] - pv[0] * sin(a)
	self.barSprite.rotation = a * 180 / pi

	// The base's picture is centered on the footprint, half its height below
	// the line the blade lies along.
	o = self.fulcrum.position
	a = self.fulcrum.angle
	h = (s.fulcrumHeight + s.thickness / 2) / 2
	dx = -pv[0]; dy = -h
	self.fulcrumSprite.x = o[0] + dx * cos(a) - dy * sin(a)
	self.fulcrumSprite.y = o[1] + dx * sin(a) + dy * cos(a)
	self.fulcrumSprite.rotation = a * 180 / pi
end function

// The palette icon: the whole thing at rest, laid out as the sprites sit.
BladeSwitch.drawAssembly = function(g)
	s = self.spec
	sz = self.size
	pv = self.pivotLocal
	px = sz[0] / 2 + pv[0]
	py = sz[1] / 2 + pv[1]
	f = self.fulcrumImage
	g.drawImage f, px - pv[0] - f.width / 2, py - f.height
	// The blade is drawn at the angle it starts at, so the icon says which
	// way round the switch comes -- and drawn by hand rather than blitted,
	// because PixelDisplay.drawImage cannot rotate.
	t = self.spec.angle + self.startTilt
	c = cos(t); sn = sin(t)
	hw = s.thickness / 2
	quad = []
	for uv in [[0, -hw], [s.length, -hw], [s.length, hw], [0, hw]]
		quad.push [px + uv[0] * c - uv[1] * sn, py + uv[0] * sn + uv[1] * c]
	end for
	g.fillPoly quad, s.color
	g.drawPoly quad, "#00000070", 1
	grip = [px + (s.length - 4) * c, py + (s.length - 4) * sn]
	artUtil.fillCircle g, grip[0], grip[1], s.thickness * 0.8, "#D8442C"
	artUtil.drawCircle g, grip[0], grip[1], s.thickness * 0.8, "#00000070", 1
end function
