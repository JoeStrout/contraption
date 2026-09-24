//----------------------------------------------------------------------
// Balternator: a seesaw with a short post standing up from its middle,
// which makes it a flip-flop that sends balls left and right in turn.
//
// The post is what makes it bistable, and it does that by weight alone:
// it puts the bar's center of mass above the pivot, so the bar is an
// inverted pendulum -- level is a balance point it falls away from, and
// whichever way it falls, the post's weight holds it against the stop
// there.  Nothing here has to know that; Lever already turns an
// off-center bar's weight into torque about the pivot.
//
// It also steers.  The post leans with the bar, toward the end that is
// down, so a ball dropped straight onto the middle meets the post's upper
// face and is turned off toward the end that is *up*.  It lands on that
// arm beside the post, where its weight outweighs the post's, and the bar
// flips; that arm is now the one sloping down, and the ball rolls off its
// end.  The post now leans the other way, ready to send the next ball to
// the other side.
//
// The post must stay light for that to work: a ball beside it has a short
// arm, and must still beat the post's own tipping torque at full tilt.
//
// There are no pans -- the bar itself is the ramp that sends a ball on its
// way -- so this is a Lever with one more shape on its bar, and the pin,
// the stops and the momentum all come from there.  What is new is that
// the authored pose is tipped to one side, since level is the one pose it
// cannot rest in; which side is its authored state, and a click in the
// editor flips it.
//----------------------------------------------------------------------

globals.Balternator = new Lever
Balternator.typeName = "balternator"
Balternator.displayName = "Balternator"
Balternator.defaultSpec = Lever.defaultSpec + {"fulcrumHeight": 30,
  "postWidth": 8, "postHeight": 30, "postDensity": 0.5,
  "postColor": "#6C7A88", "downSide": 1}

Balternator.postSprite = null   // per-instance, see makeSprites

Balternator.init = function
	super.init
	self.postSprite = null
end function

// Which end starts down: 1 for the right, -1 for the left.
Balternator.stateSpecs = function
	return [{"downSide": 1}, {"downSide": -1}]
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// Room in the footprint for the post, standing straight up as the palette
// draws it.  Tipped, it leans lower than that; the rising end of the bar
// sweeps above, as any lever's does.
Balternator.headroom = function
	return self.spec.postHeight
end function

// The bar's resting angle: all the way over to the authored side.  Right
// end down is a clockwise turn, hence the minus.
Balternator.restAngle = function
	s = self.spec
	return s.angle - s.downSide * self.maxTilt
end function

//----------------------------------------------------------------------
// Physics bodies
//----------------------------------------------------------------------

Balternator.makeBodies = function
	super.makeBodies
	s = self.spec
	pv = self.pivotLocal
	sh = self.bar.addBox(s.postWidth, s.postHeight, -pv[0],
	  s.thickness / 2 + s.postHeight / 2, 0, s.postDensity)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
	sh.setFilter config.catDefault, config.maskBar
	self.placeBodies
end function

// Every reset comes through here, and Part.placeBody puts the bar level;
// tip it over to the side it rests on.  The pivot is the bar's origin, so
// putting that back where it was is all the placing there is.
Balternator.placeBodies = function
	super.placeBodies
	if self.bar == null then return
	p = self.pivotWorld
	self.bar.setAngle self.restAngle
	self.bar.setPosition p[0], p[1]
end function

//----------------------------------------------------------------------
// Appearance
//----------------------------------------------------------------------

Balternator.postImageKey = function
	s = self.spec
	return "balternator-post:" + s.postWidth + "x" + s.postHeight + ":" +
	  s.postColor
end function

Balternator.postImage = function
	key = self.postImageKey
	if not artUtil.cache.hasIndex(key) then artUtil.cache[key] = self.drawPost
	return artUtil.cache[key]
end function

Balternator.drawPost = function
	s = self.spec
	w = s.postWidth; h = s.postHeight
	g = artUtil.canvas(w, h)
	g.fillRect 0, 0, w, h, s.postColor
	g.fillRect w - 2, 0, 2, h, "#00000038"
	g.fillRect 0, 0, 2, h, "#FFFFFF38"
	g.drawRect 0, 0, w, h, "#00000070", 2
	return g.getImage
end function

Balternator.imageKey = function
	return "balternator:" + super.imageKey + "/" + self.postImageKey
end function

Balternator.drawAssembly = function(g)
	super.drawAssembly g
	s = self.spec
	sz = self.size
	pv = self.pivotLocal
	py = sz[1] / 2 + pv[1] + s.thickness / 2
	g.drawImage self.postImage, sz[0] / 2 - s.postWidth / 2, py
end function

// After the bar, so the post stands on it rather than behind it.
Balternator.makeSprites = function
	super.makeSprites
	self.postSprite = new Sprite
	self.postSprite.image = self.postImage
	self.sprites.push self.postSprite
	self.spriteDisp.sprites.push self.postSprite
end function

Balternator.syncSprites = function
	super.syncSprites
	if not self.bodies then return
	s = self.spec
	// The post's center in the bar's frame: over the bar's middle, which
	// is `pivotFrac` of an arm from the pivot the bar turns about.
	lx = -self.pivotLocal[0]
	ly = s.thickness / 2 + s.postHeight / 2
	o = self.bar.position
	a = self.bar.angle
	c = cos(a); sn = sin(a)
	self.postSprite.x = o[0] + lx * c - ly * sn
	self.postSprite.y = o[1] + lx * sn + ly * c
	self.postSprite.rotation = a * 180 / pi
end function
