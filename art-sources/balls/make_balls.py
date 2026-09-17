#!/usr/bin/env python3
"""Render rotating-ball sprite sheets for Contraption.

A 2D physics circle has only one degree of freedom -- its rotation about the
axis pointing out of the screen -- so that is the axis we spin the sphere
around, and the camera looks straight down it.  Frame i is the ball turned
i * 360/frames degrees counterclockwise, which is exactly Mini Micro's
Sprite.rotation convention, so the game can do:

    frameIndex = round(rotationDegrees / (360/frames)) % frames

Run it through Blender (there is no Blender module on the system python):

    blender -b --factory-startup -P make_balls.py -- [options]

or just use ./render.sh, which finds Blender for you.
"""

import argparse
import math
import os
import shutil
import sys

import numpy as np
import bpy
from mathutils import Euler, Matrix, Vector

# ---------------------------------------------------------------------------
# What to render.  Add a dict here to get another ball.
#
#   sizes    pixel width/height of one frame, and so also the ball's diameter,
#            since the sphere is framed edge to edge (see MARGIN); a ball can
#            list several, and each gets its own sheet
#   skip     true to leave it out of a plain run (--only still finds it)
#   pattern  one of the make_*_texture functions below
#   base / accent / accent2   sRGB hex, meaning depends on the pattern
#   tilt     degrees about X/Y/Z applied once before the spin, so the pattern
#            is not staring straight down the camera (see TILT)
#   model    a file to import instead of building a patterned sphere
# ---------------------------------------------------------------------------

BALLS = [
	dict(name="ball-star",  sizes=[32, 40], pattern="star",
	     base="#d8321f", accent="#f5f0e6", accent2="#ffcf3f",
	     tilt=(26.0, -19.0, 7.0)),
	# "Bowling ball" by Diversant-ka, CC-BY-4.0 -- see art-attribution.txt
	dict(name="ball-bowling", sizes=[40],
	     model="../models/bowling_ball.glb",
	     # this model has a single hole, about 30 degrees off its pole; near
	     # 180 it faces us and orbits the centre as the ball spins, which at
	     # 40px is the only thing that reads as rotation
	     tilt=(172.0, 9.0, 14.0)),
	# "Tennis Ball" by Arman.Abgaryan, CC-BY-4.0 -- see art-attribution.txt
	dict(name="ball-tennis", sizes=[20],
	     model="../models/tennis_ball.glb",
	     tilt=(33.0, -24.0, 17.0)),
	# "Soccer Ball" by typhomnt, CC-BY-4.0 -- see art-attribution.txt
	dict(name="ball-soccer", sizes=[40],
	     model="../models/soccer_ball/scene.gltf",
	     tilt=(21.0, 34.0, -13.0)),

	# --- not currently used by the game; render with --only or --all --------
	dict(name="ball-beach", sizes=[64], pattern="beach", skip=True,
	     base="#f5f0e6", accent="#1f7ad8", accent2="#e8b820",
	     tilt=(-31.0, 14.0, 23.0)),
	dict(name="ball-dots",  sizes=[48], pattern="dots", skip=True,
	     base="#2f9e4f", accent="#f5f0e6", accent2="#f5f0e6",
	     tilt=(18.0, 27.0, -11.0)),
	# A latitude-only pattern (plain "stripe") is symmetric about the spin
	# axis and so looks motionless; the small ball gets dots instead.
	dict(name="ball-steel", sizes=[32], pattern="dots", skip=True,
	     base="#9aa3ad", accent="#4a525c", accent2="#4a525c",
	     dot_count=10, dot_deg=26, roughness=0.22, metallic=0.35,
	     tilt=(-22.0, -13.0, 29.0)),
]

# Default pre-spin tilt.  Without it the pattern faces the camera dead-on for
# all 64 frames, which reads as a flat disc turning rather than a ball.
TILT = (23.0, -17.0, 9.0)

# The sphere spans the frame exactly, so sprite size == ball diameter in
# pixels.  Raise this if you want padding (and then diameter = size/(1+margin)).
MARGIN = 0.0

TEX_SIZE = 1024          # equirectangular texture width (height is half)
TEX_SUPERSAMPLE = 2      # pattern is drawn at this multiple, then box-filtered


# ---------------------------------------------------------------------------
# colour helpers
# ---------------------------------------------------------------------------

def hex_to_srgb(h):
	h = h.lstrip("#")
	return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
	c = np.asarray(c, dtype=np.float32)
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_rgb(hex_color):
	return srgb_to_linear(hex_to_srgb(hex_color))


# ---------------------------------------------------------------------------
# textures
#
# Every pattern is evaluated in 3D on the sphere's surface rather than in UV
# space: a star drawn straight into an equirectangular image would be smeared
# into a sunburst by the pole pinch.  We build theta/phi from the UVs, turn
# those into directions, and test the shape there.
# ---------------------------------------------------------------------------

def _sphere_grid(w, h):
	"""theta (0 at +Z pole .. pi at -Z) and phi (0..2pi) per texel."""
	u = (np.arange(w, dtype=np.float32) + 0.5) / w
	v = (np.arange(h, dtype=np.float32) + 0.5) / h
	uu, vv = np.meshgrid(u, v)
	theta = (1.0 - vv) * math.pi
	phi = uu * 2.0 * math.pi
	return theta, phi


def _point_in_poly(px, py, verts):
	"""Vectorised crossing-number test; the star is concave, so half-planes
	are not enough."""
	inside = np.zeros(px.shape, dtype=bool)
	n = len(verts)
	for i in range(n):
		x0, y0 = verts[i]
		x1, y1 = verts[(i + 1) % n]
		straddles = (y0 > py) != (y1 > py)
		with np.errstate(divide="ignore", invalid="ignore"):
			xint = (x1 - x0) * (py - y0) / (y1 - y0) + x0
		inside ^= straddles & (px < xint)
	return inside


def _star_verts(points=5, inner=0.42, phase=math.pi / 2):
	verts = []
	for i in range(points * 2):
		r = 1.0 if i % 2 == 0 else inner
		a = phase + i * math.pi / points
		verts.append((r * math.cos(a), r * math.sin(a)))
	return verts


def _polar_cap_mask(theta, phi, cap, shape_verts, north=True):
	"""Azimuthal-equidistant projection of a polar cap onto the unit disk,
	then a polygon test in that disk -- so the shape keeps its proportions."""
	t = theta if north else (math.pi - theta)
	r = t / cap
	inside_cap = r <= 1.0
	px = r * np.cos(phi)
	py = r * np.sin(phi)
	return inside_cap & _point_in_poly(px, py, shape_verts)


def make_star_texture(theta, phi, spec):
	"""Stripe around the middle, big star on each pole.  Viewed down the spin
	axis the stripe reads as a rim band and the star as the ball's face."""
	rgb = np.empty(theta.shape + (3,), dtype=np.float32)
	rgb[:] = linear_rgb(spec["base"])

	stripe = np.abs(theta - math.pi / 2) < math.radians(spec.get("stripe_deg", 20))
	rgb[stripe] = linear_rgb(spec["accent2"])

	star = _star_verts(spec.get("star_points", 5), spec.get("star_inner", 0.42))
	cap = math.radians(spec.get("star_cap_deg", 46))
	for north in (True, False):
		m = _polar_cap_mask(theta, phi, cap, star, north)
		rgb[m] = linear_rgb(spec["accent"])
	return rgb


def make_beach_texture(theta, phi, spec):
	"""Classic beach ball: wedges of longitude, plain caps."""
	rgb = np.empty(theta.shape + (3,), dtype=np.float32)
	wedges = spec.get("wedges", 6)
	idx = np.floor(phi / (2 * math.pi / wedges)).astype(int) % 2
	rgb[idx == 0] = linear_rgb(spec["base"])
	rgb[idx == 1] = linear_rgb(spec["accent"])
	# a second colour on every fourth wedge keeps it from looking striped
	idx4 = np.floor(phi / (2 * math.pi / wedges)).astype(int) % 4
	rgb[idx4 == 3] = linear_rgb(spec["accent2"])

	cap = math.radians(spec.get("cap_deg", 14))
	rgb[theta < cap] = linear_rgb(spec["base"])
	rgb[theta > math.pi - cap] = linear_rgb(spec["base"])
	return rgb


def make_stripe_texture(theta, phi, spec):
	rgb = np.empty(theta.shape + (3,), dtype=np.float32)
	rgb[:] = linear_rgb(spec["base"])
	half = math.radians(spec.get("stripe_deg", 12))
	for centre in spec.get("stripe_centres", (90.0,)):
		c = math.radians(centre)
		rgb[np.abs(theta - c) < half] = linear_rgb(spec["accent"])
	return rgb


def _directions(theta, phi):
	st = np.sin(theta)
	return np.stack([st * np.cos(phi), st * np.sin(phi), np.cos(theta)], axis=-1)


def make_dots_texture(theta, phi, spec):
	"""Dots on a Fibonacci sphere, so they stay evenly spaced and round."""
	rgb = np.empty(theta.shape + (3,), dtype=np.float32)
	rgb[:] = linear_rgb(spec["base"])

	dirs = _directions(theta, phi)

	n = spec.get("dot_count", 18)
	cos_r = math.cos(math.radians(spec.get("dot_deg", 20)))
	golden = math.pi * (3.0 - math.sqrt(5.0))
	accent = linear_rgb(spec["accent"])
	for i in range(n):
		z = 1.0 - (2.0 * i + 1.0) / n
		r = math.sqrt(max(0.0, 1.0 - z * z))
		a = i * golden
		p = np.array([r * math.cos(a), r * math.sin(a), z], dtype=np.float32)
		rgb[dirs @ p > cos_r] = accent
	return rgb


PATTERNS = {
	"star": make_star_texture,
	"beach": make_beach_texture,
	"stripe": make_stripe_texture,
	"dots": make_dots_texture,
}


def build_texture_image(spec):
	ss = TEX_SUPERSAMPLE
	w, h = TEX_SIZE * ss, TEX_SIZE // 2 * ss
	theta, phi = _sphere_grid(w, h)
	rgb = PATTERNS[spec["pattern"]](theta, phi, spec)

	# box-filter the supersampled pattern; it is linear light, so a plain
	# mean is the right average
	if ss > 1:
		h2, w2 = h // ss, w // ss
		rgb = rgb.reshape(h2, ss, w2, ss, 3).mean(axis=(1, 3))

	img = bpy.data.images.new(spec["name"] + "-tex", width=rgb.shape[1],
	                          height=rgb.shape[0], alpha=False, float_buffer=True)
	# Non-Color: the values we wrote are already linear, so nothing should
	# touch them on the way into the shader.
	img.colorspace_settings.name = "Non-Color"
	rgba = np.concatenate([rgb, np.ones(rgb.shape[:2] + (1,), np.float32)], axis=-1)
	img.pixels.foreach_set(rgba.ravel())
	img.pack()
	return img


# ---------------------------------------------------------------------------
# scene
# ---------------------------------------------------------------------------

def clear_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def add_light(name, kind, direction, energy, color=(1, 1, 1), size=3.0,
              glossy=True):
	data = bpy.data.lights.new(name, kind)
	data.energy = energy
	data.color = color
	if kind == "SUN":
		data.angle = math.radians(12)   # soft-ish terminator
	else:
		data.size = size
	obj = bpy.data.objects.new(name, data)
	bpy.context.collection.objects.link(obj)
	d = Vector(direction).normalized()
	obj.location = -d * 8.0
	obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
	if not glossy:
		# One specular highlight looks like a light source; three look like
		# smudges, so only the key gets to make one.
		obj.visible_glossy = False          # Cycles
		data.specular_factor = 0.0          # EEVEE
	return obj


def build_scene(args):
	"""Everything that does not depend on which ball we are rendering.
	Returns the empty whose Z rotation is the spin."""
	clear_scene()
	scene = bpy.context.scene

	spin = bpy.data.objects.new("spin", None)
	bpy.context.collection.objects.link(spin)

	cam_data = bpy.data.cameras.new("Cam")
	cam_data.type = "ORTHO"
	cam_data.ortho_scale = 2.0 * (1.0 + args.margin)
	cam = bpy.data.objects.new("Cam", cam_data)
	# Straight down -Z with +Y up: world X/Y become screen X/Y, so a +Z object
	# rotation is a counterclockwise spin on screen.
	cam.location = (0, 0, 6)
	cam.rotation_euler = (0, 0, 0)
	bpy.context.collection.objects.link(cam)
	scene.camera = cam

	# Key from the upper left and toward the viewer; the lights do not move
	# with the ball, so the highlight stays put while the pattern spins.
	add_light("key", "SUN", (1.0, -0.9, -0.75), 1.5, (1.0, 0.97, 0.92))
	add_light("fill", "SUN", (-0.8, 0.5, -0.9), 0.35, (0.75, 0.82, 1.0),
	          glossy=False)
	add_light("rim", "SUN", (-0.2, 0.9, 0.35), 0.5, (1.0, 1.0, 1.0),
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
	# AgX would wash the flat game colours out; we want what we authored.
	scene.view_settings.view_transform = "Standard"
	scene.view_settings.look = "None"
	return spin


def tilt_matrix(spec):
	tilt = spec.get("_tilt_override") or spec.get("tilt", TILT)
	return Euler([math.radians(a) for a in tilt], "XYZ").to_matrix().to_4x4()


def add_procedural_ball(spec, spin):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, radius=1.0)
	ball = bpy.context.object
	bpy.ops.object.shade_smooth()
	apply_material(ball, spec, build_texture_image(spec))
	ball.parent = spin
	ball.matrix_world = tilt_matrix(spec)
	return ball


def _world_bounds(objs):
	lo = Vector(( 1e18,  1e18,  1e18))
	hi = Vector((-1e18, -1e18, -1e18))
	for obj in objs:
		if obj.type != "MESH" or not obj.data.vertices:
			continue
		n = len(obj.data.vertices)
		co = np.empty(n * 3, dtype=np.float32)
		obj.data.vertices.foreach_get("co", co)
		co = co.reshape(n, 3)
		m = obj.matrix_world
		# tight bounds: transform the actual vertices, not the local AABB,
		# which the importer's Y-up-to-Z-up rotation would inflate
		for v in co:
			w = m @ Vector(v.tolist())
			for i in range(3):
				lo[i] = min(lo[i], w[i])
				hi[i] = max(hi[i], w[i])
	return lo, hi


def add_model_ball(spec, spin, here):
	"""Import a model, centre it on the origin and scale it to radius 1 so it
	frames exactly like the generated spheres."""
	path = spec["model"]
	if not os.path.isabs(path):
		path = os.path.normpath(os.path.join(here, path))
	if not os.path.exists(path):
		sys.exit("model not found: %s" % path)

	before = set(bpy.data.objects)
	ext = os.path.splitext(path)[1].lower()
	if ext in (".gltf", ".glb"):
		bpy.ops.import_scene.gltf(filepath=path)
	elif ext == ".obj":
		bpy.ops.wm.obj_import(filepath=path)
	elif ext == ".fbx":
		bpy.ops.import_scene.fbx(filepath=path)
	else:
		sys.exit("do not know how to import %s" % ext)
	imported = [o for o in bpy.data.objects if o not in before]
	if not imported:
		sys.exit("nothing imported from %s" % path)

	roots = [o for o in imported if o.parent is None]
	lo, hi = _world_bounds(imported)
	centre = (lo + hi) / 2.0
	half = max((hi - lo)[i] for i in range(3)) / 2.0
	if half <= 0:
		sys.exit("model %s has no size" % path)
	scale = 1.0 / half

	# normalise first, then tilt, then the parent's Z rotation spins it
	fix = (tilt_matrix(spec)
	       @ Matrix.Translation(-scale * centre)
	       @ Matrix.Scale(scale, 4))
	for root in roots:
		m = root.matrix_world.copy()
		root.parent = spin
		root.matrix_world = fix @ m

	for obj in imported:
		if obj.type == "MESH":
			for poly in obj.data.polygons:
				poly.use_smooth = True
	return roots[0]


def apply_material(ball, spec, tex):
	mat = bpy.data.materials.new(spec["name"] + "-mat")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.42)
	if "Specular IOR Level" in bsdf.inputs:
		bsdf.inputs["Specular IOR Level"].default_value = spec.get("specular", 0.4)
	if "Metallic" in bsdf.inputs:
		bsdf.inputs["Metallic"].default_value = spec.get("metallic", 0.0)
	node = mat.node_tree.nodes.new("ShaderNodeTexImage")
	node.image = tex
	node.interpolation = "Cubic"
	node.location = (-400, 200)
	mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
	ball.data.materials.clear()
	ball.data.materials.append(mat)


# ---------------------------------------------------------------------------
# render / compositing
# ---------------------------------------------------------------------------

def render_frame(scene, path):
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


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
	# Same colourspace the rendered PNGs were read through, so the linear
	# values we hold get re-encoded the way they came in.
	img.colorspace_settings.name = "sRGB"
	img.alpha_mode = "STRAIGHT"
	img.pixels.foreach_set(np.ascontiguousarray(rgba, np.float32).ravel())
	img.file_format = "PNG"
	img.filepath_raw = path
	img.save()
	bpy.data.images.remove(img)


def sheet_layout(count):
	cols = int(math.ceil(math.sqrt(count)))
	rows = int(math.ceil(count / cols))
	return cols, rows


def supersample_for(size, args):
	if args.supersample:
		return args.supersample
	# Render at roughly 160px whatever the sprite size, so a 20px ball gets as
	# much edge detail as a 64px one.
	return max(2, min(8, int(round(160.0 / size))))


def render_size(spec, spin, size, args, tmpdir):
	scene = bpy.context.scene
	ss = supersample_for(size, args)
	scene.render.resolution_x = size * ss
	scene.render.resolution_y = size * ss
	scene.render.resolution_percentage = 100

	frames = args.frames or spec.get("frames", 64)
	out_dir = os.path.join(args.out, "%s_%d" % (spec["name"], size))
	if args.write_frames:
		os.makedirs(out_dir, exist_ok=True)

	cols, rows = sheet_layout(frames)
	sheet = np.zeros((rows * size, cols * size, 4), dtype=np.float32)

	for i in range(frames):
		spin.rotation_euler = (0.0, 0.0, 2.0 * math.pi * i / frames)
		tmp = os.path.join(tmpdir, "frame")
		render_frame(scene, tmp)
		rgba = downsample(load_rgba(tmp + ".png"), ss)

		if args.write_frames:
			save_rgba(rgba, os.path.join(out_dir, "frame_%02d.png" % i))

		# Sheet rows read top to bottom, but the buffer is bottom-up, so
		# row 0 of the layout lands at the top of the array.
		c, r = i % cols, i // cols
		y = (rows - 1 - r) * size
		sheet[y:y + size, c * size:(c + 1) * size] = rgba
		print("  %s@%d frame %d/%d" % (spec["name"], size, i + 1, frames))

	sheet_path = os.path.join(args.out, "%s_%dx%d_%d.png"
	                          % (spec["name"], cols, rows, size))
	save_rgba(sheet, sheet_path)
	print("wrote %s" % sheet_path)


def render_ball(spec, args, tmpdir):
	spin = build_scene(args)
	if spec.get("model"):
		add_model_ball(spec, spin, args.here)
	else:
		add_procedural_ball(spec, spin)

	sizes = [args.size] if args.size else spec.get("sizes") or [spec["size"]]
	for size in sizes:
		render_size(spec, spin, size, args, tmpdir)


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	here = os.path.dirname(os.path.abspath(__file__))
	p = argparse.ArgumentParser(prog="make_balls.py")
	p.add_argument("--out", default=os.path.join(here, "out"))
	p.add_argument("--only", action="append", default=[],
	               help="render just this ball (repeatable); finds skipped ones too")
	p.add_argument("--all", action="store_true",
	               help="include the balls marked skip")
	p.add_argument("--frames", type=int, default=None)
	p.add_argument("--size", type=int, default=None,
	               help="override every ball's own pixel size (previewing)")
	p.add_argument("--supersample", type=int, default=0,
	               help="0 (the default) picks one per size")
	p.add_argument("--samples", type=int, default=64)
	p.add_argument("--engine", choices=["cycles", "eevee"], default="cycles")
	p.add_argument("--margin", type=float, default=MARGIN)
	p.add_argument("--tilt", default=None,
	               help="override the tilt as X,Y,Z degrees (for dialling one in)")
	p.add_argument("--write-frames", action="store_true",
	               help="also write each frame as its own PNG")
	args = p.parse_args(argv)
	args.here = here

	os.makedirs(args.out, exist_ok=True)
	tmpdir = os.path.join(args.out, ".tmp")
	os.makedirs(tmpdir, exist_ok=True)

	if args.only:
		todo = [b for b in BALLS if b["name"] in args.only]
	else:
		todo = [b for b in BALLS if args.all or not b.get("skip")]
	if not todo:
		sys.exit("no balls matched %s" % args.only)
	try:
		for spec in todo:
			if args.tilt:
				spec["_tilt_override"] = [float(v) for v in args.tilt.split(",")]
			render_ball(spec, args, tmpdir)
	finally:
		shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
	main()
