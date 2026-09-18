// contraption.ms
// A build-a-machine puzzle game, in the spirit of The Incredible Machine.
//
// Run this from Mini Micro with the contraption disk mounted:  run "contraption"
//
// Controls:
//   drag from the palette   place a new part
//   drag a placed part      move it (it turns red where it will not fit)
//   click a part            select it
//   click it again          for a part with more than one sensible way to
//                           start -- a toggle switch -- flip to the next one
//                           (a quick click; a press and hold still moves it)
//   Backspace / Delete      delete the selected part
//   mouse wheel over panel  scroll the palette
//   drag Rope from palette  drop it on a tie point to make one end fast,
//                           then click another to finish the run (a click
//                           on a pulley's wheel routes the rope over it;
//                           Return ends it loose, as if it had been cut)
//   drag Fuse from palette  the same, between tie points -- but a fuse is
//                           stiff, so shift-click pins it to the board where
//                           the mouse is and carries the run on from there,
//                           and Return ends it at a pin rather than loose.
//                           A fuse may therefore go anywhere, not only from
//                           one part to another.
//   drag Wire from palette  the same, between the square terminals: an
//                           outlet's sockets, a motor's post, a relay's four
//                           pads.  A live wire goes bright, and a powered
//                           motor turns.
//   play / pause / stop     run, hold, and reset the simulation
//   Esc                     quit

import "importUtil"
ensureImport ["mathUtil", "config", "physics", "artUtil", "util", "part",
  "parts", "gameWorld", "panel", "editor"]

//----------------------------------------------------------------------
// Displays.  Lower slot numbers draw on top.
//----------------------------------------------------------------------
clear
display(0).setMode displayMode.text
globals.text = display(0)
text.clear

display(1).setMode displayMode.sprite      // the part being dragged
dragDisp = display(1)
dragDisp.clear

display(2).setMode displayMode.pixel       // the panel
panelDisp = display(2)
panelDisp.clear color.clear, 960, 640

display(3).setMode displayMode.pixel       // selection box and handles
overlayDisp = display(3)
overlayDisp.clear color.clear, 960, 640

display(4).setMode displayMode.pixel       // ropes and belts, over the parts
ropeDisp = display(4)                      // they are fastened to
ropeDisp.clear color.clear, 960, 640

display(5).setMode displayMode.sprite      // placed parts
partDisp = display(5)
partDisp.clear

display(6).setMode displayMode.pixel       // pegboard and scenery
bgDisp = display(6)
bgDisp.clear config.fieldColor, 960, 640

display(7).setMode displayMode.solidColor
display(7).color = config.backdropColor

//----------------------------------------------------------------------
// The pegboard the parts hang on.
//----------------------------------------------------------------------
drawPegboard = function
	bgDisp.fillRect 0, 0, config.fieldWidth, config.fieldHeight, config.fieldColor
	g = config.grid
	y = config.floorHeight + g
	while y < config.fieldHeight
		x = g
		while x < config.fieldWidth
			bgDisp.setPixel x, y, config.pegColor
			x = x + g
		end while
		y = y + g
	end while
	bgDisp.fillRect 0, 0, config.fieldWidth, config.floorHeight, config.floorColor
	bgDisp.line 0, config.floorHeight, config.fieldWidth, config.floorHeight,
	  "#00000060", 2
end function

//----------------------------------------------------------------------
// Build the world.
//----------------------------------------------------------------------
world = GameWorld.make(partDisp)

// The floor is scenery: it collides, but it is not a part you can pick up.
// It gets no sprite, because the background art already draws it.
Floor = new Part
Floor.typeName = "floor"
Floor.displayName = "Floor"
Floor.bodyType = physics.STATIC
Floor.fixed = true
Floor.defaultSpec = Part.defaultSpec + {"width": config.fieldWidth,
  "height": config.floorHeight}
Floor.size = function
	return [self.spec.width, self.spec.height]
end function
Floor.makeBodies = function
	b = self.addBody
	sh = b.addBox(self.spec.width, self.spec.height)
	sh.setFriction 0.7
	sh.setRestitution 0.2
end function
Floor.makeSprites = function
end function

world.addPart Floor.make({"x": config.fieldWidth / 2,
  "y": config.floorHeight / 2})

// Walls, so that parts cannot be shoved out of the world during play.  Tall
// and thin, just outside the playfield.
Wall = new Floor
Wall.typeName = "wall"
Wall.defaultSpec = Part.defaultSpec + {"width": 20,
  "height": config.fieldHeight * 3}
world.addPart Wall.make({"x": -10, "y": config.fieldHeight})
world.addPart Wall.make({"x": config.fieldWidth + 10, "y": config.fieldHeight})

thePanel = Panel.make(panelDisp)
theEditor = Editor.make(world, thePanel, dragDisp, overlayDisp)

drawPegboard

//----------------------------------------------------------------------
// Main loop.
//----------------------------------------------------------------------
lastTime = time
while not key.pressed("escape")
	now = time
	elapsed = now - lastTime
	lastTime = now

	action = theEditor.update(world.mode)
	if action == "play" then
		theEditor.clearSelection
		world.play
	else if action == "pause" then
		world.pause
	else if action == "stop" then
		world.stop
	end if

	world.advance elapsed

	// Ropes draw themselves, in every mode: a slack one hangs while you are
	// still building.  So do flames, for the same reason.
	world.updateRopes elapsed
	world.updateEffects elapsed
	world.drawLinks ropeDisp

	thePanel.trackMouse mouse.x, mouse.y, world.mode
	thePanel.draw world.mode
	theEditor.drawOverlay
	yield
end while

key.clear
clear
