// artUtil.ms
// Procedurally drawn art for parts, and the cache that keeps us from drawing
// the same thing twice.
//
// Parts do not load images from disk; they draw themselves into an offscreen
// PixelDisplay and keep the resulting Image.  Two balls of the same radius
// and color therefore share one Image, and a hundred of them cost one draw.

import "importUtil"
ensureImport "mathUtil"

cache = {}

// An offscreen display of the given size, cleared to transparent, ready to
// draw into.  Call `getImage` on it when you are done.
canvas = function(width, height)
	g = new PixelDisplay
	g.clear color.clear, ceil(width), ceil(height)
	return g
end function

// Draw an image scaled to fit inside a box, centered, without distorting it.
// Used for palette icons, where parts vary a lot in size but the rows do not.
drawFitted = function(disp, img, left, bottom, width, height)
	scale = 1
	if img.width > width or img.height > height then
		scale = mathUtil.min(width / img.width, height / img.height)
	end if
	w = img.width * scale
	h = img.height * scale
	disp.drawImage img, left + (width - w) / 2, bottom + (height - h) / 2, w, h
end function

// A rounded-corner filled rectangle, since PixelDisplay has no such call.
// Used for buttons and panel wells.
fillRoundRect = function(disp, left, bottom, width, height, radius, fillColor)
	r = mathUtil.min(radius, mathUtil.min(width, height) / 2)
	d = r * 2
	disp.fillRect left + r, bottom, width - d, height, fillColor
	disp.fillRect left, bottom + r, r, height - d, fillColor
	disp.fillRect left + width - r, bottom + r, r, height - d, fillColor
	if r <= 0 then return
	disp.fillEllipse left, bottom, d, d, fillColor
	disp.fillEllipse left + width - d, bottom, d, d, fillColor
	disp.fillEllipse left, bottom + height - d, d, d, fillColor
	disp.fillEllipse left + width - d, bottom + height - d, d, d, fillColor
end function
