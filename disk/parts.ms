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
Ball.defaultSpec = Part.defaultSpec + {"radius": 20, "color": "#E08828",
  "restitution": 0.55, "density": 1, "friction": 0.4}

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

Ball.imageKey = function
	return "ball:" + self.spec.radius + ":" + self.spec.color
end function

Ball.makeImage = function
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
	{"cls": Ball, "spec": {"radius": 20}, "label": "Ball"},
	{"cls": Ball, "spec": {"radius": 30, "color": "#C04830"}, "label": "Big Ball"},
	{"cls": Ball, "spec": {"radius": 10, "color": "#E0D040"}, "label": "Marble"},
	{"cls": Block, "spec": {"width": 40, "height": 40}, "label": "Block"},
	{"cls": Block, "spec": {"width": 80, "height": 20}, "label": "Plank"},
	{"cls": Block, "spec": {"width": 20, "height": 80}, "label": "Post"},
	{"cls": Platform, "spec": {"width": 120, "height": 20}, "label": "Platform"},
	{"cls": Platform, "spec": {"width": 60, "height": 20}, "label": "Ledge"},
]

// A fresh part from a catalog entry.
spawn = function(entry)
	return entry.cls.make(entry.spec)
end function
