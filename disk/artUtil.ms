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
//
// Frames are square unless `height` says otherwise, which is what a sheet of
// poses rather than rotations tends to need (the scissors are 48 by 32).
sheets = {}
frames = function(path, size, cols=8, count=64, height=0)
	if sheets.hasIndex(path) then return sheets[path]
	if height <= 0 then height = size
	sheet = file.loadImage(path)
	result = null
	if sheet != null then
		result = []
		rows = ceil(count / cols)
		for i in range(0, count - 1, 1)
			c = i % cols
			r = floor(i / cols)
			// Sheet rows read top-down, but getImage's y is bottom-up.
			img = sheet.getImage(c * size, (rows - 1 - r) * height, size, height)
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

// Mix a color toward white: the counterpart to multiply, and the way to get
// a highlight onto a *shared* display.  Every PixelDisplay call but text and
// drawImage draws in replace mode, so a translucent color there does not
// blend -- it overwrites, and whatever is on the layer below shows through
// the hole.  Inside a part's own cached image that is harmless, since the
// image is composited with drawImage afterwards; drawn straight onto the
// links or overlay layer it is a bug, so highlights there are worked out
// opaque in advance.
lighten = function(c, f)
	ca = color.toList(c)
	out = []
	for i in [0, 1, 2]
		out.push floor(ca[i] + (255 - ca[i]) * f)
	end for
	out.push ca[3]
	return color.fromList(out)
end function

// A circle as a polygon, for fill and outline both.
//
// PixelDisplay.fillEllipse hands the job straight to raylib's DrawEllipse,
// which is a fan of 36 triangles with its seam at angle 0 -- and one triangle
// of it goes missing, so every circle of any size is drawn with a ten-degree
// bite out of its right-hand side.  fillPoly next door is our own
// triangulation, and it is careful about the culling and batching that
// DrawEllipse is not, so anything big enough for the bite to show goes
// through here instead.
//
// Segments are chosen to keep the flats under a tenth of a pixel, and capped,
// since fillPoly's ear clipping is quadratic in the point count.
circlePoints = function(cx, cy, r, segments=0)
	if segments <= 0 then
		segments = ceil(r * 1.2)
		if segments < 12 then segments = 12
		if segments > 48 then segments = 48
	end if
	pts = []
	for i in range(0, segments - 1, 1)
		a = 2 * pi * i / segments
		pts.push [cx + r * cos(a), cy + r * sin(a)]
	end for
	return pts
end function

fillCircle = function(disp, cx, cy, r, fillColor, segments=0)
	disp.fillPoly circlePoints(cx, cy, r, segments), fillColor
end function

drawCircle = function(disp, cx, cy, r, penColor, penSize=1, segments=0)
	disp.drawPoly circlePoints(cx, cy, r, segments), penColor, penSize
end function
