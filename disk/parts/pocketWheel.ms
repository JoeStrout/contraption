//----------------------------------------------------------------------
// Pocket wheel: a belt-driven wheel with a quarter of it cut away -- a
// Pac-Man -- which lets balls off a ramp one at a time, one per turn.
//
// Stand it at the low end of a ramp, with the front ball of the queue
// resting against its rim.  The rim holds back the whole queue.  When the
// mouth comes round to face the queue, the front ball rolls into it, and
// the jaw that follows sweeps past the next ball, which is left resting
// against the first.  Then the wheel carries the ball round and lets it
// fall out: over the top and down the far side if the wheel turns up past
// the queue, or straight down under the end of the ramp if it turns the
// other way.  Either way it is one ball per revolution, and nothing here
// counts anything -- the pocket has room for exactly one.
//
// That room is the whole of the tuning.  A ball in a right-angled mouth
// sits against both jaws with its center r / sin(45 deg) out from the
// apex, so a tennis ball (r = 10) reaches 24.1 px from the axle, and on a
// 20 px wheel stands 4 px proud of the rim.  That is not enough for the
// next ball to find a seat, so it is still one at a time; and 20 rather
// than the 25 that would hold it entirely is what lets the wheel sit on
// the grid with a platform butted right up against it.  A bigger ball
// would not fit, and a smaller one might take two.
//
// It is a Wheel in every way the train cares about -- a hub on a fixed
// axle, turned by a belt -- except that it is not round.  Its center of
// mass is off the axle, which is why Gear works in terms of `hubArm`, and
// its shape is three convex sectors, since the physics has only convex
// shapes and 270 degrees of disc is not one.
//
// The belt runs in a groove on the hub, not on the rim, because a belt
// round the rim would be drawn straight across the mouth.  That makes it a
// small pulley, and so a fast one: from a motor it turns at 10/8 of the
// motor's speed.  A step pulley in between is the way to slow it down.
//
// Which way the mouth faces to begin with decides when the first ball
// comes, so it is authored: a click in the editor turns it a quarter.
//----------------------------------------------------------------------

globals.PocketWheel = new Wheel
PocketWheel.typeName = "pocketWheel"
PocketWheel.displayName = "Pocket Wheel"
PocketWheel.defaultSpec = Wheel.defaultSpec + {"radius": 40,
  "ringRadius": 8, "mouth": 110 * pi/180, "facing": 0}

PocketWheel.beltRings = function
	return [self.spec.ringRadius]
end function

// Right, up, left, down: a quarter turn per click.
PocketWheel.stateSpecs = function
	return [{"facing": 0}, {"facing": 1}, {"facing": 2}, {"facing": 3}]
end function

// The mouth is drawn and built facing along the wheel's own zero, so which
// way it faces is simply the wheel's angle.
PocketWheel.applyState = function
	self.spec.angle = self.spec.facing * pi / 2
	super.applyState
end function

//----------------------------------------------------------------------
// Shape
//----------------------------------------------------------------------

// The rim, as points from one jaw round the back to the other, in the
// wheel's own frame.  Every 15 degrees, so the flats between them sit a
// fifth of a pixel inside the circle.
PocketWheel.rimPoints = function(cx=0, cy=0, r=null)
	if r == null then r = self.spec.radius
	half = self.spec.mouth / 2
	span = 2 * pi - self.spec.mouth
	n = ceil(span / (pi / 12))
	pts = []
	for i in range(0, n, 1)
		a = half + span * i / n
		pts.push [cx + r * cos(a), cy + r * sin(a)]
	end for
	return pts
end function

// The rim in convex pieces, each a sector of no more than a quarter turn
// with its point at the axle.
PocketWheel.sectors = function(cx=0, cy=0, r=null)
	rim = self.rimPoints(cx, cy, r)
	per = ceil((rim.len - 1) / ceil((rim.len - 1) / 6))
	out = []
	i = 0
	while i < rim.len - 1
		j = i + per
		if j > rim.len - 1 then j = rim.len - 1
		out.push [[cx, cy]] + rim[i:j + 1]
		i = j
	end while
	return out
end function

PocketWheel.makeBodies = function
	s = self.spec
	b = self.addBody
	for poly in self.sectors
		sh = b.addPolygon(poly, s.density)
		sh.setRestitution s.restitution
		sh.setFriction s.friction
		sh.setFilter config.catHub, config.maskHub
	end for
	// As for any gear: the axle carries the weight.
	b.setGravityScale 0
	// addBody placed it before it had any shapes, and a body is placed by
	// its center of mass -- which the shapes have just moved off the axle.
	self.placeBody b
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

PocketWheel.imageKey = function
	s = self.spec
	return "pocketWheel:" + s.radius + ":" + s.mouth + ":" + s.ringRadius +
	  ":" + s.color
end function

PocketWheel.makeImage = function
	s = self.spec
	r = s.radius
	g = artUtil.canvas(r * 2, r * 2)
	// Piece by piece, as the physics has it: fillPoly is for convex shapes.
	for poly in self.sectors(r, r, r)
		g.fillPoly poly, config.wheelRimColor
	end for
	for poly in self.sectors(r, r, r - 3)
		g.fillPoly poly, s.color
	end for
	// The jaws, and the rim between them.
	edge = "#00000070"
	rim = self.rimPoints(r, r)
	for p in [rim[0], rim[-1]]
		g.line r, r, p[0], p[1], edge, 2
	end for
	for i in range(0, rim.len - 2, 1)
		g.line rim[i][0], rim[i][1], rim[i + 1][0], rim[i + 1][1], edge, 1
	end for
	// The belt's sheave on the hub, grooved like a gearwheel's; it stands in
	// the mouth, because on a real one it would be behind the wheel on the
	// same shaft.
	rs = s.ringRadius
	artUtil.fillCircle g, r, r, rs + 2, config.gearHubColor
	artUtil.drawCircle g, r, r, rs, "#00000060", 3
	artUtil.drawCircle g, r, r, rs + 2, "#00000070", 1
	artUtil.fillCircle g, r, r, 2.5, "#00000090"
	return g.getImage
end function
