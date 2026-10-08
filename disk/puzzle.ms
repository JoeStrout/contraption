// puzzle.ms
// A puzzle: the finished machine as its author laid it out, and which parts
// of it the player has to supply.  Later, what they get to do it with and
// what counts as done.
//
// It is one file in the data directory.  Editing works on the whole layout.
// Playing starts from the same layout with the puzzle parts taken out (see
// Part.isPuzzle), and everything left is locked where the author put it --
// the player builds around it, and may tie to it, but may not move it.
//
// Either way the world underneath is the same GameWorld, with the same
// DESIGN / PLAY / PAUSED modes: testing a puzzle and playtesting one are both
// just running it.  What differs is what the board was set up with, and
// what the editor will let you touch.

import "importUtil"
ensureImport ["config", "json", "gameWorld"]

globals.Puzzle = {}

Puzzle.make = function(name)
	pz = new Puzzle
	pz.name = name
	pz.path = config.puzzle.dataDir + "/" + name + ".json"
	pz.design = []      // the whole layout, as saved parts ({type, spec})
	pz.playing = false  // set up for the player, rather than for its author
	return pz
end function

// Read the file in, if there is one.  Returns whether there was.
Puzzle.readFile = function
	if not file.exists(self.path) then return false
	data = json.parse(file.readLines(self.path).join(char(10)))
	// A bare list of parts is how a board was saved before there were
	// puzzles (current.json), so an old layout renamed into a puzzle file
	// opens as one.
	if data isa list then self.design = data else self.design = data.parts
	return true
end function

// A map rather than a bare list of parts, because the inventory and the win
// conditions are coming, and will sit beside the parts.
Puzzle.writeFile = function
	data = {"version": 1, "parts": self.design}
	file.makedir config.puzzle.dataDir
	file.writeLines self.path, [json.toJSON(data)]
end function

// Take the author's layout from the world.  While it is being tested, the
// world is wherever the run has got to, and the layout is the one the run
// started from -- which is exactly what play saved before it began.
Puzzle.capture = function(world)
	if self.playing then return
	if world.mode == GameWorld.DESIGN then
		self.design = json.parse(world.save)
	else
		self.design = json.parse(world.snapshot)
	end if
end function

// Lay the board out for the author (playing false) or for the player.  The
// world is stopped first, so that what it is handed is a design and not a
// run.  Read in through JSON, so that the world's parts never share a list
// with the design held here.
Puzzle.setUp = function(world, playing)
	world.stop
	self.playing = playing
	world.authoring = not playing
	world.locked = {}
	world.load json.toJSON(self.design)
	if playing then
		// Taken out one at a time through removePart, which takes whatever
		// depended on each along with it: a rope tied to a puzzle part goes
		// with the part, since there is nothing left for it to be tied to.
		// (It shrugs off one already gone that way.)
		doomed = []
		for p in world.parts
			if p.isPuzzle then doomed.push p
		end for
		for p in doomed
			world.removePart p
		end for
		for p in world.parts
			if not p.fixed then world.locked[p.id] = true
		end for
	end if
	world.refreshTints
end function
