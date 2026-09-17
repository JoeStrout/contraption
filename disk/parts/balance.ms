//----------------------------------------------------------------------
// Balance: a lever carrying a pan at each end, for weighing things.
//
// The pans ride a little above the ends of the bar and stay level however
// far the bar tips, which is what lets a ball sit on one instead of rolling
// off the moment the balance moves.  A real balance does that by hanging its
// pans from pivots; ours is more direct -- a pan is simply held where the
// bar end has got to, upright, every step.
//
// That leaves the assembly with the same single degree of freedom a plain
// lever has, so it is still solved the same way, with the pans joining in
// through the four hooks: each one adds its weight and whatever is riding on
// it to the momentum turning the bar, and adds `m * r^2` to the inertia
// resisting it.  A pan contributes no spin of its own -- it cannot turn --
// which is why it takes `m * r^2` rather than anything involving its own
// moment of inertia.
//----------------------------------------------------------------------

globals.Balance = new Lever
Balance.typeName = "balance"
Balance.displayName = "Balance"
Balance.defaultSpec = Lever.defaultSpec + {"fulcrumHeight": 40,
  "panWidth": 44, "panThickness": 8, "panGap": 2,
  "panColor": "#9AA6B2", "panDensity": 0.5, "panRestitution": 0.1,
  "panFriction": 0.8}

Balance.pans = null             // per-instance, see makeBodies
Balance.panSprites = null
Balance.panMass = null          // what a pan really weighs
Balance.panSolverMass = null    // what the solver was told this step
Balance.panV0 = null            // its velocity going into the step

Balance.init = function
	super.init
	self.pans = []
	self.panSprites = []
	self.panMass = []
	self.panSolverMass = []
	self.panV0 = []
end function

//----------------------------------------------------------------------
// Geometry.  A pan is inset by half its width from the end of the bar, so
// that the footprint stays exactly as wide as the bar.
//----------------------------------------------------------------------

// How high a pan's center rides above the bar's midline.
Balance.panRise = function
	s = self.spec
	return s.thickness / 2 + s.panGap + s.panThickness / 2
end function

Balance.headroom = function
	s = self.spec
	return s.panGap + s.panThickness
end function

// The offset from the pivot to pan i's anchor on the bar, in world
// coordinates: the arm the pan swings on, and the one the momentum and
// inertia it contributes are measured with.  The pan itself sits panRise
// straight up from there, which does not turn with the bar and so is no part
// of the arm.
Balance.panArm = function(i)
	s = self.spec
	ax = s.length / 2 - s.panWidth / 2
	if i == 0 then ax = -ax
	ax = ax - self.pivotLocal[0]
	a = self.bar.angle
	return [ax * cos(a), ax * sin(a)]
end function

//----------------------------------------------------------------------
// Physics bodies
//----------------------------------------------------------------------

Balance.makeBodies = function
	super.makeBodies
	s = self.spec
	pv = self.pivotLocal
	rise = self.panRise
	half = s.length / 2 - s.panWidth / 2
	self.pans = []
	self.panMass = []
	self.panSolverMass = []
	self.panV0 = []
	for ax in [-half, half]
		b = self.addBody(ax, pv[1] + rise)
		sh = b.addBox(s.panWidth, s.panThickness, 0, 0, 0, s.panDensity)
		sh.setRestitution s.panRestitution
		sh.setFriction s.panFriction
		sh.setFilter config.catPan, config.maskPan
		// A pan stays level because it cannot turn at all: no contact on it,
		// however far out on its edge, ever spins it.  What that contact
		// does instead is push the pan down, which is what tips the bar.
		b.setFixedRotation
		// And it does not fall on its own, because preStep hangs its weight
		// on the bar instead.  A pan's mass is a fiction the solver is told
		// (see preStep), and gravity must not be computed from the fiction.
		b.setGravityScale 0
		self.pans.push b
		self.panMass.push b.mass
		self.panSolverMass.push b.mass
		self.panV0.push [0, 0]
	end for
	self.placePans
end function

Balance.onPlay = function
	super.onPlay
	for b in self.pans
		b.setType physics.DYNAMIC
	end for
end function

// Put the pans' real weight back, so that nothing outside of play ever sees
// the fiction preStep tells the solver.
Balance.onStop = function
	super.onStop
	for i in self.pans.indexes
		self.panSolverMass[i] = self.panMass[i]
		self.pans[i].mass = self.panMass[i]
		self.pans[i].updateInvMass
		self.panV0[i] = [0, 0]
	end for
end function

// Part.placeBodies knows each pan's resting offset, but not that a pan is
// always upright; this is the funnel every reset goes through, so level them
// here.
Balance.placeBodies = function
	super.placeBodies
	self.placePans
end function

// Hold each pan where the bar has carried it, and level.
Balance.placePans = function
	p = self.pivotWorld
	rise = self.panRise
	for i in self.pans.indexes
		e = self.panArm(i)
		self.pans[i].setAngle 0
		self.pans[i].setPosition p[0] + e[0], p[1] + e[1] + rise
	end for
end function

// Tell the solver what a pan is worth before it solves anything against it.
//
// This is what makes a balance hit hard.  A pan is a body of its own, and
// the solver knows nothing of the bar behind it, so left alone it solves a
// ball landing on a pan against the pan's own few grams -- the pan is
// knocked aside, almost no impulse passes, and the far end barely twitches.
// What the ball should meet is the whole assembly's resistance at that
// point, which for a pin is the assembly's moment about the pivot over the
// pan's arm squared.  So that is the mass the pan is given, freshly each
// step because the arm turns with the bar.
//
// It is a fiction in one direction only: an inflated pan must not be given
// an inflated weight to match, so a pan does not fall on its own at all
// (makeBodies turns its gravity off) and its real weight is hung on the bar
// here instead, at the point the pan hangs from.
Balance.preStep = function(dt)
	super.preStep dt
	moment = self.generalizedMass
	p = self.pivotWorld
	rise = self.panRise
	for i in self.pans.indexes
		b = self.pans[i]
		e = self.panArm(i)
		self.bar.applyForce 0, -self.panMass[i] * config.gravity,
		  p[0] + e[0], p[1] + e[1] + rise
		arm2 = e[0] * e[0] + e[1] * e[1]
		if arm2 > 0 then
			self.panSolverMass[i] = moment / arm2
		else
			self.panSolverMass[i] = self.panMass[i]
		end if
		b.mass = self.panSolverMass[i]
		b.updateInvMass
		// The velocity the step starts from, so that what the step adds to it
		// can be read back as the impulse it was.
		self.panV0[i] = [b.vx, b.vy]
	end for
end function

Balance.pinRiders = function
	self.placePans
end function

// A pan's share of the assembly's momentum, in two pieces, because its mass
// means two different things.  What it was already carrying is real momentum
// and goes at its real mass; what the step just added to it is an impulse,
// and an impulse is `mass * change in velocity` at whatever mass the solver
// used to work it out.  Told that way, the fiction cancels: the assembly
// receives exactly the impulse that landed on the pan, whatever we claimed
// the pan weighed while it was landing.
Balance.momentum = function
	total = super.momentum
	for i in self.pans.indexes
		b = self.pans[i]
		e = self.panArm(i)
		v0 = self.panV0[i]
		total = total + self.panMass[i] * (e[0] * e[0] + e[1] * e[1]) * self.spin
		total = total + self.panSolverMass[i] *
		  (e[0] * (b.vy - v0[1]) - e[1] * (b.vx - v0[0]))
	end for
	return total
end function

// The inertia is the assembly's real one: real pan masses, on their arms.
Balance.generalizedMass = function
	total = super.generalizedMass
	for i in self.pans.indexes
		e = self.panArm(i)
		total = total + self.panMass[i] * (e[0] * e[0] + e[1] * e[1])
	end for
	return total
end function

Balance.applySpin = function(spin)
	super.applySpin spin
	for i in self.pans.indexes
		e = self.panArm(i)
		self.pans[i].setVelocity -spin * e[1], spin * e[0]
		self.pans[i].setAngularVelocity 0
	end for
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

// The stem below the pan, which reaches down into the bar so that a pan
// riding above a tilted bar still reads as mounted to it.
Balance.yokeHeight = function
	s = self.spec
	return s.thickness / 2 + s.panGap
end function

Balance.panImageKey = function
	s = self.spec
	return "balance-pan:" + s.panWidth + "x" + s.panThickness + ":" +
	  self.yokeHeight + ":" + s.panColor
end function

Balance.panImage = function
	key = self.panImageKey
	if not artUtil.cache.hasIndex(key) then artUtil.cache[key] = self.drawPan
	return artUtil.cache[key]
end function

Balance.drawPan = function
	s = self.spec
	w = s.panWidth; h = s.panThickness
	yh = self.yokeHeight
	g = artUtil.canvas(w, h + yh)
	// The stem first, so the pan draws over where they meet.
	g.fillPoly [[w / 2 - 3, 0], [w / 2 + 3, 0], [w / 2 + 6, yh],
	  [w / 2 - 6, yh]], "#5A6672"
	g.fillRect 0, yh, w, h, s.panColor
	g.fillRect 0, yh + h - 2, w, 2, "#FFFFFF48"
	g.fillRect 0, yh, w, 2, "#00000038"
	g.drawRect 0, yh, w, h, "#00000070", 2
	return g.getImage
end function

Balance.imageKey = function
	return "balance:" + super.imageKey + "/" + self.panImageKey
end function

Balance.drawAssembly = function(g)
	super.drawAssembly g
	s = self.spec
	sz = self.size
	pv = self.pivotLocal
	py = sz[1] / 2 + pv[1] + self.panRise - s.panThickness / 2 -
	  self.yokeHeight
	img = self.panImage
	for ax in [s.panWidth / 2, sz[0] - s.panWidth / 2]
		g.drawImage img, ax - s.panWidth / 2, py
	end for
end function

Balance.makeSprites = function
	super.makeSprites
	img = self.panImage
	self.panSprites = []
	for b in self.pans
		sp = new Sprite
		sp.image = img
		self.panSprites.push sp
		self.sprites.push sp
		self.spriteDisp.sprites.push sp
	end for
end function

Balance.syncSprites = function
	super.syncSprites
	if not self.bodies then return
	// The pan's picture hangs below its body by half the stem: the body is
	// the slab alone.
	drop = self.yokeHeight / 2
	for i in self.panSprites.indexes
		o = self.pans[i].position
		self.panSprites[i].x = o[0]
		self.panSprites[i].y = o[1] - drop
		self.panSprites[i].rotation = 0
	end for
end function
