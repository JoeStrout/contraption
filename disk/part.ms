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

import "config"
import "physics"
import "artUtil"
import "util"

globals.Part = {}

Part.typeName = "part"              // registry key; what a save file records
Part.displayName = "Part"
Part.bodyType = physics.DYNAMIC     // body type applied when play begins
Part.fixed = false                  // level scenery: not draggable or deletable
Part.defaultSpec = {"x": 0, "y": 0, "angle": 0,
  "linearDamping": 0, "angularDamping": 0, "bounceSoftSpeed": 0}

Part.spec = null                    // per-instance, see make
Part.bodies = null
Part.sprites = null
Part.spriteDisp = null              // the display our sprites are currently on
Part.world = null                   // the GameWorld we belong to
Part.settleTime = 0                 // runtime: seconds spent barely moving

//----------------------------------------------------------------------
// Construction
//----------------------------------------------------------------------

// Make a part of this type.  `spec` overrides individual defaults; anything
// it leaves out comes from defaultSpec.
Part.make = function(spec=null)
	p = new self
	p.spec = {} + self.defaultSpec
	if spec != null then p.spec = p.spec + spec
	p.bodies = []
	p.sprites = []
	p.settleTime = 0
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
// which is right as long as each shape is centered on its body's origin.
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
