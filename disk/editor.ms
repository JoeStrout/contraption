// editor.ms
// Design-mode interaction: dragging parts out of the palette, moving the ones
// already placed, selecting, and deleting.
//
// The editor is a small state machine.  Its one interesting job is that while
// a part is being dragged it lives in the world like any other -- so the
// overlap query sees it -- but its sprite is moved to a display above the
// panel, so it does not slide underneath while crossing back over.

import "config"
import "parts"
import "gameWorld"
import "panel"
import "util"

globals.Editor = {}

Editor.IDLE = 0
Editor.DRAGGING = 1

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
		if action == null and mode == GameWorld.DESIGN and
		   self.state == Editor.IDLE then
			self.onMouseDown mx, my
		end if
	end if

	if self.state == Editor.DRAGGING then
		self.dragTo mx, my
		if not down then self.onMouseUp
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
	if p != null then self.beginMove p, mx, my
end function

Editor.onMouseUp = function
	p = self.dragPart
	// Return the sprites first, so that a part we are about to throw away is
	// destroyed with its sprites back under its own display.
	self.returnSprites p
	if self.dropOK then
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
	self.dropOK = true      // sprites are untinted again; keep the flag in step
	self.overlayDirty = true
end function

Editor.handleKeys = function(mode)
	while key.available
		k = key.get
		if mode != GameWorld.DESIGN then continue
		// Not mid-drag: the drag still holds a reference to the part, and
		// would put a destroyed one back down on release.
		if self.state != Editor.IDLE then continue
		if k == char(8) or k == char(127) then
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
	p = parts.spawn(parts.catalog[entryIndex])
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
		self.tintSprites p
	end if
end function

Editor.tintSprites = function(p)
	if self.dropOK then
		tint = "#FFFFFF"
	else
		tint = "#FF8080"
	end if
	for sp in p.sprites
		sp.tint = tint
	end for
end function

// Float a part's sprites above the panel while it is being dragged, so they
// do not slide underneath as it crosses the palette edge.
Editor.liftSprites = function(p)
	p.moveSpritesTo self.dragDisp
end function

// Put them back among the placed parts, untinted.
Editor.returnSprites = function(p)
	for sp in p.sprites
		sp.tint = "#FFFFFF"
	end for
	p.moveSpritesTo self.world.partDisp
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
