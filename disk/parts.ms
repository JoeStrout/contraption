// parts.ms
// The concrete part types, and the catalog that the palette is built from.

import "importUtil"
ensureImport ["config", "part", "artUtil", "physics", "rope", "util"]

//----------------------------------------------------------------------
// Ball: a rolling, bouncing sphere.
//----------------------------------------------------------------------

globals.Ball = new Part
Ball.typeName = "ball"
Ball.displayName = "Ball"
// Damping is what stands in for the losses a real ball has and a 2D impulse
// solver does not: a circle on a flat floor has nothing to stop its spin, so
// without angular damping a bouncy ball rolls forever.
Ball.defaultSpec = Part.defaultSpec + {"radius": 20, "sheet": "ball-bowling",
  "color": "#E08828", "restitution": 0.55, "density": 1, "friction": 0.4,
  "linearDamping": 0.05, "angularDamping": 0.3, "bounceSoftSpeed": 250}

Ball.size = function
	return [self.spec.radius * 2, self.spec.radius * 2]
end function

Ball.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addCircle(s.radius, 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

//----------------------------------------------------------------------
// Appearance.  A ball is drawn from a pre-rendered sheet of 64 views of the
// same sphere, one per 360/64 degrees of spin, rather than by rotating one
// picture: a rotated flat disc reads as a spinning coin, while the sheet has
// real shading that stays put while the pattern turns.
//
// The sheet's cell size is the ball's diameter (the sphere is framed edge to
// edge), so the sprite never needs scaling and `radius` is what picks which
// sheet of a given ball we load.
//----------------------------------------------------------------------

Ball.sheetPath = function
	return config.picsDir + self.spec.sheet + "_" + config.ballSheetCols +
	  "x" + config.ballSheetCols + "_" + round(self.spec.radius * 2) + ".png"
end function

// The 64 frames, or null if there is no sheet for this ball yet -- in which
// case we fall back to the procedural art below.
Ball.frames = function
	return artUtil.frames(self.sheetPath, round(self.spec.radius * 2),
	  config.ballSheetCols, config.ballFrameCount)
end function

// Which frame shows the ball turned `angle` radians counterclockwise.
Ball.frameIndex = function(angle)
	n = config.ballFrameCount
	idx = round(angle * n / (2 * pi)) % n
	if idx < 0 then idx = idx + n
	return idx
end function

// Each sprite shows the frame matching its body's rotation, and is itself
// left unrotated -- the frame already carries the rotation.
Ball.syncSprites = function
	fr = self.frames
	if fr == null then
		super.syncSprites
		return
	end if
	for i in self.sprites.indexes
		if i >= self.bodies.len then break
		b = self.bodies[i]
		sp = self.sprites[i]
		sp.x = b.x
		sp.y = b.y
		sp.rotation = 0
		sp.image = fr[self.frameIndex(b.angle)]
	end for
end function

Ball.imageKey = function
	return "ball:" + self.spec.sheet + ":" + self.spec.radius + ":" +
	  self.spec.color
end function

// The resting image: frame 0 of the sheet, which is also the palette icon.
Ball.makeImage = function
	fr = self.frames
	if fr != null then return fr[0]
	r = self.spec.radius
	d = r * 2
	g = artUtil.canvas(d, d)
	g.fillEllipse 0, 0, d, d, self.spec.color
	// A rim a little darker than the body, and an off-center highlight, so
	// that the ball reads as round and its spin is visible.
	g.drawEllipse 0, 0, d, d, "#00000060", 2
	g.fillEllipse d * 0.52, d * 0.58, d * 0.26, d * 0.26, 
		color.lerp(self.spec.color, color.white)
	return g.getImage
end function

//----------------------------------------------------------------------
// Block: a wooden crate that tumbles and stacks.
//----------------------------------------------------------------------

globals.Block = new Part
Block.typeName = "block"
Block.displayName = "Block"
Block.defaultSpec = Part.defaultSpec + {"width": 40, "height": 40,
  "color": "#B0793F", "restitution": 0.1, "density": 0.8, "friction": 0.6}

Block.size = function
	return [self.spec.width, self.spec.height]
end function

Block.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Block.imageKey = function
	s = self.spec
	return "block:" + s.width + "x" + s.height + ":" + s.color
end function

Block.makeImage = function
	s = self.spec
	w = s.width; h = s.height
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.color
	// Plank lines and a bevel, so rotation is legible.
	g.line 0, h / 3, w, h / 3, "#00000030"
	g.line 0, h * 2 / 3, w, h * 2 / 3, "#00000030"
	g.fillRect 0, h - 2, w, 2, "#FFFFFF38"
	g.fillRect 0, 0, w, 2, "#00000038"
	g.drawRect 0, 0, w, h, "#00000070", 2
	return g.getImage
end function

//----------------------------------------------------------------------
// Platform: static scenery.  Used for the level floor, and placeable as a
// ledge for things to land on.
//----------------------------------------------------------------------

globals.Platform = new Part
Platform.typeName = "platform"
Platform.displayName = "Platform"
Platform.bodyType = physics.STATIC
Platform.defaultSpec = Part.defaultSpec + {"width": 120, "height": 20,
  "color": "#7A8894", "restitution": 0.2, "friction": 0.7}

Platform.size = function
	return [self.spec.width, self.spec.height]
end function

Platform.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Platform.imageKey = function
	s = self.spec
	return "platform:" + s.width + "x" + s.height + ":" + s.color
end function

Platform.makeImage = function
	s = self.spec
	w = s.width; h = s.height
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.color
	g.fillRect 0, h - 3, w, 3, "#FFFFFF40"
	g.fillRect 0, 0, w, 3, "#00000040"
	g.drawRect 0, 0, w, h, "#00000060", 1
	return g.getImage
end function

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

//----------------------------------------------------------------------
// Weight: a lump of metal of a stated mass, with a ring on top to tie on to.
//
// Mass is the one thing a weight is for, so it is authored in kilograms and
// the density worked back from it.  The engine's mass is density times area
// in pixels, and config.pxPerMeter says what a pixel is worth.
//----------------------------------------------------------------------

globals.Weight = new Part
Weight.typeName = "weight"
Weight.displayName = "Weight"
Weight.defaultSpec = Part.defaultSpec + {"width": 30, "height": 30, "kg": 1,
  "color": "#6E7A86", "restitution": 0.05, "friction": 0.7,
  "linearDamping": 0.02, "angularDamping": 0.05}

Weight.size = function
	return [self.spec.width, self.spec.height]
end function

Weight.density = function
	s = self.spec
	return s.kg * config.pxPerMeter ^ 2 / (s.width * s.height)
end function

// The ring on top, which is where a rope goes.
Weight.tieLocals = function
	return [[0, self.spec.height / 2]]
end function

Weight.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, self.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Weight.imageKey = function
	s = self.spec
	return "weight:" + s.width + "x" + s.height + ":" + s.kg + ":" + s.color
end function

Weight.makeImage = function
	s = self.spec
	w = s.width; h = s.height
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.color
	// A chamfer, so it reads as a solid block rather than a card.
	g.fillRect 0, h - 3, w, 3, "#FFFFFF30"
	g.fillRect 0, 0, w, 3, "#00000040"
	g.fillRect 0, 0, 3, h, "#FFFFFF18"
	g.drawRect 0, 0, w, h, "#00000080", 2
	// The ring, drawn straddling the top edge where the tie point is.
	g.drawEllipse w / 2 - 5, h - 6, 10, 10, "#3A444E", 3
	g.print s.kg + "kg", (w - 8 * (("" + s.kg).len + 2)) / 2, h / 2 - 8,
	  "#E8EEF4", "small"
	return g.getImage
end function

//----------------------------------------------------------------------
// TiePoint: an eye bolted to the wall, and nothing else.  Somewhere for a
// rope to be fastened that does not move.
//----------------------------------------------------------------------

globals.TiePoint = new Part
TiePoint.typeName = "tiepoint"
TiePoint.displayName = "Tie Point"
TiePoint.bodyType = physics.STATIC
TiePoint.defaultSpec = Part.defaultSpec + {"size": 14, "color": "#5A6672",
  "restitution": 0.1, "friction": 0.6}

TiePoint.size = function
	return [self.spec.size, self.spec.size]
end function

TiePoint.tieLocals = function
	return [[0, 0]]
end function

TiePoint.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.size, s.size, 0, 0, 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

TiePoint.imageKey = function
	return "tiepoint:" + self.spec.size + ":" + self.spec.color
end function

TiePoint.makeImage = function
	s = self.spec
	d = s.size
	g = artUtil.canvas(d, d)
	g.fillRect 1, 1, d - 2, d - 2, s.color
	g.drawRect 1, 1, d - 2, d - 2, "#00000080", 2
	g.drawEllipse d / 2 - 4, d / 2 - 4, 8, 8, "#2A3038", 3
	return g.getImage
end function

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

//----------------------------------------------------------------------
// The registry, for loading a saved design.
//----------------------------------------------------------------------

byName = {}
byName[Ball.typeName] = Ball
byName[Block.typeName] = Block
byName[Platform.typeName] = Platform
byName[Lever.typeName] = Lever
byName[Balance.typeName] = Balance
byName[Weight.typeName] = Weight
byName[TiePoint.typeName] = TiePoint
byName[Pulley.typeName] = Pulley
byName[MountedPulley.typeName] = MountedPulley
byName[Rope.typeName] = Rope

// Rebuild a part from what Part.save wrote out.
fromSaved = function(saved)
	cls = byName[saved.type]
	return cls.make(saved.spec)
end function

//----------------------------------------------------------------------
// The catalog: what the palette offers, in order.
//
// An entry is a part class plus the spec to stamp out, so that one class can
// appear several times at different sizes.  Puzzle mode will later add a
// `count` field here; nothing else needs to change for that.
//----------------------------------------------------------------------

catalog = [
	{"cls": Ball, "spec": {"radius": 20, "sheet": "ball-bowling",
	  "color": "#202028", "density": 3, "restitution": 0.15, "friction": 0.5,
	  "linearDamping": 0.02, "angularDamping": 0.2, "bounceSoftSpeed": 150},
	  "label": "Bowling Ball"},
	{"cls": Ball, "spec": {"radius": 20, "sheet": "ball-soccer",
	  "color": "#F0F0E8", "density": 0.6, "restitution": 0.55, "friction": 0.5,
	  "linearDamping": 0.08, "angularDamping": 0.5, "bounceSoftSpeed": 250},
	  "label": "Soccer Ball"},
	{"cls": Ball, "spec": {"radius": 16, "sheet": "ball-star",
	  "color": "#D8321F", "density": 1, "restitution": 0.8, "friction": 0.6,
	  "linearDamping": 0.1, "angularDamping": 0.6, "bounceSoftSpeed": 300},
	  "label": "Rubber Ball"},
	{"cls": Ball, "spec": {"radius": 10, "sheet": "ball-tennis",
	  "color": "#C8E040", "density": 0.7, "restitution": 0.75, "friction": 0.7,
	  "linearDamping": 0.15, "angularDamping": 0.8, "bounceSoftSpeed": 250},
	  "label": "Tennis Ball"},
	{"cls": Block, "spec": {"width": 40, "height": 40}, "label": "Block"},
	{"cls": Block, "spec": {"width": 100, "height": 20}, "label": "Plank"},
	{"cls": Block, "spec": {"width": 20, "height": 80}, "label": "Post"},
	{"cls": Platform, "spec": {"width": 120, "height": 20}, "label": "Platform"},
	{"cls": Platform, "spec": {"width": 60, "height": 20}, "label": "Ledge"},
	{"cls": Lever, "spec": {"length": 160}, "label": "Seesaw"},
	{"cls": Lever, "spec": {"length": 200, "pivotFrac": 0.55,
	  "fulcrumHeight": 40}, "label": "Lever"},
	{"cls": Balance, "spec": {}, "label": "Balance"},
	{"cls": Weight, "spec": {"width": 30, "height": 30, "kg": 1}, "label": "1 kg"},
	{"cls": Weight, "spec": {"width": 40, "height": 40, "kg": 3}, "label": "3 kg"},
	{"cls": Weight, "spec": {"width": 50, "height": 50, "kg": 5}, "label": "5 kg"},
	{"cls": TiePoint, "spec": {}, "label": "Tie Point"},
	{"cls": Pulley, "spec": {}, "label": "Pulley"},
	{"cls": MountedPulley, "spec": {}, "label": "Mounted Pulley"},
	{"cls": Rope, "spec": {}, "label": "Rope"},
]

// A fresh part from a catalog entry.
spawn = function(entry)
	return entry.cls.make(entry.spec)
end function
