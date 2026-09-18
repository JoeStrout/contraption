//----------------------------------------------------------------------
// Platform: static scenery.  Used for the level floor, and placeable as a
// ledge for things to land on.
//----------------------------------------------------------------------

globals.Platform = new Part
Platform.typeName = "platform"
Platform.displayName = "Platform"
Platform.bodyType = physics.STATIC
Platform.breakPower = 1             // breakable -- but the level floor is fixed, and
                                    // a blast spares anything fixed
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
