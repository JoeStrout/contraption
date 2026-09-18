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

// Telling a click from a drag or a long press, for the second click on an
// already selected part -- which cycles its authored starting state.
clickTime = 0.35            // seconds a click may last
clickSlop = 4               // ...and px the mouse may wander in it

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

// Light.  A lamp or a flame lays a pool of light on the board: one pre-drawn
// radial gradient, laid over the parts as an ordinary sprite.  There is no
// shadow and no occlusion -- the pool simply sits where the light is -- which
// is all it has to do while nothing in the game asks what light *reaches*.
// See glow.ms.
//
// Whether the pool lies over the other parts or behind them.  Behind is the
// truer of the two -- light falls on the board, and a block in front of the
// lamp is lit on its own face, not washed out -- but in front is warmer, and
// which one looks better is a matter of taste.  See GameWorld.restackSprites.
glowInFront = false

// The lamp: a steady, wide, cool-white pool.
lampGlowColor = "#FFE8B0"
lampGlowAlpha = 0.5
lampGlowScale = 1           // 1 is the picture's own 234px across

// The candle: smaller, warmer, dimmer, and never quite still.  `flicker` is
// how far the pool swings either side of its size, in both its reach and its
// brightness at once; much past a fifth and it reads as a fault rather than a
// flame.
candleGlowColor = "#FFD088"
candleGlowAlpha = 0.4
candleGlowScale = 0.5
candleGlowFlicker = 0.12

// The candle's flame: the first particle effect, and the one every fire in
// the game will be built from.  The particle is the same radial gradient the
// pool of light is, shrunk right down -- a soft blob, which is what a flame
// is made of at this size -- so the scales below are fractions of 234px:
// 0.035 is about 8 pixels across.
//
// A flame is not a spray of debris.  It rises *faster* as it goes, because
// the gas is buoyant, and it narrows, because the hot column draws air in
// behind it: `flameRise` is the first and `flameTaper` the second.  See
// Flame in particles.ms.
flameCount = 24             // sprites the effect costs, forever
flameRate = 40              // born per second
flameLife = 0.35            // seconds, plus or minus
flameLifeVar = 0.08
flameSpeed = 34             // px/sec upward at birth, plus or minus
flameSpeedVar = 10
flameSpread = 0.25          // radians either side of straight up
flameWidth = 1.5            // px: how wide across the wick they are born
flameRise = 70              // px/sec^2 of buoyancy
flameTaper = 8              // how hard the column is pinched closed
flameStartScale = 0.035     // about 8px across: a flame is taller than wide
flameEndScale = 0.012
flameHotColor = "#FFF0A0D0" // at the wick...
flameCoolColor = "#FF400000" // ...and at the top, gone

// Heat: what is hot enough to light what.  A source carries `heat` and
// whatever might catch carries the `light` it takes, and the whole of the
// catalogue is those two numbers meeting.  See heat.ms.
candleHeat = 1              // a flame will light a fuse...
candleHeatRadius = 9
candleLightHeat = 0.9       // ...and it takes about a flame to light a wick
// ...and how fast the wick may be travelling before the flame is blown out.
// Measured at the wick rather than at the body, so that a candle whirled
// round on the end of a lever goes out although its middle has barely moved.
// 350 px/s is about 3.5 m/s: a candle knocked off a shelf is out before it
// lands, one merely shoved along a table is not.
candleBlowOutSpeed = 350
fuseHeat = 1                // a burning fuse is as hot as the flame that lit it
fuseHeatRadius = 7
fuseLightHeat = 0.5         // and a fuse is the easiest thing on the board to light

// The fuse: a stiff cord between two fastenings, which burns.
//
// Stiff is the whole of what makes it useful.  A rope and a wire hang, and a
// fuse that hung would only ever be able to light things lying on the floor,
// so this one is pinned to the board along the line it was run and stays
// there -- burning does not make it fall.
fuseColor = "#4A4038"
fuseWidth = 3
fuseEmberColor = "#FFA030"  // the last inch before the front
fuseEmberLength = 10
fuseBurnRate = 18           // px/sec, so a run across two grid cells is ~2s
fuseSampleStep = 5          // px between the points that ask whether they caught
// How near an end a catch has to be to count as that end catching, rather
// than as the fuse being lit in the middle and coming apart in two.
fuseEndSlop = 6
fuseGlowColor = "#FFB060"   // the little pool of light at the front
fuseGlowAlpha = 0.35
fuseGlowScale = 0.12

// Sparks off the burning front: a sparkler, which is what a fuse sounds like
// it should look like.  Unlike the flame these *are* a spray of debris --
// thrown out hard in every direction, slowed by the air and pulled down -- so
// they are a plain ParticleSystem with nothing subclassed at all, which is
// the thing that system was written to make easy.
//
// They are drawn from the same soft blob everything else here is, small and
// at full alpha, because a spark has to read as a *point of light* against a
// pale pegboard: translucent and it disappears, large and it is a fireball.
// How far they get is `speed / drag` -- about fifty pixels -- and not the
// speed alone, since the air has most of it within the first tenth of a
// second, which is also what gives the spray its shape.
sparkCount = 44             // sprites each front costs, forever
sparkRate = 70
sparkLife = 0.55
sparkLifeVar = 0.2
sparkSpeed = 170
sparkSpeedVar = 90
sparkSpread = pi            // every direction: a sparkler throws them all ways
sparkGravity = -220         // px/sec^2
sparkDrag = 2.5             // fraction of speed shed per second
sparkStartScale = 0.03      // about 7px of blob, whose core is a bright point
sparkEndScale = 0.008
sparkHotColor = "#FFFFF0FF" // white hot, and opaque, or it will not be seen
sparkCoolColor = "#FF500000"

// Explosives: a firecracker, which lies on its side, and a stick of dynamite,
// which stands up.  Both carry a short fuse of their own -- drawn art, walked
// by a timer, not a Fuse part -- so that lighting one straight from a candle
// still leaves you a moment to be somewhere else.  See parts/explosives.ms.
//
// A BLAST is one instant and three things: an impulse on everything within
// reach, a patch of heat while the fireball lasts, and whatever it breaks.
//
// The impulse falls off with the square of how far in the target is, and is
// applied at the point of each body *nearest* the blast rather than at its
// middle -- which is what tips a post over instead of sliding it, and is the
// same free torque a real blast gets.  It is stated here in kg*px/s, so that
// a 1 kg part at ground zero leaves at that many pixels a second; the engine
// wants it times pxPerMeter^2 (see Weight.density).
//
// What a blast BREAKS is the same two-constants arrangement heat uses: the
// blast carries a `power` and every part carries the power it takes to break
// it (Part.breakPower, zero for everything that cannot be broken at all).
// Only dynamite has any power, which is what makes it the one thing in the
// game that destroys a block or a platform.
explosiveLightHeat = 0.5    // its cap is as easy to light as a fuse...
explosiveFuseHeat = 1       // ...and burns as hot as one, so they chain
explosiveFuseHeatRadius = 7
explosionHeat = 1           // the fireball itself, while it lasts
explosionHeatFrac = 0.5     // of the blast radius: the fire, not the pressure
explosionFireTime = 0.2     // seconds it is hot for
explosionLinger = 2.5       // seconds of smoke before the wreck is swept up
explosionFlashTime = 0.18   // the white of the flash, fading and spreading
explosionFlashGrowth = 1.6  // how much wider it is by the time it is gone

firecrackerFuseTime = 1.2   // seconds from catching to going off
firecrackerBlastRadius = 70
firecrackerImpulse = 260    // kg*px/s at ground zero; see above
firecrackerPower = 0        // it breaks nothing at all
firecrackerBreakRadius = 0
firecrackerSparks = 26      // particles in the pop...
firecrackerSmoke = 0        // ...and no smoke to speak of
firecrackerFlashAlpha = 0.7
firecrackerFlashScale = 0.25
firecrackerSound = "/sys/sounds/blam.wav"
firecrackerVolume = 0.4

dynamiteFuseTime = 1.8
dynamiteBlastRadius = 190
dynamiteImpulse = 900
dynamitePower = 1           // enough for a block or a platform
dynamiteBreakRadius = 55    // ...within this much of the stick
dynamiteSparks = 48
dynamiteSmoke = 24
dynamiteFlashAlpha = 0.95
dynamiteFlashScale = 0.85
dynamiteSound = "/sys/sounds/airburst.wav"
dynamiteVolume = 0.85

// A ROCKET is an explosive that goes somewhere first.  Its fuse lights the
// motor rather than the charge: it climbs for rocketFlightTime and then goes
// off like a small stick of dynamite, wherever it has got to.
//
// Thrust is an acceleration, in px/sec^2, so that it reads against gravity
// (980) directly: the difference is what the rocket actually climbs at, and
// half that difference times the flight time squared is how high it gets.
//
// Until it is lit a rocket is PINNED -- it stands on the board and neither
// falls over nor falls down -- and the pin is broken by being lit, or by any
// blow hard enough to leave it moving faster than rocketFreeSpeed (or
// spinning faster than rocketFreeSpin) after a step.  Those two have to sit
// well above what one step of gravity alone adds, which is 980 * timestep.
rocketFuseTime = 1.0        // seconds from catching to lift-off
rocketFlightTime = 1.25     // ...and from lift-off to going off
rocketThrust = 1600         // px/sec^2, against gravity's 980
rocketFreeSpeed = 150       // px/sec of it after a step, and...
rocketFreeSpin = 3          // ...radians/sec, either of which breaks the pin
rocketBlastRadius = 150
rocketImpulse = 700         // kg*px/s at ground zero; see above
rocketPower = 1             // enough for a block or a platform, like dynamite
rocketBreakRadius = 40      // ...but it has to be closer
rocketSparks = 40
rocketSmoke = 18
rocketFlashAlpha = 0.9
rocketFlashScale = 0.7
rocketSound = "/sys/sounds/airburst.wav"
rocketVolume = 0.7
rocketLaunchSound = "/sys/sounds/swoosh.wav"
rocketLaunchVolume = 0.6

// The spray a blast throws: the fuse's sparks, harder and shorter-lived,
// since a blast is over at once where a sparkler goes on and on.
blastSparkLife = 0.55
blastSparkLifeVar = 0.25
blastSparkSpeed = 300
blastSparkSpeedVar = 170
blastSparkGravity = -300
blastSparkDrag = 2.2
blastSparkStartScale = 0.045
blastSparkEndScale = 0.01

// ...and the smoke, which is the same soft blob as everything else here, big
// and gray and slow.  It is thrown out in every direction like the sparks and
// then *rises*, because what is left after a blast is hot air.
smokeLife = 1.8
smokeLifeVar = 0.5
smokeSpeed = 70
smokeSpeedVar = 40
smokeDrag = 3
smokeRise = 30              // px/sec^2 of buoyancy
smokeStartScale = 0.07
smokeEndScale = 0.34
smokeStartColor = "#585048C0"
smokeEndColor = "#8A857E00"

// The trickle of sparks off an explosive's own fuse while it burns down: the
// warning that something is about to happen, and much quieter than the fuse
// part's sparkler, since this one is a few pixels long.
capSparkCount = 16
capSparkRate = 40
capSparkLife = 0.35
capSparkSpeed = 90
capSparkSpeedVar = 50
capSparkStartScale = 0.022
capSparkEndScale = 0.006

// The rocket's exhaust: the same bright blob as a spark, thrown hard out of
// the nozzle and left behind in world coordinates, which is what draws the
// trail.  It is not given any gravity -- it is burning gas, and it is gone
// long before gravity would have made a difference to it.
rocketExhaustCount = 40
rocketExhaustRate = 70
rocketExhaustLife = 0.4
rocketExhaustLifeVar = 0.15
rocketExhaustSpeed = 180
rocketExhaustSpeedVar = 80
rocketExhaustSpread = 0.35  // radians either side of straight out the tail
rocketExhaustDrag = 3
rocketExhaustStartScale = 0.05
rocketExhaustEndScale = 0.012
rocketExhaustHeatRadius = 12  // the flame out the back, which lights fuses
