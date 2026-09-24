//----------------------------------------------------------------------
// Gear: a toothed wheel on a fixed axle, and Spool, the one that can haul on
// a rope.  Motor, which drives a train rather than being driven by it, is in
// parts/motor.ms -- it is built on Gearwheel, which belts.ms defines.
//
// Gears connect by being next to each other.  There is nothing to wire up
// and nothing to author: two of them mesh when their pitch circles touch,
// and a set of meshed gears turns as one, in the ratios their teeth say.
// torque.ms works all that out and does the turning; what lives here is the
// one gear -- its axle, its body, and its picture.
//
// The teeth are drawn, not simulated.  What the physics sees is a plain
// circle a little inside the pitch circle, so that meshing gears do not
// grind on each other, and so that what a gear carries rides on its teeth.
// That circle is a dynamic body between one step and the next, which is what
// lets a gear be *driven* by something falling on it as well as drive
// something by turning under it.
//
// The axle is a peg: a gear's center snaps to the pegboard rather than its
// footprint to the grid, because the pitch radii (20, 30, 40 px) are chosen
// so that a meshing pair has both its centers on pegs.
//----------------------------------------------------------------------

globals.Gear = new Part
Gear.typeName = "gear"
Gear.displayName = "Gear"
Gear.turns = true
Gear.defaultSpec = Part.defaultSpec + {"teeth": 12, "color": config.gearColor,
  "density": 1.5, "restitution": 0.05, "friction": 0.9,
  // A gear left to itself coasts to a stop rather than turning forever.
  "angularDamping": 0.5}

Gear.spin = 0           // runtime: the rate torque.ms last solved for

Gear.init = function
	self.spin = 0
end function

//----------------------------------------------------------------------
// Geometry.  One module (config.gearModule) is the pitch diameter per tooth;
// it is shared by every gear, which is exactly what lets gears of different
// sizes mesh.  A tooth stands one module proud of the pitch circle and its
// root is 1.25 modules inside it, which are the usual proportions.
//----------------------------------------------------------------------

Gear.teeth = function
	return self.spec.teeth
end function

Gear.pitchRadius = function
	return self.spec.teeth * config.gearModule / 2
end function

Gear.outerRadius = function
	return self.pitchRadius + config.gearModule
end function

// The circles a belt may run on, innermost first, or nothing for a hub with
// nowhere to put one.  A plain gear is one: it is teeth the whole way round,
// and teeth would chew a belt.  What takes a belt is a rim or a groove -- a
// wheel, a gearwheel, or a step pulley, which is three grooves and the reason
// any of this is a list rather than a number.
Gear.beltRings = function
	return []
end function

Gear.rootRadius = function
	return self.pitchRadius - 1.25 * config.gearModule
end function

// What the physics actually sees: inside the pitch circle, so that a meshing
// pair (whose pitch circles touch) never collides, and design mode is free to
// put them in mesh.
Gear.bodyRadius = function
	return self.pitchRadius - config.gearModule
end function

Gear.size = function
	d = self.outerRadius * 2
	return [d, d]
end function

// The axle goes on the pegboard lattice rather than the footprint on the
// grid -- but on the half-peg lattice, because whole pegs are not enough to
// mesh with.  Two gears mesh at exactly the sum of their pitch radii, and
// those sums are 40, 50, 60, 70 and 80 px: on a 20 px lattice a 12-tooth
// gear could never reach a 18-tooth one at all, since no two pegs are 50
// apart.  Halving it puts every sum within reach straight across, and the
// 30-40-50 triangle within reach diagonally as well.
Gear.snapPose = function(world, x, y)
	return world.pegSnap(self, x, y, config.grid / 2)
end function

Gear.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addCircle(self.bodyRadius, 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	// Hubs ignore motor cases: a gearwheel turns on the face of its own
	// case, and a gear meshed with it reaches over that case too.  See the
	// cat* constants in config.
	sh.setFilter config.catHub, config.maskHub
	// The axle carries the gear's weight, not the solver: letting gravity
	// pull on it would only mean a contact impulse every step against
	// whatever is resting on it, and the axle putting it back again.
	b.setGravityScale 0
end function

//----------------------------------------------------------------------
// What torque.ms asks of us
//----------------------------------------------------------------------

// A gear is bolted to the board, so its axle is simply where it was placed.
Gear.hubWorld = function
	return [self.spec.x, self.spec.y]
end function

Gear.hubAngle = function
	if not self.bodies then return self.spec.angle
	return self.bodies[0].angle
end function

Gear.hubBody = function
	if not self.bodies then return null
	return self.bodies[0]
end function

// Where the hub's center of mass is, from the axle: nothing, for anything
// round, but a pocket wheel is a disc with a bite out of it.  Measured from
// the authored axle rather than the body's origin, since in between two
// solves the body has drifted off it.
Gear.hubArm = function
	b = self.hubBody
	com = b.centerOfMass
	return [com[0] - self.spec.x, com[1] - self.spec.y]
end function

// The two things the train asks of a hub, taken about the axle, which is
// what it turns about -- the Lever's reasoning, and for the same reason: an
// off-center hub is flung sideways by whatever hits it, and that sideways
// momentum is turn about the axle, not something to throw away.
Gear.hubMoment = function
	b = self.hubBody
	r = self.hubArm
	return b.inertia + b.mass * (r[0] * r[0] + r[1] * r[1])
end function

Gear.hubMomentum = function
	b = self.hubBody
	r = self.hubArm
	return b.inertia * b.angularVelocity + b.mass * (r[0] * b.vy - r[1] * b.vx)
end function

// `dt` is the step the torque will be applied over, which a part whose
// torque comes out of an impulse -- a spool's does -- needs to know.
Gear.driveTorque = function(dt)
	return 0
end function

// How much torque this part gives up per unit of the speed it is turning at.
// A plain gear has none: what slows it is the damping on its body.
Gear.dragTorque = function(dt)
	return 0
end function

// A direction this part can turn no further in, as the sign of its own
// rotation, or 0 for a wheel that is free to go either way.
Gear.spinStop = function
	return 0
end function

// Back on the axle, turning at w.  The angular velocity is left on the body
// rather than merely drawn, because it is what the next step's friction has
// to work with: a gear drags along whatever is lying on it.
Gear.setSpin = function(angle, w)
	if not self.bodies then return
	b = self.bodies[0]
	s = self.spec
	b.setAngle angle
	b.setPosition s.x, s.y
	// The center of mass swings round the axle, if it is off it at all.
	r = self.hubArm
	b.setVelocity -w * r[1], w * r[0]
	b.setAngularVelocity w
	self.spin = w
end function

// Design mode: stand at this angle, and mean it -- the mesh a gear is drawn
// in is part of the authored design, so it goes into spec like any pose.
Gear.setPhase = function(angle)
	self.spec.angle = angle
	self.placeBodies
	self.syncSprites
end function

// Moving a gear re-meshes it with whatever it now touches, and can knock its
// old neighbors out of mesh, so the whole board is re-aligned.
Gear.setPose = function(x, y, angle=null)
	super.setPose x, y, angle
	if self.world != null then self.world.alignGears
end function

// The axle holds it, so there is no resting jitter to crush; and settling a
// gear would stall a train that is turning slowly under load, which is a gear
// doing its job.  Angular damping is what quiets this one.
Gear.settle = function(dt)
end function

Gear.onStop = function
	super.onStop
	self.spin = 0
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

polar = function(cx, cy, r, a)
	return [cx + r * cos(a), cy + r * sin(a)]
end function

// Whether the face is cut away.  Only a big enough gear has the room, and a
// gearwheel wants that room for its belt groove.
Gear.hasHoles = function
	return self.spec.teeth >= 18
end function

Gear.imageKey = function
	return self.typeName + ":" + self.spec.teeth + ":" + self.spec.color
end function

Gear.makeImage = function
	s = self.spec
	ro = self.outerRadius
	g = artUtil.canvas(ro * 2, ro * 2)
	self.drawGear g, ro, ro
	return g.getImage
end function

// Draw the gear centered at (cx, cy) in `g`, at the angle its teeth are
// numbered from: one tooth centered on the part's own zero, which is what
// torque.ms assumes when it works out where a neighbor has to stand.
Gear.drawGear = function(g, cx, cy)
	s = self.spec
	n = s.teeth
	ro = self.outerRadius
	ri = self.rootRadius
	dark = artUtil.multiply(s.color, "#606878")
	edge = artUtil.multiply(s.color, "#404850")

	// The disc, out to the root of the teeth -- a hair past it, since a
	// polygon's edges fall inside the circle they stand for.
	artUtil.fillCircle g, cx, cy, ri + 0.5, s.color

	// The teeth: a tooth every 2*pi/n, half a tooth pitch wide and tapered,
	// which is near enough an involute at this size.
	half = pi / (2 * n)
	for k in range(0, n - 1, 1)
		a = 2 * pi * k / n
		p0 = polar(cx, cy, ri, a - half * 1.35)
		p1 = polar(cx, cy, ro, a - half * 0.6)
		p2 = polar(cx, cy, ro, a + half * 0.6)
		p3 = polar(cx, cy, ri, a + half * 1.35)
		g.fillPoly [p0, p1, p2, p3], s.color
		g.line p0[0], p0[1], p1[0], p1[1], edge
		g.line p1[0], p1[1], p2[0], p2[1], edge
		g.line p2[0], p2[1], p3[0], p3[1], edge
	end for

	// Lightening holes, which are what make the turn readable at a glance.
	if self.hasHoles then
		rh = self.pitchRadius * 0.16
		for k in [0, 1, 2, 3]
			c = polar(cx, cy, self.pitchRadius * 0.55, pi * k / 2 + pi / 4)
			artUtil.fillCircle g, c[0], c[1], rh, dark
		end for
	end if

	// The hub and the axle.
	rb = self.pitchRadius * 0.3
	artUtil.fillCircle g, cx, cy, rb, config.gearHubColor
	artUtil.drawCircle g, cx, cy, rb, "#00000070", 1
	artUtil.fillCircle g, cx, cy, 2.5, "#00000090"
end function

//----------------------------------------------------------------------
// Spool: a gear with a drum, and as much rope as anyone needs wound on it.
//
// This is how a train gets a load.  Everything else a gear can do to the
// world it does by friction, which is good for shoving a ball along and no
// good at all for lifting one; a spool turns the train's torque into a pull
// on a rope, and a pull on a rope into torque on the train.
//
// The mechanism is two lines, either way round:
//
//      the rope's length changes by drumRadius * dtheta as the drum turns
//      the rope's tension puts drumRadius * tension of torque on the drum
//
// and everything else follows from machinery that is already here.  A taut
// rope is one constraint on its total path length, so shortening that length
// *is* hauling the load in; the tension the rope solve works out every step
// is what the load weighs, and that times the radius is what the train has to
// beat to lift it.  A motor that cannot stalls, and a load heavier still
// runs the whole train backwards, which is a winch with no brake -- exactly
// what this is.
//
// The solver does not pull on the spool itself (`ropeFixed`).  It could not
// usefully: the drum's body is put back on its axle at the end of every step,
// so an impulse there is thrown away, and meanwhile the rope would have gone
// as soft as the gear's own mass makes it and the load would sag.  The spool
// answers for its rope itself, with the torque above.
//----------------------------------------------------------------------

globals.Spool = new Gear
Spool.typeName = "spool"
Spool.displayName = "Spool"
Spool.ropeFixed = true
Spool.defaultSpec = Gear.defaultSpec + {"teeth": 12, "drumRadius": 10,
  // Which way winds the rope in.  1 is counterclockwise, to match the sense
  // of every other angle here.
  "wind": 1,
  "drumColor": "#9A7248"}

Spool.lastAngle = 0     // runtime: where the drum stood at the last step
Spool.stalled = false   // ...and whether it is wound out (see minLength)

Spool.init = function
	super.init
	self.lastAngle = 0
	self.stalled = false
end function

// The rope is made fast to the drum, which is to say to the axle: the physics
// treats the whole spool as the one point its rope ends at, and the radius is
// what turns tension into torque rather than anything the path knows about.
// (The drawing does know: see Rope.trimEnds.)
Spool.tieLocals = function
	return [[0, 0]]
end function

Spool.wrapRadius = function
	return self.spec.drumRadius
end function

// The drum has a rim like a pulley's wheel, but a rope does not pass over it:
// this is where the rope stops and starts being wound.
Spool.ropeRoutes = function(i)
	return false
end function

// The rope comes off the drum at a tangent, and on the side it would be
// wound onto -- which is the whole point of drawing it there at all.  A drum
// that takes rope in when it turns counterclockwise has to be handed that
// rope up its right-hand side, and seeing which side it hangs down is the
// only way to tell a spool that is about to lift from one that is about to
// drop.
//
// The tangent point is `acos(r / d)` round from the load, on the side `wind`
// says; a quarter turn is the same thing for a load far enough away, but the
// exact angle costs nothing and a close one would look wrong.
Spool.ropeExit = function(i, toward)
	c = self.hubWorld
	rd = self.spec.drumRadius
	dx = toward[0] - c[0]; dy = toward[1] - c[1]
	d = sqrt(dx * dx + dy * dy)
	if d <= rd then return c
	a = atan(dy, dx) + self.spec.wind * acos(rd / d)
	return [c[0] + rd * cos(a), c[1] + rd * sin(a)]
end function

// The ropes this spool is the end of.  One that merely passes over it is a
// rope over a pulley -- it turns a corner and takes nothing in or out.
Spool.ownRopes = function
	out = []
	if self.world == null then return out
	for r in self.world.ropes
		pts = r.spec.points
		if not pts then continue
		if pts[0].part == self.id or pts[pts.len - 1].part == self.id then
			out.push r
		end if
	end for
	return out
end function

// Rope is paid out at the rim, so this is just the rim's speed.
Spool.windRate = function(i)
	return -self.spec.wind * self.spec.drumRadius * self.spin
end function

// The load, as a torque on the train -- and, below, as the inertia that goes
// with it.
//
// The pair of them is one linearization, and it is not optional.  The rope
// works out its tension against a drum it believes cannot move, because that
// is what `ropeFixed` tells it; hand the train that tension as a plain torque
// and the drum turns away under a load whose pull was worked out for a drum
// that did not -- so the next step's tension has to be bigger, in the other
// direction, and with anything heavier than the gears themselves on the end
// (which is everything) the two whip each other apart within a dozen steps.
//
// What the train is missing is that the tension answers to its own speed: an
// extra radian per second of drum pays rope out at `drumRadius` more, and the
// load must be hauled that much less hard.  Differentiating the tension by
// the drum's speed gives exactly `mEff * drumRadius^2` -- the load's mass
// carried round to the rim -- which `Train.solve` then folds into the
// implicit step, where it belongs: a two-kilogram weight on a drum weighs
// far more than the drum, and the drum should have been turning as though it
// did all along.  `driveTorque` is the same curve's intercept.
Spool.driveTorque = function(dt)
	if dt <= 0 then return 0
	s = self.spec
	rd = s.drumRadius
	t = 0
	for r in self.ownRopes
		if r.jac == null then continue      // slack, or pulling on nothing
		// Tension is an impulse, since that is what the rope hands the
		// bodies; a torque is what the train is adding up.
		t = t + (r.mEff * rd * rd * self.spin - s.wind * r.tension * rd) / dt
	end for
	return t
end function

// The load, carried round to the rim.  See driveTorque.
Spool.dragTorque = function(dt)
	if dt <= 0 then return 0
	rd = self.spec.drumRadius
	t = 0
	for r in self.ownRopes
		if r.jac == null then continue
		t = t + r.mEff * rd * rd / dt
	end for
	return t
end function

Spool.onPlay = function
	super.onPlay
	self.lastAngle = self.hubAngle
	self.stalled = false
end function

Spool.onStop = function
	super.onStop
	self.lastAngle = self.spec.angle
	self.stalled = false
end function

// How short this rope may be wound, which is the rule that stops a winch.
//
// The obvious answer is the drum's own radius, since that is where the rope
// runs out -- and it is the floor here.  But it is almost never what stops a
// real hoist: the load reaches the drum long before the rope does, and from
// then on the drum would go on turning while nothing moved, hauling on a rope
// that has nowhere left to go.
//
// So the rule is the more general one that covers both: a drum cannot take in
// rope the load is not giving it.  The length may run ahead of the path it is
// measured along by `lead` and no further -- and that margin is not slack in
// the rule, it *is* the pull, since a taut rope is brought back to its length
// by moving whatever is on the end of it.  Hence enough for the step's
// winding and the slop the rope solve leaves, and not a pixel more: it is
// also how far a load that cannot move gets dragged into whatever is stopping
// it before the drum gives up.
Spool.minLength = function(rope, lead)
	lo = self.spec.drumRadius
	p = rope.path
	if p == null then return lo
	g = rope.pathLength(p) - lead
	if g > lo then lo = g
	return lo
end function

// Wound out, the drum stops -- and stops the train with it, because the rope
// is not going to stretch and neither is whatever it has hauled up against.
// A motor that has taken its load as far as it goes should stall there, not
// go on turning while nothing moves.
//
// One direction only: what is on the end can always be let back down.
Spool.spinStop = function
	if self.stalled then return self.spec.wind
	return 0
end function

// Wind the rope on or off by however far the drum actually turned in the step
// just taken.  Reading the angle back rather than integrating the spin is
// what keeps the rope and the picture of the drum from drifting apart.
Spool.update = function(dt)
	super.update dt
	a = self.hubAngle
	d = -self.spec.wind * self.spec.drumRadius * (a - self.lastAngle)
	self.lastAngle = a
	lead = 2 * (config.ropeSlop + abs(d))
	stuck = false
	for r in self.ownRopes
		lo = self.minLength(r, lead)
		L = r.curLen + d
		if L < lo then
			// Winding in rope that is not coming.  The clamp is for the step
			// it happens in; the stop is what arrests it from then on.
			if d < 0 then L = lo
			stuck = true
		end if
		r.curLen = L
	end for
	self.stalled = stuck
end function

Spool.imageKey = function
	return super.imageKey + ":" + self.spec.drumRadius + ":" + self.spec.drumColor
end function

// The gear, with the drum drawn over its hub: a coil of rope, and one radial
// mark, because a smooth drum turning is a drum that looks like it is not.
Spool.makeImage = function
	img = super.makeImage
	g = artUtil.canvas(img.width, img.height)
	g.drawImage img, 0, 0
	cx = img.width / 2; cy = img.height / 2
	rd = self.spec.drumRadius
	c = self.spec.drumColor
	artUtil.fillCircle g, cx, cy, rd, c
	artUtil.drawCircle g, cx, cy, rd, "#00000070", 1
	artUtil.drawCircle g, cx, cy, rd * 0.7, artUtil.multiply(c, "#B0B0B0"), 1
	artUtil.drawCircle g, cx, cy, rd * 0.4, artUtil.multiply(c, "#B0B0B0"), 1
	g.line cx, cy, cx + rd, cy, artUtil.multiply(c, "#707070"), 1
	artUtil.fillCircle g, cx, cy, 2, "#00000090"
	return g.getImage
end function
