import AVFoundation
import ImageIO

/// A set, a mannequin, and a camera that moves: the box's Blender renders them
/// as a depth video, and the video model paints over it.
///
/// A flat skeleton can only be filmed from where the reference was filmed. A
/// body in 3D (`MotionPose3D`) stands on a set, and a set can be walked round:
/// Blender, headless on the box, builds a blockout — ground, a pavilion, trees,
/// a bench — and a mannequin of capsules keyed to the tracked joints on every
/// frame, moves a camera through it, and renders how far away everything is
/// (near is white), which is one of the three things LTX's union-control LoRA
/// follows. It also renders the first frame plainly lit; the image editor is
/// asked to re-render *that* as a photograph with her in it, moving nothing,
/// and that is the still the take starts from. First try: the same woman,
/// clothes and pavilion for 97 frames while the camera walked thirty degrees
/// round her, with parallax — a shot the skeleton route cannot express.
/// 39 seconds of Blender, 14 of editing, 132 of filming, for four seconds.
enum MotionStage {
    enum Camera: String, CaseIterable, Codable {
        case still = "static", orbit, push
        var title: String {
            switch self { case .still: return "3D · 固定"; case .orbit: return "3D · 环绕"; case .push: return "3D · 推近" }
        }
        /// For the video model's prompt.
        var words: String {
            switch self {
            case .still: return "Static camera."
            case .orbit: return "The camera moves slowly in an arc around her, from her right front toward her front, always facing her, at chest height."
            case .push: return "The camera moves slowly and steadily closer to her, from a full-length view toward her upper body."
            }
        }
    }

    enum Place: String, CaseIterable, Codable {
        case park, open
        var title: String { self == .park ? "公园亭子" : "空地" }
        /// What the blockout's plain shapes are, for whoever re-renders it.
        var words: String {
            self == .park
                ? "The plain shapes become real things: the red-pillared structure is a wooden pavilion on a stone platform, the green balls on sticks are leafy trees, the long green box is a trimmed hedge, the small box is a stone bench."
                : "The plain shapes become real things: the green balls on sticks far away are trees; the ground is open and empty."
        }
    }

    enum Failure: LocalizedError {
        case noBox, noBlender, render(String), transfer(String)
        var errorDescription: String? {
            switch self {
            case .noBox: return "3D 机位要用盒子上的 Blender：先在 设置 → Backend 里填盒子的 SSH"
            case .noBlender: return "盒子上还没有 Blender（\(MotionStage.blender)）。在盒子上：brew fetch --cask blender，再把 dmg 里的 Blender.app 拷到 ~/.kinclaw/blender/"
            case .render(let said): return "盒子上的 Blender 没渲染出来：\(said)"
            case .transfer(let said): return "和盒子之间传文件失败：\(said)"
            }
        }
    }

    static let blender = "~/.kinclaw/blender/Blender.app/Contents/MacOS/Blender"

    /// Is there a Blender on the box to ask?
    static func ready() async -> Bool {
        await BoxServices.run("test -x \(blender) && echo yes").1.contains("yes")
    }

    /// Render the whole movement in one go — one camera move from the first
    /// frame to the last, however many stretches it is later filmed in — and
    /// bring back the depth frames and the plainly lit first frame.
    static func render(_ frames: [MotionPose3D.Pose], camera: Camera, place: Place, id: String, into folder: URL,
                       progress: @escaping @Sendable (Int) -> Void) async throws -> (depth: [URL], first: URL) {
        let target = await BoxServices.ssh
        guard !target.isEmpty else { throw Failure.noBox }
        guard await ready() else { throw Failure.noBlender }
        let fm = FileManager.default
        let name = "take-" + id.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.map(String.init).joined().suffix(12)
        let work = "~/.kinclaw/blender/work/\(name)"
        let local = folder.appendingPathComponent("stage")
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        let motion = local.appendingPathComponent("motion3d.json"), code = local.appendingPathComponent("stage.py")
        try MotionPose3D.json(frames).write(to: motion)
        try Data(script.utf8).write(to: code)

        _ = await BoxServices.run("mkdir -p \(work)/out && rm -f \(work)/out/depth-*.png")
        try await copy([motion, code], to: "\(target):\(work)/")
        // Blender says nothing useful until it is done; the frames landing on disk do.
        let watching = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let count = Int(await BoxServices.run("ls \(work)/out 2>/dev/null | grep -c depth-").1.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if Task.isCancelled { break }                   // the answer to a question asked before the render ended
                progress(count)
            }
        }
        let (status, said) = await BoxServices.run(
            "cd \(work) && \(blender) -b -P stage.py -- motion3d.json out \(camera.rawValue) \(place.rawValue) > render.log 2>&1; "
            // Blender's own last words come after the script's: look for the
            // script's line, not at the end of the log. (The first take through
            // the app rendered all 97 frames and was called a failure for it.)
            + "grep -E '^DONE|Error|Traceback' render.log | tail -4")
        watching.cancel()
        guard status == 0, said.contains("DONE") else {
            throw Failure.render(String(said.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300)))
        }
        try await fetch("\(target):\(work)/out/", into: local)
        let out = local.appendingPathComponent("out")
        let depth = ((try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("depth-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let first = out.appendingPathComponent("blockout-first.png")
        guard depth.count == frames.count, fm.fileExists(atPath: first.path) else {
            throw Failure.render("要 \(frames.count) 帧，回来 \(depth.count) 帧")
        }
        return (depth, first)
    }

    /// Some of the depth frames as the control video of one stretch.
    static func video(from frames: [URL], to file: URL, size: Int = 704) async throws {
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.moveItem(at: file, to: file.deletingPathExtension().appendingPathExtension("old-\(Int(Date().timeIntervalSince1970)).mp4"))
        }
        let writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.render("写不出控制视频") }
        writer.startSession(atSourceTime: .zero)
        for (index, url) in frames.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let pool = adaptor.pixelBufferPool else { continue }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size, height: size, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 24))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? Failure.render("写不出控制视频") }
    }

    // MARK: Files, to the box and back

    private static func copy(_ files: [URL], to remote: String) async throws {
        let (status, said) = await scp(files.map(\.path) + [remote])
        if status != 0 { throw Failure.transfer(said) }
    }

    private static func fetch(_ remote: String, into local: URL) async throws {
        let (status, said) = await scp(["-r", remote, local.path])
        if status != 0 { throw Failure.transfer(said) }
    }

    /// `BatchMode`, as everywhere the app talks to the box: a key that works, or a failure.
    nonisolated private static func scp(_ arguments: [String]) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
                process.arguments = ["-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6"] + arguments
                let pipe = Pipe()
                process.standardOutput = pipe; process.standardError = pipe
                do { try process.run() } catch { continuation.resume(returning: (255, error.localizedDescription)); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }

    // MARK: The script Blender runs

    static let script = #"""
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
"""#
}
