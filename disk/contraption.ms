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
//
// Puzzles (see puzzle.ms).  Run menu.ms to pick one, and whether to edit or
// play it; run this directly to edit puzzle1.  Play/stop while editing is
// testing it.
//   P                       mark the selected part as a puzzle part (one the
//                           player must supply; shown faded), or unmark it
//   S                       save the puzzle, to /usr/puzzles/<name>.json
//   R                       swap between laying the puzzle out and playing
//                           it -- the board without its puzzle parts, and
//                           everything left on it locked in place.  Only
//                           for a puzzle opened to edit: one opened to play
//                           stays that way, or R would show the solution.
//   Esc                     back to the menu, if we came from it, or else
//                           quit (without saving, either way)

import "importUtil"
ensureImport ["mathUtil", "config", "physics", "artUtil", "util", "part",
  "parts", "gameWorld", "panel", "editor", "puzzle"]

//----------------------------------------------------------------------
// Displays.  Lower slot numbers draw on top.
//----------------------------------------------------------------------
clear
display(0).mode = displayMode.text
globals.text = display(0)
text.clear

display(1).mode = displayMode.sprite      // the part being dragged
dragDisp = display(1)
dragDisp.clear

display(2).mode = displayMode.pixel       // the panel
panelDisp = display(2)
panelDisp.clear color.clear, 960, 640

display(3).mode = displayMode.pixel       // selection box and handles
overlayDisp = display(3)
overlayDisp.clear color.clear, 960, 640

display(4).mode = displayMode.pixel       // ropes and belts, over the parts
ropeDisp = display(4)                      // they are fastened to
ropeDisp.clear color.clear, 960, 640

display(5).mode = displayMode.sprite      // placed parts
partDisp = display(5)
partDisp.clear

display(6).mode = displayMode.pixel       // pegboard and scenery
bgDisp = display(6)
bgDisp.clear config.fieldColor, 960, 640

display(7).mode = displayMode.solidColor
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

// Which puzzle, and whether to edit or play it, is the menu's to say (see
// menu.ms), and it says so in globals that `run` keeps.  Run on its own,
// this edits puzzle1.  A name with no file behind it is a new puzzle, and
// starts out empty.
fromMenu = globals.hasIndex("puzzleName")
if fromMenu then
	thePuzzle = Puzzle.make(puzzleName)
	startPlaying = puzzlePlaying
else
	thePuzzle = Puzzle.make("puzzle1")
	startPlaying = false
end if
thePuzzle.readFile
// The author may swap back and forth to try the puzzle out; a player may not.
canSwitch = not startPlaying

theEditor.puzzle = thePuzzle

// Lay the board out for the author or for the player.
setUpPuzzle = function(playing)
	theEditor.reset
	thePuzzle.setUp world, playing
	if playing then thePanel.setTag "PLAYING" else thePanel.setTag "EDITING"
end function
setUpPuzzle startPlaying

//----------------------------------------------------------------------
// Main loop.
//----------------------------------------------------------------------
lastTime = time
lastInvKey = null
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
	else if action == "run" and canSwitch then
		// Leaving the editor, the layout is taken first, so that coming back
		// finds it as it was left, saved or not.
		if not thePuzzle.playing then thePuzzle.capture world
		setUpPuzzle not thePuzzle.playing
	else if action == "save" then
		thePuzzle.capture world
		thePuzzle.writeFile
		thePanel.showNote "SAVED"
	end if

	world.advance elapsed

	// Ropes draw themselves, in every mode: a slack one hangs while you are
	// still building.  So do flames, for the same reason.
	world.updateRopes elapsed
	world.updateEffects elapsed
	world.drawLinks ropeDisp

	// The palette's counts, redone only when something they count has
	// changed: a part placed or taken away, marked or unmarked as a puzzle
	// part, or the author's extras -- or the board set up the other way.
	invKey = [world.designVersion, thePuzzle.version, thePuzzle.playing]
	if invKey != lastInvKey and world.mode == GameWorld.DESIGN then
		lastInvKey = invKey
		thePanel.setInventory thePuzzle.inventory(world), not thePuzzle.playing
	end if

	thePanel.trackMouse mouse.x, mouse.y, world.mode
	thePanel.draw world.mode
	theEditor.drawOverlay
	yield
end while

// Let go of Esc first, or its auto-repeat lands in the menu's key buffer and
// quits that as well.
while key.pressed("escape")
	yield
end while
key.clear
clear
if fromMenu then run "menu"
