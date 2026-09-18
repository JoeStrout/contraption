// glow.ms
// The pool of light a lamp or a flame lays on the board.
//
// One sprite, one pre-drawn radial gradient, tinted and faded.  There is no
// occlusion of any kind: the pool sits where the light is and the parts
// around it are neither lit nor shadowed.  That is the whole of it, and it
// is deliberate -- what light *reaches* is a different question, and when
// the game grows a lens and things that catch fire it will be answered with
// rays, in its own module, and this will still be the picture that says a
// thing is burning.
//
// A part owns a Glow the way it owns a ParticleSystem: it splices `sprite`
// into its own sprite list, so destroy, moveSpritesTo and the layer
// restacking all account for it, and drives it from `updateEffects`.
//
// FLICKER is two sine waves at rates with no common multiple, so a flame
// wavers without ever repeating, plus a phase picked when the glow is made,
// so that two candles on the same board are not in step.  It rides on the
// scale and the alpha together, because a flame that brightens also reaches
// further, and moving only one of them reads as a fault in the drawing.

import "importUtil"
ensureImport ["config", "artUtil"]

globals.Glow = {}

Glow.sprite = null                  // per-instance
Glow.color = "#FFE8B0"
Glow.alpha = 0.5                    // how strongly the pool reads at its brightest
Glow.scale = 1                      // 1 is the picture's own size
Glow.flicker = 0                    // 0 is a steady lamp; see wobble
Glow.phase = 0
Glow.lit = false
Glow.wash = "#FFFFFF"               // what the editor is laying over the part

Glow.make = function(image, glowColor, alpha, scale, flicker=0)
	g = new self
	g.sprite = new Sprite
	g.sprite.image = image
	g.color = glowColor
	g.alpha = alpha
	g.scale = scale
	g.flicker = flicker
	g.lit = false
	// Anywhere in the cycle will do; what matters is that it is not zero for
	// every candle in the level.
	g.phase = rnd * 100
	g.wash = "#FFFFFF"
	g.apply 0
	return g
end function

Glow.moveTo = function(x, y)
	self.sprite.x = x
	self.sprite.y = y
end function

Glow.setLit = function(v, t=0)
	if v == self.lit then return
	self.lit = v
	self.apply t
end function

Glow.setWash = function(wash, t=0)
	self.wash = wash
	self.apply t
end function

// One frame.  A steady glow has nothing to do here: its tint was worked out
// when it was lit and does not change again.
Glow.update = function(t)
	if self.flicker <= 0 or not self.lit then return
	self.apply t
end function

Glow.wobble = function(t)
	if self.flicker <= 0 then return 1
	u = t + self.phase
	return 1 + self.flicker * (0.6 * sin(u * 11.3) + 0.4 * sin(u * 17.7))
end function

Glow.apply = function(t)
	if not self.lit then
		self.sprite.tint = "#00000000"
		return
	end if
	w = self.wobble(t)
	self.sprite.scale = self.scale * w
	a = round(255 * self.alpha * w)
	if a > 255 then a = 255
	if a < 0 then a = 0
	c = color.toList(self.color)
	c[3] = a
	self.sprite.tint = artUtil.multiply(color.fromList(c), self.wash)
end function
