//----------------------------------------------------------------------
// Scissors: bolted to the pegboard, and the one thing in the world that can
// cut a rope.
//
// They are a trigger and an animation, not a mechanism.  Press on either
// handle -- from above or below -- and they snap shut of their own accord,
// over eight drawn poses, and on the way through they cut whatever rope lies
// between the jaws.  Nothing about the closing is simulated: the blades have
// no shapes and the halves do not turn on the screw, because the only thing
// they have to do to anything is happen at the right moment.
//
// What *is* physics is the handles: two boxes where the rings are drawn, so
// that a weight can be dropped on one, and so that the push that closes the
// scissors is a real contact with a real force behind it.  They are a static
// body, and the boxes stay in the open pose throughout -- the close is over
// in half a second, and a shape that moved would only drop whatever was
// resting on it.
//
// The geometry below is measured off the art, in the part's own frame, with
// the origin at the middle of a frame -- which is also the middle of the
// picture, in every pose.  There is no scaling.
//----------------------------------------------------------------------

sheetPath = "/usr/pics/scissors_8x1_48x32.png"
frameWidth = 48
frameHeight = 32
frameCount = 8

// The pose at which the blades have all but met, and so the moment a rope
// between them parts.  The last frame is shut.
cutFrame = 4

// What the eight poses cover between them, which is the footprint: the
// selection ring and the grid snap work from it.
artWidth = 42
artHeight = 30

// The handle rings, in the open pose.  Blades point right, handles left.
handleW = 15
handleH = 9
handleX = -13.5
handleY = 10.5          // and -handleY for the lower ring

// The screw the halves turn on, a little left of center.
pivotX = -1.5
pivotSize = 6

// The jaws: the right half of the picture, and the region a rope has to be
// lying in to be cut.  It is the whole half rather than the sliver left
// between the blades at cutFrame, because the rope does not move while the
// scissors close -- what matters is that it was in the way of them.
jawX0 = 0
jawX1 = 21
jawHalfH = 15

// The tips of the two blades, which are the only sharp thing in the game:
// wide apart in the open pose and together once the scissors are shut.  A
// rope does not care where they are -- it is cut by the pose reaching
// cutFrame, wherever it lies between the jaws -- but a balloon does, since
// what pops it is a point actually inside its skin.
bladeTipX = 18
bladeTipY = 7

sheetFrames = function
	return artUtil.frames(sheetPath, frameWidth, frameCount, frameCount,
	  frameHeight)
end function

globals.Scissors = new Part
Scissors.typeName = "scissors"
Scissors.displayName = "Scissors"
Scissors.bodyType = physics.STATIC
Scissors.defaultSpec = Part.defaultSpec + {"restitution": 0.1, "friction": 0.6,
  // Eight poses over 32 frames of a 60 Hz game.
  "closeTime": 32 / 60,
  // How hard something has to bear on a handle before the scissors go.  The
  // engine's impulses are mass times velocity, and a resting mass m delivers
  // m * gravity * timestep each step, so this is about ten grams' worth --
  // low enough that anything which actually lands on a handle sets them off.
  "triggerImpulse": 1500}

// Runtime: where the animation has got to, and whether it has cut yet.
Scissors.frame = 0
Scissors.closing = false
Scissors.closeElapsed = 0
Scissors.hasCut = false

Scissors.init = function
	self.frame = 0
	self.closing = false
	self.closeElapsed = 0
	self.hasCut = false
end function

Scissors.size = function
	return [artWidth, artHeight]
end function

Scissors.makeBodies = function
	s = self.spec
	b = self.addBody
	shapes = [b.addBox(handleW, handleH, handleX, handleY, 0, 1),
	  b.addBox(handleW, handleH, handleX, -handleY, 0, 1),
	  b.addBox(pivotSize, pivotSize, pivotX, 0, 0, 1)]
	for sh in shapes
		sh.setRestitution s.restitution
		sh.setFriction s.friction
	end for
end function

//----------------------------------------------------------------------
// The trigger and the close
//----------------------------------------------------------------------

// A world point in the part's own frame.  The scissors never move, so this
// is the authored pose rather than anything read back off the body.
Scissors.toLocal = function(x, y)
	s = self.spec
	dx = x - s.x; dy = y - s.y
	c = cos(s.angle); sn = sin(s.angle)
	return [dx * c + dy * sn, -dx * sn + dy * c]
end function

// Is something bearing up or down on a handle hard enough to close us?
//
// The engine leaves each contact's accumulated normal impulse on the
// manifold, which is the force the solver actually had to find -- so this
// asks the real question, and a ball merely rolling past a handle sideways
// does not count: the normal has to be more vertical than horizontal.
Scissors.pushedOn = function
	if not self.bodies then return false
	s = self.spec
	for m in self.world.phys.contactsOf(self.bodies[0])
		if abs(m.ny) <= abs(m.nx) then continue
		for pt in m.points
			if pt.Pn < s.triggerImpulse then continue
			// The left half is the handles; the blades are not pressed on,
			// they are what does the cutting.
			if self.toLocal(pt.x, pt.y)[0] < 0 then return true
		end for
	end for
	return false
end function

// The blade tips, wherever the closing has got to.  The scissors never move,
// so this works from the authored pose like toLocal does.
Scissors.sharpPoints = function
	s = self.spec
	y = bladeTipY * (1 - self.frame / (frameCount - 1))
	c = cos(s.angle); sn = sin(s.angle)
	out = []
	for ly in [y, -y]
		out.push [s.x + bladeTipX * c - ly * sn,
		  s.y + bladeTipX * sn + ly * c]
	end for
	return out
end function

Scissors.update = function(dt)
	if self.frame >= frameCount - 1 then return    // already shut
	if not self.closing then
		if not self.pushedOn then return
		self.closing = true
	end if
	self.closeElapsed = self.closeElapsed + dt
	f = floor(self.closeElapsed / self.spec.closeTime * frameCount)
	if f > frameCount - 1 then f = frameCount - 1
	if f == self.frame then return
	self.frame = f
	self.showFrame f
	// `>=` rather than `==`, because a hitch can skip a pose and the rope
	// still has to part.
	if f >= cutFrame and not self.hasCut then
		self.hasCut = true
		self.cutRopes
	end if
end function

// Cut every rope lying between the jaws, once.  The cut itself is queued:
// we are inside an update hook, and cutting adds and removes parts.
Scissors.cutRopes = function
	for r in self.world.ropes
		pl = r.polyline
		if pl == null then continue
		pts = pl.pts
		for i in range(0, pts.len - 2, 1)
			a = self.toLocal(pts[i][0], pts[i][1])
			b = self.toLocal(pts[i+1][0], pts[i+1][1])
			t = clipToJaws(a, b)
			if t == null then continue
			self.world.cutRope r, i, t
			break
		end for
	end for
end function

// Where along the segment a -> b (both in the part's frame) the scissors
// have hold of it: the middle of the piece lying inside the jaw box, or null
// if none of it does.  Liang-Barsky, which gives the entry and exit
// parameters directly.
clipToJaws = function(a, b)
	dx = b[0] - a[0]; dy = b[1] - a[1]
	ps = [-dx, dx, -dy, dy]
	qs = [a[0] - jawX0, jawX1 - a[0], a[1] + jawHalfH, jawHalfH - a[1]]
	t0 = 0; t1 = 1
	for i in [0, 1, 2, 3]
		p = ps[i]
		if p == 0 then
			// Parallel to this edge: either wholly inside it or wholly out.
			if qs[i] < 0 then return null
			continue
		end if
		r = qs[i] / p
		if p < 0 then
			if r > t1 then return null
			if r > t0 then t0 = r
		else
			if r < t0 then return null
			if r < t1 then t1 = r
		end if
	end for
	return (t0 + t1) / 2
end function

Scissors.onStop = function
	super.onStop
	self.frame = 0
	self.closing = false
	self.closeElapsed = 0
	self.hasCut = false
	self.showFrame 0
end function

//----------------------------------------------------------------------
// Appearance: one sprite, whose image is swapped for the pose of the moment.
//----------------------------------------------------------------------

Scissors.showFrame = function(i)
	fr = sheetFrames
	if fr == null or not self.sprites then return
	self.sprites[0].image = fr[i]
end function

Scissors.imageKey = function
	return "scissors"
end function

// The open pose, which is what the palette shows and what a new pair starts
// as.  The magenta square is the usual "there is no art here" marker.
Scissors.makeImage = function
	fr = sheetFrames
	if fr == null then return super.makeImage
	return fr[0]
end function
