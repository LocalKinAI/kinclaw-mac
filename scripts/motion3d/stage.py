"""A park blockout, a mannequin that performs a tracked movement, a camera that walks
round her — rendered as a depth video (near is white) for a video model to paint over,
plus one plainly shaded frame for whoever has to draw the first picture.

  blender -b -P stage.py -- motion3d.json outdir [static|orbit|push] [park|open]
"""
import bpy, json, math, os, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
motion = json.load(open(argv[0])); out = argv[1]
mode = argv[2] if len(argv) > 2 else "orbit"; place = argv[3] if len(argv) > 3 else "park"
os.makedirs(out, exist_ok=True)
names, frames = motion["names"], motion["frames"]
J = {n: i for i, n in enumerate(names)}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.resolution_x = scene.render.resolution_y = 704
scene.render.resolution_percentage = 100
scene.render.fps = int(motion["fps"])
scene.frame_start, scene.frame_end = 1, len(frames)

# ---- materials: `depth` shows how far each point is; the others are for the shaded frame
def depth_material(near=1.6, far=30.0):
    m = bpy.data.materials.new("depth"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    cam = nt.nodes.new("ShaderNodeCameraData")
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "DIVIDE"; inv.inputs[0].default_value = 1.0
    nt.links.new(cam.outputs["View Z Depth"], inv.inputs[1])
    # what a depth estimator gives: inverse depth, stretched between the nearest and the farthest
    rng = nt.nodes.new("ShaderNodeMapRange"); rng.clamp = True
    rng.inputs["From Min"].default_value = 1.0 / far; rng.inputs["From Max"].default_value = 1.0 / near
    rng.inputs["To Min"].default_value = 0.0; rng.inputs["To Max"].default_value = 1.0
    nt.links.new(inv.outputs[0], rng.inputs["Value"])
    em = nt.nodes.new("ShaderNodeEmission"); nt.links.new(rng.outputs[0], em.inputs["Color"])
    o = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0], o.inputs["Surface"])
    return m
def plain(name, rgb, rough=0.8):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    return m
DEPTH = depth_material()
LOOK = {"ground": plain("ground", (0.42, 0.40, 0.36)), "wood": plain("wood", (0.45, 0.16, 0.10)), "roof": plain("roof", (0.18, 0.20, 0.22)),
        "leaf": plain("leaf", (0.16, 0.36, 0.14)), "trunk": plain("trunk", (0.22, 0.15, 0.10)), "stone": plain("stone", (0.55, 0.55, 0.52)),
        "jacket": plain("jacket", (0.10, 0.22, 0.55)), "trousers": plain("trousers", (0.45, 0.46, 0.48)), "skin": plain("skin", (0.85, 0.66, 0.55)),
        "hair": plain("hair", (0.04, 0.03, 0.03)), "shoe": plain("shoe", (0.92, 0.92, 0.90))}
things = []                                                     # (object, name of its look)
def keep(obj, look):
    obj.data.materials.clear(); obj.data.materials.append(DEPTH); things.append((obj, look)); return obj
def box(loc, size, look):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.object; o.scale = size; return keep(o, look)
def cyl(loc, r, h, look, verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc); return keep(bpy.context.object, look)
def ball(loc, r, look, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=r, location=loc)
    o = bpy.context.object; o.scale = scale; bpy.ops.object.shade_smooth(); return keep(o, look)

# ---- the place: a park at the edge of things, nothing that needs a texture to be read
bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, 0)); keep(bpy.context.object, "ground")
if place == "park":
    px, py = 4.2, 6.5                                           # a pavilion behind her, to her left as the camera sees it
    box((px, py, 0.2), (4.4, 4.4, 0.4), "stone")
    for dx in (-1.8, 1.8):
        for dy in (-1.8, 1.8): cyl((px + dx, py + dy, 1.9), 0.16, 3.0, "wood")
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=3.6, radius2=0.2, depth=1.5, location=(px, py, 4.15), rotation=(0, 0, math.radians(45)))
    keep(bpy.context.object, "roof")
    for (tx, ty, s) in [(-4.0, 7.0, 1.0), (-7.5, 11.0, 1.25), (-1.0, 12.5, 1.1), (9.0, 13.0, 1.3), (-10.0, 4.0, 0.9)]:
        cyl((tx, ty, 1.6 * s), 0.22 * s, 3.2 * s, "trunk"); ball((tx, ty, 4.2 * s), 2.0 * s, "leaf", (1, 1, 0.85))
    box((-3.0, 3.8, 0.25), (1.7, 0.45, 0.5), "stone")             # a bench
    box((0, 17, 0.6), (60, 0.8, 1.2), "leaf")                     # a hedge along the back
else:                                                           # open ground: a line of trees a long way off, and nothing else
    for (tx, ty, s) in [(-14.0, 22.0, 1.4), (-5.0, 26.0, 1.6), (6.0, 24.0, 1.5), (16.0, 27.0, 1.7), (-24.0, 25.0, 1.5)]:
        cyl((tx, ty, 1.6 * s), 0.22 * s, 3.2 * s, "trunk"); ball((tx, ty, 4.2 * s), 2.0 * s, "leaf", (1, 1, 0.85))

# ---- her: capsules between the joints, keyed on every frame
BONES = [("root", "spine", 0.135, "jacket"), ("spine", "centerShoulder", 0.145, "jacket"), ("centerShoulder", "centerHead", 0.055, "skin"),
         ("leftHip", "rightHip", 0.12, "trousers"), ("centerShoulder", "leftShoulder", 0.075, "jacket"), ("centerShoulder", "rightShoulder", 0.075, "jacket"),
         ("leftShoulder", "leftElbow", 0.06, "jacket"), ("leftElbow", "leftWrist", 0.05, "jacket"),
         ("rightShoulder", "rightElbow", 0.06, "jacket"), ("rightElbow", "rightWrist", 0.05, "jacket"),
         ("leftHip", "leftKnee", 0.095, "trousers"), ("leftKnee", "leftAnkle", 0.075, "trousers"),
         ("rightHip", "rightKnee", 0.095, "trousers"), ("rightKnee", "rightAnkle", 0.075, "trousers"),
         ("root", "leftHip", 0.12, "trousers"), ("root", "rightHip", 0.12, "trousers")]
KNOBS = [("leftShoulder", 0.078, "jacket"), ("rightShoulder", 0.078, "jacket"), ("leftElbow", 0.06, "jacket"), ("rightElbow", 0.06, "jacket"),
         ("leftWrist", 0.052, "skin"), ("rightWrist", 0.052, "skin"), ("leftKnee", 0.092, "trousers"), ("rightKnee", 0.092, "trousers"),
         ("leftHip", 0.125, "trousers"), ("rightHip", 0.125, "trousers"), ("spine", 0.15, "jacket")]
bones = []
for a, b, r, look in BONES:
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=1, depth=1); o = bpy.context.object
    o.rotation_mode = "QUATERNION"; bpy.ops.object.shade_smooth(); bones.append((keep(o, look), a, b, r))
knobs = [(ball((0, 0, 0), r, look), n) for n, r, look in KNOBS]
head = ball((0, 0, 0), 0.115, "skin", (1, 1.08, 1.2)); hair = ball((0, 0, 0), 0.122, "hair", (1.02, 1.05, 1.0))
feet = [(ball((0, 0, 0), 1, "shoe"), side) for side in ("left", "right")]
Z = Vector((0, 0, 1))
for index, joints in enumerate(frames):
    f = index + 1
    P = {n: Vector(joints[J[n]]) for n in names}
    for o, a, b, r in bones:
        d = P[b] - P[a]
        o.location = (P[a] + P[b]) / 2; o.rotation_quaternion = Z.rotation_difference(d.normalized()); o.scale = (r, r, max(d.length, 0.01))
        for path in ("location", "rotation_quaternion", "scale"): o.keyframe_insert(path, frame=f)
    for o, n in knobs:
        o.location = P[n]; o.keyframe_insert("location", frame=f)
    front = (P["leftHip"] - P["rightHip"]).cross(Z).normalized()          # the way her body faces
    head.location = (P["centerHead"] + P["topHead"]) / 2; head.keyframe_insert("location", frame=f)
    hair.location = head.location - front * 0.035 + Z * 0.03; hair.keyframe_insert("location", frame=f)
    for o, side in feet:
        ankle = P[side + "Ankle"]
        o.location = Vector((ankle.x, ankle.y, 0.05)) + front * 0.07
        o.scale = (0.055, 0.13, 0.05); o.rotation_euler = (0, 0, math.atan2(front.y, front.x) - math.pi / 2)
        for path in ("location", "rotation_euler", "scale"): o.keyframe_insert(path, frame=f)

# ---- the camera: a quarter view, and (orbit) a slow walk round toward her front
aim = bpy.data.objects.new("aim", None); scene.collection.objects.link(aim); aim.location = (0, -0.1, 0.95)
cam_data = bpy.data.cameras.new("camera"); cam_data.lens = 45; cam_data.sensor_width = 36; cam_data.clip_end = 300
cam = bpy.data.objects.new("camera", cam_data); scene.collection.objects.link(cam); scene.camera = cam
track = cam.constraints.new("TRACK_TO"); track.target = aim; track.track_axis = "TRACK_NEGATIVE_Z"; track.up_axis = "UP_Y"
# degrees round from straight in front of her, distance in metres, and the height looked at — first frame, last frame
PATHS = {"static": ((-30.0, 3.5, 0.95), (-30.0, 3.5, 0.95)), "orbit": ((-38.0, 3.5, 0.95), (-8.0, 3.5, 0.95)),
         "push": ((-22.0, 4.4, 0.95), (-16.0, 2.7, 1.15))}
(a0, r0, h0), (a1, r1, h1) = PATHS.get(mode, PATHS["orbit"])
# She may walk. The camera's path is round HER, not round where she started — on the first
# take with a step in it she walked a metre up the set and ended half the size she began —
# and it goes with her two seconds late and looks at her one second late, as somebody
# carrying it would.
hips = [Vector(joints[J["root"]]) for joints in frames]
def lately(i, k):
    window = hips[max(0, i - k):i + k + 1]
    return sum(window, Vector((0, 0, 0))) / len(window)
for f in range(1, len(frames) + 1):
    t = (f - 1) / max(1, len(frames) - 1); t = t * t * (3 - 2 * t)        # ease in and out
    angle = math.radians(a0 + (a1 - a0) * t); radius = r0 + (r1 - r0) * t
    about, her = lately(f - 1, 24), lately(f - 1, 12)
    cam.location = (about.x + radius * math.sin(angle), about.y - radius * math.cos(angle), 1.45)
    cam.keyframe_insert("location", frame=f)
    aim.location = (her.x, her.y - 0.1, h0 + (h1 - h0) * t); aim.keyframe_insert("location", frame=f)

# ---- render 1: depth, every frame, exactly as the numbers are
world = bpy.data.worlds.new("far"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: scene.render.engine = engine; break
    except TypeError: pass
scene.view_settings.view_transform = "Raw"; scene.view_settings.look = "None"
scene.render.image_settings.file_format = "PNG"; scene.render.image_settings.color_mode = "RGB"
scene.render.filepath = os.path.join(out, "depth-")
print("ENGINE", scene.render.engine, "frames", len(frames), "mode", mode)
bpy.ops.render.render(animation=True)

# ---- render 2: the first frame, plainly lit, so that somebody can see what the blockout is
for o, look in things:
    o.data.materials.clear(); o.data.materials.append(LOOK[look])
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.74, 0.90, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3.0
sun.rotation_euler = (math.radians(55), 0, math.radians(-40)); scene.collection.objects.link(sun)
scene.view_settings.view_transform = "Standard"
scene.frame_set(1); scene.render.filepath = os.path.join(out, "blockout-first.png"); bpy.ops.render.render(write_still=True)
print("DONE", out)
