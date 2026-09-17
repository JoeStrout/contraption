
//----------------------------------------------------------------------
// Weight: a lump of metal of a stated mass, with a ring on top to tie on to.
//
// Mass is the one thing a weight is for, so it is authored in kilograms and
// the density worked back from it.  The engine's mass is density times area
// in pixels, and config.pxPerMeter says what a pixel is worth.
//----------------------------------------------------------------------

globals.Weight = new Part
Weight.typeName = "weight"
Weight.displayName = "Weight"
Weight.defaultSpec = Part.defaultSpec + {"width": 30, "height": 30, "kg": 1,
  "color": "#6E7A86", "restitution": 0.05, "friction": 0.7,
  "linearDamping": 0.02, "angularDamping": 0.05}

Weight.size = function
	return [self.spec.width, self.spec.height]
end function

Weight.density = function
	s = self.spec
	return s.kg * config.pxPerMeter ^ 2 / (s.width * s.height)
end function

// The ring on top, which is where a rope goes.
Weight.tieLocals = function
	return [[0, self.spec.height / 2]]
end function

Weight.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, self.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Weight.imageKey = function
	s = self.spec
	return "weight:" + s.width + "x" + s.height + ":" + s.kg + ":" + s.color
end function

Weight.makeImage = function
	s = self.spec
	w = s.width; h = s.height
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.color
	// A chamfer, so it reads as a solid block rather than a card.
	g.fillRect 0, h - 3, w, 3, "#FFFFFF30"
	g.fillRect 0, 0, w, 3, "#00000040"
	g.fillRect 0, 0, 3, h, "#FFFFFF18"
	g.drawRect 0, 0, w, h, "#00000080", 2
	// The ring, drawn straddling the top edge where the tie point is.
	g.drawEllipse w / 2 - 5, h - 6, 10, 10, "#3A444E", 3
	g.print s.kg + "kg", (w - 8 * (("" + s.kg).len + 2)) / 2, h / 2 - 8,
	  "#E8EEF4", "small"
	return g.getImage
end function
