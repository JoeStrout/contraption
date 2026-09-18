//----------------------------------------------------------------------
// Relay: a switch thrown by electricity instead of by a ball.
//
// This is the part the whole one-bit model was chosen for.  Everything else
// electrical takes a net and does something physical with it -- a motor
// turns, a plate closes when something sits on it -- and none of that feeds
// back into the wiring.  A relay does: its coil is a load like any other,
// and what it drives is a *switch*, so the output of one net becomes the
// input of the next.  Once you can do that, NOT, AND, OR, latches and
// oscillators are all things the player can discover with cord and relays,
// and none of them had to be built.
//
// Four terminals, and the picture says which is which:
//
//   common    the pole of the switch, at the hinge of the armature
//   control   the coil, which grounds through the board like any load
//   0 (off)   the contact the armature rests on with the coil dead
//   1 (on)    the contact it is pulled down to with the coil live
//
// So the contacts are changeover, not simply make: wiring through 0 gives a
// NOT for free, which is the piece a beginner would otherwise have no way
// to build.
//
// The coil's liveness is a *terminal's*, not the part's: `powered` is true
// if anything at all on the relay is live, and the contacts usually are.
// That is what Part.termLive is for.
//
// A relay reads its coil in `update`, one step after the fill that decided
// it, so a chain of them propagates a stage per step.  That delay is also
// what keeps a relay wired to break its own coil honest -- it buzzes at a
// step a flip instead of hanging the solve.  See circuit.ms.
//----------------------------------------------------------------------

import "importUtil"
ensureImport ["config", "part", "artUtil", "physics", "util"]

offImg = file.loadImage("/usr/pics/relay-off.png")
onImg = file.loadImage("/usr/pics/relay-on.png")

// The art is the authority on where the terminals are: these are the pads
// drawn in the two pictures, in image pixels from the top-left corner.
// Nothing may be moved here without moving it there.
imgWidth = 43
imgHeight = 47
termPix = [[4.5, 10], [4.5, 42], [38.5, 4.5], [38.5, 16.5]]

// ...and the names of those four, in that order.
COMMON = 0
CONTROL = 1
OFFOUT = 2
ONOUT = 3

globals.Relay = new Part
Relay.typeName = "relay"
Relay.displayName = "Relay"
Relay.bodyType = physics.STATIC
Relay.defaultSpec = Part.defaultSpec + {"width": imgWidth,
  "height": imgHeight, "restitution": 0.15, "friction": 0.6}

Relay.energized = false             // runtime: the coil is live

Relay.size = function
	return [self.spec.width, self.spec.height]
end function

// Image pixels are y-down from the top-left; part-frame coordinates are
// y-up from the middle.
Relay.terminalLocals = function
	out = []
	for t in termPix
		out.push [t[0] - imgWidth / 2, imgHeight / 2 - t[1]]
	end for
	return out
end function

// The changeover contact: common meets whichever output the armature is
// lying on, and the coil meets nothing.
Relay.conducts = function(i, j)
	out = OFFOUT
	if self.energized then out = ONOUT
	return (i == COMMON and j == out) or (j == COMMON and i == out)
end function

Relay.makeBodies = function
	s = self.spec
	b = self.addBody
	sh = b.addBox(s.width, s.height, 0, 0, 0, 1)
	sh.setRestitution s.restitution
	sh.setFriction s.friction
end function

Relay.update = function(dt)
	super.update dt
	self.setEnergized self.termLive(CONTROL)
end function

Relay.setEnergized = function(v)
	if v == self.energized then return
	self.energized = v
	self.showState
	// The contacts have just moved, so what was live may not be any more.
	if self.world != null then self.world.circuitDirty = true
end function

Relay.showState = function
	if self.sprites then self.sprites[0].image = self.image
end function

Relay.onStop = function
	super.onStop
	self.energized = false
	self.showState
end function

//----------------------------------------------------------------------
// Appearance: two pre-drawn pictures, so nothing here is cached -- the
// images themselves are the cache, loaded once when this module is.
//----------------------------------------------------------------------

Relay.image = function
	if self.energized then return onImg
	return offImg
end function
