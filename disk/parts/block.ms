//----------------------------------------------------------------------
// Block: a wooden crate that tumbles and stacks.
//----------------------------------------------------------------------

globals.Block = new Part
Block.typeName = "block"
Block.displayName = "Block"
Block.breakPower = 1                // splinters, given enough of a blast
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
