#!/usr/bin/env python3
"""Render articulated-prop sprite strips for Contraption.

A prop here is a model that neither spins nor rolls: either one that opens and
closes, or one that just sits there.  Where make_balls.py renders one turn of a
sphere, this renders one sweep of a joint: frame 0 is fully open, the last frame
is fully shut, evenly spaced in joint angle.  A prop with no `joints` is a
single still frame, and says how to face the camera with `view` instead.

The camera does not move and the framing is computed once from every frame at
once, so a fixed point of the model (the scissors' pivot screw) stays on the
same pixel all the way through.

The joint is driven directly rather than by playing the model's own animation:
an authored animation has easing and usually loops open-shut-open, so sampling
it evenly in *time* would bunch the frames up at the ends.  We read only which
nodes turn and how far, and then space the frames evenly in angle.

Run it through Blender (there is no Blender module on the system python):

    blender -b --factory-startup -P make_props.py -- [options]

or just use ./render.sh, which finds Blender for you.
"""

import argparse
import math
import os
import shutil
import sys

import numpy as np
import bpy
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# What to render.  Add a dict here to get another prop.
#
#   size     [width, height] of one frame in pixels
#   frames   how many steps from open to shut
#   joints   the objects that move, by glTF node name, each with the angle
#            (degrees) it is turned at frame 0; they all reach 0 at the last
#            frame.  Signs are opposite for the two halves of a scissors.
#   axis     the joints' local rotation axis, as Blender holds it after import
#            (not as the glTF file writes it -- see the note on scissors)
#   open     scale on every joint angle, for opening wider or less wide than
#            the model's own animation does
#   view     for a prop with no joints, which way it faces: yaw spins it about
#            its own upright axis, pitch tips its top toward the camera.  A
#            jointless prop has nothing to measure an orientation from, and
#            models of this kind arrive upright anyway.
# ---------------------------------------------------------------------------

PROPS = [
	# "Scissors (Low Poly)" by game_travel, CC-BY-4.0 -- see art-attribution.txt
	dict(name="scissors", size=[48, 32], frames=8, open=0.6,
	     model="../models/scissors_low_poly.glb",
	     # Signs matter: the other way round, the two halves open by swinging
	     # through each other, which reads as the handles passing through the
	     # frame where they should be spreading apart.
	     joints={"Obj_Scissors_2": -30.0, "Obj_Scissors.001_4": 30.0},
	     # glTF has the hinge on the nodes' local Z, but Blender's importer
	     # turns the model Y-up to Z-up, which lands it on -Y.  check_axis
	     # below catches this if a new prop gets it wrong.
	     axis=(0, 1, 0),
	     # The model is one flat white material, which at 48x24 disappears
	     # against the playfield.  Steel blades and a saturated handle are
	     # what make the silhouette read at this size.
	     materials=dict(blade="#9FB0BE", handle="#D8481F", split=-0.12)),
	# The cell is 3:2 because that is the shape the prop actually makes: the
	# shut pose sets the width, the open pose sets the height, and at this
	# gape those come out at about 1.45:1.  A 2:1 cell left a third of every
	# frame empty and shrank the scissors to fit the height.

	# "[REMAKE] - Net basket" by RaynaudL, CC-BY-4.0 -- see art-attribution.txt
	dict(name="basket", size=[48, 48], frames=1,
	     model="../models/wicker_basket.glb",
	     # Straight from the side, with no pitch: the playfield is seen dead
	     # on, and any pitch looks down into the basket from a camera the rest
	     # of the game does not have.  Yaw 0 puts the handle across the screen
	     # rather than edge on, and the silhouette comes out 0.93 wide to
	     # tall, so a square cell wastes almost nothing.
	     view=dict(yaw=0.0, pitch=0.0)),
]

# Padding around the model, as a fraction of the frame.  Unlike the balls --
# which are framed edge to edge, so that the sprite size is the diameter -- a
# prop wants a little air: its silhouette changes shape as it opens, and a
# blade tip landing exactly on the last pixel column looks clipped.
MARGIN = 0.04


# ---------------------------------------------------------------------------
# scene
# ---------------------------------------------------------------------------

def add_light(name, kind, direction, energy, color=(1, 1, 1), glossy=True):
	data = bpy.data.lights.new(name, kind)
	data.energy = energy
	data.color = color
	if kind == "SUN":
		data.angle = math.radians(12)
	obj = bpy.data.objects.new(name, data)
	bpy.context.collection.objects.link(obj)
	d = Vector(direction).normalized()
	obj.location = -d * 8.0
	obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
	if not glossy:
		# One specular highlight looks like a light source; three look like
		# smudges.  Steel shows this far more than a matte ball does.
		obj.visible_glossy = False
		data.specular_factor = 0.0
	return obj


def build_scene(args):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene

	cam_data = bpy.data.cameras.new("Cam")
	cam_data.type = "ORTHO"
	cam = bpy.data.objects.new("Cam", cam_data)
	# Straight down -Z with +Y up, so world X/Y are screen X/Y.
	cam.location = (0, 0, 6)
	cam.rotation_euler = (0, 0, 0)
	bpy.context.collection.objects.link(cam)
	scene.camera = cam

	add_light("key", "SUN", (1.0, -0.9, -0.75), 1.6, (1.0, 0.97, 0.92))
	add_light("fill", "SUN", (-0.8, 0.5, -0.9), 0.4, (0.75, 0.82, 1.0),
	          glossy=False)
	add_light("rim", "SUN", (-0.2, 0.9, 0.35), 0.55, (1.0, 1.0, 1.0),
	          glossy=False)

	world = bpy.data.worlds.new("World")
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs[0].default_value = (0.18, 0.20, 0.24, 1.0)
	bg.inputs[1].default_value = 0.25
	scene.world = world

	scene.render.engine = ("CYCLES" if args.engine == "cycles"
	                       else "BLENDER_EEVEE_NEXT")
	if args.engine == "cycles":
		scene.cycles.samples = args.samples
		scene.cycles.use_denoising = True
		scene.cycles.device = "CPU"
	else:
		scene.eevee.taa_render_samples = args.samples
	scene.render.film_transparent = True
	scene.render.image_settings.file_format = "PNG"
	scene.render.image_settings.color_mode = "RGBA"
	scene.render.image_settings.color_depth = "8"
	scene.view_settings.view_transform = "Standard"
	scene.view_settings.look = "None"
	return cam


# ---------------------------------------------------------------------------
# the model
# ---------------------------------------------------------------------------

def import_model(spec, here):
	path = spec["model"]
	if not os.path.isabs(path):
		path = os.path.normpath(os.path.join(here, path))
	if not os.path.exists(path):
		sys.exit("model not found: %s" % path)
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	imported = [o for o in bpy.data.objects if o not in before]
	if not imported:
		sys.exit("nothing imported from %s" % path)
	for obj in imported:
		# The model's own animation would fight the poses we set below.
		obj.animation_data_clear()
	return imported


def find_joints(spec, imported):
	"""Match the configured node names to imported objects.  Blender uniquifies
	names on collision, so match by prefix rather than equality."""
	out = []
	for name, angle in spec.get("joints", {}).items():
		hits = [o for o in imported if o.name == name or
		        o.name.startswith(name + ".")]
		if not hits:
			sys.exit("joint %r not found among: %s"
			         % (name, ", ".join(sorted(o.name for o in imported))))
		out.append((hits[0], math.radians(angle) * spec.get("open", 1.0)))
	return out


def pose(joints, spec, t):
	"""Set every joint to fraction t of its open angle (1 = open, 0 = shut).
	A prop with no joints has no axis either, and this does nothing."""
	axis = spec.get("axis", (0, 0, 1))
	for obj, angle in joints:
		obj.rotation_mode = "AXIS_ANGLE"
		obj.rotation_axis_angle = (angle * t, axis[0], axis[1], axis[2])
	bpy.context.view_layer.update()


def world_verts(objs):
	"""Every mesh vertex in world space, as one (n, 3) array."""
	chunks = []
	for obj in objs:
		if obj.type != "MESH" or not obj.data.vertices:
			continue
		n = len(obj.data.vertices)
		co = np.empty(n * 3, dtype=np.float32)
		obj.data.vertices.foreach_get("co", co)
		co = co.reshape(n, 3)
		m = obj.matrix_world
		rot = np.array([[m[r][c] for c in range(3)] for r in range(3)])
		off = np.array([m[r][3] for r in range(3)])
		chunks.append(co @ rot.T + off)
	if not chunks:
		sys.exit("model has no mesh vertices")
	return np.vstack(chunks)


def check_axis(imported, joints, spec):
	"""Fail loudly if the joints turn about the wrong axis.

	A prop like this is flat, and its joint is meant to swing within that flat
	plane.  Turning about one of the other two axes swings it out of the plane
	instead, which is easy to do -- the axis the model file names is not the
	axis Blender ends up with -- and renders as a strip whose frames all look
	much alike, rather than as an error.  So: opening it must not thicken it.
	"""
	pose(joints, spec, 0.0)
	shut = world_verts(imported).ptp(0)
	thin = int(np.argmin(shut))
	pose(joints, spec, 1.0)
	wide = world_verts(imported).ptp(0)
	if wide[thin] > 1.5 * shut[thin]:
		sys.exit("joint axis %s swings %s out of its own plane (thickness "
		         "%.4f -> %.4f on opening); pick the axis the hinge really "
		         "turns about" % (spec["axis"], spec["name"], shut[thin],
		                          wide[thin]))


def orient(imported, joints, spec):
	"""Turn the model so it lies flat to the camera with its business end to
	the right, and return the empty it is now parented to.

	This is measured rather than configured, so a new prop does not need its
	Euler angles dialled in by hand: the thinnest axis of the silhouette is the
	one we should be looking down, the longest is the one that should run
	across the screen, and the pointed end of that long axis is the end that
	should face right -- for anything tool-shaped, the working end is the end
	that tapers.
	"""
	if not joints:
		return orient_by_view(imported, spec)

	# Measure shut, not open.  Open, *both* ends are spread wide -- the
	# handles most of all, being the longer arms -- and the taper test below
	# reads that as the pointed end and mirrors the prop.  Shut, the two
	# halves lie on top of each other and the only thing separating the ends
	# is the shape we actually mean to test.
	pose(joints, spec, 0.0)
	v = world_verts(imported)
	centre = (v.min(0) + v.max(0)) / 2.0
	extent = v.max(0) - v.min(0)
	thin = int(np.argmin(extent))
	long_ = int(np.argmax(extent))
	side = ({0, 1, 2} - {thin, long_}).pop()

	# Which end of the long axis tapers?  Compare the spread across the other
	# two axes over the outermost tenth of each end.
	lo, hi = v[:, long_].min(), v[:, long_].max()
	span = hi - lo
	def spread(mask):
		s = v[mask]
		return np.hypot(s[:, side].std(), s[:, thin].std())
	at_lo = spread(v[:, long_] < lo + 0.1 * span)
	at_hi = spread(v[:, long_] > hi - 0.1 * span)
	tip_is_hi = at_hi < at_lo

	# Build the rotation that takes those three model axes to screen X, Y, Z.
	basis = np.zeros((3, 3))
	basis[0, long_] = 1.0 if tip_is_hi else -1.0    # long axis -> screen X
	basis[2, thin] = 1.0                            # thin axis -> toward camera
	basis[1] = np.cross(basis[2], basis[0])         # keep it right-handed

	empty = bpy.data.objects.new("prop", None)
	bpy.context.collection.objects.link(empty)
	m = Matrix.Identity(4)
	for r in range(3):
		for c in range(3):
			m[r][c] = basis[r][c]
	fix = m @ Matrix.Translation(Vector(-centre))
	for obj in imported:
		if obj.parent is None:
			obj.parent = empty
			obj.matrix_parent_inverse = Matrix.Identity(4)
	empty.matrix_world = fix
	bpy.context.view_layer.update()
	return empty


def orient_by_view(imported, spec):
	"""Face a jointless prop at the camera by the angles it asks for.

	orient() measures its rotation from the silhouette, which needs a shut pose
	to measure and a tapering working end to point right; a basket has neither.
	What it does have is glTF's own up axis, which the importer turns into +Z,
	so the whole job is standing that up on screen: -90 degrees about X puts
	model +Z on screen +Y.  `pitch` past that tips the top toward the camera,
	and `yaw` spins the prop about its own upright axis first.
	"""
	view = spec.get("view", {})
	v = world_verts([o for o in imported if o.type == "MESH"])
	centre = (v.min(0) + v.max(0)) / 2.0

	rot = (Matrix.Rotation(math.radians(view.get("pitch", 0.0) - 90.0), 4, "X")
	       @ Matrix.Rotation(math.radians(view.get("yaw", 0.0)), 4, "Z"))

	empty = bpy.data.objects.new("prop", None)
	bpy.context.collection.objects.link(empty)
	for obj in imported:
		if obj.parent is None:
			obj.parent = empty
			obj.matrix_parent_inverse = Matrix.Identity(4)
	empty.matrix_world = rot @ Matrix.Translation(Vector(-centre))
	bpy.context.view_layer.update()
	return empty


def hex_to_linear(h):
	h = h.lstrip("#")
	srgb = np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
	return np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)


def make_material(name, hex_color, roughness, metallic):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	rgb = hex_to_linear(hex_color)
	bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
	bsdf.inputs["Roughness"].default_value = roughness
	if "Metallic" in bsdf.inputs:
		bsdf.inputs["Metallic"].default_value = metallic
	return mat


def recolor(imported, spec):
	"""Replace the model's materials with a blade colour and a handle colour,
	split along the long axis.

	The split is geometric rather than per-object because each half of the
	scissors is one mesh running handle to tip: there is no object boundary at
	the grip, only a place along its length where steel becomes plastic.  The
	split is given relative to the pivot, as a fraction of the model's length,
	so the steel shank can reach back behind the screw the way a real pair
	does.  Run this after orient(), where the long axis is world X.
	"""
	mats = spec.get("materials")
	if not mats:
		return
	blade = make_material("blade", mats["blade"], 0.28, 0.85)
	handle = make_material("handle", mats["handle"], 0.45, 0.0)

	meshes = [o for o in imported if o.type == "MESH" and o.data.vertices]
	v = world_verts(meshes)
	length = v[:, 0].max() - v[:, 0].min()
	pivot = float(np.median(v[:, 0]))
	for name in (spec.get("pivot"), "Obj_Screw"):
		if not name:
			continue
		hits = [o for o in meshes if o.name.startswith(name) or
		        (o.parent is not None and o.parent.name.startswith(name))]
		if hits:
			pv = world_verts(hits)
			pivot = float((pv[:, 0].min() + pv[:, 0].max()) / 2.0)
			break
	cut = pivot + mats.get("split", 0.0) * length

	for obj in meshes:
		obj.data.materials.clear()
		obj.data.materials.append(blade)
		obj.data.materials.append(handle)
		m = obj.matrix_world
		for poly in obj.data.polygons:
			c = m @ poly.center
			poly.material_index = 0 if c.x >= cut else 1


def frame_bounds(imported, joints, spec, frames):
	"""The box that holds the model in every frame, so the camera can be fixed
	and the pivot stays put from frame to frame."""
	lo = np.array([1e18, 1e18, 1e18])
	hi = -lo
	for i in range(frames):
		pose(joints, spec, openness(i, frames))
		v = world_verts(imported)
		lo = np.minimum(lo, v.min(0))
		hi = np.maximum(hi, v.max(0))
	return lo, hi


def openness(i, frames):
	"""Frame 0 is wide open, the last frame is shut."""
	if frames <= 1:
		return 0.0
	return 1.0 - i / (frames - 1.0)


# ---------------------------------------------------------------------------
# render / compositing
# ---------------------------------------------------------------------------

def load_rgba(path):
	img = bpy.data.images.load(path)
	w, h = img.size
	buf = np.empty(w * h * 4, dtype=np.float32)
	img.pixels.foreach_get(buf)
	bpy.data.images.remove(img)
	return buf.reshape(h, w, 4)          # bottom-up rows, linear, straight alpha


def downsample(rgba, factor):
	if factor == 1:
		return rgba
	h, w = rgba.shape[0] // factor, rgba.shape[1] // factor
	# Average premultiplied, or partly-covered edge pixels drag the background
	# colour of fully transparent texels into the rim.
	pm = rgba.copy()
	pm[..., :3] *= pm[..., 3:4]
	pm = pm.reshape(h, factor, w, factor, 4).mean(axis=(1, 3))
	a = pm[..., 3:4]
	out = pm.copy()
	np.divide(out[..., :3], a, out=out[..., :3], where=a > 1e-6)
	out[..., :3] = np.where(a > 1e-6, out[..., :3], 0.0)
	return out


def save_rgba(rgba, path):
	h, w = rgba.shape[:2]
	img = bpy.data.images.new(os.path.basename(path), width=w, height=h,
	                          alpha=True, float_buffer=True)
	img.colorspace_settings.name = "sRGB"
	img.alpha_mode = "STRAIGHT"
	img.pixels.foreach_set(np.ascontiguousarray(rgba, np.float32).ravel())
	img.file_format = "PNG"
	# save_render, not save: save writes the float buffer as 16-bit PNG, which
	# doubles the file for precision nothing downstream can use.  save_render
	# goes through the scene's image settings, where color_depth is 8.
	img.save_render(filepath=path, scene=bpy.context.scene)
	bpy.data.images.remove(img)


def supersample_for(size, args):
	if args.supersample:
		return args.supersample
	# Render at roughly 200px on the long side whatever the sprite size, so a
	# small prop gets as much edge detail as a big one.
	return max(2, min(8, int(round(200.0 / max(size)))))


def render_prop(spec, args, tmpdir):
	cam = build_scene(args)
	imported = import_model(spec, args.here)
	joints = find_joints(spec, imported)
	if joints:
		check_axis(imported, joints, spec)
	orient(imported, joints, spec)
	recolor(imported, spec)

	frames = args.frames or spec.get("frames", 8)
	width, height = args.size or spec["size"]
	lo, hi = frame_bounds(imported, joints, spec, frames)

	# Fit the box into the frame without distorting it, and centre the camera
	# on it.  Blender's ortho_scale measures the view along whichever of the
	# two resolutions is larger, so which axis we solve for depends on shape.
	centre = (lo + hi) / 2.0
	need = (hi - lo)[:2] / (1.0 - 2.0 * args.margin)
	if width >= height:
		ortho = max(need[0], need[1] * width / height)
	else:
		ortho = max(need[1], need[0] * height / width)
	cam.data.ortho_scale = ortho
	# Stand the camera clear of the model along its own depth, and open the
	# clip range to match.  A prop keeps the model's units -- nothing here
	# scales it the way make_balls.py does -- so a big model reaches past a
	# camera parked at a fixed distance, and its near face is sliced off by
	# the near clip plane.  That reads as a hole in the front of the prop
	# rather than as an error.
	depth = float(hi[2] - lo[2])
	standoff = depth + max(1.0, depth)
	cam.location = (centre[0], centre[1], hi[2] + standoff)
	cam.data.clip_start = standoff / 2.0
	cam.data.clip_end = standoff + depth * 2.0 + 1.0

	scene = bpy.context.scene
	ss = supersample_for([width, height], args)
	scene.render.resolution_x = width * ss
	scene.render.resolution_y = height * ss
	scene.render.resolution_percentage = 100

	out_dir = os.path.join(args.out, "%s_%dx%d" % (spec["name"], width, height))
	if args.write_frames:
		os.makedirs(out_dir, exist_ok=True)

	strip = np.zeros((height, width * frames, 4), dtype=np.float32)
	for i in range(frames):
		pose(joints, spec, openness(i, frames))
		tmp = os.path.join(tmpdir, "frame")
		scene.render.filepath = tmp
		bpy.ops.render.render(write_still=True)
		rgba = downsample(load_rgba(tmp + ".png"), ss)
		if args.write_frames:
			save_rgba(rgba, os.path.join(out_dir, "frame_%02d.png" % i))
		strip[:, i * width:(i + 1) * width] = rgba
		print("  %s frame %d/%d (open %.2f)"
		      % (spec["name"], i + 1, frames, openness(i, frames)))

	if frames == 1:
		path = os.path.join(args.out, "%s_%dx%d.png"
		                    % (spec["name"], width, height))
	else:
		path = os.path.join(args.out, "%s_%dx1_%dx%d.png"
		                    % (spec["name"], frames, width, height))
	save_rgba(strip, path)
	print("wrote %s" % path)


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	here = os.path.dirname(os.path.abspath(__file__))
	p = argparse.ArgumentParser(prog="make_props.py")
	p.add_argument("--out", default=os.path.join(here, "out"))
	p.add_argument("--only", action="append", default=[])
	p.add_argument("--all", action="store_true")
	p.add_argument("--frames", type=int, default=None)
	p.add_argument("--size", type=int, nargs=2, default=None,
	               metavar=("W", "H"))
	p.add_argument("--supersample", type=int, default=0)
	p.add_argument("--samples", type=int, default=64)
	p.add_argument("--engine", choices=["cycles", "eevee"], default="cycles")
	p.add_argument("--margin", type=float, default=MARGIN)
	p.add_argument("--open", type=float, default=None, dest="open_scale",
	               help="scale every joint angle, for a wider or narrower gape")
	p.add_argument("--yaw", type=float, default=None,
	               help="override a jointless prop's yaw, for finding a view")
	p.add_argument("--pitch", type=float, default=None,
	               help="override a jointless prop's pitch")
	p.add_argument("--write-frames", action="store_true")
	p.add_argument("--as-modelled", action="store_true",
	               help="keep the model's own materials instead of recolouring")
	args = p.parse_args(argv)
	args.here = here

	os.makedirs(args.out, exist_ok=True)
	tmpdir = os.path.join(args.out, ".tmp")
	os.makedirs(tmpdir, exist_ok=True)

	if args.only:
		todo = [s for s in PROPS if s["name"] in args.only]
	else:
		todo = [s for s in PROPS if args.all or not s.get("skip")]
	if not todo:
		sys.exit("no props matched %s" % args.only)
	try:
		for spec in todo:
			if (args.as_modelled or args.open_scale is not None
					or args.yaw is not None or args.pitch is not None):
				spec = dict(spec)
				if args.as_modelled:
					spec.pop("materials", None)
				if args.open_scale is not None:
					spec["open"] = args.open_scale
				view = dict(spec.get("view", {}))
				if args.yaw is not None:
					view["yaw"] = args.yaw
				if args.pitch is not None:
					view["pitch"] = args.pitch
				if view:
					spec["view"] = view
			render_prop(spec, args, tmpdir)
	finally:
		shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
	main()
