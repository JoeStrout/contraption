// part.ms
// The Part base class: one thing sitting in the world.
//
// A part's authored state lives entirely in its `spec` map -- position,
// angle, and whatever else the type needs (radius, color, switch position).
// Nothing in the running simulation may write to `spec`.  That one rule buys
// us two things: Stop is just "put the bodies back where spec says", and
// saving a design is just writing out each part's type name and its spec.
//
// Runtime state -- whether a candle is lit, how much charge a capacitor
// holds -- lives on the part itself, and onStop is responsible for clearing
// it.
//
// Subclassing: `Ball = new Part`, then override the hooks below.  Note that
// every mutable per-instance field (bodies, sprites, spec) must be assigned
// fresh in `make`; a list left on the class would be shared by every
// instance of it.

import "importUtil"
ensureImport ["config", "physics", "artUtil", "util"]

globals.Part = {}

Part.typeName = "part"              // registry key; what a save file records
Part.displayName = "Part"
Part.bodyType = physics.DYNAMIC     // body type applied when play begins
Part.fixed = false                  // level scenery: not draggable or deletable
Part.defaultSpec = {"x": 0, "y": 0, "angle": 0,
  "linearDamping": 0, "angularDamping": 0, "bounceSoftSpeed": 0}

Part.isRope = false                 // ropes are solved and drawn specially
Part.draggable = true               // a rope is not moved by dragging it
Part.mountsOnTie = false            // dropped on a tie point, not on the grid
Part.drawsInFront = false           // kept at the top of the part layer; see
                                    // GameWorld.restackSprites
Part.wrapRadius = 0                 // pulleys: the wheel a rope bends around
Part.turns = false                  // gears and wheels: a hub that turns with
                                    // whatever it is linked to; see torque.ms
Part.isBelt = false                 // belts are drawn and linked specially
Part.ropeFixed = false              // a rope tied here is not pulled on by the
                                    // rope solver: the part answers for it
                                    // itself, as a spool does
Part.isWire = false                 // a wire is a rope that carries current
                                    // instead of tension; see parts/wire.ms
Part.liveSource = false             // an outlet: its terminals are always live
Part.breakPower = 0                 // what a blast has to be worth to destroy
                                    // this part outright; 0 is indestructible.
                                    // The mirror of heat's two constants --
                                    // see config's explosives section.

Part.spec = null                    // per-instance, see make
Part.bodies = null
Part.sprites = null                 // per-instance.  An entry may itself be a
                                    // *list* of sprites, which a SpriteDisplay
                                    // draws depth first: that is how a whole
                                    // particle pool holds one place in the
                                    // draw order.  See particles.ms.
Part.spriteDisp = null              // the display our sprites are currently on
Part.world = null                   // the GameWorld we belong to
Part.settleTime = 0                 // runtime: seconds spent barely moving
Part.tethered = false               // runtime: a taut rope is holding us
Part.ties = null                    // per-instance, resolved lazily; see tieList
Part.terms = null                   // ...and the same for terminals
Part.powered = false                // runtime: a live net reaches us
Part.liveTerms = null               // runtime: per terminal, the same; see
                                    // termLive
Part.id = 0                         // stable identity, for parts that name others
Part.nextId = 1                     // the next id to hand out

//----------------------------------------------------------------------
// Construction
//----------------------------------------------------------------------

// Make a part of this type.  `spec` overrides individual defaults; anything
// it leaves out comes from defaultSpec.
Part.make = function(spec=null)
	p = new self
	p.spec = {} + self.defaultSpec
	if spec != null then p.spec += spec
	p.bodies = []
	p.sprites = []
	p.settleTime = 0
	p.ties = null
	p.terms = null
	p.powered = false
	p.liveTerms = []
	// Identity lives in spec, so that it survives a save and the references
	// other parts hold -- a rope's tie points, a pulley's mount -- still mean
	// the same parts when the design is loaded back.
	if not p.spec.hasIndex("id") or not p.spec.id then
		p.spec.id = Part.nextId
	else if p.spec.id >= Part.nextId then
		Part.nextId = p.spec.id
	end if
	Part.nextId += 1
	p.id = p.spec.id
	p.init
	return p
end function

// Subclass hook: set up type-specific fields, after spec is in place.
Part.init = function
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// Subclass hook: the part's footprint, [width, height], ignoring rotation.
// This drives snapping, the selection box, and the palette icon.
Part.size = function
	return [config.grid, config.grid]
end function

// The footprint in world coordinates: [left, bottom, width, height].
Part.designBounds = function
	sz = self.size
	return [self.spec.x - sz[0] / 2, self.spec.y - sz[1] / 2, sz[0], sz[1]]
end function

//----------------------------------------------------------------------
// Tie points: the places a rope may be fastened to this part.
//----------------------------------------------------------------------

// Subclass hook: the tie points, as [x, y] in the part's own frame (relative
// to spec.x/y, unrotated), each optionally followed by the index of the body
// that carries it.
Part.tieLocals = function
	return []
end function

// The same points resolved to [body, lx, ly], in that body's own frame,
// which is what a rope needs to follow them around.
//
// Resolved on demand rather than at build time, because a part may tie onto
// another part (a mounted pulley rides on whatever it is bolted to) and the
// order parts are built in says nothing about which of them that is.
Part.tieList = function
	if self.ties == null then self.makeTies
	return self.ties
end function

Part.makeTies = function
	self.ties = self.resolveLocals(self.tieLocals)
end function

// Turn a list of part-frame points into [body, lx, ly] in each body's own
// frame.  Shared by tie points and terminals, which differ in what they are
// for and not at all in how they are pinned to the part.
Part.resolveLocals = function(pts)
	out = []
	for t in pts
		bi = 0
		if t.len > 2 then bi = t[2]
		if bi >= self.bodies.len then continue
		b = self.bodies[bi]
		out.push [b, t[0] - b.localX, t[1] - b.localY]
	end for
	return out
end function

// Subclass hook: where a rope that ends at tie point i is drawn leaving this
// part, given the next point along the rope.  The physics has the rope ending
// at the tie point itself, wherever that is; this is only the picture.
//
// The default is the near edge of whatever the rope wraps, which is right for
// a wheel a rope is simply tied to, and nothing at all for a part with no
// wrap radius.
Part.ropeExit = function(i, toward)
	w = self.tieWorld(i)
	r = self.wrapRadius
	if w == null or r <= 0 then return w
	u = util.unit(toward[0] - w[0], toward[1] - w[1])
	if u == null then return w
	return [w[0] + u[0] * r, w[1] + u[1] * r]
end function

// Subclass hook: does a rope clicked at tie point i carry on over it, rather
// than ending there?  Both a pulley's wheel and a spool's drum have a rim for
// a rope to wrap, but only one of them is a place to route through.
Part.ropeRoutes = function(i)
	return self.wrapRadius > 0 and i == 0
end function

// Subclass hook: how fast this part is letting rope out at tie point i, in
// pixels per second, negative to take it in.  A spool is the only thing that
// does; for everything else a rope's length is its own business.
Part.windRate = function(i)
	return 0
end function

// Where tie point i has got to in the world.
Part.tieWorld = function(i)
	return self.pointWorld(self.tieList, i)
end function

// Where point i of a resolved list has got to in the world.
Part.pointWorld = function(pts, i)
	if i >= pts.len then return null
	t = pts[i]
	b = t[0]
	o = b.position
	a = b.angle
	c = cos(a); sn = sin(a)
	return [o[0] + t[1] * c - t[2] * sn, o[1] + t[1] * sn + t[2] * c]
end function

//----------------------------------------------------------------------
// Terminals: where a wire may be connected.
//
// The same machinery as tie points, kept apart from them because they mean
// different things and the editor must only ever offer one of them: a rope
// is tied to tie points, a wire is run between terminals.
//
// Every part here has one terminal and grounds through the pegboard, which
// is what lets a wire be a single conductor and a net be one bit.  Two
// terminals are for parts that sit *in line* -- a switch, a fuse, a relay's
// contacts -- and what such a part joins up inside itself is `conducts`.
//----------------------------------------------------------------------

// Subclass hook: the terminals, as [x, y] in the part's own frame, each
// optionally followed by the index of the body that carries it.
Part.terminalLocals = function
	return []
end function

Part.terminalList = function
	if self.terms == null then self.terms = self.resolveLocals(self.terminalLocals)
	return self.terms
end function

Part.terminalWorld = function(i)
	return self.pointWorld(self.terminalList, i)
end function

// Subclass hook: how big the head of a cord plugged in at terminal i is.
// A bare post takes the default collar; a socket takes a plug that covers
// it, which is the whole of how a socket shows it is occupied.
Part.plugRadius = function(i)
	return config.plugRadius
end function

// Is terminal i, specifically, on a live net?  `powered` answers for the
// whole part, which is all a load with one terminal needs; a part that has
// to tell its terminals apart -- a relay, whose coil is live or not quite
// independently of its contacts -- asks here.  Filled by circuit.solve.
Part.termLive = function(i)
	if self.liveTerms == null or i >= self.liveTerms.len then return false
	return self.liveTerms[i]
end function

// Subclass hook: does current pass between terminals i and j inside this
// part?  Never, for a part with one terminal; for a switch, when it is
// closed.  See circuit.ms.
Part.conducts = function(i, j)
	return false
end function

//----------------------------------------------------------------------
// Authored starting states
//
// Some parts have more than one sensible state to start a run in: a switch
// open or shut, a candle lit or not.  Which one is *authored* state, so it
// lives in spec and is restored by Stop like everything else there, and the
// editor sets it by clicking a part that is already selected (see
// Editor.tryCycle).
//
// A state is a fragment of spec rather than a number, because more than one
// field may have to move together and because what a part calls its state is
// then readable in the saved design instead of being an index into a list
// this file happens to be keeping.
//----------------------------------------------------------------------

// Subclass hook: the states this part may be started in, in the order a
// click walks through them.  Fewer than two means a click does nothing.
Part.stateSpecs = function
	return []
end function

// Which of them the part is in: the first whose every field matches spec, or
// -1 for a spec that is none of them (a design saved before a state was
// added, say), which cycles to the first.
Part.stateIndex = function
	ss = self.stateSpecs
	for i in ss.indexes
		hit = true
		for kv in ss[i]
			if not self.spec.hasIndex(kv.key) or self.spec[kv.key] != kv.value then
				hit = false
				break
			end if
		end for
		if hit then return i
	end for
	return -1
end function

// Move on to the next state, and return whether there was one.  Design mode
// only: this writes to spec, which is the authored state, and authoring it
// is the whole point.
Part.cycleState = function
	ss = self.stateSpecs
	if ss.len < 2 then return false
	// Field by field, into the map we have: a fresh `spec + fragment` would
	// leave anything already holding this part's spec looking at the old one.
	for kv in ss[(self.stateIndex + 1) % ss.len]
		self.spec[kv.key] = kv.value
	end for
	self.applyState
	return true
end function

// Subclass hook: spec has just changed, so look like it.  The default puts
// the bodies back where the new spec says and redraws, which covers a part
// whose state is a *pose* -- a switch's paddle standing the other way.  A
// part whose state is a different picture swaps its sprites' images here; a
// part with runtime state derived from spec re-derives it here.
Part.applyState = function
	self.placeBodies
	self.syncSprites
	if self.world != null then self.world.syncDependents self
end function

//----------------------------------------------------------------------
// Placement and picking
//----------------------------------------------------------------------

// Subclass hook: where a part dropped at (x, y) should actually land.
Part.snapPose = function(world, x, y)
	return world.gridSnap(self, x, y)
end function

// Subclass hook: may the part sit where it now is?
Part.placementOK = function(world)
	return world.footprintOK(self)
end function

// Subclass hook: does (x, y) hit this part?  For parts the physics cannot
// answer for -- a rope has no shapes, a mounted pulley has no body.
Part.hitTest = function(x, y)
	return false
end function

// Subclass hook: is this part only meaningful while `other` exists?  If so,
// deleting `other` deletes this one too.
Part.dependsOn = function(other)
	return false
end function

//----------------------------------------------------------------------
// Edit handles
//
// A part whose shape can be changed in the editor -- not just moved --
// offers a handle for it: a point the editor draws on the selection box and
// lets the user drag.  What dragging it means is entirely the part's own
// business; the editor only asks where the handle is and reports where the
// mouse has taken it.  Like cycleState, this is authoring, so it writes to
// spec.
//----------------------------------------------------------------------

// Subclass hook: where the handle is, in world coordinates, or null for a
// part that has none.
Part.handleWorld = function
	return null
end function

// Subclass hook: the handle has been dragged to (x, y).  Change spec to
// suit, rebuild to match (see reshape), and return whether anything changed.
Part.dragHandle = function(x, y)
	return false
end function

// Spec has changed in a way that changes the shapes themselves, which
// placeBodies cannot follow: take the part out of the physics and build it
// again.  Design mode only.
Part.reshape = function
	w = self.world
	self.destroy
	self.build w
	w.restackSprites
	w.syncDependents self
end function

//----------------------------------------------------------------------
// Physics bodies
//----------------------------------------------------------------------

// Add a body at (dx, dy) in the part's own frame, and remember that offset so
// we can put it back on reset.
//
// The body is created DYNAMIC whatever the part's real bodyType, because in
// design mode everything must be dynamic: physics.findPairs skips any pair
// where neither body is dynamic, so two static parts would otherwise be
// invisible to each other and could be placed overlapping.  onPlay applies
// the real type.
Part.addBody = function(dx=0, dy=0)
	b = self.world.phys.addBody(0, 0, physics.DYNAMIC, 0)
	b.part = self
	b.localX = dx
	b.localY = dy
	b.setDamping self.spec.linearDamping, self.spec.angularDamping
	self.bodies.push b
	self.placeBody b
	return b
end function

// Put one body where the authored pose says it belongs, at rest.
Part.placeBody = function(b)
	s = self.spec
	a = s.angle
	c = cos(a); sn = sin(a)
	// Angle first: setPosition works from the body's current angle to place
	// the center of mass, so setting the angle afterwards would shift a
	// body whose shapes are not centered on its origin.
	b.setAngle a
	b.setPosition s.x + b.localX * c - b.localY * sn,
	  s.y + b.localX * sn + b.localY * c
	b.setVelocity 0, 0
	b.setAngularVelocity 0
end function

Part.placeBodies = function
	for b in self.bodies
		self.placeBody b
	end for
end function

// Subclass hook: create the part's bodies and shapes, using addBody.
Part.makeBodies = function
end function

//----------------------------------------------------------------------
// Sprites
//----------------------------------------------------------------------

// Subclass hook: a cache key that distinguishes this part's appearance from
// every other.  Everything the drawing depends on belongs in it.
Part.imageKey = function
	return self.typeName
end function

// Subclass hook: draw and return the part's Image.
Part.makeImage = function
	g = artUtil.canvas(config.grid, config.grid)
	g.fillRect 0, 0, config.grid, config.grid, "#FF00FF"
	return g.getImage
end function

// The part's Image, drawn once per distinct imageKey and then shared.
Part.image = function
	key = self.imageKey
	if not artUtil.cache.hasIndex(key) then
		artUtil.cache[key] = self.makeImage
	end if
	return artUtil.cache[key]
end function

// Subclass hook: the one picture that stands for the whole part in the
// palette.  It is the part's Image for anything drawn as a single sprite,
// and something else for an assembly whose sprites move separately -- a
// motor's Image is only the gearwheel, because that is the piece that turns.
Part.paletteImage = function
	return self.image
end function

// Subclass hook: create the part's sprites.  The default makes one sprite per
// body, all showing self.image, which is what single-shape parts want.
Part.makeSprites = function
	self.spriteDisp = self.world.partDisp
	for b in self.bodies
		sp = new Sprite
		sp.image = self.image
		self.sprites.push sp
		self.spriteDisp.sprites.push sp
	end for
end function

// Lay a wash of color over the part, by multiplying it into each sprite's
// tint: white for the part's own colors, anything else to say something
// about it -- the editor washes a part red while it is over a spot it
// cannot be dropped on.
//
// It is a hook because a part whose art carries a tint of its own (a
// balloon is one flat gray picture, tinted to whatever color it is) has to
// put that tint back underneath, rather than have it painted over.
//
// A nested list is a particle pool, whose tints are its own business -- they
// are the particles' age -- and the wash is gone again the moment the part
// is dropped, so it is left alone.
Part.tintSprites = function(wash="#FFFFFF")
	for sp in self.sprites
		if sp isa list then continue
		sp.tint = wash
	end for
end function

// Subclass hook: what this part has got that is hot enough to set something
// alight, as [x, y, radius, power] each.  A lit candle has its flame, a
// burning fuse has its front.  Gathered once a step and only in play; see
// heat.ms.
Part.heatSources = function
	return []
end function

// Subclass hook: what this part is giving off light from, as [x, y,
// brightness] each -- a lit lamp's filament, a candle's flame.  Asked every
// frame, in every mode, by whatever cares where light comes from, which is so
// far only a lens.  Brightness is 1 for a lamp.
Part.lightSources = function
	return []
end function

// Subclass hook: work this part asked to have done once the step is over,
// because doing it during the step would mean adding to or removing from the
// list `advance` is walking.  `what` is whatever the part passed to
// GameWorld.defer and means nothing outside the part that asked.
Part.applyDeferred = function(what, arg)
end function

// Subclass hook: one frame of whatever the part does purely for the look of
// it -- a flame's particles, a glow's flicker.  Unlike `update` this runs in
// every mode but PAUSED, design mode included, because a lit candle should
// burn while the machine is still being built.  Nothing here may touch the
// physics or the spec.  See GameWorld.updateEffects.
Part.updateEffects = function(dt)
end function

// Subclass hooks: sprites that belong at the very back or the very front of
// the part layer, wherever the part itself sits in it.  `drawsInFront` is the
// same idea for a whole part; this is for one sprite of several, which is
// what a lamp's pool of light is -- the lamp stands among the other parts and
// its glow lies under (or over) all of them.  Returned sprites must be the
// part's own, so that destroy and moveSpritesTo still account for them.
// See GameWorld.restackSprites.
Part.backSprites = function
	return []
end function

Part.frontSprites = function
	return []
end function

// Move this part's sprites to another display, and remember where they went.
// The editor uses this to float a part above the panel while it is dragged.
Part.moveSpritesTo = function(disp)
	if self.spriteDisp != null and refEquals(self.spriteDisp, disp) then return
	for sp in self.sprites
		if self.spriteDisp != null then util.removeRef self.spriteDisp.sprites, sp
		disp.sprites.push sp
	end for
	self.spriteDisp = disp
end function

// Copy body transforms onto sprites.  The default pairs them up in order,
// which is right as long as each shape is centered on its body's origin --
// and so is only for parts whose sprites are all plain sprites; anything
// with a nested list among them has its own ideas anyway and overrides this.
Part.syncSprites = function
	for i in self.sprites.indexes
		if i >= self.bodies.len then break
		b = self.bodies[i]
		sp = self.sprites[i]
		sp.x = b.x
		sp.y = b.y
		sp.rotation = b.angle * 180 / pi
	end for
end function

//----------------------------------------------------------------------
// Lifecycle
//----------------------------------------------------------------------

// Bring the part into a world.  Called by GameWorld.addPart.
Part.build = function(world)
	self.world = world
	self.ties = null
	self.terms = null
	self.makeBodies
	self.makeSprites
	self.syncSprites
end function

// Take the part back out of the world.
Part.destroy = function
	for b in self.bodies
		self.world.phys.removeBody b
	end for
	self.bodies = []
	self.ties = null
	self.terms = null
	if self.spriteDisp != null then
		for sp in self.sprites
			util.removeRef self.spriteDisp.sprites, sp
		end for
	end if
	self.sprites = []
	self.spriteDisp = null
end function

// Move the authored pose, taking the bodies along.  Design mode only -- this
// writes to spec.
Part.setPose = function(x, y, angle=null)
	self.spec.x = x
	self.spec.y = y
	if angle != null then self.spec.angle = angle
	self.placeBodies
	self.syncSprites
	// Anything riding on us reads its position off our bodies, and nothing
	// else is going to redraw it: in design mode there is no per-frame sync.
	if self.world != null then self.world.syncDependents self
end function

// Play is starting: give each body its real type.  Subclasses that need to
// arm runtime state do it here.
Part.onPlay = function
	for b in self.bodies
		b.setType self.bodyType
	end for
end function

// Back to design mode: everything dynamic again (see addBody), bodies back
// where spec says.  Subclasses with runtime state clear it here.
Part.onStop = function
	self.settleTime = 0
	self.tethered = false
	self.powered = false
	self.liveTerms = []
	self.resetBounce
	for b in self.bodies
		b.setType physics.DYNAMIC
	end for
	self.placeBodies
	self.syncSprites
end function

// Fade a part's bounce out as it slows down.  A real ball is less elastic the
// slower it hits -- the energy a bounce loses to squashing does not scale
// with the energy it has -- while one constant restitution bounces the same
// fraction forever, which is what leaves a lively ball pattering away in
// ever-smaller, ever-faster hops it never quite finishes.  Fading it means
// the last few bounces get shorter fast, and at the bottom restitution
// reaches zero, so the velocity the solver's overlap bias hands a resting
// part has nothing left to bounce off.
//
// The solver reads restitution off the shape, so this rewrites it every step
// from the part's current speed; spec.restitution stays the authored value.
// Parts that leave bounceSoftSpeed at 0 keep a constant restitution.
Part.softenBounce = function
	s = self.spec
	if s.bounceSoftSpeed <= 0 then return
	for b in self.bodies
		f = sqrt(b.vx * b.vx + b.vy * b.vy) / s.bounceSoftSpeed
		if f > 1 then f = 1
		for sh in b.shapes
			sh.setRestitution s.restitution * f
		end for
	end for
end function

// Put the authored restitution back, for when play ends.
Part.resetBounce = function
	s = self.spec
	if s.bounceSoftSpeed <= 0 then return
	for b in self.bodies
		for sh in b.shapes
			sh.setRestitution s.restitution
		end for
	end for
end function

// Crush the residual jitter of a part that has come to rest.  See the
// settle* constants in config for why this damps rather than freezes.
//
// This is deliberately per-part rather than per-body: a part is one object,
// and settling half of a multi-body part would tear it.
Part.settle = function(dt)
	if self.bodyType != physics.DYNAMIC then return
	// A part on a taut rope is held, not resting: settling a pendulum would
	// stop it dead at the bottom of its swing.
	if self.tethered then
		self.settleTime = 0
		return
	end if
	for b in self.bodies
		if b.vx * b.vx + b.vy * b.vy > config.settleSpeed ^ 2 or
		   abs(b.angularVelocity) > config.settleSpin then
			self.settleTime = 0
			return
		end if
	end for
	self.settleTime = self.settleTime + dt
	if self.settleTime < config.settleDelay then return
	k = config.settleDamp
	for b in self.bodies
		b.setVelocity b.vx * k, b.vy * k
		b.setAngularVelocity b.angularVelocity * k
	end for
end function

// Get ready for the step about to run.  Anything the solver has to be told
// before it solves belongs here, because by `update` it is too late.
Part.preStep = function(dt)
	// Cleared now, set again by any rope that turns out to be pulling on us
	// in this step's constraint pass, and read by settle after that.
	self.tethered = false
	self.softenBounce
end function

// Per-step simulation that physics does not do for us, once the step has
// run.  Play mode only.
Part.update = function(dt)
end function

//----------------------------------------------------------------------
// Serialization
//----------------------------------------------------------------------

Part.save = function
	return {"type": self.typeName, "spec": {} + self.spec}
end function
