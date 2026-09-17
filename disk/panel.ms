// panel.ms
// The panel down the right-hand side: the scrolling parts palette in design
// mode, and the play/pause/stop transport across the bottom in both modes.

import "importUtil"
ensureImport ["config", "artUtil", "parts", "gameWorld"]

globals.Panel = {}

// Vertical extent of the scrolling palette area.
Panel.top = function
	return config.fieldHeight - config.paletteTitleHeight
end function

Panel.bottom = function
	return config.buttonBarHeight
end function

Panel.make = function(disp)
	p = new Panel
	p.disp = disp
	p.scroll = 0            // pixels the palette content has scrolled up
	p.hotEntry = null       // catalog index under the mouse
	p.hotButton = null      // "play" / "pause" / "stop" under the mouse
	p.dirty = true
	p.drawnMode = null
	// One icon Image per catalog entry, built once.  Part.image caches by
	// appearance, so entries that look alike share the same Image.
	p.icons = []
	for entry in parts.catalog
		p.icons.push parts.spawn(entry).image
	end for
	return p
end function

Panel.contains = function(x, y)
	return x >= config.panelLeft
end function

//----------------------------------------------------------------------
// Palette geometry
//----------------------------------------------------------------------

Panel.contentHeight = function
	return parts.catalog.len * config.paletteRowHeight
end function

Panel.maxScroll = function
	over = self.contentHeight - (self.top - self.bottom)
	if over < 0 then return 0
	return over
end function

// The y of the bottom edge of row i, in screen coordinates.
Panel.rowBottom = function(i)
	return self.top + self.scroll - (i + 1) * config.paletteRowHeight
end function

Panel.scrollBy = function(dy)
	was = self.scroll
	self.scroll = self.scroll + dy
	if self.scroll < 0 then self.scroll = 0
	if self.scroll > self.maxScroll then self.scroll = self.maxScroll
	if self.scroll != was then self.dirty = true
end function

// Which catalog entry is at (x, y), or null.
Panel.entryAt = function(x, y)
	if x < config.panelLeft then return null
	if y < self.bottom or y >= self.top then return null
	for i in parts.catalog.indexes
		b = self.rowBottom(i)
		if y >= b and y < b + config.paletteRowHeight then return i
	end for
	return null
end function

//----------------------------------------------------------------------
// Button geometry
//----------------------------------------------------------------------

Panel.buttonNames = ["play", "pause", "stop"]

// [left, bottom, size] of button i.
Panel.buttonRect = function(i)
	sz = config.buttonSize
	gap = 12
	total = 3 * sz + 2 * gap
	left = config.panelLeft + (config.panelWidth - total) / 2 + i * (sz + gap)
	return [left, (config.buttonBarHeight - sz) / 2, sz]
end function

Panel.buttonAt = function(x, y)
	for i in Panel.buttonNames.indexes
		r = self.buttonRect(i)
		if x >= r[0] and x < r[0] + r[2] and y >= r[1] and y < r[1] + r[2] then
			return Panel.buttonNames[i]
		end if
	end for
	return null
end function

//----------------------------------------------------------------------
// Mouse tracking (hover highlights)
//----------------------------------------------------------------------

Panel.trackMouse = function(x, y, mode)
	entry = null
	if mode == GameWorld.DESIGN then entry = self.entryAt(x, y)
	button = self.buttonAt(x, y)
	if entry != self.hotEntry or button != self.hotButton then
		self.hotEntry = entry
		self.hotButton = button
		self.dirty = true
	end if
end function

//----------------------------------------------------------------------
// Drawing
//----------------------------------------------------------------------

Panel.draw = function(mode)
	if not self.dirty and mode == self.drawnMode then return
	self.dirty = false
	self.drawnMode = mode
	d = self.disp
	L = config.panelLeft
	W = config.panelWidth

	d.fillRect L, 0, W, config.fieldHeight, config.panelColor
	d.line L, 0, L, config.fieldHeight, config.panelEdgeColor, 2

	// Title.
	if mode == GameWorld.DESIGN then
		title = "PARTS"
	else
		title = "GOALS"
	end if
	d.print title, L + 16, config.fieldHeight - 24, config.titleColor, "medium"

	if mode == GameWorld.DESIGN then
		self.drawPalette
	else
		d.print "(none yet)", L + 16, self.top - 30, config.labelColor, "small"
	end if

	self.drawButtons mode
end function

Panel.drawPalette = function
	d = self.disp
	L = config.panelLeft
	W = config.panelWidth
	rowH = config.paletteRowHeight

	d.setClip L, self.bottom, W, self.top - self.bottom
	for i in parts.catalog.indexes
		entry = parts.catalog[i]
		b = self.rowBottom(i)
		// Rows outside the visible band cost us nothing but a compare.
		if b + rowH < self.bottom or b > self.top then continue
		if i == self.hotEntry then
			artUtil.fillRoundRect d, L + 6, b + 3, W - 12, rowH - 6, 6,
			  config.buttonColor
		end if
		artUtil.drawFitted d, self.icons[i], L + 14, b + 4, 48, rowH - 8
		d.print entry.label, L + 72, b + rowH / 2 - 6, config.labelColor, "small"
	end for
	d.clearClip

	// A scrollbar, but only when there is something to scroll.
	maxS = self.maxScroll
	if maxS > 0 then
		trackH = self.top - self.bottom
		thumbH = trackH * trackH / self.contentHeight
		frac = self.scroll / maxS
		thumbY = self.top - thumbH - frac * (trackH - thumbH)
		d.fillRect L + W - 7, self.bottom, 3, trackH, config.buttonOffColor
		d.fillRect L + W - 7, thumbY, 3, thumbH, config.panelEdgeColor
	end if
end function

Panel.drawButtons = function(mode)
	d = self.disp
	d.fillRect config.panelLeft, 0, config.panelWidth, config.buttonBarHeight,
	  config.buttonOffColor
	d.line config.panelLeft, config.buttonBarHeight, config.fieldWidth +
	  config.panelWidth, config.buttonBarHeight, config.panelEdgeColor, 1

	// A button is lit when its mode is the current one, and highlighted when
	// the mouse is over it.
	for i in Panel.buttonNames.indexes
		name = Panel.buttonNames[i]
		r = self.buttonRect(i)
		bg = config.buttonColor
		if (name == "play" and mode == GameWorld.PLAY) or
		   (name == "pause" and mode == GameWorld.PAUSED) or
		   (name == "stop" and mode == GameWorld.DESIGN) then
			bg = config.buttonHiColor
		else if name == self.hotButton then
			bg = config.panelEdgeColor
		end if
		artUtil.fillRoundRect d, r[0], r[1], r[2], r[2], 8, bg
		self.drawButtonIcon name, r
	end for
end function

Panel.drawButtonIcon = function(name, r)
	d = self.disp
	cx = r[0] + r[2] / 2
	cy = r[1] + r[2] / 2
	s = r[2] * 0.3
	c = config.buttonIconColor
	if name == "play" then
		d.fillPoly [[cx - s * 0.7, cy - s], [cx - s * 0.7, cy + s],
		  [cx + s, cy]], c
	else if name == "pause" then
		d.fillRect cx - s * 0.8, cy - s, s * 0.6, s * 2, c
		d.fillRect cx + s * 0.2, cy - s, s * 0.6, s * 2, c
	else
		d.fillRect cx - s * 0.85, cy - s * 0.85, s * 1.7, s * 1.7, c
	end if
end function
