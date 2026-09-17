// torque.ms
// Rotating systems: which wheels turn together, and how fast.
//
// A gear, a belt wheel and a motor are all one thing -- a hub, bolted to the
// board, that turns -- and they are linked to each other by ratios: meshed
// gears by their tooth counts, belted wheels (later) by their rim radii.  A
// connected set of them is a *train*, and a train has exactly one degree of
// freedom, because fixing one wheel's angle fixes every other's.
//
// So a train is a lever with more pieces, and it is held the same way.  The
// engine has no joints, so after each step we take whatever free-body state
// the contacts produced, read out the train's momentum in its one coordinate,
// and put every hub back on its axle turning at the one rate that carries
// that momentum.  As with the lever this is exact rather than approximate,
// and it is two-way for the same reason: between projections the hubs are
// ordinary dynamic bodies, so a ball dropped on a gear spins the train, and
// a spinning train drags the ball along by friction.
//
// What a part must provide to join in (see Gear):
//      turns           true, which is what marks it as one of these
//      teeth           tooth count, or 0 for a smooth wheel
//      pitchRadius     the circle that touches its neighbor's
//      beltRings       ...and the ones a belt may run on, innermost first
//      hubWorld        [x, y] of the axle
//      hubAngle        where it stands now
//      hubBody         the body that turns, or null
//      driveTorque(dt) what it drives the train with, in engine units
//      dragTorque(dt)  and how much of that it loses per unit of speed
//      spinStop        a direction it cannot turn any further, or 0
//      setSpin(a, w)   put it at angle a, turning at w
//      setPhase(a)     design mode: author that angle (writes spec)

import "importUtil"
ensureImport ["config", "physics", "util"]

globals.Train = {}

Train.parts = null      // per-instance; see build
Train.ratio = null      // each part's turn rate, per unit of the train's
Train.phase = null      // ...and its angle when the train's own angle is zero
Train.theta = 0         // the train's one coordinate
Train.spin = 0
Train.locked = false    // a cycle that disagrees with itself: it jams

//----------------------------------------------------------------------
// Finding the trains
//----------------------------------------------------------------------

// Every pair of toothed hubs that mesh, as indices into `hubs`.  Meshing is
// not authored: two gears engage because their pitch circles touch, which is
// what makes a gear train something you build by placing parts rather than by
// connecting them up.
meshPairs = function(hubs)
	out = []
	for i in range(0, hubs.len - 2, 1)
		a = hubs[i]
		if a.teeth <= 0 then continue
		ca = a.hubWorld
		for j in range(i + 1, hubs.len - 1, 1)
			b = hubs[j]
			if b.teeth <= 0 then continue
			cb = b.hubWorld
			d = sqrt((cb[0] - ca[0]) ^ 2 + (cb[1] - ca[1]) ^ 2)
			if abs(d - a.pitchRadius - b.pitchRadius) <= config.gearMeshTolerance then
				out.push [i, j]
			end if
		end for
	end for
	return out
end function

// Every belt in the world, as [hub, hub, radius, radius] -- indices into
// `hubs`, and the radius the belt runs at on each.  Unlike a mesh this is
// authored, all of it: a belt reaches as far as it likes, so only the player
// knows which two wheels were meant, and on a step pulley, which groove.
beltPairs = function(world, hubs)
	byId = {}
	for i in hubs.indexes
		byId[hubs[i].id] = i
	end for
	out = []
	for p in world.parts
		if not p.isBelt then continue
		if not byId.hasIndex(p.spec.a) or not byId.hasIndex(p.spec.b) then continue
		ia = byId[p.spec.a]; ib = byId[p.spec.b]
		if ia == ib then continue
		ra = p.ringRadius(0); rb = p.ringRadius(1)
		if ra <= 0 or rb <= 0 then continue
		out.push [ia, ib, ra, rb]
	end for
	return out
end function

// Where `b` has to stand for its teeth to interleave with `a`'s, given that
// `a` stands at `aAngle`.
//
// Teeth are drawn with one centered at each multiple of 2*pi/N in the part's
// own frame, so the fraction of a tooth that the meshing point falls at on
// `a` is `u` below.  The two pitch circles roll on each other without slip,
// so the contact traverses both at the same rate, and interleaving means `b`
// must be half a tooth out of step with that: a tooth of one lands in a gap
// of the other, now and therefore always.
//
// That leaves the choice of *which* whole tooth, and any of them will do --
// so we take the one that leaves `b` nearest to where it already stands,
// which is what keeps a gear from visibly jumping as its neighbor is dragged
// into mesh with it.
meshAngle = function(a, aAngle, b)
	ca = a.hubWorld; cb = b.hubWorld
	alpha = atan(cb[1] - ca[1], cb[0] - ca[0])
	u = (alpha - aAngle) * a.teeth / (2 * pi)
	u = u - floor(u)
	step = 2 * pi / b.teeth
	base = alpha + pi - step * (0.5 - u)
	return base - step * round((base - b.hubAngle) / step)
end function

// The world's trains, worked out from where its parts are standing.
//
// Cheap enough to redo whenever the design changes, which is how it is used:
// there is no incremental version and no need for one.
build = function(world)
	hubs = []
	for p in world.parts
		if p.turns then hubs.push p
	end for
	// One entry per link: [the hub at the other end, how fast it turns per
	// unit of this one, whether it is a belt].  Both kinds of link are just
	// a ratio, which is what lets the rest of this not care which is which.
	adj = []
	for i in hubs.indexes
		adj.push []
	end for
	for e in meshPairs(hubs)
		a = hubs[e[0]]; b = hubs[e[1]]
		// Meshed gears turn opposite ways, in inverse proportion to teeth.
		adj[e[0]].push [e[1], -a.teeth / b.teeth, false]
		adj[e[1]].push [e[0], -b.teeth / a.teeth, false]
	end for
	for e in beltPairs(world, hubs)
		// Belted rims travel together, and the same way round.  This is the
		// one link whose ratio is not settled by what the two parts are: a
		// step pulley answers differently for each of its grooves, which is
		// the whole of how a belt train trades speed for force.
		adj[e[0]].push [e[1], e[2] / e[3], true]
		adj[e[1]].push [e[0], e[3] / e[2], true]
	end for

	trains = []
	slot = {}           // hub index -> its place in the train being built
	for i in hubs.indexes
		if slot.hasIndex(i) then continue
		t = new Train
		t.parts = [hubs[i]]
		t.ratio = [1]
		t.phase = [hubs[i].hubAngle]
		t.theta = 0
		t.spin = 0
		t.locked = false
		slot[i] = 0
		queue = [i]
		while queue
			k = queue.pull
			for link in adj[k]
				m = link[0]
				r = t.ratio[slot[k]] * link[1]
				if slot.hasIndex(m) then
					// Reached twice by different routes: unless both agree,
					// the train is over-constrained and cannot turn at all.
					// Three gears in a triangle jam in just this way, and so
					// does a belt run the wrong way round a pair of them.
					if abs(r - t.ratio[slot[m]]) > 1e-6 * abs(r) then
						t.locked = true
					end if
					continue
				end if
				slot[m] = t.parts.len
				t.parts.push hubs[m]
				t.ratio.push r
				// A belt has no teeth to line up, so the wheel stays where
				// it stands.
				if link[2] then
					t.phase.push hubs[m].hubAngle
				else
					t.phase.push meshAngle(hubs[k], t.phase[slot[k]], hubs[m])
				end if
				queue.push m
			end for
		end while
		trains.push t
	end for
	return trains
end function

//----------------------------------------------------------------------
// Turning
//----------------------------------------------------------------------

// One step of the train's one degree of freedom.  Call it after the physics
// step, so that what the contacts did to each hub is in hand.
Train.solve = function(dt)
	moment = 0          // what the train resists a turn with
	mom = 0             // ...and what it is carrying, out of the step just run
	drive = 0           // torque applied to it, in the same coordinate
	drag = 0            // and how fast that torque falls off with speed
	for i in self.parts.indexes
		p = self.parts[i]
		b = p.hubBody
		if b == null then continue
		r = self.ratio[i]
		moment = moment + b.inertia * r * r
		mom = mom + b.inertia * r * b.angularVelocity
		drive = drive + p.driveTorque(dt) * r
		drag = drag + p.dragTorque(dt) * r * r
	end for
	if moment <= 0 then return

	if self.locked then
		self.spin = 0
	else
		// A motor's torque falls off with speed, and `drag` is how steeply.
		// Solved for the speed at the *end* of the step rather than applied
		// from the speed at the start of it, which is not fussiness: the
		// slope is steep enough here that the explicit version would
		// oscillate and then diverge inside a few steps.  Written this way
		// it is both exact for a straight-line torque curve and
		// unconditionally stable, and a drag of zero leaves it as it was.
		self.spin = (mom + drive * dt) / (moment + drag * dt)
		self.applyStops
	end if
	self.theta = self.theta + self.spin * dt
	for i in self.parts.indexes
		self.parts[i].setSpin self.phase[i] + self.ratio[i] * self.theta,
		  self.ratio[i] * self.spin
	end for
end function

// A train that has run up against something -- a spool wound out to its drum
// -- stops dead, and stays stopped until it is driven the other way.  The
// whole train, because every wheel in it is the same wheel; and dead, with
// the momentum dropped rather than returned, because what it has run into is
// the end of the rope and not a spring.
Train.applyStops = function
	for i in self.parts.indexes
		st = self.parts[i].spinStop
		if st == 0 then continue
		// The blocked direction as the train sees it: a hub on a negative
		// ratio is stopped by the train turning the other way.
		if self.spin * st * self.ratio[i] > 0 then
			self.spin = 0
			return
		end if
	end for
end function

// Design mode: author the angles the train was built with, so that gears sit
// in mesh as they are dragged about and Play changes nothing.
Train.applyPhase = function
	for i in self.parts.indexes
		self.parts[i].setPhase self.phase[i]
	end for
end function
