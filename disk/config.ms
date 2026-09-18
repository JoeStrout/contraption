// config.ms
// Screen layout, tuning constants, and the UI color scheme, all in one place.

// The screen is 960 x 640: the playfield on the left, the panel on the right.
fieldWidth = 760
fieldHeight = 640
panelLeft = 760
panelWidth = 200

// Parts snap so that their footprint lands on this lattice.  Part sizes are
// multiples of it, so that neighbors abut exactly.  Positions themselves stay
// floats; snapping happens only in the editor, on the way into spec.
grid = 20

// Height of the level floor, which is scenery rather than a placeable part.
floorHeight = 40

// The transport buttons live in a strip across the bottom of the panel.
buttonBarHeight = 64
buttonSize = 44

// Palette layout.
paletteRowHeight = 56
paletteTitleHeight = 32

// Physics.
gravity = 980
timestep = 1/60
maxStepsPerFrame = 5

// Impacts slower than this don't bounce at all.  physics.ms defaults to 30,
// which is far too low at our scale: gravity 980 px/s^2 against the real
// 9.8 m/s^2 makes a meter 100 pixels, so 30 is 0.3 m/s, and a bounce that
// slow is under half a pixel high -- yet still fast enough to keep bouncing
// forever off a lively ball.  1 m/s (100 here) is the usual value; this is
// tuned by eye instead, since what matters is how tall the last bounce is:
// a bounce leaving at v rises v^2 / (2 * gravity) pixels, so 65 stops a ball
// from about a pixel up.  It has to stay well clear of settleSpeed below.
restitutionThreshold = 70

// Settling.  The engine has no sleeping of its own, so a part whose motion
// stays under both of these for settleDelay seconds has its velocity crushed
// by settleDamp each step, which kills the residual jitter a bouncy part
// shows at rest -- the position bias that pushes overlapping shapes apart
// hands a resting part a few px/s every step, and nothing takes it back.
// settleSpeed has to sit above that, which is why it is not smaller.
//
// We damp hard rather than freeze outright: a frozen part whose support was
// knocked away would hang in the air, while a damped one builds speed under
// gravity until it is moving again.
settleSpeed = 25        // pixels/second
settleSpin = 0.4        // radians/second
settleDelay = 0.35      // seconds under both before a part counts as settled
settleDamp = 0.2        // velocity kept per step once it does

// How deeply two parts must interpenetrate before we call it an overlap.
// A little slack lets parts rest flush against each other without the
// editor calling that a collision.
overlapTolerance = 0.5

// Colors.
backdropColor = "#101820"
fieldColor = "#E7D2C1"
pegColor = "#243240"
floorColor = "#5A4632"
panelColor = "#2A3642"
panelEdgeColor = "#4A5A6A"
titleColor = "#C8D4E0"
labelColor = "#A0B0C0"
selectColor = "#50D0FF"
badColor = "#FF4040"
buttonColor = "#3C4C5C"
buttonHiColor = "#5C7C9C"
buttonIconColor = "#D8E4F0"
buttonOffColor = "#32404C"

// Where the pre-rendered art lives, and the layout of the ball sheets:
// `<name>_8x8_<diameter>.png`, 64 frames of one full turn.
picsDir = "/usr/pics/"
ballSheetCols = 8
ballFrameCount = 64

// Collision filtering.  Two shapes collide only if each one's category bit
// is in the other's mask.  The pieces of a lever are the only things that
// must ignore each other: the bar pivots right at the fulcrum's apex and
// carries its balance pans a couple of pixels clear, so all three would
// otherwise grind together for the whole of the bar's travel.  This filters
// a bar against every fulcrum and pan rather than just its own, which costs
// us nothing: no piece of a lever leaves its own part's footprint sideways,
// and design mode does not let two footprints overlap.
catDefault = 1
catFulcrum = 2
catPan = 4
maskBar = 65535 - catFulcrum - catPan
maskFulcrum = 65535 - catPan
maskPan = 65535 - catFulcrum

// A motor is the other assembly whose own pieces must ignore each other: its
// gearwheel turns on the face of the case behind it, and a gear meshing with
// that gearwheel reaches over the case as well -- so the filter is every hub
// against every case, not a motor's own.  The reasoning is the lever's: a
// case never leaves its part's footprint, and what a hub may sit on top of is
// already settled by the mesh distance rather than by the shapes.
catCase = 8
catHub = 16
maskCase = 65535 - catHub
maskHub = 65535 - catCase

// How far a lever may tip, if its own geometry does not stop it sooner, and
// how much steeper than that its fulcrum's sides are drawn, so that the bar
// never looks like it is cutting into the apex.
leverMaxTilt = 40 * pi / 180
leverFulcrumFlare = 20 * pi / 180

// One meter is this many pixels: gravity 980 px/s^2 against the real
// 9.8 m/s^2.  A part that wants to weigh a stated number of kilograms picks
// its density from this -- mass is density * area in pixels, so a density of
// 1 means one kilogram per square meter.
pxPerMeter = 100

// Ropes.  A taut rope is one scalar constraint -- its total path length,
// through however many pulleys -- solved by sequential impulses after each
// physics step, and then a second pass that puts right whatever length error
// is left by moving the bodies rather than by pushing them.  See rope.ms for
// why the usual trick of folding the error into the velocity solve is no
// good here.  slop is the stretch we let pass, so a rope at rest stops work.
ropeIterations = 8
ropePosIterations = 2
ropeSlop = 0.25

// A slack rope is not solved at all: it is a line of beads, run for looks
// only and never pushing back on the world.  See rope.ms.
ropeSegment = 10            // px of rope per bead
ropeChainIterations = 4
ropeChainDamp = 0.98
ropeChainCollide = true     // beads stop at the world's shapes (one way)

ropeColor = "#9A7248"
ropeWidth = 3
ropeArcSteps = 4            // segments drawn around a pulley's wrap

// Tie points: where a rope may be fastened.
tieSnap = 14                // px the mouse may be from one and still grab it
mountSnap = 28              // ...and from one to mount a pulley on it
tieRadius = 4
tieColor = "#2A3642A0"
tieHotColor = "#50D0FF"

// Gears.  Teeth are not simulated: two gears mesh because their pitch circles
// touch, and a set of meshed gears turns as one thing with one degree of
// freedom -- see torque.ms.  The module is the pitch diameter per tooth, and
// it is what lets gears of different sizes mesh with each other at all: 10/3
// gives the 12, 18 and 24-tooth gears pitch radii of 20, 30 and 40 px, so
// that a meshing pair has both its axles on the pegboard.
gearModule = 10 / 3
gearMeshTolerance = 2.5     // slop in the center distance that still meshes
gearColor = "#8A94A2"
gearHubColor = "#5A6672"
gearMotorColor = "#C06038"
gearArrowColor = "#FFE0A0"

// Torque in engine units per newton-meter, for the parts that produce it.
// Engine mass is density times area in pixels, so a kilogram is pxPerMeter^2
// of it; an arm of one meter is pxPerMeter pixels, and torque is mass times
// length squared over time squared -- hence pxPerMeter^4.
torqueUnit = pxPerMeter ^ 4

// Belts and the wheels they run on.  A belt is drawn as the two lines that
// touch both wheels and the wrap at each end; what it does is a ratio, and
// nothing else -- see torque.ms.
beltColor = "#33343C"
beltWidth = 4
beltArcSteps = 16           // segments drawn around a wheel's wrap
wheelColor = "#9AA4B0"
wheelRimColor = "#4A5460"

// Electricity.  A net is live or dead and nothing else -- no voltages, no
// currents, no component values -- so all of it is a flood fill over the
// wires; see circuit.ms and notes/electrical-parts.md.
//
// A wire is a rope that never pulls, drawn this much longer than the run it
// spans so that it visibly sags.  That is not decoration: a wire pulled
// straight reads as a rope, and a wire that reads as a rope will be expected
// to haul on what it is fastened to.
wireSlack = 1.10
wireColor = "#C05A18"       // orange, and brighter still when it is live
wireLiveColor = "#FF9030"
wireWidth = 3

// Terminals, which are to a wire what tie points are to a rope.  Drawn square
// where a tie point is round, so that the two are never mistaken.
termSnap = 14
termRadius = 4
termColor = "#3A2E1CA0"
termHotColor = "#FFC040"
termPostColor = "#C8A038"
// The head of a cord, drawn over whatever it is pushed into.  A part with a
// socket rather than a post says how big its own is; see Part.plugRadius.
plugRadius = 5

// The motor's case: the box the gearwheel turns on the front of.
motorCaseColor = "#556270"
motorVentColor = "#3A434E"
