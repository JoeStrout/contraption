//----------------------------------------------------------------------
// Wire: a rope that never pulls.
//
// Everything a wire looks like, a rope already does.  A slack rope is not
// physics at all -- it is a line of beads, hung under gravity, draped over
// whatever it lies across and never pushing back -- and that is a wire
// exactly.  So a wire is a Rope with its one constraint taken out: it is
// beads and nothing else, from the moment it is made until it is cut.
//
// What it carries instead is one bit, and it carries it in circuit.ms, which
// cares only about the two terminals at its ends.
//
// Two things make it a wire rather than a rope in the editor.  It runs
// between *terminals* rather than tie points, which is the whole of
// `pointKey` and `endWorld` below; and it is made `config.wireSlack` longer
// than the run it spans, so it visibly sags.  The sag is not decoration.  A
// wire pulled straight reads as a rope, and a wire that reads as a rope will
// be expected to haul on what it is fastened to -- which this one can never
// do.  Note that the slack is a factor on `remeasure` rather than a fixed
// length, so dragging either end keeps the droop in proportion and a long
// run across the board hangs lower than a short one.
//----------------------------------------------------------------------

globals.Wire = new Rope
Wire.typeName = "wire"
Wire.displayName = "Power Cord"
Wire.isWire = true
Wire.pointKey = "term"
Wire.defaultSpec = Rope.defaultSpec + {"color": config.wireColor,
  "slack": config.wireSlack}

Wire.endWorld = function(part, i)
	return part.terminalWorld(i)
end function

// The two terminals it joins, as [part, index] each, or null for a wire
// whose ends are not both there -- a cut one, or one in a half-built world.
// This is all circuit.ms wants of it.
Wire.endpoints = function
	pts = self.links
	if pts == null or pts.len < 2 then return null
	return [pts[0], pts[pts.len - 1]]
end function

// Longer than the run it spans, and kept that way as the design is moved
// about.  See the header.
//
// A rope drops its beads here, which costs it nothing because a rope in
// design mode is taut and has none.  A cord always has them, and this runs
// on every frame of a drag -- so dropping them would relay the beads along
// the straight path between the terminals sixty times a second, and the one
// thing a cord must never look is straight.  Instead the beads stay where
// they hang and their rest lengths are stretched to suit, which is also what
// makes the sag grow and shrink smoothly as a part is pulled about.
//
// Their number is fixed once laid, though, so far enough from the length
// they were spaced for the cord would start to show its corners: past a
// factor of two either way it is cheaper to lay it again.
Wire.remeasure = function
	if self.spec.fixedLength then return
	path = self.path
	if path == null then return
	want = self.pathLength(path) * self.spec.slack
	if self.chain != null and self.linkRest != null and self.curLen > 0 and
	   want > self.chainLen / 2 and want < self.chainLen * 2 then
		f = want / self.curLen
		for i in self.linkRest.indexes
			self.linkRest[i] = self.linkRest[i] * f
		end for
	else
		self.chain = null
	end if
	self.setLength want
end function

// The constraint, deleted.  A wire is slack by construction -- it is made
// longer than its run -- but saying so here rather than relying on that is
// what makes it true of a wire pulled straight by a part that moves, which
// is the one case where the length alone would not save us.
Wire.buildJacobian = function
	self.jac = null
	self.tension = 0
	return false
end function

// No wheel to wrap and no drum to trim back to: a wire ends where its
// terminal is.
Wire.trimEnds = function(path)
	return path
end function

// Cut, it comes apart into wires rather than into ropes, and each piece is
// a dead end that conducts nothing -- which falls out of endpoints, since a
// piece has one terminal at most.
Wire.makePiece = function(w, points, length, tail=null)
	pts = []
	for p in points
		pts.push {} + p
	end for
	r = Wire.make({"points": pts, "freeEnd": true, "fixedLength": true,
	  "color": self.spec.color, "tail": tail})
	w.addPart r
	r.setLength length
	return r
end function

// The cord, and then the plug on each end of it.
//
// The plug is drawn here rather than baked into the socket's picture for two
// reasons.  It belongs to the cord, so it goes wherever the cord is run --
// an outlet's socket, a motor's post -- and takes that terminal's own size
// from `Part.plugRadius`.  And it has to be drawn last: links draw on the
// layer above the parts, which is the only way anything can cover a socket's
// holes, and covering them is the whole point.
Wire.draw = function(disp)
	super.draw disp
	pts = self.links
	if pts == null then return
	for k in [0, pts.len - 1]
		self.drawPlug disp, pts[k][0], pts[k][1]
	end for
end function

Wire.drawPlug = function(disp, part, i)
	w = part.terminalWorld(i)
	if w == null then return
	r = part.plugRadius(i)
	// Half a pixel proud of the face it covers.  fillCircle is a polygon
	// inscribed in the circle it stands for, so two discs of equal radius
	// leave a thin crescent of the lower one showing at every flat.
	artUtil.fillCircle disp, w[0], w[1], r + 0.5, self.drawColor
end function

Wire.drawColor = function
	if self.powered then return config.wireLiveColor
	return self.spec.color
end function

Wire.drawWidth = function
	return config.wireWidth
end function

Wire.imageKey = function
	return "wire:" + self.spec.color
end function

// The palette icon: a length of wire, hanging the way a placed one will.
Wire.makeImage = function
	w = config.grid * 2
	h = config.grid * 2
	g = artUtil.canvas(w, h)
	prev = null
	for i in range(0, 16, 1)
		f = i / 16
		x = 2 + f * (w - 4)
		y = h - 4 - sin(f * pi) * (h / 2 - 3)
		if prev != null then
			g.line prev[0], prev[1], x, y, self.spec.color, config.wireWidth
		end if
		prev = [x, y]
	end for
	// A terminal at each end, so it is not mistaken for the rope two rows up.
	for e in [[2, h - 4], [w - 2, h - 4]]
		g.fillRect e[0] - 3, e[1] - 3, 6, 6, config.termPostColor
	end for
	return g.getImage
end function
