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

// One pre-rendered sprite sheet, sliced into frames and cached by path.
//
// The ball sheets are laid out left to right, top to bottom, with frame i the
// ball turned i * 360/count degrees counterclockwise -- the same sense as
// Sprite.rotation.  See art-sources/balls/README.md.
sheets = {}
frames = function(path, size, cols=8, count=64)
	if sheets.hasIndex(path) then return sheets[path]
	sheet = file.loadImage(path)
	result = null
	if sheet != null then
		result = []
		rows = ceil(count / cols)
		for i in range(0, count - 1, 1)
			c = i % cols
			r = floor(i / cols)
			// Sheet rows read top-down, but getImage's y is bottom-up.
			img = sheet.getImage(c * size, (rows - 1 - r) * size, size, size)
			// Force the GPU upload now.  Image.texture is lazy, so otherwise
			// each frame's first appearance would call LoadTextureFromImage
			// from inside the render loop -- 64 uploads per sheet, spread
			// over the first seconds of play, at whatever moment the ball
			// happens to reach that angle.
			img.texture
			result.push img
		end for
	end if
	sheets[path] = result
	return result
end function

// Multiply two colors together, which is exactly what a tint does when it is
// drawn.  Used to lay the editor's drag feedback over art that is already
// tinted, so that neither one throws the other away.
multiply = function(a, b)
	ca = color.toList(a); cb = color.toList(b)
	out = []
	for i in [0, 1, 2, 3]
		out.push floor(ca[i] * cb[i] / 255)
	end for
	return color.fromList(out)
end function
