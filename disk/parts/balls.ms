//----------------------------------------------------------------------
// Ball: a rolling, bouncing sphere.
//----------------------------------------------------------------------

globals.Ball = new Part
Ball.typeName = "ball"
Ball.displayName = "Ball"
// Damping is what stands in for the losses a real ball has and a 2D impulse
// solver does not: a circle on a flat floor has nothing to stop its spin, so
// without angular damping a bouncy ball rolls forever.
Ball.defaultSpec = Part.defaultSpec + {"radius": 20, "sheet": "ball-bowling",
  "color": "#E08828", "restitution": 0.55, "density": 1, "friction": 0.4,
  "linearDamping": 0.05, "angularDamping": 0.3, "bounceSoftSpeed": 250}

Ball.size = function
	return [self.spec.radius * 2, self.spec.radius * 2]
end function

Ball.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addCircle(s.radius, 0, 0, s.density)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

//----------------------------------------------------------------------
// Appearance.  A ball is drawn from a pre-rendered sheet of 64 views of the
// same sphere, one per 360/64 degrees of spin, rather than by rotating one
// picture: a rotated flat disc reads as a spinning coin, while the sheet has
// real shading that stays put while the pattern turns.
//
// The sheet's cell size is the ball's diameter (the sphere is framed edge to
// edge), so the sprite never needs scaling and `radius` is what picks which
// sheet of a given ball we load.
//----------------------------------------------------------------------

Ball.sheetPath = function
	return config.picsDir + self.spec.sheet + "_" + config.ballSheetCols +
	  "x" + config.ballSheetCols + "_" + round(self.spec.radius * 2) + ".png"
end function

// The 64 frames, or null if there is no sheet for this ball yet -- in which
// case we fall back to the procedural art below.
Ball.frames = function
	return artUtil.frames(self.sheetPath, round(self.spec.radius * 2),
	  config.ballSheetCols, config.ballFrameCount)
end function

// Which frame shows the ball turned `angle` radians counterclockwise.
Ball.frameIndex = function(angle)
	n = config.ballFrameCount
	idx = round(angle * n / (2 * pi)) % n
	if idx < 0 then idx = idx + n
	return idx
end function

// Each sprite shows the frame matching its body's rotation, and is itself
// left unrotated -- the frame already carries the rotation.
Ball.syncSprites = function
	fr = self.frames
	if fr == null then
		super.syncSprites
		return
	end if
	for i in self.sprites.indexes
		if i >= self.bodies.len then break
		b = self.bodies[i]
		sp = self.sprites[i]
		sp.x = b.x
		sp.y = b.y
		sp.rotation = 0
		sp.image = fr[self.frameIndex(b.angle)]
	end for
end function

Ball.imageKey = function
	return "ball:" + self.spec.sheet + ":" + self.spec.radius + ":" +
	  self.spec.color
end function

// The resting image: frame 0 of the sheet, which is also the palette icon.
Ball.makeImage = function
	fr = self.frames
	if fr != null then return fr[0]
	r = self.spec.radius
	d = r * 2
	g = artUtil.canvas(d, d)
	g.fillEllipse 0, 0, d, d, self.spec.color
	// A rim a little darker than the body, and an off-center highlight, so
	// that the ball reads as round and its spin is visible.
	g.drawEllipse 0, 0, d, d, "#00000060", 2
	g.fillEllipse d * 0.52, d * 0.58, d * 0.26, d * 0.26, 
		color.lerp(self.spec.color, color.white)
	return g.getImage
end function
