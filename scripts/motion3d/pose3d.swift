import AVFoundation
import Vision
import simd

// usage: pose3d <video> <start seconds> <frames> <fps> <out.json>
// Every frame's 17 joints in 3D, in the camera's space (metres), from Apple's Vision.
let args = CommandLine.arguments
guard args.count >= 6 else { print("usage: pose3d video start frames fps out.json"); exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let start = Double(args[2])!, count = Int(args[3])!, fps = Double(args[4])!
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let names: [(String, VNHumanBodyPose3DObservation.JointName)] = [
    ("root", .root), ("leftHip", .leftHip), ("rightHip", .rightHip), ("leftKnee", .leftKnee), ("rightKnee", .rightKnee),
    ("leftAnkle", .leftAnkle), ("rightAnkle", .rightAnkle), ("spine", .spine), ("centerShoulder", .centerShoulder),
    ("centerHead", .centerHead), ("topHead", .topHead), ("leftShoulder", .leftShoulder), ("rightShoulder", .rightShoulder),
    ("leftElbow", .leftElbow), ("rightElbow", .rightElbow), ("leftWrist", .leftWrist), ("rightWrist", .rightWrist),
]
var frames: [[String: Any]] = []
var missed = 0
for index in 0..<count {
    let time = CMTime(seconds: start + Double(index) / fps, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { missed += 1; frames.append([:]); continue }
    let request = VNDetectHumanBodyPose3DRequest()
    let handler = VNImageRequestHandler(cgImage: image)
    try? handler.perform([request])
    guard let body = request.results?.first else { missed += 1; frames.append([:]); continue }
    // cameraOriginMatrix: the camera as seen from the root joint. Its inverse takes root space to camera space.
    let toCamera = body.cameraOriginMatrix.inverse
    var joints: [String: [Double]] = [:]
    var locals: [String: [Double]] = [:]
    for (name, joint) in names {
        guard let point = try? body.recognizedPoint(joint) else { continue }
        let local = point.position.columns.3                       // relative to the root, metres
        let seen = toCamera * SIMD4<Float>(local.x, local.y, local.z, 1)
        joints[name] = [Double(seen.x), Double(seen.y), Double(seen.z)]
        locals[name] = [Double(local.x), Double(local.y), Double(local.z)]
    }
    let m = body.cameraOriginMatrix
    let matrix = (0..<4).map { c in [Double(m[c].x), Double(m[c].y), Double(m[c].z), Double(m[c].w)] }
    frames.append(["joints": joints, "local": locals, "camera": matrix, "height": Double(body.bodyHeight),
                   "measured": body.heightEstimation == .measured])
    if index % 24 == 0 { FileHandle.standardError.write("frame \(index)/\(count)\n".data(using: .utf8)!) }
}
let out: [String: Any] = ["fps": fps, "start": start, "frames": frames, "missed": missed]
try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]).write(to: URL(fileURLWithPath: args[5]))
print("frames \(count), missed \(missed)")
