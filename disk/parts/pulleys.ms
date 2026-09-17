
//----------------------------------------------------------------------
// Pulley: a wheel a rope bends around.
//
// The wheel is the rope's turning point, and the rope's own constraint is
// what gives it purchase -- a pulley has no code of its own beyond being a
// place to route through.  This one hangs free: it has mass, it falls, and
// a load tied beneath it is how a block and tackle is built.
//----------------------------------------------------------------------

globals.Pulley = new Part
Pulley.typeName = "pulley"
Pulley.displayName = "Pulley"
Pulley.defaultSpec = Part.defaultSpec + {"radius": 5, "kg": 0.05,
  "color": "#B8C2CC", "restitution": 0.1, "friction": 0.5,
  "linearDamping": 0.05, "angularDamping": 0.5}

// The frame around the wheel: wide enough to see, with the hook below it.
Pulley.size = function
	r = self.spec.radius
	return [r * 3, r * 5]
end function

Pulley.hookDrop = function
	return self.spec.radius * 1.8
end function

// Tie point 0 is the wheel itself, which is what a rope routes over; tie
// point 1 is the hook below, which is what a load hangs from.
Pulley.tieLocals = function
	return [[0, self.spec.radius], [0, self.spec.radius - self.hookDrop]]
end function

Pulley.wrapRadius = function
	return self.spec.radius
end function

Pulley.makeBodies = function
	s = self.spec
	b = self.addBody
	r = s.radius
	dens = s.kg * config.pxPerMeter ^ 2 / (pi * r * r)
	sh = b.addCircle(r, 0, r, dens)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	// A pulley block hangs straight: letting it spin would swing the hook
	// (and the load under it) around the wheel.
	b.setFixedRotation
end function

Pulley.imageKey = function
	return "pulley:" + self.spec.radius + ":" + self.spec.color +
	  ":" + self.hookDrop
end function

Pulley.drawWheel = function(g, cx, cy, r, c)
	g.fillEllipse cx - r, cy - r, r * 2, r * 2, c
	g.drawEllipse cx - r, cy - r, r * 2, r * 2, "#00000090", 2
	g.fillEllipse cx - 1, cy - 1, 3, 3, "#3A444E"
end function

Pulley.makeImage = function
	s = self.spec
	sz = self.size
	r = s.radius
	g = artUtil.canvas(sz[0], sz[1])
	cx = sz[0] / 2
	// The wheel is where tie point 0 is, which is where the body's circle
	// is: half a radius above the middle of the footprint.
	cy = sz[1] / 2 + r
	// The hook, below the wheel.
	g.line cx, cy, cx, cy - self.hookDrop, "#5A6672", 3
	g.drawEllipse cx - 3, cy - self.hookDrop - 3, 6, 6, "#5A6672", 2
	self.drawWheel g, cx, cy, r, s.color
	return g.getImage
end function

//----------------------------------------------------------------------
// MountedPulley: the same wheel, bolted to a tie point.
//
// It has no body and no tie points of its own: its wheel *is* the tie point
// it is mounted on, so a rope routed over it pulls on whatever it is bolted
// to, at exactly the right place, with no joint of any kind in between.
// Rigid by construction rather than by constraint.
//----------------------------------------------------------------------

globals.MountedPulley = new Part
MountedPulley.typeName = "mountedPulley"
MountedPulley.displayName = "Mounted Pulley"
MountedPulley.defaultSpec = Part.defaultSpec + {"radius": 5, "host": 0,
  "tie": 0, "color": "#B8C2CC"}
// There is nowhere to put one but a tie point, so the editor shows where
// they are while this is being dragged.
MountedPulley.mountsOnTie = true

MountedPulley.size = function
	r = self.spec.radius
	return [r * 2.4, r * 2.4]
end function

MountedPulley.wrapRadius = function
	return self.spec.radius
end function

MountedPulley.hostPart = function
	if not self.spec.host then return null
	return self.world.partById(self.spec.host)
end function

// Our one tie point is the host's, verbatim: same body, same offset.
MountedPulley.makeTies = function
	self.ties = []
	host = self.hostPart
	if host == null then return
	tl = host.tieList
	if self.spec.tie >= tl.len then return
	t = tl[self.spec.tie]
	self.ties.push [t[0], t[1], t[2]]
end function

MountedPulley.makeBodies = function
end function

// Follows its host, wherever the host has got to.
MountedPulley.syncSprites = function
	if not self.sprites then return
	w = null
	if self.spec.host then w = self.tieWorld(0)
	if w == null then w = [self.spec.x, self.spec.y]
	self.sprites[0].x = w[0]
	self.sprites[0].y = w[1]
	self.sprites[0].rotation = 0
end function

MountedPulley.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sp = new Sprite
	sp.image = self.image
	self.sprites.push sp
	self.spriteDisp.sprites.push sp
end function

// It can only be put on a tie point, so that is what it snaps to.
MountedPulley.snapPose = function(world, x, y)
	t = world.tieAt(x, y, config.mountSnap, self)
	host = 0
	tie = 0
	if t != null then
		host = t[0].id
		tie = t[1]
	end if
	if host != self.spec.host or tie != self.spec.tie then
		self.spec.host = host
		self.spec.tie = tie
		self.ties = null
	end if
	if host then return [t[2], t[3]]
	return [x, y]
end function

MountedPulley.placementOK = function(world)
	if not self.spec.host then return false
	for p in world.parts
		if util.sameRef(p, self) then continue
		if p.typeName != self.typeName then continue
		if p.spec.host == self.spec.host and p.spec.tie == self.spec.tie then
			return false
		end if
	end for
	return true
end function

MountedPulley.hitTest = function(x, y)
	w = self.tieWorld(0)
	if w == null then w = [self.spec.x, self.spec.y]
	return (x - w[0]) ^ 2 + (y - w[1]) ^ 2 <= (self.spec.radius * 1.4) ^ 2
end function

MountedPulley.designBounds = function
	sz = self.size
	w = null
	if self.spec.host then w = self.tieWorld(0)
	if w == null then w = [self.spec.x, self.spec.y]
	return [w[0] - sz[0] / 2, w[1] - sz[1] / 2, sz[0], sz[1]]
end function

MountedPulley.dependsOn = function(other)
	return self.spec.host == other.id
end function

MountedPulley.imageKey = function
	return "mountedPulley:" + self.spec.radius + ":" + self.spec.color
end function

MountedPulley.makeImage = function
	s = self.spec
	sz = self.size
	g = artUtil.canvas(sz[0], sz[1])
	Pulley.drawWheel g, sz[0] / 2, sz[1] / 2, s.radius, s.color
	return g.getImage
end function
