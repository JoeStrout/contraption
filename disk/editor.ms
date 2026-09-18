// editor.ms
// Design-mode interaction: dragging parts out of the palette, moving the ones
// already placed, selecting, and deleting.
//
// The editor is a small state machine.  Its one interesting job is that while
// a part is being dragged it lives in the world like any other -- so the
// overlap query sees it -- but its sprite is moved to a display above the
// panel, so it does not slide underneath while crossing back over.

import "importUtil"
ensureImport ["config", "parts", "gameWorld", "panel", "rope", "wire", "util"]

globals.Editor = {}

Editor.IDLE = 0
Editor.DRAGGING = 1
Editor.LINKING = 2      // running a rope, belt or wire: picking its ends

Editor.make = function(world, thePanel, dragDisp, overlayDisp)
	e = new Editor
	e.world = world
	e.panel = thePanel
	e.dragDisp = dragDisp          // sprite display above the panel
	e.overlayDisp = overlayDisp    // pixel display for selection boxes
	e.state = Editor.IDLE
	e.selected = null
	e.dragPart = null
	e.dragIsNew = false            // came from the palette: delete if rejected
	e.grabX = 0                    // mouse-to-part offset at grab time
	e.grabY = 0
	e.dragFromX = 0                // pose to fall back to if the drop is bad
	e.dragFromY = 0
	e.dropOK = true
	e.wasDown = false
	e.overlayDirty = true
	e.linkKind = "rope"            // ...or "belt" or "wire"; see beginNewPart
	e.linkPts = []                 // [part, tieIndex] chosen so far
	e.hotTie = null                // the tie point (or wheel) under the mouse
	e.linkDragging = false         // still holding the end we pulled out
	return e
end function

//----------------------------------------------------------------------
// Input
//----------------------------------------------------------------------

// Run one frame of interaction.  Returns the transport action the user asked
// for ("play", "pause", "stop"), or null.  The transport works in every mode;
// everything else is design mode only.
Editor.update = function(mode)
	mx = mouse.x
	my = mouse.y
	down = mouse.button
	action = null

	if down and not self.wasDown then
		action = self.panel.buttonAt(mx, my)
		if action == null and mode == GameWorld.DESIGN then
			if self.state == Editor.LINKING and not self.panel.contains(mx, my) then
				self.onLinkClick mx, my
			else if self.state != Editor.DRAGGING then
				// Back to the palette mid-run means the run is off, and the
				// click means whatever it would have meant anyway.
				if self.state == Editor.LINKING then self.cancelLink
				self.onMouseDown mx, my
			end if
		end if
	end if

	if self.state == Editor.LINKING then
		if mode != GameWorld.DESIGN then
			self.cancelLink
		else
			// The rubber band follows the mouse, so the overlay is never
			// clean while a link is being run.
			self.hotTie = self.linkTarget(mx, my)
			self.overlayDirty = true
			// The end pulled out of the palette is still in hand until the
			// button comes up, exactly as a dragged part is.
			if self.linkDragging and not down then self.onLinkDrop
		end if
	end if

	if self.state == Editor.DRAGGING then
		// A part that mounts on a tie point needs to show which ones there
		// are, or it just looks like it cannot be put down anywhere.
		if self.dragPart.mountsOnTie then
			self.hotTie = self.world.tieAt(mx, my, config.mountSnap, self.dragPart)
			self.overlayDirty = true
		end if
		self.dragTo mx, my
		if not down then self.onMouseUp mx, my
	end if
	self.wasDown = down

	wheel = key.axis("Mouse ScrollWheel")
	if wheel and self.panel.contains(mx, my) then self.panel.scrollBy -wheel * 48

	self.handleKeys mode
	return action
end function

Editor.onMouseDown = function(mx, my)
	// Buttons and the palette belong to the panel; it is checked first, so a
	// click in the strip never falls through to the field.
	if self.panel.contains(mx, my) then
		entry = self.panel.entryAt(mx, my)
		if entry != null then self.beginNewPart entry, mx, my
		return
	end if

	p = self.world.partAt(mx, my)
	// Scenery -- the floor, the walls -- is not selectable, and clicking it
	// means the same as clicking empty space.
	if p != null and p.fixed then p = null
	self.select p
	if p != null and p.draggable then self.beginMove p, mx, my
end function

Editor.onMouseUp = function(mx, my)
	p = self.dragPart
	// Return the sprites first, so that a part we are about to throw away is
	// destroyed with its sprites back under its own display.
	self.returnSprites p
	if self.panel.contains(mx, my) then
		// Put back where it came from: dragging a part onto the palette is
		// how you throw it away, and it takes whatever depended on it along.
		self.world.removePart p
		self.select null
	else if self.dropOK then
		self.select p
	else if self.dragIsNew then
		self.world.removePart p
		self.select null
	else
		// Put it back where it was picked up.
		p.setPose self.dragFromX, self.dragFromY
		self.select p
	end if
	self.state = Editor.IDLE
	self.dragPart = null
	self.hotTie = null
	self.dropOK = true      // sprites are untinted again; keep the flag in step
	self.overlayDirty = true
end function

Editor.handleKeys = function(mode)
	while key.available
		k = key.get
		if mode != GameWorld.DESIGN then continue
		// Not mid-drag: the drag still holds a reference to the part, and
		// would put a destroyed one back down on release.
		if self.state == Editor.DRAGGING then continue
		if self.state == Editor.LINKING then
			if k == char(27) then
				self.cancelLink
				continue
			end if
			// Return cuts the rope off where the mouse is, instead of
			// fastening it to anything.  Neither a belt nor a wire has a
			// loose end worth authoring.
			if k == char(3) or k == char(10) then
				if self.linkKind == "rope" then
					self.finishLooseRope mouse.x, mouse.y
				else
					self.cancelLink
				end if
				continue
			end if
		end if
		if k == char(8) or k == char(127) then
			if self.state == Editor.LINKING then
				self.cancelLink
				continue
			end if
			if self.selected != null and not self.selected.fixed then
				self.world.removePart self.selected
				self.select null
			end if
		end if
	end while
end function

//----------------------------------------------------------------------
// Dragging
//----------------------------------------------------------------------

// Pull a brand new part out of the palette.  It joins the world right away,
// so that the overlap query can see it while it is still under the mouse.
Editor.beginNewPart = function(entryIndex, mx, my)
	entry = parts.catalog[entryIndex]
	// A rope is not dragged into place: it is run from tie point to tie
	// point, so picking it up starts that instead.  A belt is run the same
	// way from wheel to wheel, and a wire from terminal to terminal.
	if entry.cls.isRope or entry.cls.isBelt then
		self.select null
		self.state = Editor.LINKING
		self.linkKind = "rope"
		if entry.cls.isBelt then self.linkKind = "belt"
		// Checked after isRope, because a wire is a Rope: see parts/wire.ms.
		if entry.cls.isWire then self.linkKind = "wire"
		self.linkPts = []
		self.linkDragging = true
		self.overlayDirty = true
		return
	end if
	p = parts.spawn(entry)
	snapped = self.world.snap(p, mx, my)
	p.spec.x = snapped[0]
	p.spec.y = snapped[1]
	self.world.addPart p
	self.dragIsNew = true
	self.grabX = 0
	self.grabY = 0
	self.dragFromX = mx
	self.dragFromY = my
	self.startDrag p, mx, my
end function

Editor.beginMove = function(p, mx, my)
	self.dragIsNew = false
	self.grabX = p.spec.x - mx
	self.grabY = p.spec.y - my
	self.dragFromX = p.spec.x
	self.dragFromY = p.spec.y
	self.startDrag p, mx, my
end function

Editor.startDrag = function(p, mx, my)
	self.dragPart = p
	self.state = Editor.DRAGGING
	self.selected = p
	self.liftSprites p
	self.dragTo mx, my
end function

// Move the part to follow the mouse, snapped, and work out whether it could
// legally be dropped there.
Editor.dragTo = function(mx, my)
	p = self.dragPart
	snapped = self.world.snap(p, mx + self.grabX, my + self.grabY)
	if snapped[0] != p.spec.x or snapped[1] != p.spec.y then
		p.setPose snapped[0], snapped[1]
		self.overlayDirty = true
	end if
	ok = self.world.placementOK(p)
	if ok != self.dropOK then
		self.dropOK = ok
		self.overlayDirty = true
		p.tintSprites self.dropWash
	end if
end function

// The wash a dragged part wears: red while it is somewhere it cannot be
// dropped.  The part lays it on itself, since only the part knows what its
// own art is tinted with already.
Editor.dropWash = function
	if self.dropOK then return "#FFFFFF"
	return "#FF8080"
end function

// Float a part's sprites above the panel while it is being dragged, so they
// do not slide underneath as it crosses the palette edge.
Editor.liftSprites = function(p)
	p.moveSpritesTo self.dragDisp
end function

// Put them back among the placed parts, untinted.
Editor.returnSprites = function(p)
	p.tintSprites
	p.moveSpritesTo self.world.partDisp
	// It lands at the end of the layer, which would put an ordinary part
	// over a basket; the parts that draw in front go back on top.
	self.world.raiseFrontParts
end function

//----------------------------------------------------------------------
// Running a rope
//
// A rope comes out of the palette the way everything else does -- press and
// drag -- and where it lands is where its first end is made fast.  From
// there it trails from the mouse until a second tie point is clicked.  A
// click on a pulley's wheel is neither end: the rope carries on over it,
// which is all a block and tackle needs to be built.
//----------------------------------------------------------------------

// The end we dragged out of the palette, let go of.  On a tie point it
// fastens there; anywhere else it is dropped, like any other bad placement.
Editor.onLinkDrop = function
	self.linkDragging = false
	if self.hotTie == null then
		self.cancelLink
		return
	end if
	self.linkPts.push [self.hotTie[0], self.hotTie[1]]
	self.overlayDirty = true
end function

// What the link being run could be fastened to at (x, y): a tie point for a
// rope, a wheel for a belt, a terminal for a wire.  All three come back as
// [part, index, x, y].
Editor.linkTarget = function(mx, my)
	if self.linkKind == "belt" then return self.world.hubAt(mx, my)
	if self.linkKind == "wire" then
		return self.world.terminalAt(mx, my, config.termSnap)
	end if
	return self.world.tieAt(mx, my, config.tieSnap)
end function

Editor.onLinkClick = function(mx, my)
	tie = self.linkTarget(mx, my)
	if tie == null then
		self.cancelLink
		return
	end if
	// The same point twice in a row would be a zero-length run -- and, for a
	// belt, a wheel belted to itself.
	if self.linkPts and util.sameRef(self.linkPts[-1][0], tie[0]) and
	   self.linkPts[-1][1] == tie[1] then return
	self.linkPts.push [tie[0], tie[1]]
	self.overlayDirty = true
	if self.linkKind == "wire" then
		// Two terminals, and not two of the same part's: an outlet bridged to
		// itself is the one wire that could never do anything.
		if self.linkPts.len >= 2 and
		   util.sameRef(self.linkPts[0][0], self.linkPts[1][0]) then
			self.linkPts.pop
			return
		end if
		if self.linkPts.len >= 2 then self.finishWire
		return
	end if
	if self.linkKind == "belt" then
		// A belt joins two hubs, not two grooves of one.
		if self.linkPts.len >= 2 and
		   util.sameRef(self.linkPts[0][0], self.linkPts[1][0]) then
			self.linkPts.pop
			return
		end if
		if self.linkPts.len >= 2 then self.finishBelt
		return
	end if
	// A wheel is a place to route through, anything else is an end.
	if tie[0].ropeRoutes(tie[1]) then return
	if self.linkPts.len >= 2 then self.finishRope
end function

Editor.finishRope = function
	pts = []
	for p in self.linkPts
		pts.push {"part": p[0].id, "tie": p[1]}
	end for
	r = Rope.make({"points": pts})
	self.world.addPart r
	// A rope is made exactly as long as the path it was drawn along, so it
	// starts taut.
	r.setLength r.measure
	self.endLink r
end function

// Done running one: back to idle, with the new part selected.
Editor.endLink = function(p)
	self.state = Editor.IDLE
	self.linkPts = []
	self.hotTie = null
	self.linkDragging = false
	self.select p
	self.overlayDirty = true
end function

// A wire joins exactly two terminals, and is made a little longer than the
// run between them so that it hangs: see parts/wire.ms.
Editor.finishWire = function
	pts = []
	for p in self.linkPts
		pts.push {"part": p[0].id, "term": p[1]}
	end for
	w = Wire.make({"points": pts})
	self.world.addPart w
	w.setLength w.measure * w.spec.slack
	self.endLink w
end function

// A belt joins exactly two wheels, so there is nothing to decide once the
// second is picked.
Editor.finishBelt = function
	b = Belt.make({"a": self.linkPts[0][0].id, "ra": self.linkPts[0][1],
	  "b": self.linkPts[1][0].id, "rb": self.linkPts[1][1]})
	self.world.addPart b
	self.endLink b
end function

// End the rope in mid air: tied at the points picked so far, and loose from
// there out to the mouse.  The length that gives it is the length it keeps,
// so it hangs from the moment it is made -- a rope that starts out cut.
Editor.finishLooseRope = function(mx, my)
	if not self.linkPts then return
	pts = []
	for p in self.linkPts
		pts.push {"part": p[0].id, "tie": p[1]}
	end for
	r = Rope.make({"points": pts, "freeEnd": true, "fixedLength": true})
	self.world.addPart r
	last = self.linkPts[-1][0].tieWorld(self.linkPts[-1][1])
	r.setLength r.measure + sqrt((mx - last[0]) ^ 2 + (my - last[1]) ^ 2)
	self.endLink r
end function

Editor.cancelLink = function
	self.state = Editor.IDLE
	self.linkPts = []
	self.hotTie = null
	self.linkDragging = false
	self.overlayDirty = true
end function

// Every tie point in the world, with the one under the mouse picked out.
Editor.drawTiePoints = function(d)
	for t in self.world.tiePoints
		c = config.tieColor
		r = config.tieRadius
		if self.hotTie != null and util.sameRef(self.hotTie[0], t[0]) and
		   self.hotTie[1] == t[1] then
			c = config.tieHotColor
			r = r + 2
		end if
		d.drawEllipse t[2] - r, t[3] - r, r * 2, r * 2, c, 2
	end for
end function

// The tie points, plus the rope so far trailing from the last point clicked.
Editor.drawRopeGuides = function(d)
	self.drawTiePoints d
	to = [mouse.x, mouse.y]
	if self.hotTie != null then to = [self.hotTie[2], self.hotTie[3]]
	prev = null
	for p in self.linkPts
		w = p[0].tieWorld(p[1])
		if prev != null then
			d.line prev[0], prev[1], w[0], w[1], config.tieHotColor, 2
		end if
		prev = w
	end for
	if prev != null then
		d.line prev[0], prev[1], to[0], to[1], config.tieHotColor, 2
		return
	end if
	// Nothing made fast yet: a tail of rope in hand, so that dragging one
	// out of the palette looks like dragging anything else out of it.
	d.line to[0], to[1], to[0] - 16, to[1] - 10, config.ropeColor,
	  config.ropeWidth
end function

// Every terminal in the world, with the one under the mouse picked out, and
// the wire so far trailing from the one already chosen.  Terminals are drawn
// square where tie points are round, so the two can never be confused.
Editor.drawWireGuides = function(d)
	for t in self.world.terminals
		c = config.termColor
		r = config.termRadius
		if self.hotTie != null and util.sameRef(self.hotTie[0], t[0]) and
		   self.hotTie[1] == t[1] then
			c = config.termHotColor
			r = r + 2
		end if
		d.drawRect t[2] - r, t[3] - r, r * 2, r * 2, c, 2
	end for
	to = [mouse.x, mouse.y]
	if self.hotTie != null then to = [self.hotTie[2], self.hotTie[3]]
	if self.linkPts then
		w = self.linkPts[0][0].terminalWorld(self.linkPts[0][1])
		d.line w[0], w[1], to[0], to[1], config.termHotColor, 2
		return
	end if
	// Nothing fastened yet: a tail of wire in hand, as a dragged part would
	// be.
	d.line to[0], to[1], to[0] - 16, to[1] - 10, config.wireColor,
	  config.wireWidth
end function

Editor.ringHot = function(p, i)
	if self.hotTie != null and util.sameRef(self.hotTie[0], p) and
	   self.hotTie[1] == i then return true
	if not self.linkPts then return false
	return util.sameRef(self.linkPts[0][0], p) and self.linkPts[0][1] == i
end function

// Every groove a belt could go on, with the one under the mouse picked out,
// and the belt so far trailing from the one already chosen.
Editor.drawBeltGuides = function(d)
	for p in self.world.parts
		if not p.turns then continue
		rings = p.beltRings
		if not rings then continue
		c = p.hubWorld
		for i in rings.indexes
			col = config.tieColor
			w = 2
			// Lit up: the groove under the mouse, and the one already picked,
			// so that a step pulley shows which of its steps the belt is on.
			if self.ringHot(p, i) then
				col = config.tieHotColor
				w = 3
			end if
			artUtil.drawCircle d, c[0], c[1], rings[i], col, w
		end for
	end for
	to = [mouse.x, mouse.y]
	if self.hotTie != null then to = [self.hotTie[2], self.hotTie[3]]
	if self.linkPts then
		c = self.linkPts[0][0].hubWorld
		d.line c[0], c[1], to[0], to[1], config.tieHotColor, 2
		return
	end if
	// Nothing chosen yet: a loop of belt in hand, as a dragged part would be.
	artUtil.drawCircle d, to[0] - 8, to[1] - 6, 9, config.beltColor,
	  config.beltWidth
end function

//----------------------------------------------------------------------
// Selection
//----------------------------------------------------------------------

Editor.select = function(p)
	if util.sameRef(p, self.selected) then return
	self.selected = p
	self.overlayDirty = true
end function

// The selection box, drawn around the part's design bounds.  There are no
// edit handles yet; this is where they will go.
Editor.drawOverlay = function
	if not self.overlayDirty then return
	self.overlayDirty = false
	d = self.overlayDisp
	d.fillRect 0, 0, d.width, d.height, color.clear
	if self.state == Editor.LINKING then
		if self.linkKind == "belt" then
			self.drawBeltGuides d
		else if self.linkKind == "wire" then
			self.drawWireGuides d
		else
			self.drawRopeGuides d
		end if
		return
	end if
	if self.state == Editor.DRAGGING and self.dragPart.mountsOnTie then
		self.drawTiePoints d
	end if
	p = self.selected
	if p == null then return
	b = p.designBounds
	if self.state == Editor.DRAGGING and not self.dropOK then
		c = config.badColor
	else
		c = config.selectColor
	end if
	d.drawRect b[0] - 2, b[1] - 2, b[2] + 4, b[3] + 4, c, 2
end function

// Design mode is over: drop any selection, so the box does not hang around
// while the simulation runs.
Editor.clearSelection = function
	self.selected = null
	self.overlayDirty = true
end function
