// kin-faces — the faces in a video, found by Apple's Vision, in OpenMontage face_tracker's format.
//
// OpenMontage tracks faces with MediaPipe's legacy Solutions API, which MediaPipe 1.0 dropped and
// whose 0.10 releases need numpy < 2 (OpenMontage's own environment has numpy 2). macOS has a face
// detector of its own: face_tracker uses this first on the LocalKin box (Jacky, 2026-10-04:
// 「两个都要」 — this first, MediaPipe in its own environment as the fallback).
//
//   kin-faces <video> [--fps 5] [--min-confidence 0.5]
//
// Samples every round(fps_video / fps)-th frame, keeps the most confident face, and prints JSON:
// {video_width, video_height, fps, duration_seconds, frame_count, face_detected_count, method,
//  faces: [{frame_index, timestamp_seconds, confidence, bbox: {x, y, width, height}}]} — the box
// relative to the frame as shown, from its top-left corner.
//
// Build: swiftc -O -target arm64-apple-macos14 kin-faces.swift -o kin-faces

import AVFoundation
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("kin-faces: \(message)\n".utf8))
    exit(1)
}

func rounded(_ value: Double, _ places: Double) -> Double {
    (value * pow(10, places)).rounded() / pow(10, places)
}

var path = ""
var sampleFPS = 5.0
var minConfidence: Float = 0.5
var rest = Array(CommandLine.arguments.dropFirst())
while !rest.isEmpty {
    let arg = rest.removeFirst()
    switch arg {
    case "--fps": sampleFPS = Double(rest.isEmpty ? "" : rest.removeFirst()) ?? 5
    case "--min-confidence": minConfidence = Float(rest.isEmpty ? "" : rest.removeFirst()) ?? 0.5
    default: path = arg
    }
}
guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { fail("usage: kin-faces <video> [--fps 5] [--min-confidence 0.5]") }

let asset = AVURLAsset(url: URL(fileURLWithPath: path))
guard let track = asset.tracks(withMediaType: .video).first else { fail("no video track in \(path)") }
let videoFPS = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30
let shown = track.naturalSize.applying(track.preferredTransform)
let width = Int(abs(shown.width).rounded()), height = Int(abs(shown.height).rounded())

// Frames come out as stored; Vision is told how they are shown, so its boxes are in that frame.
let t = track.preferredTransform
let orientation: CGImagePropertyOrientation
switch (t.a, t.b, t.c, t.d) {
case (0, 1, -1, 0): orientation = .right
case (0, -1, 1, 0): orientation = .left
case (-1, 0, 0, -1): orientation = .down
default: orientation = .up
}

let reader: AVAssetReader
do { reader = try AVAssetReader(asset: asset) } catch { fail("cannot read \(path): \(error)") }
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
])
output.alwaysCopiesSampleData = false
reader.add(output)
guard reader.startReading() else { fail("cannot decode \(path): \(String(describing: reader.error))") }

let interval = max(1, Int(videoFPS / max(0.1, sampleFPS)))
var index = 0
var sampled = 0
var faces: [[String: Any]] = []
while let sample = output.copyNextSampleBuffer() {
    defer { index += 1 }
    guard index % interval == 0, let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    sampled += 1
    let request = VNDetectFaceRectanglesRequest()
    try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation, options: [:]).perform([request])
    let found = (request.results ?? []).filter { $0.confidence >= minConfidence }
    guard let best = found.max(by: { $0.confidence < $1.confidence }) else { continue }
    let box = best.boundingBox  // normalized, origin at the bottom left
    faces.append([
        "frame_index": index,
        "timestamp_seconds": rounded(Double(index) / videoFPS, 3),
        "confidence": rounded(Double(best.confidence), 3),
        "bbox": [
            "x": rounded(Double(box.minX), 4),
            "y": rounded(Double(1 - box.maxY), 4),
            "width": rounded(Double(box.width), 4),
            "height": rounded(Double(box.height), 4),
        ],
    ])
}

let result: [String: Any] = [
    "video_width": width,
    "video_height": height,
    "fps": rounded(videoFPS, 2),
    "duration_seconds": rounded(asset.duration.seconds, 3),
    "frame_count": sampled,
    "face_detected_count": faces.count,
    "method": "vision",
    "faces": faces,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
