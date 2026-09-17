// rope.ms
// A rope, which is two different things depending on whether it is pulling.
//
// TAUT, a rope is not a shape at all: it is one scalar constraint, saying
// that the total length of the path through its tie points cannot exceed the
// length it was made with.  Everything a rope does under load comes out of
// that one equation.  With
//
//     C  = sum |P[i] - P[i-1]| - length        the stretch
//     C' = sum u[i] . (v[P[i]] - v[P[i-1]])    the rate it is stretching
//
// the solver finds the one scalar impulse -- the tension -- that stops the
// path lengthening, and applies it to each body at the point the rope pulls
// on it.  The tension is clamped at zero, because a rope pulls and never
// pushes, and that single clamp is the whole of the taut/slack distinction:
// a rope with slack in it wants negative tension, gets none, and does
// nothing.  There is no state machine.
//
// What falls out of this for free is worth spelling out.  A point where the
// rope merely turns a corner -- a pulley -- contributes u[i] - u[i+1] to the
// Jacobian, so a pulley the rope doubles back around contributes twice the
// motion and takes twice the force, and a block and tackle trades distance
// for force with no code that knows what a block and tackle is.  Two weights
// either side of a fixed pulley come out at exactly g(m1-m2)/(m1+m2).
//
// Slack normally only arises in play: while the design is being edited a
// rope simply takes its length from the layout (see remeasure), so
// rearranging things never leaves ropes drooping about the place.  The
// exception is a rope with a `freeEnd` -- tied at one end and cut at the
// other -- which is beads from the moment it is made, and keeps the length
// it was drawn with.
//
// SLACK, a rope exerts nothing on anything -- it has no mass worth reckoning
// with -- so it stops being physics and becomes a line of beads, run purely
// for looks and never pushing back on the world.  The beads are pinned at
// the tie points, fall under gravity, and are pulled straight again as the
// rope runs out of slack, so nothing pops when the constraint takes over.
// They stop at the world's shapes, one way only: a rope drapes over a ledge,
// but never moves it.
//
// The solve is in two passes, which is worth knowing about.  The impulse
// pass drives the rate of stretch to zero and nothing else; the length error
// that is left -- a step's worth of free fall, because the engine integrates
// positions before we ever see them -- is then taken out geometrically, by
// moving the bodies.  The usual shortcut of folding that error into the
// impulse pass instead (a Baumgarte bias) quietly wrecks the answer: it
// works by demanding a rate of stretch that is not zero, and every result
// the rope produces is then wrong by that amount.  It costs a real Atwood
// machine several percent of its acceleration, and two equal weights drift
// instead of balancing.  Fixing position errors with positions is exact.
//
// What a rope does NOT model: its own weight, friction at a pulley, the
// length taken up by the wrap (the physics treats a pulley as a point, while
// the drawing wraps the wheel properly), and stretch.
//
// A rope's authored state is the tie points it is fastened to, by part id,
// and its length -- which is simply the path it was drawn along.

import "importUtil"
ensureImport ["config", "part", "artUtil", "util"]

globals.Rope = new Part
Rope.typeName = "rope"
Rope.displayName = "Rope"
Rope.isRope = true
Rope.draggable = false
Rope.bodyType = null                // no bodies at all
Rope.defaultSpec = Part.defaultSpec + {"points": null, "length": 0,
  "fixedLength": false, "freeEnd": false, "color": config.ropeColor}

Rope.pts = null                     // per-instance: resolved [part, tieIndex]
Rope.jac = null                     // this step's rows: one per body pulled on
Rope.mEff = 0
Rope.tension = 0                    // kept between steps, to warm start
Rope.stretch = 0
Rope.chain = null                   // the beads, while it hangs slack
Rope.chainPrev = null
Rope.pins = null                    // bead index of each tie point
Rope.pinned = null                  // those same indexes, as a set
Rope.linkRest = null

Rope.init = function
	self.pts = null
	self.jac = null
	self.tension = 0
	self.chain = null
	if self.spec.points == null then self.spec.points = []
end function

//----------------------------------------------------------------------
// The path
//----------------------------------------------------------------------

// Our tie points, resolved to [part, tieIndex].  Null if any part it names
// has gone; the world deletes a rope whose parts go, so that is only ever a
// half-built world.
Rope.links = function
	if self.pts != null then return self.pts
	out = []
	for p in self.spec.points
		part = self.world.partById(p.part)
		if part == null then return null
		out.push [part, p.tie]
	end for
	self.pts = out
	return self.pts
end function

// Where the rope is made fast, in order.  A rope with a free end is tied at
// one end only, so a single point is a whole path.
Rope.path = function
	pts = self.links
	if pts == null then return null
	if self.spec.freeEnd then
		if pts.len < 1 then return null
	else if pts.len < 2 then
		return null
	end if
	out = []
	for p in pts
		w = p[0].tieWorld(p[1])
		if w == null then return null
		out.push w
	end for
	return out
end function

Rope.pathLength = function(path)
	total = 0
	for i in range(1, path.len - 1, 1)
		total = total + sqrt((path[i][0] - path[i-1][0]) ^ 2 +
		  (path[i][1] - path[i-1][1]) ^ 2)
	end for
	return total
end function

// Take the length from the layout, which is what design mode does every
// frame: move something a rope is tied to and the rope keeps up, rather than
// hanging slack until play is pressed.  A rope that is *meant* to hang loose
// -- a balloon's string, a fuse -- sets fixedLength and keeps the length it
// was given, which is what the beads below are there for.
Rope.remeasure = function
	if self.spec.fixedLength then return
	path = self.path
	if path == null then return
	self.spec.length = self.pathLength(path)
	self.chain = null
end function

// The length a rope is made with is the path it was drawn along: a new rope
// is exactly taut.
Rope.measure = function
	path = self.path
	if path == null then return 0
	return self.pathLength(path)
end function

//----------------------------------------------------------------------
// The constraint
//----------------------------------------------------------------------

// Work out this step's geometry: the direction of each run, how far the rope
// is stretched, and the row each body pulled on contributes.  Then hand back
// the tension it was carrying, which is what keeps a loaded rope from
// sagging a little further every step before the iterations catch it.
Rope.beginSolve = function(dt)
	if not self.buildJacobian then return
	self.applyTension self.tension
end function

// This step's geometry: how far the rope is stretched, and the row that each
// body it has hold of contributes to the constraint.  False if there is
// nothing to solve -- no path, slack rope, or nothing movable on the end.
Rope.buildJacobian = function
	self.jac = null
	// Nothing anywhere in a rope with a loose end is under tension: there is
	// nothing at that end for the rope to pull against.  It is beads only.
	if self.spec.freeEnd then
		self.tension = 0
		return false
	end if
	path = self.path
	if path == null then return false
	n = path.len - 1
	dirs = []
	total = 0
	for i in range(1, n, 1)
		dx = path[i][0] - path[i-1][0]
		dy = path[i][1] - path[i-1][1]
		d = sqrt(dx * dx + dy * dy)
		if d < 0.0001 then d = 0.0001
		dirs.push [dx / d, dy / d]
		total = total + d
	end for
	self.stretch = total - self.spec.length
	if self.stretch < -config.ropeSlop then
		// Slack: nothing to solve, and no tension to carry into next step.
		self.tension = 0
		return false
	end if

	rows = {}
	order = []
	pts = self.pts
	for k in path.indexes
		// How the path length changes as this point moves.  An end pulls
		// along its one run; a point the rope turns at pulls along the
		// difference of the two, which is what gives a pulley its purchase.
		if k == 0 then
			cx = -dirs[0][0]; cy = -dirs[0][1]
		else if k == n then
			cx = dirs[n-1][0]; cy = dirs[n-1][1]
		else
			cx = dirs[k-1][0] - dirs[k][0]
			cy = dirs[k-1][1] - dirs[k][1]
		end if
		tl = pts[k][0].tieList
		if pts[k][1] >= tl.len then continue
		b = tl[pts[k][1]][0]
		im = b.world.invMass.getRow(b.index)
		if im[0] == 0 and im[2] == 0 then continue    // static: unmovable
		if rows.hasIndex(b.index) then
			row = rows[b.index]
		else
			row = [b, 0, 0, 0, im[0], im[2]]
			rows[b.index] = row
			order.push row
		end if
		com = b.centerOfMass
		rx = path[k][0] - com[0]; ry = path[k][1] - com[1]
		row[1] = row[1] + cx
		row[2] = row[2] + cy
		row[3] = row[3] + rx * cy - ry * cx
		pts[k][0].tethered = true
	end for
	if not order then
		self.tension = 0
		return false
	end if

	sum = 0
	for row in order
		sum = sum + row[4] * (row[1] * row[1] + row[2] * row[2]) +
		  row[5] * row[3] * row[3]
	end for
	if sum <= 0 then
		self.tension = 0
		return false
	end if
	self.mEff = 1 / sum
	self.jac = order
	return true
end function

// One relaxation pass: find the tension that would stop the rope stretching,
// add it to what we have already applied, and never let the total go
// negative -- a rope cannot push.  Nothing here knows or cares how long the
// rope currently is; that is the position pass's business.
Rope.solveOnce = function(dt)
	if self.jac == null then return
	cdot = 0
	for row in self.jac
		b = row[0]
		cdot = cdot + row[1] * b.vx + row[2] * b.vy + row[3] * b.angularVelocity
	end for
	want = self.tension + self.mEff * cdot
	if want < 0 then want = 0
	delta = want - self.tension
	self.tension = want
	self.applyTension delta
end function

// Hand out an impulse of `t` along the constraint: every body gets it at the
// point the rope has hold of, which is what a rope tied off center does to
// the thing it is tied to.
Rope.applyTension = function(t)
	if t == 0 or self.jac == null then return
	for row in self.jac
		b = row[0]
		b.setVelocity b.vx - row[4] * row[1] * t, b.vy - row[4] * row[2] * t
		b.setAngularVelocity b.angularVelocity - row[5] * row[3] * t
	end for
end function

// Take the remaining stretch out of the geometry: shift each body along the
// rope, by the same shares of the correction that an impulse would have been
// split into.  Only ever shortens, and only past the slop, so a rope that is
// merely lying at its length does nothing at all.
Rope.solvePosition = function
	if not self.buildJacobian then return
	over = self.stretch - config.ropeSlop
	if over <= 0 then return
	lam = self.mEff * over
	for row in self.jac
		b = row[0]
		if row[5] != 0 then b.setAngle b.angle - row[5] * row[3] * lam
		o = b.position
		b.setPosition o[0] - row[4] * row[1] * lam, o[1] - row[4] * row[2] * lam
	end for
end function

Rope.onStop = function
	super.onStop
	self.tension = 0
	self.jac = null
	self.chain = null
end function

//----------------------------------------------------------------------
// The beads, for when it hangs
//----------------------------------------------------------------------

// Run every frame in every mode: this is appearance, not physics.
Rope.updateVisual = function(dt)
	path = self.path
	if path == null then
		self.chain = null
		return
	end if
	if self.spec.length - self.pathLength(path) <= config.ropeSlop then
		self.chain = null
		return
	end if
	if self.chain == null then self.startChain path
	self.stepChain path
end function

// Lay beads along the path as it stands, at rest.  The slack is shared out
// between the runs in proportion to their length, which is exactly right for
// the one-run rope that is the common case, and plausible otherwise (what
// really decides it is friction at the pulleys, which we do not model).
Rope.startChain = function(path)
	self.chain = []
	self.chainPrev = []
	self.pins = []
	self.pinned = {}
	self.linkRest = []
	geo = self.pathLength(path)
	// A loose end holds no tension, so the runs between tie points are
	// simply straight and the whole of the slack is in the tail.
	tail = 0
	if self.spec.freeEnd then
		tail = self.spec.length - geo
		if tail < 0 then tail = 0
	end if
	share = self.spec.length - tail
	if geo < 0.0001 then geo = 0.0001
	for k in range(0, path.len - 2, 1)
		run = sqrt((path[k+1][0] - path[k][0]) ^ 2 +
		  (path[k+1][1] - path[k][1]) ^ 2)
		// Each run after the first starts on the bead the last one ended on,
		// which is the one pinned to the tie point they share.
		if k == 0 then
			self.pins.push 0
		else
			self.pins.push self.chain.len - 1
		end if
		self.addBeads path[k], path[k+1], share * run / geo
	end for
	if path.len >= 2 then self.pins.push self.chain.len - 1
	if tail > 0 then
		last = path[path.len - 1]
		// Tied at one end only: the tail is the whole rope, and it starts on
		// the bead at that one tie point.
		if not self.chain then self.pins.push 0
		// Hung straight down, which is where it is going anyway.
		self.addBeads last, [last[0], last[1] - tail], tail
	end if
	for c in self.chain
		self.chainPrev.push [c[0], c[1]]
	end for
	for i in self.pins
		self.pinned[i] = true
	end for
end function

// Lay beads from a to b with `rest` px of rope between them.  The bead at a
// is only pushed for the first run; every run after that begins on the bead
// the one before it ended on.
Rope.addBeads = function(a, b, rest)
	n = ceil(rest / config.ropeSegment) + 1
	if n < 2 then n = 2
	if not self.chain then self.chain.push [a[0], a[1]]
	for i in range(1, n - 1, 1)
		f = i / (n - 1)
		self.chain.push [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
		self.linkRest.push rest / (n - 1)
	end for
end function

// Verlet, then a few passes of "no link may be longer than its rest length".
// Links are free to be shorter, which is what lets a slack rope gather.
Rope.stepChain = function(path)
	dt = config.timestep
	drop = config.gravity * dt * dt
	damp = config.ropeChainDamp
	ch = self.chain
	pv = self.chainPrev
	for i in ch.indexes
		x = ch[i][0]; y = ch[i][1]
		ch[i] = [x + (x - pv[i][0]) * damp, y + (y - pv[i][1]) * damp - drop]
		pv[i] = [x, y]
	end for
	if config.ropeChainCollide then self.collideChain
	for iter in range(1, config.ropeChainIterations, 1)
		for k in self.pins.indexes
			if k < path.len then ch[self.pins[k]] = [path[k][0], path[k][1]]
		end for
		for i in range(0, ch.len - 2, 1)
			ax = ch[i][0]; ay = ch[i][1]
			bx = ch[i+1][0]; by = ch[i+1][1]
			dx = bx - ax; dy = by - ay
			d = sqrt(dx * dx + dy * dy)
			rest = self.linkRest[i]
			if d <= rest or d < 0.0001 then continue
			f = (d - rest) / d / 2
			// A bead pinned to a tie point does not give: the whole of the
			// correction falls on the other end.  Sharing it and then
			// putting the pinned bead back, which is what happens if you
			// treat it like any other bead, leaves the links either side of
			// every tie point permanently overstretched.
			pa = self.pinned.hasIndex(i)
			pb = self.pinned.hasIndex(i + 1)
			if pa and pb then continue
			if pa then
				ch[i+1] = [bx - dx * f * 2, by - dy * f * 2]
			else if pb then
				ch[i] = [ax + dx * f * 2, ay + dy * f * 2]
			else
				ch[i] = [ax + dx * f, ay + dy * f]
				ch[i+1] = [bx - dx * f, by - dy * f]
			end if
		end for
	end for
	for k in self.pins.indexes
		if k < path.len then ch[self.pins[k]] = [path[k][0], path[k][1]]
	end for
end function

// One-way collision: a bead that has ended up inside something goes back
// where it came from.  Nothing is pushed in return.
Rope.collideChain = function
	ph = self.world.phys
	ch = self.chain
	pv = self.chainPrev
	for i in ch.indexes
		if ph.shapesAt(ch[i][0], ch[i][1]).len > 0 then
			ch[i] = [pv[i][0], pv[i][1]]
		end if
	end for
end function

//----------------------------------------------------------------------
// Cutting
//----------------------------------------------------------------------

// The line the rope is actually drawn along, together with the two things a
// cut has to know about it: which vertex each tie point sits on, and how
// much *rope* lies between consecutive vertices.  Hanging, that is the beads
// and their rest lengths.  Taut, it is the straight runs between the tie
// points, and the rope is shared out along them in proportion, so that the
// pieces of a cut rope still add up to the whole.
Rope.polyline = function
	if self.chain != null and self.pins != null then
		return {"pts": self.chain, "pins": self.pins, "rest": self.linkRest}
	end if
	path = self.path
	if path == null or path.len < 2 then return null
	geo = self.pathLength(path)
	if geo < 0.0001 then return null
	f = self.spec.length / geo
	rest = []
	pins = []
	for i in range(0, path.len - 1, 1)
		pins.push i
		if i == 0 then continue
		rest.push f * sqrt((path[i][0] - path[i-1][0]) ^ 2 +
		  (path[i][1] - path[i-1][1]) ^ 2)
	end for
	return {"pts": path, "pins": pins, "rest": rest}
end function

// Cut the rope between vertices i and i+1 of that line, `t` of the way along.
// What is left is up to two ropes, each still made fast wherever it still has
// a tie point and loose at the cut, and the rope itself is taken out of the
// world.  A piece with no tie point left at all -- the far end of something
// that was already hanging free -- simply falls away.
//
// Whoever does the cutting must queue it rather than call this during a step:
// see GameWorld.cutRope.
Rope.cutAt = function(i, t)
	w = self.world
	if w == null or w.partById(self.id) == null then return []
	pl = self.polyline
	if pl == null or i >= pl.rest.len then return []
	rest = pl.rest
	before = rest[i] * t
	for k in range(0, i - 1, 1)
		before = before + rest[k]
	end for
	after = self.spec.length - before
	if before < 0 then before = 0
	if after < 0 then after = 0
	// A tie point sitting on vertex i or earlier is on the near side of the
	// cut; everything after it goes with the far piece.
	n = 0
	for k in pl.pins.indexes
		if pl.pins[k] <= i then n = k + 1
	end for
	pts = self.spec.points
	head = pts[:n]
	// The far piece is tied at what was the rope's far end and loose at the
	// cut, so its points run backwards: a free-ended rope hangs its slack
	// from the last tie point in the list.
	tail = []
	for k in range(pts.len - 1, n, -1)
		tail.push pts[k]
	end for
	w.removePart self
	out = []
	if head then out.push self.makePiece(w, head, before)
	if tail then out.push self.makePiece(w, tail, after)
	return out
end function

// One piece of a cut rope: tied where it still can be, loose from there on.
Rope.makePiece = function(w, points, length)
	pts = []
	for p in points
		pts.push {} + p
	end for
	r = Rope.make({"points": pts, "freeEnd": true, "fixedLength": true,
	  "color": self.spec.color})
	w.addPart r
	r.spec.length = length
	return r
end function

//----------------------------------------------------------------------
// Drawing
//----------------------------------------------------------------------

Rope.draw = function(disp)
	c = self.spec.color
	w = config.ropeWidth
	if self.chain != null then
		ch = self.chain
		for i in range(0, ch.len - 2, 1)
			disp.line ch[i][0], ch[i][1], ch[i+1][0], ch[i+1][1], c, w
		end for
		return
	end if
	path = self.path
	if path == null then return
	// Taut: straight runs between the tangent points of each wheel, and the
	// wrap itself drawn around the rim.  The physics treats a pulley as a
	// point; only the drawing knows it has a radius.
	n = path.len - 1
	from = path[0]
	for k in range(1, n, 1)
		if k == n then
			disp.line from[0], from[1], path[k][0], path[k][1], c, w
			break
		end if
		r = self.pts[k][0].wrapRadius
		if r <= 0 then
			disp.line from[0], from[1], path[k][0], path[k][1], c, w
			from = path[k]
			continue
		end if
		arc = self.wrapPoints(path[k-1], path[k], path[k+1], r)
		if arc == null then
			disp.line from[0], from[1], path[k][0], path[k][1], c, w
			from = path[k]
			continue
		end if
		disp.line from[0], from[1], arc[0][0], arc[0][1], c, w
		for i in range(0, arc.len - 2, 1)
			disp.line arc[i][0], arc[i][1], arc[i+1][0], arc[i+1][1], c, w
		end for
		from = arc[arc.len - 1]
	end for
end function

// The points the rope actually touches, going around a wheel of radius r at
// b, coming from a and leaving towards c.
//
// The rope leaves the wheel where the radius is square to the rope, on the
// outside of the bend.  That side is found from the bisector of the turn,
// which stays well behaved right through the half turn of a rope hung over a
// pulley -- where the two tangent points are opposite ends of a diameter and
// any formula built on which way the rope turns has nothing to go on.
Rope.wrapPoints = function(a, b, c, r)
	d1 = util.unit(b[0] - a[0], b[1] - a[1])
	d2 = util.unit(c[0] - b[0], c[1] - b[1])
	if d1 == null or d2 == null then return null
	m = util.unit(d1[0] - d2[0], d1[1] - d2[1])     // outward bisector
	if m == null then return null                   // straight through
	p1 = [d1[1], -d1[0]]
	if p1[0] * m[0] + p1[1] * m[1] < 0 then p1 = [-p1[0], -p1[1]]
	p2 = [d2[1], -d2[0]]
	if p2[0] * m[0] + p2[1] * m[1] < 0 then p2 = [-p2[0], -p2[1]]
	a1 = atan(p1[1], p1[0])
	a2 = atan(p2[1], p2[0])
	delta = a2 - a1
	while delta > pi; delta = delta - 2 * pi; end while
	while delta <= -pi; delta = delta + 2 * pi; end while
	// Of the two ways round, take the one that passes the outward side.
	mid = a1 + delta / 2
	if cos(mid) * m[0] + sin(mid) * m[1] < 0 then
		if delta > 0 then delta = delta - 2 * pi else delta = delta + 2 * pi
	end if
	out = []
	steps = config.ropeArcSteps
	for i in range(0, steps, 1)
		ang = a1 + delta * i / steps
		out.push [b[0] + r * cos(ang), b[1] + r * sin(ang)]
	end for
	return out
end function

//----------------------------------------------------------------------
// Editor odds and ends.  A rope has no footprint and no shapes, so it plays
// no part in the placement rules and has to answer for itself when clicked.
//----------------------------------------------------------------------

Rope.placementOK = function(world)
	return true
end function

Rope.snapPose = function(world, x, y)
	return [x, y]
end function

Rope.designBounds = function
	path = self.chain
	if path == null then path = self.path
	if path == null then return [self.spec.x, self.spec.y, 1, 1]
	x0 = path[0][0]; y0 = path[0][1]; x1 = x0; y1 = y0
	for p in path
		if p[0] < x0 then x0 = p[0]
		if p[0] > x1 then x1 = p[0]
		if p[1] < y0 then y0 = p[1]
		if p[1] > y1 then y1 = p[1]
	end for
	return [x0 - 2, y0 - 2, x1 - x0 + 4, y1 - y0 + 4]
end function

Rope.hitTest = function(x, y)
	pts = self.chain
	if pts == null then pts = self.path
	if pts == null then return false
	for i in range(0, pts.len - 2, 1)
		if util.distToSegment(x, y, pts[i], pts[i+1]) < config.ropeWidth + 3 then
			return true
		end if
	end for
	return false
end function

// A rope is only a rope while everything it is tied to is still there.
Rope.dependsOn = function(other)
	for p in self.spec.points
		if p.part == other.id then return true
	end for
	return false
end function

Rope.imageKey = function
	return "rope:" + self.spec.color
end function

// The palette icon: a bight of rope.
Rope.makeImage = function
	w = config.grid * 2
	h = config.grid * 2
	g = artUtil.canvas(w, h)
	prev = null
	for i in range(0, 16, 1)
		f = i / 16
		x = 2 + f * (w - 4)
		y = h / 2 - sin(f * pi) * (h / 2 - 3)
		if prev != null then
			g.line prev[0], prev[1], x, y, self.spec.color, config.ropeWidth
		end if
		prev = [x, y]
	end for
	return g.getImage
end function
