// sim.ms -- run a puzzle headless: load it, play it for a while, and say
// where everything got to.  For testing puzzle designs without anyone at
// the screen.  Run it through tools/simPuzzle, which sets up the disks:
//
//	tools/simPuzzle heavyLifting                  the solution, 5 seconds
//	tools/simPuzzle heavyLifting --player         what the player is handed
//	tools/simPuzzle heavyLifting --time 3 --every 0.5
//	tools/simPuzzle --script my/experiment.ms     anything else: see below
//
// It is the game's own code, unmodified: the same modules, the same
// GameWorld.step, the same scenery.  The window is created hidden, because
// the parts still build their art (and that needs a GL context) even though
// nobody will see it.
//
// A --script is an ordinary MiniScript file, imported once everything is
// loaded, which drives the global `sim` below -- load a puzzle, add or
// remove parts, run, inspect.  For example:
//
//	sim.load "heavyLifting", true          // the player's board
//	sim.add "3 kg", {"x": 320, "y": 320}
//	sim.rope [[1, 0], [4, 0], [sim.last.id, 0]]
//	sim.run 3
//	sim.report

//----------------------------------------------------------------------
// Boot: the import path, the window, and the Mini Micro API.
//----------------------------------------------------------------------

bootDir = env.MS_SCRIPT_DIR
root = bootDir + "/../.."
disk = root + "/disk"
// Our own lib goes ahead of Soda's: physics.ms needs our matrixUtil, and the
// one in /sys/lib clobbers the intrinsic Matrix class.  See CLAUDE.md.
env.MS_IMPORT_PATH = [disk, disk + "/lib", disk + "/parts",
  root + "/../MiniMicro2/assets/lib", bootDir + "/sys/lib"].join(":")

// The Mini Micro shell would have set this up; parts.ms adds to it.
env.importPaths = [".", "/usr/lib", "/sys/lib"]

raylib.SetTraceLogLevel raylib.LOG_WARNING
raylib.SetConfigFlags raylib.FLAG_WINDOW_HIDDEN
raylib.InitWindow 960, 640
import "soda"

import "importUtil"
ensureImport ["mathUtil", "config", "physics", "artUtil", "util", "part",
  "parts", "gameWorld", "scenery", "puzzle", "json"]

display(5).mode = displayMode.sprite
partDisp = display(5)

//----------------------------------------------------------------------
// The sim API
//----------------------------------------------------------------------

globals.sim = {}
sim.world = null
sim.puzzle = null
sim.time = 0        // seconds of play so far
sim.last = null     // the part most recently added

fmt = function(x, places=1)
	if not (x isa number) then return str(x)
	m = 10 ^ places
	return str(round(x * m) / m)
end function
sim.fmt = @fmt

// Lay out a puzzle: its solution (every part where the author put it), or
// with `playing` true the board the player is handed.  Either way the world
// is left in design mode, ready for parts to be added or moved.
sim.load = function(name, playing=false)
	if sim.world != null then
		// Starting over: everything from the last world goes, sprites too.
		for p in sim.world.parts[:]
			sim.world.removePart p
		end for
	end if
	w = GameWorld.make(partDisp)
	scenery.addTo w
	pz = Puzzle.make(name)
	if not pz.readFile then
		print "No such puzzle: " + pz.path
		exit 1
	end if
	pz.setUp w, playing
	sim.world = w
	sim.puzzle = pz
	sim.time = 0
	return w
end function

sim.part = function(id)
	if id isa map then return id
	return sim.world.partById(id)
end function

// The parts from a palette entry ("3 kg"), or of a type ("weight").
sim.find = function(what)
	out = []
	for p in sim.world.parts
		if p.fixed then continue
		i = parts.entryFor(p.typeName, p.spec)
		if p.typeName == what or (i != null and parts.catalog[i].label == what) then
			out.push p
		end if
	end for
	return out
end function

// Add a part from the palette entry with this label, as the editor would,
// with `spec` laid over the entry's own (x and y at least).  Snapped like a
// drop is, unless `snap` is false.  Design mode only.
sim.add = function(label, spec=null, snap=true)
	if not parts.entryByLabel.hasIndex(label) then
		print "No palette entry: " + label
		exit 1
	end if
	p = parts.spawn(parts.catalog[parts.entryByLabel[label]])
	if spec != null then p.spec += spec
	if snap then
		s = sim.world.snap(p, p.spec.x, p.spec.y)
		p.spec.x = s[0]
		p.spec.y = s[1]
	end if
	sim.world.addPart p
	if not sim.world.placementOK(p) then print "Warning: " + label +
	  " at " + fmt(p.spec.x) + "," + fmt(p.spec.y) + " overlaps something"
	sim.last = p
	return p
end function

// Run a rope (or a fuse: cls) through tie points, as [part or id, tie]
// pairs in order -- a pulley in the middle is routed over -- made exactly as
// long as the path, as the editor makes one.
sim.rope = function(points, cls=null)
	if cls == null then cls = Rope
	pts = []
	for pt in points
		pts.push {"part": sim.part(pt[0]).id, "tie": pt[1]}
	end for
	r = cls.make({"points": pts, "kind": "Rope"})
	sim.world.addPart r
	r.setLength r.measure
	sim.last = r
	return r
end function

// A belt between two hubs, in groove ra of the first and rb of the second.
sim.belt = function(a, b, ra=0, rb=0)
	r = Belt.make({"a": sim.part(a).id, "b": sim.part(b).id, "ra": ra, "rb": rb})
	sim.world.addPart r
	sim.last = r
	return r
end function

// A power cord between two terminals, as [part or id, terminal] pairs.
sim.wire = function(a, b)
	pts = [{"part": sim.part(a[0]).id, "term": a[1]},
	  {"part": sim.part(b[0]).id, "term": b[1]}]
	r = Wire.make({"points": pts})
	sim.world.addPart r
	r.setLength r.measure * r.spec.slack
	sim.last = r
	return r
end function

sim.remove = function(id)
	sim.world.removePart sim.part(id)
end function

// Run for `seconds` of play, in the game's own fixed steps.  `every`, if
// given, prints a line of positions that often; `ids` limits which parts.
sim.run = function(seconds, every=0, ids=null)
	w = sim.world
	if w.mode != GameWorld.PLAY then w.play
	dt = config.timestep
	steps = round(seconds / dt)
	nextLine = 0
	if every > 0 then sim.traceHeader ids
	for i in range(1, steps, 1)
		w.step dt
		// Not only for looks: a rope's bead chain and a part's effects clock
		// both run from these, so the game calls them every frame and so do we.
		w.updateRopes dt
		w.updateEffects dt
		sim.time += dt
		if every > 0 and sim.time >= nextLine - dt / 2 then
			sim.traceLine ids
			nextLine += every
		end if
	end for
	for p in w.parts
		p.syncSprites
	end for
end function

// Back to the design, as Stop does.
sim.stop = function
	sim.world.stop
	sim.time = 0
end function

//----------------------------------------------------------------------
// Inspection
//----------------------------------------------------------------------

sim.label = function(p)
	i = parts.entryFor(p.typeName, p.spec)
	if i == null then return p.typeName
	return parts.catalog[i].label
end function

// Where a part is: its first body's position, or for one without a body of
// its own, the tie point it hangs on.
sim.where = function(p)
	if p.bodies then return [p.bodies[0].x, p.bodies[0].y]
	if p.tieList then
		w = p.tieWorld(0)
		if w != null then return w
	end if
	return null
end function

// Everything worth knowing about a part, as a map: pose and motion from its
// first body, and its own runtime fields (lit, popped, powered, curLen, ...)
// -- whatever simple values it carries that differ from its class's, so
// that a candle says lit=1 only once it is lit.
sim.state = function(p)
	p = sim.part(p)
	st = {"id": p.id, "label": sim.label(p)}
	if p.isPuzzle then st.puzzle = true
	if sim.world.inPuzzle(p) then st.inPuzzle = true
	if p.bodies then
		b = p.bodies[0]
		st.x = b.x; st.y = b.y
		st.angle = b.angle * 180 / pi
		st.vx = b.vx; st.vy = b.vy
		st.spin = b.angularVelocity
		st.dx = b.x - p.spec.x
		st.dy = b.y - p.spec.y
	else
		w = sim.where(p)
		if w != null then
			st.x = w[0]; st.y = w[1]
		end if
	end if
	for kv in p
		if kv.key == "id" or kv.key == "spec" or kv.key == "world" then continue
		if @kv.value isa funcRef then continue
		if not (kv.value isa number or kv.value isa string) then continue
		if sim.isDefault(p, kv.key, kv.value) then continue
		st[kv.key] = kv.value
	end for
	return st
end function

// Is `value` what the part's class (or one above it) already says for `key`?
sim.isDefault = function(p, key, value)
	c = p.__isa
	while c != null
		if c.hasIndex(key) then return c[key] == value
		if not c.hasIndex("__isa") then return false
		c = c.__isa
	end while
	return false
end function

// A table of every part (or just `ids`), one line each.
sim.report = function(ids=null)
	print "t=" + fmt(sim.time, 2) + "s"
	for p in sim.select(ids)
		st = sim.state(p)
		line = "  #" + st.id + " " + st.label
		if st.hasIndex("inPuzzle") then line += "*"
		if st.hasIndex("x") then line += "  at " + fmt(st.x) + "," + fmt(st.y)
		if st.hasIndex("dx") then
			line += "  moved " + fmt(st.dx) + "," + fmt(st.dy)
			line += "  angle " + fmt(st.angle)
			line += "  v " + fmt(st.vx) + "," + fmt(st.vy)
		end if
		extra = []
		for kv in st
			if ["id", "label", "puzzle", "inPuzzle", "x", "y", "angle", "vx", "vy",
			  "spin", "dx", "dy"].indexOf(kv.key) != null then continue
			extra.push kv.key + "=" + fmt(kv.value, 2)
		end for
		if extra then line += "  [" + extra.join(" ") + "]"
		print line
	end for
end function

sim.select = function(ids)
	if ids == null then
		out = []
		for p in sim.world.parts
			if not p.fixed then out.push p
		end for
		return out
	end if
	out = []
	for id in ids
		p = sim.part(id)
		if p != null then out.push p
	end for
	return out
end function

// A trace is one line per sample: the time, then where each part that can
// move is.  Parts without a body (ropes, mounted pulleys) only move with
// something else, which is in the trace already; static ones not at all.
sim.traceParts = function(ids)
	out = []
	for p in sim.select(ids)
		if p.bodies and p.bodyType == physics.DYNAMIC then out.push p
	end for
	return out
end function

sim.traceHeader = function(ids)
	line = "     t"
	for p in sim.traceParts(ids)
		line += "  " + ("#" + p.id + " " + sim.label(p) + "               ")[:15]
	end for
	print line
end function

sim.traceLine = function(ids)
	line = ("      " + fmt(sim.time, 2))[-6:]
	for p in sim.traceParts(ids)
		b = p.bodies[0]
		line += "  " + (fmt(b.x) + "," + fmt(b.y) + "               ")[:15]
	end for
	print line
end function

//----------------------------------------------------------------------
// Command line
//----------------------------------------------------------------------

args = shellArgs[1:]
name = null
playing = false
seconds = 5
every = 1
script = null
i = 0
while i < args.len
	a = args[i]
	if a == "--player" then
		playing = true
	else if a == "--time" then
		i += 1; seconds = val(args[i])
	else if a == "--every" then
		i += 1; every = val(args[i])
	else if a == "--script" then
		i += 1; script = args[i]
	else
		name = a
	end if
	i += 1
end while

if script != null then
	// Imported rather than read and run, so that it sees the globals: the
	// sim, and every class the game defines.
	if script[0] != "/" then script = env.PWD + "/" + script
	pathParts = script.split("/")
	modName = pathParts.pop
	env.MS_IMPORT_PATH += ":" + pathParts.join("/")
	if modName[-3:] == ".ms" then modName = modName[:-3]
	import modName
else if name != null then
	sim.load name, playing
	if playing then print "Player's board" else print "Solution"
	sim.report
	print
	sim.run seconds, every
	print
	sim.report
else
	print "Usage: tools/simPuzzle <puzzle> [--player] [--time S] [--every S]"
	print "       tools/simPuzzle --script file.ms"
end if

// The host would otherwise sit there with its (hidden) window open.
exit
