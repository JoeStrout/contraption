// puzzle.ms
// A puzzle: the finished machine as its author laid it out, which parts of
// it the player has to supply, and what they get to do it with.  Later, what
// counts as done.
//
// What the player gets is the inventory: of each palette entry, as many as
// the solution uses as puzzle parts, plus however many extras the author
// throws in.  So the solution is always buildable from what is handed out,
// and the extras are the author's to make it harder (red herrings) or easier
// (another way round).  Extras are kept by palette label; see parts.entryFor.
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
ensureImport ["config", "json", "gameWorld", "parts"]

globals.Puzzle = {}

Puzzle.make = function(name)
	pz = new Puzzle
	pz.name = name
	pz.path = config.puzzle.dataDir + "/" + name + ".json"
	pz.design = []      // the whole layout, as saved parts ({type, spec})
	pz.playing = false  // set up for the player, rather than for its author
	pz.extras = {}      // palette label -> extra parts beyond the solution's
	pz.budget = null    // per catalog index, what the player was handed;
	                    // see setUp
	pz.version = 0      // bumped when the extras change; see inventory
	return pz
end function

// Read the file in, if there is one.  Returns whether there was.
Puzzle.readFile = function
	if not file.exists(self.path) then return false
	data = json.parse(file.readLines(self.path).join(char(10)))
	// A bare list of parts is how a board was saved before there were
	// puzzles (current.json), so an old layout renamed into a puzzle file
	// opens as one.
	if data isa list then
		self.design = data
	else
		self.design = data.parts
		if data.hasIndex("extras") then self.extras = data.extras
	end if
	return true
end function

// A map rather than a bare list of parts, because the inventory and the win
// conditions are coming, and will sit beside the parts.
Puzzle.writeFile = function
	data = {"version": 1, "parts": self.design, "extras": self.extras}
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
		// Counted off the whole layout, before anything is taken away.
		self.budget = self.extraCounts
		used = self.countOnBoard(world, true)
		for i in used.indexes
			self.budget[i] += used[i]
		end for
		// Everything the player has to supply goes: the puzzle parts, and
		// whatever is fastened to them.  removePart would take those along
		// anyway, and shrugs off a part already gone that way.
		doomed = []
		for p in world.parts
			if world.inPuzzle(p) then doomed.push p
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

//----------------------------------------------------------------------
// Inventory
//----------------------------------------------------------------------

Puzzle.extraFor = function(i)
	label = parts.catalog[i].label
	if not self.extras.hasIndex(label) then return 0
	return self.extras[label]
end function

// Change the extras of catalog entry i by `delta`, never below none.  A zero
// is taken out of the map rather than kept, so that the file lists only the
// entries the author has actually given extras of.
Puzzle.addExtra = function(i, delta)
	n = self.extraFor(i) + delta
	if n < 0 then n = 0
	label = parts.catalog[i].label
	if n == 0 then
		if self.extras.hasIndex(label) then self.extras.remove label
	else
		self.extras[label] = n
	end if
	self.version += 1
end function

// The extras as a list, one per catalog index.
Puzzle.extraCounts = function
	out = []
	for i in parts.catalog.indexes
		out.push self.extraFor(i)
	end for
	return out
end function

// Of each catalog entry, how many parts of it are on the board -- only the
// puzzle parts (marked or fastened to one), or only the ones the player put
// there.
Puzzle.countOnBoard = function(world, puzzleOnly)
	out = [0] * parts.catalog.len
	for p in world.parts
		if p.fixed or world.isLocked(p) then continue
		if puzzleOnly and not world.inPuzzle(p) then continue
		i = parts.entryFor(p.typeName, p.spec)
		if i != null then out[i] += 1
	end for
	return out
end function

// What the palette shows, one per catalog index: for the author, [puzzle
// parts in use, extras]; for the player, how many are left to take, or null
// for an entry the puzzle hands out none of at all, which the palette then
// leaves out.
Puzzle.inventory = function(world)
	out = []
	if not self.playing then
		used = self.countOnBoard(world, true)
		for i in parts.catalog.indexes
			out.push [used[i], self.extraFor(i)]
		end for
		return out
	end if
	placed = self.countOnBoard(world, false)
	for i in parts.catalog.indexes
		if self.budget[i] <= 0 then
			out.push null
		else
			out.push self.budget[i] - placed[i]
		end if
	end for
	return out
end function
