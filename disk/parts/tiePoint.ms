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
