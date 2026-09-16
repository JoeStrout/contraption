// ballTest.ms
// Minimal Contraption test: a ground plane drawn with gfx.fillRect, and a
// ball drawn as a Sprite whose position comes from the physics engine.
//
// Note on coordinates: physics.ms is agnostic about which way y points; we
// use Mini Micro screen coordinates (y up, origin at lower left) throughout,
// so gravity points in -y.  Body angles are radians, CCW; Sprite.rotation is
// degrees, CCW -- so the conversion is just a scale factor.

import "physics"

clear
gfx.clear color.clear
disp = display(4)		// the sprite display
disp.clear

//----------------------------------------------------------------------
// Make a round ball image, by drawing a circle on gfx and grabbing it.
//----------------------------------------------------------------------
makeBallImage = function(radius, ballColor)
	d = radius * 2
	g = new PixelDisplay
	g.clear color.clear, d, d
	g.fillEllipse 0, 0, d, d, ballColor
	// a highlight, so we can see it spin
	g.fillEllipse d * 0.55, d * 0.55, d * 0.25, d * 0.25, "#FFFFFFA0"
	img = g.getImage
	return img
end function

//----------------------------------------------------------------------
// Set up the world.
//----------------------------------------------------------------------
groundHeight = 40
world = physics.World.make(0, -980)

ground = world.addBody(480, groundHeight/2, physics.STATIC)
ground.addBox 960, groundHeight

ballRadius = 24
ball = world.addBody(430, 560)
ball.addCircle ballRadius
ball.shapes[0].setRestitution 0.6
ball.shapes[0].setFriction 0.4
ball.setAngularVelocity 3

ballSprite = new Sprite
ballSprite.image = makeBallImage(ballRadius, color.orange)
disp.sprites.push ballSprite

//----------------------------------------------------------------------
// Draw the static scenery once.
//----------------------------------------------------------------------
gfx.fillRect 0, 0, 960, groundHeight, color.brown
gfx.print "Contraption: ball test.  Esc to quit.", 20, 600, color.silver

//----------------------------------------------------------------------
// Main loop.
//----------------------------------------------------------------------
dt = 1/60
while not key.pressed("escape")
	world.step dt
	ballSprite.x = ball.x
	ballSprite.y = ball.y
	ballSprite.rotation = ball.angle * 180 / pi
	yield
end while

key.clear
