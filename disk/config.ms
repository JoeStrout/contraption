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
