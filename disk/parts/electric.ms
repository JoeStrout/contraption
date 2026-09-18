//----------------------------------------------------------------------
// Outlet: the wall socket everything else plugs into, and for now the only
// source of power on the board.
//
// It is always live, it is bolted to the wall, and it has two sockets --
// which are its two terminals.  That is worth more than the symmetry: a net
// may branch, and rather than explain that anywhere in the interface, the
// part that branches it simply looks like the thing everyone already knows
// takes two plugs.  The two sockets are joined inside the outlet (see
// `conducts`), so either one powers whatever is on the other.
//
// See circuit.ms for what "live" amounts to, and notes/electrical-parts.md
// for why it amounts to so little.
//----------------------------------------------------------------------

globals.Outlet = new Part
Outlet.typeName = "outlet"
Outlet.displayName = "Outlet"
Outlet.bodyType = physics.STATIC
Outlet.liveSource = true
Outlet.defaultSpec = Part.defaultSpec + {"width": 40, "height": 60,
  "color": "#E8E0D4", "restitution": 0.2, "friction": 0.6}

// The sockets, and so the terminals: one above the other, as on a real
// duplex outlet.
socketOffset = 14
socketRadius = 9

Outlet.size = function
	return [self.spec.width, self.spec.height]
end function

Outlet.terminalLocals = function
	return [[0, socketOffset], [0, -socketOffset]]
end function

// Both sockets are the same net, which is what makes an outlet a place to
// branch rather than two separate supplies.
Outlet.conducts = function(i, j)
	return true
end function

Outlet.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Outlet.imageKey = function
	s = self.spec
	return "outlet:" + s.width + "x" + s.height + ":" + s.color
end function

Outlet.makeImage = function
	s = self.spec
	w = s.width; h = s.height
	g = artUtil.canvas(w, h)
	// The cover plate, with the usual bevel.
	artUtil.fillRoundRect g, 0, 0, w, h, 4, s.color
	g.drawRect 1, 1, w - 2, h - 2, "#00000030", 1
	g.fillRect 2, h - 4, w - 4, 2, "#FFFFFF60"
	g.fillRect 2, 2, w - 4, 2, "#00000025"
	// The mounting screw between the two sockets.
	self.drawScrew g, w / 2, h / 2
	for dy in [socketOffset, -socketOffset]
		self.drawSocket g, w / 2, h / 2 + dy
	end for
	return g.getImage
end function

Outlet.drawScrew = function(g, cx, cy)
	artUtil.fillCircle g, cx, cy, 3, "#A09888"
	g.line cx - 2, cy, cx + 2, cy, "#403830", 1
end function

// A plug pushed in here covers the whole socket, holes and all, which is
// what says at a glance that this one is occupied and the other is free.
Outlet.plugRadius = function(i)
	return socketRadius
end function

// One empty socket face: the recess, two blades, and the ground pin under
// them.  What it looks like with something in it is the cord's business --
// see Wire.drawPlug -- because the plug is on the end of the cord and links
// draw above parts.
Outlet.drawSocket = function(g, cx, cy)
	face = artUtil.multiply(self.spec.color, "#F0F0F0")
	// Round, and exactly socketRadius: a plug is drawn as a disc of that same
	// radius, and the two have to agree or the plug sits in a visible collar.
	artUtil.fillCircle g, cx, cy, socketRadius, face
	artUtil.drawCircle g, cx, cy, socketRadius, "#00000025", 1
	slot = "#1A1A20"
	g.fillRect cx - 5, cy - 1, 2, 8, slot
	g.fillRect cx + 3, cy - 1, 2, 8, slot
	artUtil.fillCircle g, cx, cy - 5, 2.5, slot
end function
