//----------------------------------------------------------------------
// Wheel, and the Belt that runs between two of them.
//
// A wheel is a gear with no teeth: the same hub on the same fixed axle,
// turning with whatever it is linked to, and told apart only by how the link
// is made.  Gears mesh because they are next to each other; belted wheels can
// be anywhere, so the link has to be drawn, which makes a belt a part that
// names two others -- a rope, in that respect, rather than a gear.
//
// What a belt does is one line: the rims travel together, so the far wheel
// turns at `Ra / Rb` of the near one's rate, the same way round.  torque.ms
// takes it from there; a belt has no code in the solver at all, because a
// train was always a graph of ratios and this is one more kind of edge.
//
// What is not here yet: slip.  A real belt carries only so much tension
// before the two ends part company, which is how a jammed machine stops
// short of tearing itself up.  Ours is rigid, so a locked wheel locks the
// whole train.
//----------------------------------------------------------------------

globals.Wheel = new Gear
Wheel.typeName = "wheel"
Wheel.displayName = "Wheel"
// No teeth, so nothing meshes with it: a belt is the only way in or out.
Wheel.defaultSpec = Gear.defaultSpec + {"teeth": 0, "radius": 30,
  "color": config.wheelColor}

// A wheel is its rim, all the way out: there is no tooth standing proud of it
// and no neighbor to keep clear of, so the picture, the footprint and the
// shape the physics sees are all the same circle.
Wheel.pitchRadius = function
	return self.spec.radius
end function

Wheel.outerRadius = function
	return self.spec.radius
end function

Wheel.rootRadius = function
	return self.spec.radius
end function

Wheel.bodyRadius = function
	return self.spec.radius
end function

// The whole rim is the belt's to run on, and there is only the one of it.
Wheel.beltRings = function
	return [self.spec.radius]
end function

Wheel.imageKey = function
	return "wheel:" + self.spec.radius + ":" + self.spec.color
end function

Wheel.makeImage = function
	s = self.spec
	r = s.radius
	g = artUtil.canvas(r * 2, r * 2)
	rim = config.wheelRimColor
	artUtil.fillCircle g, r, r, r, rim
	artUtil.fillCircle g, r, r, r - 3, s.color
	// Spokes, so that a turning wheel looks like one.  A smooth disc does
	// not, which is the whole difficulty with drawing a wheel.
	spoke = artUtil.multiply(s.color, "#8890A0")
	for k in [0, 1, 2, 3]
		a = pi * k / 4 * 2 + pi / 8
		g.line r + cos(a) * r * 0.3, r + sin(a) * r * 0.3,
		  r + cos(a) * (r - 4), r + sin(a) * (r - 4), spoke, 3
	end for
	rb = r * 0.3
	artUtil.fillCircle g, r, r, rb, config.gearHubColor
	artUtil.drawCircle g, r, r, rb, "#00000070", 1
	artUtil.fillCircle g, r, r, 2.5, "#00000090"
	return g.getImage
end function

//----------------------------------------------------------------------
// Gearwheel: a gear with a belt groove cut into its face, and so the one
// part that is in a geared train and a belted one at once.
//
// The groove is well inside the teeth, where there is room for it, which
// means the belt runs at a good deal less than the pitch radius -- a
// reduction in its own right, and the reason to reach for one.  The belt is
// drawn over the gear's face, since links draw above parts, so which groove
// it is in can be seen; on a real gearwheel the sheave sits behind the gear
// on the same shaft, and a flat view has nowhere to put that.
//----------------------------------------------------------------------

globals.Gearwheel = new Gear
Gearwheel.typeName = "gearwheel"
Gearwheel.displayName = "Gearwheel"
Gearwheel.defaultSpec = Gear.defaultSpec + {"teeth": 18, "ringRadius": 15}

Gearwheel.beltRings = function
	return [self.spec.ringRadius]
end function

// The groove is where the holes would have been.
Gearwheel.hasHoles = function
	return false
end function

Gearwheel.imageKey = function
	return super.imageKey + ":" + self.spec.ringRadius
end function

Gearwheel.makeImage = function
	img = super.makeImage
	g = artUtil.canvas(img.width, img.height)
	g.drawImage img, 0, 0
	cx = img.width / 2; cy = img.height / 2
	r = self.spec.ringRadius
	// The channel, and the bright bottom of it.
	artUtil.drawCircle g, cx, cy, r, "#00000060", 5
	artUtil.drawCircle g, cx, cy, r, artUtil.multiply(self.spec.color, "#C8C8C8"), 1
	return g.getImage
end function

//----------------------------------------------------------------------
// Step pulley: a wheel cut into three steps, any of which a belt may run on.
//
// This is the part that makes belts able to trade speed for force, and it is
// worth saying why it takes a part at all.  The ratio of a whole train is the
// product of `R out / R in` over the hubs along the way -- and that is 1 for
// any hub with a single working radius, which every other hub here has.  So a
// train of them comes out at whatever the two ends are, however much is put
// in between: idlers are idlers.  Something in the middle has to take power
// in at one radius and give it out at another, and this is that something.
//
// It is a pulley rather than a gear because two radii cost nothing here.  A
// compound gear has the same job and cannot be drawn flat: whatever meshes
// its small half sits inside its big half, and real ones only get away with
// it by standing at different depths on the shaft.  A belt reaches from
// anywhere, so the inner steps need no room of their own: their belts cross
// the face of the pulley, which is also how you see which step is in use.
//----------------------------------------------------------------------

globals.StepPulley = new Wheel
StepPulley.typeName = "stepPulley"
StepPulley.displayName = "Step Pulley"
StepPulley.defaultSpec = Wheel.defaultSpec + {"radius": 32}

// The steps, as fractions of the rim, innermost first.  They are a ratio
// apiece against every other: 2.67 from the rim to the middle of the axle,
// 1.83 and 1.45 for the pairs in between.
stepFractions = [0.375, 0.6875, 1]

StepPulley.beltRings = function
	out = []
	for f in stepFractions
		out.push self.spec.radius * f
	end for
	return out
end function

StepPulley.imageKey = function
	return "stepPulley:" + self.spec.radius + ":" + self.spec.color
end function

// Drawn from the outside in, each step a little lighter than the one under
// it, which is what a cone of them looks like from the front.
StepPulley.makeImage = function
	s = self.spec
	rings = self.beltRings
	R = rings[rings.len - 1]
	g = artUtil.canvas(R * 2, R * 2)
	shades = ["#FFFFFF", "#E4E4E4", "#C8C8C8"]
	for k in range(rings.len - 1, 0, -1)
		r = rings[k]
		artUtil.fillCircle g, R, R, r, config.wheelRimColor
		artUtil.fillCircle g, R, R, r - 2, artUtil.multiply(s.color, shades[k])
	end for
	// Ticks across the outer step, since a smooth pulley turning looks like a
	// smooth pulley standing still.
	tick = artUtil.multiply(s.color, "#909090")
	for k in [0, 1, 2, 3]
		a = pi * k / 2 + pi / 4
		g.line R + cos(a) * (rings[1] + 1), R + sin(a) * (rings[1] + 1),
		  R + cos(a) * (rings[2] - 2), R + sin(a) * (rings[2] - 2), tick, 3
	end for
	rb = rings[0] * 0.45
	artUtil.fillCircle g, R, R, rb, config.gearHubColor
	artUtil.drawCircle g, R, R, rb, "#00000070", 1
	artUtil.fillCircle g, R, R, 2.5, "#00000090"
	return g.getImage
end function

//----------------------------------------------------------------------
// Belt
//----------------------------------------------------------------------

globals.Belt = new Part
Belt.typeName = "belt"
Belt.displayName = "Belt"
Belt.isBelt = true
Belt.bodyType = null                // no bodies, no shapes: it is a ratio
Belt.draggable = false              // run from wheel to wheel, not dragged
// `ra` and `rb` are which of each hub's grooves it runs in -- always 0 for
// anything but a step pulley, which is the only part with a choice.
Belt.defaultSpec = Part.defaultSpec + {"a": 0, "b": 0, "ra": 0, "rb": 0,
  "color": config.beltColor}

Belt.wheel = function(which)
	if self.world == null then return null
	id = self.spec.a
	if which then id = self.spec.b
	if not id then return null
	return self.world.partById(id)
end function

// The radius it runs at on one end, or 0 if that groove has gone.
Belt.ringRadius = function(which)
	p = self.wheel(which)
	if p == null then return 0
	rings = p.beltRings
	i = self.spec.ra
	if which then i = self.spec.rb
	if i >= rings.len then return 0
	return rings[i]
end function

// A belt is only a belt while both its wheels are there.
Belt.dependsOn = function(other)
	return other.id == self.spec.a or other.id == self.spec.b
end function

// The geometry, worked out fresh from where the wheels are: their centers and
// rim radii, the direction between them, and the half-angle of the wrap.
//
// Both radii to a line that touches both wheels point the same way, which is
// what makes this one angle rather than two: the tangent points are at
// `alpha +/- phi` from either center.  `cos(phi) = (Ra - Rb) / d` is that
// angle -- a right angle for two wheels of a size, tipping over as they
// differ, and the two tangents parallel when they do not.
Belt.geometry = function
	a = self.wheel(0)
	b = self.wheel(1)
	if a == null or b == null then return null
	ra = self.ringRadius(0)
	rb = self.ringRadius(1)
	if ra <= 0 or rb <= 0 then return null
	ca = a.hubWorld; cb = b.hubWorld
	dx = cb[0] - ca[0]; dy = cb[1] - ca[1]
	d = sqrt(dx * dx + dy * dy)
	if d < 0.0001 then return null
	c = (ra - rb) / d
	if c > 1 then c = 1
	if c < -1 then c = -1
	return {"ca": ca, "ra": ra, "cb": cb, "rb": rb,
	  "alpha": atan(dy, dx), "phi": acos(c)}
end function

// The two straight runs, as [[from, to], [from, to]].
Belt.runs = function(g=null)
	if g == null then g = self.geometry
	if g == null then return null
	out = []
	for side in [1, -1]
		t = g.alpha + side * g.phi
		c = cos(t); s = sin(t)
		out.push [[g.ca[0] + g.ra * c, g.ca[1] + g.ra * s],
		  [g.cb[0] + g.rb * c, g.cb[1] + g.rb * s]]
	end for
	return out
end function

Belt.draw = function(disp)
	g = self.geometry
	if g == null then return
	col = self.spec.color
	w = config.beltWidth
	for r in self.runs(g)
		disp.line r[0][0], r[0][1], r[1][0], r[1][1], col, w
	end for
	// The wrap at each end: the near wheel is held on the side away from the
	// far one, and the far wheel on all the rest of itself.
	self.drawArc disp, g.ca, g.ra, g.alpha + g.phi, 2 * pi - 2 * g.phi, col, w
	self.drawArc disp, g.cb, g.rb, g.alpha - g.phi, 2 * g.phi, col, w
end function

Belt.drawArc = function(disp, c, r, from, span, col, w)
	n = ceil(config.beltArcSteps * abs(span) / (2 * pi))
	if n < 2 then n = 2
	prev = null
	for i in range(0, n, 1)
		a = from + span * i / n
		p = [c[0] + r * cos(a), c[1] + r * sin(a)]
		if prev != null then disp.line prev[0], prev[1], p[0], p[1], col, w
		prev = p
	end for
end function

//----------------------------------------------------------------------
// Editor odds and ends.  Like a rope, a belt has no footprint and no shapes,
// so it takes no part in the placement rules and answers for its own clicks.
//----------------------------------------------------------------------

Belt.placementOK = function(world)
	return true
end function

Belt.snapPose = function(world, x, y)
	return [x, y]
end function

Belt.hitTest = function(x, y)
	runs = self.runs
	if runs == null then return false
	for r in runs
		if util.distToSegment(x, y, r[0], r[1]) < config.beltWidth + 3 then
			return true
		end if
	end for
	return false
end function

Belt.designBounds = function
	g = self.geometry
	if g == null then return [self.spec.x, self.spec.y, 1, 1]
	x0 = g.ca[0] - g.ra; x1 = g.ca[0] + g.ra
	y0 = g.ca[1] - g.ra; y1 = g.ca[1] + g.ra
	if g.cb[0] - g.rb < x0 then x0 = g.cb[0] - g.rb
	if g.cb[0] + g.rb > x1 then x1 = g.cb[0] + g.rb
	if g.cb[1] - g.rb < y0 then y0 = g.cb[1] - g.rb
	if g.cb[1] + g.rb > y1 then y1 = g.cb[1] + g.rb
	return [x0, y0, x1 - x0, y1 - y0]
end function

Belt.imageKey = function
	return "belt:" + self.spec.color
end function

// The palette icon: two wheels with a band round them, which is the one
// picture that says what the part is for.
Belt.makeImage = function
	w = config.grid * 3
	h = config.grid * 2
	g = artUtil.canvas(w, h)
	r1 = 12; r2 = 7
	c1 = [r1 + 2, h / 2]; c2 = [w - r2 - 2, h / 2]
	col = self.spec.color
	artUtil.fillCircle g, c1[0], c1[1], r1 + 3, col
	artUtil.fillCircle g, c2[0], c2[1], r2 + 3, col
	d = c2[0] - c1[0]
	phi = acos((r1 - r2) / d)
	for side in [1, -1]
		t = side * phi
		g.line c1[0] + (r1 + 3) * cos(t), c1[1] + (r1 + 3) * sin(t),
		  c2[0] + (r2 + 3) * cos(t), c2[1] + (r2 + 3) * sin(t), col, 6
	end for
	artUtil.fillCircle g, c1[0], c1[1], r1, config.wheelColor
	artUtil.fillCircle g, c2[0], c2[1], r2, config.wheelColor
	artUtil.fillCircle g, c1[0], c1[1], 3, config.gearHubColor
	artUtil.fillCircle g, c2[0], c2[1], 3, config.gearHubColor
	return g.getImage
end function
