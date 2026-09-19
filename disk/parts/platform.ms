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
  "color": "#7A8894", "restitution": 0.2, "friction": 0.7,
  "stretch": 0, "rise": 0}

// A platform is reshaped in the editor by a handle on its right end, which
// moves that end and leaves the left one where it is.  Dragged across, the
// platform gets longer or shorter; dragged up or down, it is sheared -- a
// ramp whose ends stay vertical and `height` tall, not a rotated box, so
// that both ends still sit square on the pegboard and something rolled off
// the top of it meets the next part at a corner the grid put there.
//
// Both are kept as offsets from the catalogue's shape, `stretch` added to
// `width` and `rise` the right end's height over the left, so the limits on
// them are limits on how far a part may be taken from what it was.

// The length the platform actually has.
Platform.span = function
	return self.spec.width + self.spec.stretch
end function

Platform.size = function
	return [self.span, self.spec.height + abs(self.spec.rise)]
end function

// The four corners, in the part's own frame: left bottom, right bottom,
// right top, left top.  The origin is the middle of the bounding box, which
// for a parallelogram is also its centroid, so the body's origin is its
// center of mass and the sprite needs no offset.
Platform.corners = function
	hw = self.span / 2
	hh = self.spec.height / 2
	r = self.spec.rise / 2
	return [[-hw, -r - hh], [hw, r - hh], [hw, r + hh], [-hw, -r + hh]]
end function

Platform.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addPolygon(self.corners)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

// The handle: the middle of the right end, just outside it, where the
// selection box's edge is.
Platform.handleWorld = function
	return [self.spec.x + self.span / 2 + 2, self.spec.y + self.spec.rise / 2]
end function

// Put the right end as near (x, y) as the grid and the limits allow, holding
// the left end still.  The left end's middle is the one thing that does not
// move, so everything is worked out from it and the center put back after.
Platform.dragHandle = function(x, y)
	s = self.spec
	g = config.grid
	lim = config.platformShapeLimit
	leftX = s.x - self.span / 2
	leftY = s.y - s.rise / 2
	stretch = round((x - leftX) / g) * g - s.width
	stretch = mathUtil.clamp(stretch, mathUtil.max(-lim, g - s.width), lim)
	rise = mathUtil.clamp(round((y - leftY) / g) * g, -lim, lim)
	if stretch == s.stretch and rise == s.rise then return false
	s.stretch = stretch
	s.rise = rise
	s.x = leftX + self.span / 2
	s.y = leftY + rise / 2
	self.reshape
	return true
end function

Platform.imageKey = function
	s = self.spec
	return "platform:" + self.span + "x" + s.height + "/" + s.rise + ":" + s.color
end function

Platform.makeImage = function
	s = self.spec
	sz = self.size
	w = sz[0]; h = sz[1]
	g = artUtil.canvas(w, h)
	// The corners, and the same again moved in along the ends by `d`, all
	// in canvas coordinates.
	c = self.corners
	edge = function(dx, bottomIn, topIn)
		return [[c[0][0] + w/2 + dx, c[0][1] + h/2 + bottomIn],
		  [c[1][0] + w/2 - dx, c[1][1] + h/2 + bottomIn],
		  [c[2][0] + w/2 - dx, c[2][1] + h/2 - topIn],
		  [c[3][0] + w/2 + dx, c[3][1] + h/2 - topIn]]
	end function
	g.fillPoly edge(0, 0, 0), s.color
	top = edge(0, s.height - 3, 0)
	g.fillPoly top, "#FFFFFF40"
	bottom = edge(0, 0, s.height - 3)
	g.fillPoly bottom, "#00000040"
	g.drawPoly edge(0.5, 0.5, 0.5), "#00000060", 1
	return g.getImage
end function
