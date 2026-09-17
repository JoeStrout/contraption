//----------------------------------------------------------------------
// Balloon: an object that provides lift (in air), and can be popped.
//
// The art is two images: a flat gray balloon, which we tint to whatever
// color the spec asks for, and a highlight to lay over it.  The tint goes
// on the sprite rather than into a drawn image, so every balloon shares the
// two Images however many colors are in play.
//
// The highlight is where the light is, not where the balloon is facing, so
// it gets a sprite of its own that never turns: a balloon swinging on its
// string keeps its shine in the same corner, the way a real one does.
//----------------------------------------------------------------------

baseImg = file.loadImage("/usr/pics/balloon.png")
shineImg = file.loadImage("/usr/pics/balloon_shine.png")

// The balloon's extent within the square art, in source pixels, measured out
// from the middle of the image so that the drawing is centered on the part's
// own center.  spec.width and spec.height say what that extent becomes on
// screen, and everything else here is a fraction of those.
//
// The default spec is these very numbers, so that a balloon draws its art
// pixel for pixel: artScale comes out at 1, and nothing is resampled.  A
// balloon authored at some other size still works, and will be scaled.
artWidth = 44
artHeight = 60

// The right-hand side of the balloon's outline, traced from the art, as
// fractions of width and height from the center: the bulb, then the taper
// down to the knot.  makeBodies mirrors it and hands the lot to addPolygon,
// which takes the convex hull -- which a teardrop already is.
outline = [[0.102, 0.458], [0.250, 0.417], [0.352, 0.350], [0.420, 0.267],
  [0.477, 0.125], [0.443, 0.017], [0.386, -0.067], [0.307, -0.150],
  [0.239, -0.233], [0.159, -0.317], [0.068, -0.400], [0.034, -0.492]]

globals.Balloon = new Part
Balloon.typeName = "balloon"
Balloon.displayName = "Balloon"
// A balloon is mostly helium, which is lighter than the air it sits in, so
// it falls upwards: see preStep for how that is worked out, and how the
// damping below turns it into a steady climb rather than a launch.
Balloon.defaultSpec = Part.defaultSpec + {"width": artWidth, "height": artHeight,
  "color": "#FF4444", "density": 0.1, "airDensity": 0.6, "liftRise": 0.125,
  "restitution": 0.05, "friction": 0.7,
  "linearDamping": 16, "angularDamping": 8}

Balloon.size = function
	return [self.spec.width, self.spec.height]
end function

// What the art must be scaled by to come out at the part's size.
Balloon.artScale = function
	s = self.spec
	return [s.width / artWidth, s.height / artHeight]
end function

// The tie point on bottom: the knot, which is where a string goes.
Balloon.tieLocals = function
	return [[0, -self.spec.height / 2]]
end function

Balloon.makeBodies = function
	s = self.spec
	b = self.addBody
	pts = []
	for p in outline
		pts.push [p[0] * s.width, p[1] * s.height]
		pts.push [-p[0] * s.width, p[1] * s.height]
	end for
	sh = b.addPolygon(pts, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

//----------------------------------------------------------------------
// Lift
//----------------------------------------------------------------------

// Where the gas that does the lifting has its center, in the part's own
// frame: up in the bulb, a few pixels above the center of mass of the
// balloon as a whole.  That gap is what keeps a balloon upright -- lift
// above weight is a pendulum hung the right way up -- and it is real: the
// helium is all in the bulb, while the skin and the knot hang below it.
Balloon.liftLocal = function
	return [0, self.spec.height * self.spec.liftRise]
end function

// Buoyancy: the air a balloon pushes aside weighs airDensity/density times
// what the balloon itself does, and that weight, pushing up, is the lift.
// So the net acceleration is (airDensity/density - 1) * gravity, upward,
// and spec.linearDamping is what it climbs against -- a balloon reaches the
// speed where the two balance (about 300 px/s, three meters per second,
// which is what a released helium balloon really does) in a fraction of a
// second, and holds it.  What it can carry is the difference between the
// two densities over its area: about 78 grams as authored above.
Balloon.preStep = function(dt)
	super.preStep dt
	s = self.spec
	for b in self.bodies
		f = s.airDensity / s.density * b.mass * config.gravity
		l = self.liftLocal
		a = b.angle
		c = cos(a); sn = sin(a)
		o = b.position
		b.applyForce 0, f, o[0] + l[0] * c - l[1] * sn,
		  o[1] + l[0] * sn + l[1] * c
	end for
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

// Two sprites on the one body: the balloon, tinted and turning with it, and
// the highlight, which only ever moves.
Balloon.makeSprites = function
	self.spriteDisp = self.world.partDisp
	sc = self.artScale
	for img in [baseImg, shineImg]
		sp = new Sprite
		sp.image = img
		sp.scale = sc
		self.sprites.push sp
		self.spriteDisp.sprites.push sp
	end for
	// Later sprites draw on top, so the shine is the second one.
	self.tintSprites
end function

// The balloon's own color is a tint, so anything the editor lays over it has
// to be multiplied in rather than assigned; the shine is white light and
// takes the wash alone.
Balloon.tintSprites = function(wash="#FFFFFF")
	if self.sprites.len < 2 then return
	self.sprites[0].tint = artUtil.multiply(self.spec.color, wash)
	self.sprites[1].tint = wash
end function

Balloon.syncSprites = function
	if not self.bodies then return
	b = self.bodies[0]
	for sp in self.sprites
		sp.x = b.x
		sp.y = b.y
	end for
	self.sprites[0].rotation = b.angle * 180 / pi
	self.sprites[1].rotation = 0
end function

Balloon.imageKey = function
	s = self.spec
	return "balloon:" + s.width + "x" + s.height + ":" + s.color
end function

// The palette icon: the same two images, baked into one at half size, since
// a balloon at full size would tower over the other rows.
Balloon.makeImage = function
	sc = self.artScale
	w = baseImg.width * sc[0] / 2; h = baseImg.height * sc[1] / 2
	g = artUtil.canvas(w, h)
	g.drawImage baseImg, 0, 0, w, h, 0, 0, baseImg.width, baseImg.height,
	  self.spec.color
	g.drawImage shineImg, 0, 0, w, h
	return g.getImage
end function
