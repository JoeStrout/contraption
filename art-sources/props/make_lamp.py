#!/usr/bin/env python3
"""Stand the light bulb in an old porcelain socket, for the lamp sprite.

The downloaded bulb is just a bulb, screw base and all; a lamp in the game
wants the kind of fixture a school physics lab bolted to a board: a round,
glazed porcelain body that spreads out wide at the foot and scoops up, in a
slumped cone, to a collar the bulb screws into, with a brass terminal screw on
either side.  This builds that body procedurally -- a lathed profile -- around
the bulb as imported, since the bulb's size and placement are what it has to
fit.

The bulb arrives Z-up, screw tip at z = -1 and crown at z = +1; its brass
shell runs from the tip to z = -0.49 at radius 0.267.  Every dimension below
is in those units.

Run it in Blender, with the UI to look it over:

    Blender -P make_lamp.py

or headless, writing a combined model make_props.py can import like any other:

    Blender -b --factory-startup -P make_lamp.py -- --export ../models/lamp.glb
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
BULB = os.path.join(HERE, "../models/light_bulb.glb")

SEGMENTS = 96          # around the axis; the silhouette is what shows

# The profile, (radius, z).  The collar hides all but the top of the bulb's
# screw shell, the way a real socket does, leaving a band of brass under the
# glass.
BORE = 0.285           # just clears the shell (0.267)
COLLAR = 0.37          # outer radius of the collar
COLLAR_TOP = -0.62     # where the porcelain stops
COLLAR_FOOT = -0.80    # where the collar meets the flank
FOOT = 0.82            # radius at the widest
FOOT_TOP = -1.22       # top of the foot's short upright edge
BOTTOM = -1.30         # the board it sits on
BORE_FLOOR = -1.03     # just under the bulb's contact tip
SLUMP = 0.65           # 0 is a straight cone, 1 a full quarter-round scoop

PORCELAIN = "#EEE8DA"
BRASS = "#B8913A"


def arc(cx, cz, rad, a0, a1, n):
	"""Points on a circular fillet, from angle a0 to a1 (degrees)."""
	out = []
	for i in range(n + 1):
		a = math.radians(a0 + (a1 - a0) * i / n)
		out.append((cx + rad * math.cos(a), cz + rad * math.sin(a)))
	return out


def profile():
	pts = [(0.0, BOTTOM)]
	# rounded outer edge of the foot
	f = 0.04
	pts += arc(FOOT - f, BOTTOM + f, f, -90, 0, 6)
	pts.append((FOOT, FOOT_TOP - 0.01))
	# The flank.  A concave quarter-ellipse, centred at (FOOT, COLLAR_FOOT),
	# leaves the foot nearly level and arrives at the collar nearly upright --
	# the scoop -- and blending it with a straight line lets it slump rather
	# than bowl.
	n = 40
	for i in range(n + 1):
		t = i / n
		th = t * math.pi / 2
		er = COLLAR + (FOOT - COLLAR) * (1 - math.sin(th))
		ez = FOOT_TOP + (COLLAR_FOOT - FOOT_TOP) * (1 - math.cos(th))
		lr = FOOT + (COLLAR - FOOT) * t
		lz = FOOT_TOP + (COLLAR_FOOT - FOOT_TOP) * t
		pts.append((SLUMP * er + (1 - SLUMP) * lr,
		            SLUMP * ez + (1 - SLUMP) * lz))
	# the collar, and its rounded lip over into the bore
	lip = (COLLAR - BORE) / 2
	pts.append((COLLAR, COLLAR_TOP - lip))
	pts += arc(BORE + lip, COLLAR_TOP - lip, lip, 0, 180, 12)[1:]
	# down the bore to its floor, where the bulb's contact sits
	pts.append((BORE, BORE_FLOOR))
	pts.append((0.0, BORE_FLOOR))
	return pts


def lathe(name, pts, segments):
	bm = bmesh.new()
	verts = [bm.verts.new((r, 0.0, z)) for r, z in pts]
	edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
	bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1),
	               angle=2 * math.pi, steps=segments, use_duplicate=False)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	for p in mesh.polygons:
		p.use_smooth = True
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def flank_at(t):
	"""A point on the flank and its outward normal in the XZ plane."""
	def pt(t):
		th = t * math.pi / 2
		er = COLLAR + (FOOT - COLLAR) * (1 - math.sin(th))
		ez = FOOT_TOP + (COLLAR_FOOT - FOOT_TOP) * (1 - math.cos(th))
		lr = FOOT + (COLLAR - FOOT) * t
		lz = FOOT_TOP + (COLLAR_FOOT - FOOT_TOP) * t
		return Vector((SLUMP * er + (1 - SLUMP) * lr, 0,
		               SLUMP * ez + (1 - SLUMP) * lz))
	p = pt(t)
	d = pt(t + 1e-3) - pt(t - 1e-3)
	normal = Vector((d.z, 0, -d.x)).normalized()   # rotate tangent outward
	return p, normal


def terminal(name, side, mat):
	"""A brass binding screw set into the flank: a round head with a slot,
	on a round washer, standing out along the flank's normal."""
	p, nrm = flank_at(0.30)
	objs = []
	bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.10, depth=0.03)
	plate = bpy.context.object
	objs.append(plate)
	bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.075, depth=0.07,
	                                    location=(0, 0, 0.05))
	head = bpy.context.object
	# the head's slot
	bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.085),
	                                scale=(0.18, 0.018, 0.04))
	slot = bpy.context.object
	mod = head.modifiers.new("slot", "BOOLEAN")
	mod.operation = "DIFFERENCE"
	mod.object = slot
	bpy.context.view_layer.objects.active = head
	bpy.ops.object.modifier_apply(modifier="slot")
	bpy.data.objects.remove(slot)
	for o in (plate, head):
		for poly in o.data.polygons:
			poly.use_smooth = False
	objs.append(head)

	# gather into one object and stand it on the flank; the pieces' own
	# offsets are baked in first, or the join measures them from the head
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	bpy.context.view_layer.objects.active = head
	bpy.ops.object.join()
	obj = bpy.context.object
	obj.name = name
	obj.data.materials.append(mat)
	up = Vector((0, 0, 1))
	rot = up.rotation_difference(nrm).to_matrix().to_4x4()
	sink = 0.008    # seat the plate a hair into the glaze so no gap shows
	obj.matrix_world = (Matrix.Rotation(math.pi if side < 0 else 0, 4, "Z")
	                    @ Matrix.Translation(p - nrm * sink) @ rot)
	return obj


def hex_to_linear(h):
	h = h.lstrip("#")
	out = []
	for i in (0, 2, 4):
		c = int(h[i:i + 2], 16) / 255.0
		out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
	return out


def make_material(name, hex_color, roughness, metallic, coat=0.0):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	r, g, b = hex_to_linear(hex_color)
	bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Metallic"].default_value = metallic
	if coat and "Coat Weight" in bsdf.inputs:
		# the glaze: a clear, glossy layer over a softer body
		bsdf.inputs["Coat Weight"].default_value = coat
		bsdf.inputs["Coat Roughness"].default_value = 0.05
	return mat


def build():
	# start from nothing, without resetting the UI we may be about to show
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o)
	bpy.ops.import_scene.gltf(filepath=os.path.normpath(BULB))
	for o in bpy.data.objects:
		o.animation_data_clear()

	porcelain = make_material("porcelain", PORCELAIN, 0.35, 0.0, coat=1.0)
	brass = make_material("brass", BRASS, 0.3, 1.0)

	body = lathe("socket", profile(), SEGMENTS)
	body.data.materials.append(porcelain)
	terminal("terminal_R", +1, brass)
	terminal("terminal_L", -1, brass)
	bpy.context.view_layer.update()


def look_over():
	"""Set the UI up for inspection: a light, and every 3D view framed on the
	lamp in material preview."""
	bpy.ops.object.light_add(type="SUN", location=(3, -4, 5))
	bpy.context.object.data.energy = 3.0
	bpy.ops.object.select_all(action="DESELECT")
	for win in bpy.context.window_manager.windows:
		for area in win.screen.areas:
			if area.type != "VIEW_3D":
				continue
			for space in area.spaces:
				if space.type == "VIEW_3D":
					space.shading.type = "MATERIAL"
					r3d = space.region_3d
					r3d.view_location = (0, 0, -0.2)
					r3d.view_distance = 5.0
					r3d.view_rotation = (Matrix.Rotation(math.radians(80), 3, "X")
					                     .to_quaternion())


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	build()
	if "--export" in argv:
		path = argv[argv.index("--export") + 1]
		if not os.path.isabs(path):
			path = os.path.normpath(os.path.join(HERE, path))
		bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
		                          export_animations=False)
		print("wrote", path)
	elif not bpy.app.background:
		look_over()


main()
