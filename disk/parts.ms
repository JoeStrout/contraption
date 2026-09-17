// parts.ms
// The concrete part types, and the catalog that the palette is built from.

import "config"
import "part"
import "artUtil"
import "physics"

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
// The registry, for loading a saved design.
//----------------------------------------------------------------------

byName = {}
byName[Ball.typeName] = Ball
byName[Block.typeName] = Block
byName[Platform.typeName] = Platform

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
]

// A fresh part from a catalog entry.
spawn = function(entry)
	return entry.cls.make(entry.spec)
end function
