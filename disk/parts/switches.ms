//----------------------------------------------------------------------
// Switches: the parts that decide whether a net is live.
//
// All the interesting work in this half of the game is mechanical.  A switch
// is electrically the dullest thing there is -- two terminals, joined or not
// (`conducts`) -- and everything that makes one worth placing is what closes
// it: something resting on a plate, a ball rolling into a paddle.  So the
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
// Toggle switch: a paddle that stands over to one side or the other.
//
// The paddle is a bar on a pin, which is a Lever -- so this is one, and it
// inherits the projection that makes a blow to the paddle come out as spin
// about the hinge rather than being thrown away.  What it does not inherit
// is any of the geometry: the pivot is at the foot of the bar rather than
// under its middle, the bar stands up rather than lying along the part, and
// the fulcrum is a housing a grid cell tall with a post at each end, which
// are the two terminals.  A ball reaches the paddle by rolling along the top
// of that housing, which is why it is a cell tall: snapped, that surface is
// level with the platform beside it and the run across is unbroken.
//
// It is a Lever and not a Switch, MiniScript having one parent per class, so
// the four lines of Switch are repeated below rather than inherited.  The
// pin is the part worth sharing; `conducts` is three words.
//
// Both rest positions are `throwAngle` from vertical -- left is off, right
// is on -- and that symmetry is the point of the part.  A blade switch can
// only be knocked shut, so a ball may turn a thing on and never off again;
// this one is thrown by a ball coming from either side, which is what makes
// a machine able to change its own mind.
//
// A real toggle snaps over center and stays where it is put.  Half of that
// is free here: a paddle leaning either way has its weight out to that side,
// so gravity itself pushes it further over, and the thing is bistable with
// no help at all.  What gravity cannot do is the last few degrees, because
// its leverage falls to nothing exactly at upright -- so a paddle stood
// straight up would sit there.  That is what `detent` is for: a constant
// torque away from vertical, toward whichever side the paddle is already on,
// which fills in the dead spot and makes the throw a snap rather than a
// topple.  How big it is, is how hard a ball has to hit to flip the switch.
// Past upright is where the state changes, since that is the moment the
// outcome stops being in doubt.
//----------------------------------------------------------------------

globals.ToggleSwitch = new Lever
ToggleSwitch.typeName = "toggleSwitch"
ToggleSwitch.displayName = "Toggle Switch"
ToggleSwitch.defaultSpec = Lever.defaultSpec + {"length": 30, "thickness": 10,
  // A whole grid cell tall, so that the top surface lands on the lattice
  // when the part is snapped, level with a platform's: that surface is what
  // a ball rolls along on its way into the paddle, and a switch sunk half a
  // cell below the run it sits in is a step, not a switch.
  "fulcrumHeight": 20, "baseWidth": 40,
  // How far below that surface the paddle is hinged.  Deep enough that the
  // foot of the paddle stays inside the housing at full throw, shallow
  // enough that it is not swinging about in a cellar.
  "pivotDepth": 4,
  "color": "#C8CED6", "gripColor": "#D8442C", "fulcrumColor": "#3A4450",
  "density": 2, "friction": 0.5, "restitution": 0.05,
  // Stiff, so a thrown paddle stops rather than bouncing against its stop.
  "angularDamping": 6,
  "throwAngle": 30 * pi / 180,
  // The detent, as a multiple of the torque the paddle's own weight would
  // make held straight out.  This one is the whole of what holds the paddle
  // at the top of its travel and most of what a ball has to overcome, so it
  // is the knob to turn if the switch is too easy or too stubborn.
  "detent": 0.6,
  "startOpen": true}

ToggleSwitch.closed = false

ToggleSwitch.init = function
	super.init
	self.closed = self.startClosed
end function

ToggleSwitch.startClosed = function
	return not self.spec.startOpen
end function

// The two ways it can be authored to start, which a click in the editor
// walks through.  See the note on states in part.ms.
ToggleSwitch.stateSpecs = function
	return [{"startOpen": true}, {"startOpen": false}]
end function

// A new starting state is a new resting angle for the paddle, which
// placeBodies works out for itself from startTilt; what it cannot know is
// that the contacts have moved with it.
ToggleSwitch.applyState = function
	self.closed = self.startClosed
	if self.world != null then self.world.circuitDirty = true
	super.applyState
end function

// Off stands to the left of vertical, on to the right.
ToggleSwitch.startTilt = function
	if self.spec.startOpen then return pi / 2 + self.spec.throwAngle
	return pi / 2 - self.spec.throwAngle
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// Wide enough for the paddle's corner at full throw, and never narrower than
// the base the terminals stand on; tall enough for the paddle leaning at
// that same angle, above a housing it stands the full height of.
//
// Nothing reaches below the housing, so the bottom of the footprint is the
// bottom of the housing -- which is what makes snapping the footprint put
// the top surface on the lattice, `fulcrumHeight` being a whole cell.
ToggleSwitch.size = function
	s = self.spec
	c = cos(s.throwAngle); sn = sin(s.throwAngle)
	w = 2 * (s.length * sn + s.thickness / 2 * c)
	if w < s.baseWidth then w = s.baseWidth
	rise = s.length * c + s.thickness / 2 * sn
	return [w, s.fulcrumHeight - s.pivotDepth + rise]
end function

// `pivotDepth` below the top of the housing, on its centerline.
ToggleSwitch.pivotLocal = function
	s = self.spec
	return [0, -self.size[1] / 2 + s.fulcrumHeight - s.pivotDepth]
end function

// The housing's center, measured down from the pivot the two bodies share.
// Everything about the base -- its shape, its picture, its posts -- is
// written against this rather than against the part's own center, because
// the pivot is the one point the paddle and the housing agree on.
ToggleSwitch.baseOffset = function
	s = self.spec
	return s.pivotDepth - s.fulcrumHeight / 2
end function

// The base runs the whole footprint, not a triangle under the pivot.
ToggleSwitch.fulcrumHalfWidth = function
	return self.size[0] / 2
end function

// Where the paddle stands now, measured the way startTilt is: from the
// part's own angle, so that upright is pi/2 and the two rest positions are
// `throwAngle` either side of it.
ToggleSwitch.tilt = function
	if self.bar == null then return self.startTilt
	return self.bar.angle - self.spec.angle
end function

//----------------------------------------------------------------------
// Bodies
//----------------------------------------------------------------------

ToggleSwitch.makeBodies = function
	s = self.spec
	pv = self.pivotLocal
	// The paddle's origin is the pivot at its foot, so the box it carries
	// sits half a length out along the bar.
	self.bar = self.addBody(pv[0], pv[1])
	sh = self.bar.addBox(s.length, s.thickness, s.length / 2, 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	sh.setFilter config.catDefault, config.maskBar

	// The housing hangs below the pivot, which sits `pivotDepth` under its
	// top surface rather than at its middle.
	self.fulcrum = self.addBody(pv[0], pv[1])
	fsh = self.fulcrum.addBox(self.fulcrumHalfWidth * 2, s.fulcrumHeight,
	  0, self.baseOffset, 0, 1)
	fsh.setRestitution s.restitution
	fsh.setFriction s.friction
	fsh.setFilter config.catFulcrum, config.maskFulcrum
end function

// A post at each end of the base, on the base's own body.
ToggleSwitch.terminalLocals = function
	pv = self.pivotLocal
	x = self.size[0] / 2 - 6
	y = pv[1] + self.baseOffset
	return [[-x, y, 1], [x, y, 1]]
end function

// The paddle starts wherever the design says, which is not the part's angle.
ToggleSwitch.placeBody = function(b)
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

// Lever's travel is symmetric about the authored angle; this one is
// symmetric about upright, which is a quarter turn from it.
ToggleSwitch.pinBar = function
	s = self.spec
	b = self.bar
	t = self.tilt
	lo = pi / 2 - s.throwAngle
	hi = pi / 2 + s.throwAngle
	stop = 0
	if t < lo then
		b.setAngle s.angle + lo
		stop = -1
	else if t > hi then
		b.setAngle s.angle + hi
		stop = 1
	end if
	p = self.pivotWorld
	b.setPosition p[0], p[1]
	return stop
end function

// Away from upright, toward whichever side the paddle is already on, and
// hard enough to beat its own weight there.  See the header.
ToggleSwitch.detentTorque = function
	s = self.spec
	dir = -1
	if self.tilt > pi / 2 then dir = 1
	return dir * s.detent * self.bar.mass * config.gravity * s.length / 2
end function

ToggleSwitch.update = function(dt)
	stop = self.pinBar
	spin = (self.momentum + self.detentTorque * dt) / self.generalizedMass
	// Sitting against a stop: it may leave, but it may not lean harder.
	if spin * stop > 0 then spin = 0
	self.applySpin spin
	// Over center is over: the detent will carry it the rest of the way.
	self.setClosed self.tilt < pi / 2
end function

ToggleSwitch.setClosed = function(v)
	if v == self.closed then return
	self.closed = v
	if self.world != null then self.world.circuitDirty = true
end function

ToggleSwitch.conducts = function(i, j)
	return self.closed
end function

ToggleSwitch.onStop = function
	super.onStop
	self.closed = self.startClosed
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

ToggleSwitch.barImageKey = function
	s = self.spec
	return "paddle:" + s.length + "x" + s.thickness + ":" + s.color + ":" +
	  s.gripColor
end function

// The paddle lies along +x with its pivot at x = 0, which is how the bar of
// a Lever is drawn; standing it up is the body's angle, not the picture's.
// It tapers, because a plain stick at this size reads as a lever arm and the
// thing that says "toggle" is a broad thumb end on a narrow neck.
ToggleSwitch.drawBar = function
	s = self.spec
	w = s.length; h = s.thickness
	g = artUtil.canvas(w, h)
	neck = h * 0.3
	quad = [[1, h / 2 - neck], [w - 1, 1], [w - 1, h - 1], [1, h / 2 + neck]]
	g.fillPoly quad, s.color
	g.drawPoly quad, "#00000070", 1
	// The thumb end, in the one loud color on the part, so that which way it
	// is leaning is readable at a glance across the board.
	g.fillRect w - 8, 2, 6, h - 4, s.gripColor
	g.drawRect w - 8, 2, 6, h - 4, "#00000060", 1
	// The hinge bolt, at the foot.
	artUtil.fillCircle g, 3, h / 2, 2, "#404850"
	return g.getImage
end function

ToggleSwitch.fulcrumImageKey = function
	s = self.spec
	return "toggleBase:" + self.fulcrumHalfWidth + "x" + s.fulcrumHeight +
	  ":" + s.pivotDepth + ":" + s.thickness + ":" + s.fulcrumColor
end function

ToggleSwitch.drawFulcrum = function
	s = self.spec
	w = self.fulcrumHalfWidth * 2
	h = s.fulcrumHeight
	g = artUtil.canvas(w, h)
	artUtil.fillRoundRect g, 0, 0, w, h, 3, s.fulcrumColor
	g.fillRect 2, h - 3, w - 4, 2, "#FFFFFF20"
	g.drawRect 0, 0, w, h, "#00000070", 1
	// The slot the paddle comes up out of, wide enough to still be under it
	// at full throw: the paddle crosses the top surface `pivotDepth` above
	// the hinge, leaning, so it cuts the surface wider than it is thick.
	slot = s.pivotDepth * tan(s.throwAngle) + s.thickness / 2 / cos(s.throwAngle)
	g.fillRect w / 2 - slot - 1, h - 3, slot * 2 + 2, 3, "#00000060"
	// The two posts.  The picture is centered on the housing, and the
	// terminals are given in the part's frame, so they come back by the same
	// offset that put the housing under the pivot.
	cy = self.pivotLocal[1] + self.baseOffset
	for t in self.terminalLocals
		artUtil.fillCircle g, w / 2 + t[0], h / 2 + t[1] - cy, 4,
		  config.termPostColor
		artUtil.drawCircle g, w / 2 + t[0], h / 2 + t[1] - cy, 4,
		  "#00000070", 1
	end for
	return g.getImage
end function

ToggleSwitch.imageKey = function
	return "toggleSwitch:" + self.barImageKey + "/" + self.fulcrumImageKey
end function

// Neither picture is centered on the body's origin -- both bodies are pinned
// at the pivot -- so each is placed by hand from its own center's offset in
// that frame.
ToggleSwitch.syncSprites = function
	if not self.bodies then return
	s = self.spec
	o = self.bar.position
	a = self.bar.angle
	self.barSprite.x = o[0] + s.length / 2 * cos(a)
	self.barSprite.y = o[1] + s.length / 2 * sin(a)
	self.barSprite.rotation = a * 180 / pi

	o = self.fulcrum.position
	a = self.fulcrum.angle
	d = self.baseOffset
	self.fulcrumSprite.x = o[0] - d * sin(a)
	self.fulcrumSprite.y = o[1] + d * cos(a)
	self.fulcrumSprite.rotation = a * 180 / pi
end function

// The palette icon: the whole thing at rest, laid out as the sprites sit.
ToggleSwitch.drawAssembly = function(g)
	s = self.spec
	sz = self.size
	pv = self.pivotLocal
	px = sz[0] / 2 + pv[0]
	py = sz[1] / 2 + pv[1]
	f = self.fulcrumImage
	g.drawImage f, px - f.width / 2, py + self.baseOffset - f.height / 2
	// The paddle is drawn at the angle it starts at, so the icon says which
	// way the switch comes -- and drawn by hand rather than blitted, because
	// PixelDisplay.drawImage cannot rotate.
	t = s.angle + self.startTilt
	c = cos(t); sn = sin(t)
	neck = s.thickness * 0.3
	hw = s.thickness / 2
	quad = []
	for uv in [[0, -neck], [s.length, -hw], [s.length, hw], [0, neck]]
		quad.push [px + uv[0] * c - uv[1] * sn, py + uv[0] * sn + uv[1] * c]
	end for
	g.fillPoly quad, s.color
	g.drawPoly quad, "#00000070", 1
	grip = []
	for uv in [[s.length - 7, -hw + 1], [s.length - 1, -hw + 1],
	  [s.length - 1, hw - 1], [s.length - 7, hw - 1]]
		grip.push [px + uv[0] * c - uv[1] * sn, py + uv[0] * sn + uv[1] * c]
	end for
	g.fillPoly grip, s.gripColor
	g.drawPoly grip, "#00000060", 1
end function
