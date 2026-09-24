// parts.ms
// The concrete part types, and the catalog that the palette is built from.

import "importUtil"
ensureImport ["config", "part", "artUtil", "physics", "util"]

if not env.importPaths.hasIndex("/usr/parts") then env.importPaths.insert 0, "/usr/parts"
ensureImport "balls block platform lever balance balternator rope tiePoint pulleys".split +
  "weight balloon basket scissors gears belts motor electric".split +
  "switches relay wire lamp candle lens fuse explosives".split

//----------------------------------------------------------------------
// The registry, for loading a saved design.
//----------------------------------------------------------------------

byName = {}
for var in globals.values
	if @var isa Part then byName[var.typeName] = var
end for

// Rebuild a part from what Part.save wrote out.
fromSaved = function(saved)
	cls = byName[saved.type]
	return cls.make(saved.spec)
end function

//----------------------------------------------------------------------
// The catalog: what the palette offers, in order.
//
// An entry is a part class plus the spec to stamp out, so that one class can
// appear several times at different sizes.  Puzzle mode will later add a
// `count` field here; nothing else needs to change for that.
//----------------------------------------------------------------------

catalog = [
	{"cls": Ball, "spec": {"radius": 20, "sheet": "ball-bowling",
	  "color": "#202028", "density": 3, "restitution": 0.15, "friction": 0.5,
	  "linearDamping": 0.02, "angularDamping": 0.2, "bounceSoftSpeed": 150},
	  "label": "Bowling Ball"},
	{"cls": Ball, "spec": {"radius": 20, "sheet": "ball-soccer",
	  "color": "#F0F0E8", "density": 0.6, "restitution": 0.55, "friction": 0.5,
	  "linearDamping": 0.08, "angularDamping": 0.5, "bounceSoftSpeed": 250},
	  "label": "Soccer Ball"},
	{"cls": Ball, "spec": {"radius": 16, "sheet": "ball-star",
	  "color": "#D8321F", "density": 1, "restitution": 0.8, "friction": 0.6,
	  "linearDamping": 0.1, "angularDamping": 0.6, "bounceSoftSpeed": 300},
	  "label": "Rubber Ball"},
	{"cls": Ball, "spec": {"radius": 10, "sheet": "ball-tennis",
	  "color": "#C8E040", "density": 0.7, "restitution": 0.75, "friction": 0.7,
	  "linearDamping": 0.15, "angularDamping": 0.8, "bounceSoftSpeed": 250},
	  "label": "Tennis Ball"},
	{"cls": Block, "spec": {"width": 40, "height": 40}, "label": "Block"},
	{"cls": Block, "spec": {"width": 100, "height": 20}, "label": "Plank"},
	{"cls": Block, "spec": {"width": 20, "height": 80}, "label": "Post"},
	{"cls": Platform, "spec": {"width": 120, "height": 20}, "label": "Platform"},
	{"cls": Platform, "spec": {"width": 60, "height": 20}, "label": "Ledge"},
	{"cls": Lever, "spec": {"length": 160}, "label": "Seesaw"},
	{"cls": Lever, "spec": {"length": 200, "pivotFrac": 0.55,
	  "fulcrumHeight": 40}, "label": "Lever"},
	{"cls": Balance, "spec": {}, "label": "Balance"},
	{"cls": Balternator, "spec": {}, "label": "Balternator"},
	{"cls": Weight, "spec": {"width": 30, "height": 30, "kg": 1}, "label": "1 kg"},
	{"cls": Weight, "spec": {"width": 40, "height": 40, "kg": 3}, "label": "3 kg"},
	{"cls": Weight, "spec": {"width": 50, "height": 50, "kg": 5}, "label": "5 kg"},
	{"cls": Balloon, "spec": {"color": "#FF4444"}, "label": "Balloon"},
	{"cls": Basket, "spec": {}, "label": "Basket"},
	{"cls": Scissors, "spec": {}, "label": "Scissors"},
	{"cls": Gear, "spec": {"teeth": 12}, "label": "Small Gear"},
	{"cls": Gear, "spec": {"teeth": 18}, "label": "Gear"},
	{"cls": Gear, "spec": {"teeth": 24}, "label": "Large Gear"},
	{"cls": Motor, "spec": {"dir": 1}, "label": "Motor (CCW)"},
	{"cls": Motor, "spec": {"dir": -1}, "label": "Motor (CW)"},
	{"cls": Spool, "spec": {}, "label": "Spool"},
	{"cls": Wheel, "spec": {"radius": 20}, "label": "Small Wheel"},
	{"cls": Wheel, "spec": {"radius": 30}, "label": "Wheel"},
	{"cls": Wheel, "spec": {"radius": 40}, "label": "Large Wheel"},
	{"cls": StepPulley, "spec": {}, "label": "Step Pulley"},
	{"cls": Gearwheel, "spec": {}, "label": "Gearwheel"},
	{"cls": Belt, "spec": {}, "label": "Belt"},
	{"cls": TiePoint, "spec": {}, "label": "Tie Point"},
	{"cls": Pulley, "spec": {}, "label": "Pulley"},
	{"cls": MountedPulley, "spec": {}, "label": "Mounted Pulley"},
	{"cls": Rope, "spec": {}, "label": "Rope"},
	{"cls": Outlet, "spec": {}, "label": "Outlet"},
	{"cls": PressurePlate, "spec": {}, "label": "Pressure Plate"},
	{"cls": ToggleSwitch, "spec": {"startOpen": true}, "label": "Toggle Switch"},
	{"cls": Relay, "spec": {}, "label": "Relay"},
	{"cls": Lamp, "spec": {}, "label": "Lamp"},
	{"cls": Candle, "spec": {}, "label": "Candle"},
	{"cls": Lens, "spec": {}, "label": "Lens"},
	{"cls": Fuse, "spec": {}, "label": "Fuse"},
	{"cls": Firecracker, "spec": {}, "label": "Firecracker"},
	{"cls": Dynamite, "spec": {}, "label": "Dynamite"},
	{"cls": Rocket, "spec": {}, "label": "Rocket"},
	{"cls": Wire, "spec": {}, "label": "Power Cord"},
]

// A fresh part from a catalog entry.
spawn = function(entry)
	return entry.cls.make(entry.spec)
end function
