"""A set built from a scene spec (spec.json), a camera that moves through it, rendered three ways:

  depth-####.png   every frame, inverse depth stretched between near and far (near is white)
                   — the control video the video model follows frame for frame
  blockout-####.png  the keyframes, plainly shaded and lit for the time of day
                   — what the image editor re-renders as photographs, one per keyframe
  plan.png         the set from above with the camera's path — for a person to check before anything is filmed

  blender -b -P prompt_stage.py -- spec.json outdir

The spec is written by whoever reads the prompt (an agent); this script only builds it. Shapes are
box / cyl / ball — depth control needs coarse geometry, and coarse geometry is what can be trusted.
"""
import bpy, json, math, os, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
spec = json.load(open(argv[0])); out = argv[1]
os.makedirs(out, exist_ok=True)
W, H = spec["size"]; N = int(spec["frames"])

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = W, H
scene.render.resolution_percentage = 100
scene.render.fps = int(spec.get("fps", 24))
scene.frame_start, scene.frame_end = 1, N

def depth_material(near, far):
    m = bpy.data.materials.new("depth"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    cam = nt.nodes.new("ShaderNodeCameraData")
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "DIVIDE"; inv.inputs[0].default_value = 1.0
    nt.links.new(cam.outputs["View Z Depth"], inv.inputs[1])
    rng = nt.nodes.new("ShaderNodeMapRange"); rng.clamp = True
    rng.inputs["From Min"].default_value = 1.0 / far; rng.inputs["From Max"].default_value = 1.0 / near
    rng.inputs["To Min"].default_value = 0.0; rng.inputs["To Max"].default_value = 1.0
    nt.links.new(inv.outputs[0], rng.inputs["Value"])
    em = nt.nodes.new("ShaderNodeEmission"); nt.links.new(rng.outputs[0], em.inputs["Color"])
    o = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0], o.inputs["Surface"])
    return m

def plain(name, rgb, rough=0.8, glow=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    if glow:
        b.inputs["Emission Color"].default_value = (*rgb, 1); b.inputs["Emission Strength"].default_value = glow
    return m

d = spec.get("depth", {})
DEPTH = depth_material(d.get("near", 1.0), d.get("far", 40.0))
# looks: plain colours that say what a thing is; the glowing ones are the night's light sources
LOOK = {
    "ground": plain("ground", (0.40, 0.38, 0.34)), "wet_stone": plain("wet_stone", (0.10, 0.10, 0.11), 0.22),
    "wall": plain("wall", (0.34, 0.31, 0.28), 0.9), "wall2": plain("wall2", (0.40, 0.36, 0.30), 0.9),
    "roof": plain("roof", (0.12, 0.12, 0.13), 0.7), "wood": plain("wood", (0.25, 0.15, 0.08), 0.8),
    "awning": plain("awning", (0.40, 0.08, 0.06), 0.7), "sign": plain("sign", (0.55, 0.48, 0.30), 0.6),
    "sign_lit": plain("sign_lit", (0.95, 0.55, 0.20), 0.5, 3.0), "lantern": plain("lantern", (1.0, 0.25, 0.10), 0.5, 8.0),
    "lamp": plain("lamp", (1.0, 0.85, 0.60), 0.5, 14.0), "window": plain("window", (0.06, 0.07, 0.09), 0.3),
    "window_lit": plain("window_lit", (1.0, 0.72, 0.40), 0.4, 3.5), "metal": plain("metal", (0.08, 0.08, 0.08), 0.5),
    "puddle": plain("puddle", (0.05, 0.05, 0.06), 0.05), "leaf": plain("leaf", (0.16, 0.36, 0.14)),
    "stone": plain("stone", (0.55, 0.55, 0.52)), "glass": plain("glass", (0.30, 0.35, 0.40), 0.1),
}
things = []
def keep(obj, look):
    obj.data.materials.clear(); obj.data.materials.append(DEPTH)
    things.append((obj, look if look in LOOK else "stone")); return obj

g = spec.get("ground", {})
bpy.ops.mesh.primitive_plane_add(size=g.get("size", 200), location=(0, 0, 0)); keep(bpy.context.object, g.get("look", "ground"))
for o in spec["objects"]:
    s, at, look = o["shape"], o["at"], o.get("look", "stone")
    if s == "box":
        bpy.ops.mesh.primitive_cube_add(size=1, location=at); ob = bpy.context.object; ob.scale = o["size"]
    elif s == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=o["r"], depth=o["h"], location=at); ob = bpy.context.object
    elif s == "ball":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=o["r"], location=at); ob = bpy.context.object
        bpy.ops.object.shade_smooth()
    else:
        continue
    if "rot" in o: ob.rotation_euler = [math.radians(a) for a in o["rot"]]
    keep(ob, look)

# ---- the camera: keys at progress t (0..1), eased, eye position and the point looked at
c = spec["camera"]
cam_data = bpy.data.cameras.new("camera"); cam_data.lens = c.get("lens", 30); cam_data.sensor_width = 36; cam_data.clip_end = 500
cam = bpy.data.objects.new("camera", cam_data); scene.collection.objects.link(cam); scene.camera = cam
aim = bpy.data.objects.new("aim", None); scene.collection.objects.link(aim)
track = cam.constraints.new("TRACK_TO"); track.target = aim; track.track_axis = "TRACK_NEGATIVE_Z"; track.up_axis = "UP_Y"
keys = sorted(c["keys"], key=lambda k: k["t"])
def at_progress(t):
    for a, b in zip(keys, keys[1:]):
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / max(1e-6, b["t"] - a["t"])
            return [Vector(a[k]).lerp(Vector(b[k]), u) for k in ("at", "look")]
    k = keys[0] if t <= keys[0]["t"] else keys[-1]
    return [Vector(k["at"]), Vector(k["look"])]
path = []
for f in range(1, N + 1):
    t = (f - 1) / max(1, N - 1)
    if c.get("ease", "in_out") == "in_out": t = t * t * (3 - 2 * t)
    eye, look = at_progress(t)
    cam.location = eye; cam.keyframe_insert("location", frame=f)
    aim.location = look; aim.keyframe_insert("location", frame=f)
    path.append(eye.copy())

# ---- render 1: depth, every frame
world = bpy.data.worlds.new("far"); scene.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0, 0, 0, 1)
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: scene.render.engine = engine; break
    except TypeError: pass
scene.view_settings.view_transform = "Raw"; scene.view_settings.look = "None"
scene.render.image_settings.file_format = "PNG"; scene.render.image_settings.color_mode = "RGB"
scene.render.filepath = os.path.join(out, "depth-")
print("ENGINE", scene.render.engine, "frames", N, "objects", len(things))
bpy.ops.render.render(animation=True)

# ---- render 2: the keyframes, shaded and lit for the time of day
for ob, look in things:
    ob.data.materials.clear(); ob.data.materials.append(LOOK[look])
night = spec.get("sky", "day") == "night"
bg.inputs["Color"].default_value = (0.015, 0.02, 0.045, 1) if night else (0.62, 0.74, 0.90, 1)
bg.inputs["Strength"].default_value = 1.0 if night else 0.9
light = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN"))
light.data.energy = 0.25 if night else 3.0
light.data.color = (0.55, 0.65, 1.0) if night else (1.0, 1.0, 1.0)
light.rotation_euler = (math.radians(55), 0, math.radians(-40)); scene.collection.objects.link(light)
scene.view_settings.view_transform = "AgX" if night else "Standard"
for k in spec.get("keyframes", [0]):
    scene.frame_set(int(k) + 1)
    scene.render.filepath = os.path.join(out, "blockout-%04d.png" % int(k))
    bpy.ops.render.render(write_still=True)

# ---- render 3: the plan — the set from above, the camera's path as dots, first white, last amber
for i, p in enumerate(path[::6] + [path[-1]]):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.35, location=(p.x, p.y, 12.0))
    dot = bpy.context.object; dot.data.materials.append(plain("dot%d" % i, (1.0, 0.75 if i else 1.0, 0.2 if i else 1.0), 0.5, 20.0))
top_data = bpy.data.cameras.new("top"); top_data.type = "ORTHO"
xs = [p.x for p in path]; ys = [p.y for p in path]
cy = (min(ys) + max(ys)) / 2 + 12
top_data.ortho_scale = max(60.0, (max(ys) - min(ys)) + 40)
top = bpy.data.objects.new("top", top_data); scene.collection.objects.link(top)
top.location = ((min(xs) + max(xs)) / 2, cy, 80); top.rotation_euler = (0, 0, math.radians(90))
scene.camera = top
bg.inputs["Color"].default_value = (0.03, 0.035, 0.05, 1)
sun_top = bpy.data.objects.new("top-sun", bpy.data.lights.new("top-sun", "SUN")); sun_top.data.energy = 2.5; scene.collection.objects.link(sun_top)
scene.frame_set(1); scene.render.filepath = os.path.join(out, "plan.png"); bpy.ops.render.render(write_still=True)
print("DONE", out)
