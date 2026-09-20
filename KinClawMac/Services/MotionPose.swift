import AVFoundation
import AppKit
import CoreImage
import Vision

/// The movement in a video, taken out of it: a body tracked frame by frame and
/// drawn as the stick figure that pose-control video models were trained to
/// follow — OpenPose's eighteen points and colours, on black.
///
/// This is the half of "motion transfer" that needs no model of ours. Apple's
/// Vision finds the body; nothing is downloaded, nothing leaves the Mac. Only
/// the skeleton goes on to the video model, so what is taken from a reference
/// video is how somebody moved — not their face, their clothes or their garden.
///
/// Measured on the clip that proved the method (a tai chi form filmed wide, the
/// performer 65×144 pixels in a 640×360 frame): a body in 241 of 241 frames.
enum MotionPose {

    /// OpenPose's order. Left and right are the person's own, in both systems.
    private static let points: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck, .rightShoulder, .rightElbow, .rightWrist, .leftShoulder, .leftElbow, .leftWrist,
        .rightHip, .rightKnee, .rightAnkle, .leftHip, .leftKnee, .leftAnkle, .rightEye, .leftEye, .rightEar, .leftEar,
    ]
    private static let limbs: [(Int, Int)] = [
        (1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13),
        (1, 0), (0, 14), (14, 16), (0, 15), (15, 17),
    ]
    private static let colours: [(CGFloat, CGFloat, CGFloat)] = [
        (255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0), (0, 255, 0),
        (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255), (0, 0, 255), (85, 0, 255),
        (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85),
    ]
    /// The joints a fit is made on: the ones that say where a body is and how big.
    private static let anchors = [1, 2, 5, 8, 11, 10, 13]

    /// A tracked stretch of video: for each frame, eighteen points (nil where
    /// the body part was not seen) in a unit square with the origin at the
    /// bottom left, and the square of the source they were found in.
    struct Track {
        var frames: [[CGPoint?]]
        var cut: CGRect
        var first: CGImage?
    }

    enum Failure: LocalizedError {
        case unreadable, nobody
        var errorDescription: String? {
            switch self {
            case .unreadable: return "这段视频读不出来"
            case .nobody: return "这段视频里没找到人：要单人、全身、机位尽量固定"
            }
        }
    }

    /// Track `count` frames from `start` seconds, at 24 frames a second — the
    /// rate the video model was trained at, whatever the source was filmed at.
    /// `cut` fixes the square to look in: a later segment of the same take has
    /// to be cut from the same square or the skeleton jumps at the join.
    static func track(_ video: URL, from start: Double, frames count: Int, cut fixed: CGRect? = nil,
                      progress: ((Int) -> Void)? = nil) async throws -> Track {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        func picture(_ index: Int) async -> CIImage? {
            let time = CMTime(seconds: start + Double(index) / 24.0, preferredTimescale: 24000)
            guard let image = try? await generator.image(at: time).image else { return nil }
            return CIImage(cgImage: image)
        }
        guard let opening = await picture(0) else { throw Failure.unreadable }

        // Where the person is: their box in a few frames across the stretch,
        // made square with room to move in. One frame is not enough — a form
        // that travels walks out of a square drawn round where it began.
        var cut = fixed ?? .zero
        if fixed == nil {
            var body = CGRect.null
            for index in stride(from: 0, to: count, by: max(1, count / 6)) {
                guard let image = await picture(index) else { continue }
                let request = VNDetectHumanRectanglesRequest()
                request.upperBodyOnly = false
                try? VNImageRequestHandler(ciImage: image).perform([request])
                if let box = request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height })?.boundingBox {
                    let size = image.extent
                    body = body.union(CGRect(x: box.minX * size.width, y: box.minY * size.height,
                                             width: box.width * size.width, height: box.height * size.height))
                }
            }
            guard !body.isNull else { throw Failure.nobody }
            let size = opening.extent
            let side = min(max(body.height * 1.45, body.width * 1.3), size.width, size.height)
            let x = min(max(body.midX - side / 2, 0), size.width - side)
            let y = min(max(body.midY + body.height * 0.04 - side / 2, 0), size.height - side)
            cut = CGRect(x: x, y: y, width: side, height: side)
        }

        let context = CIContext()
        var track = Track(frames: [], cut: cut, first: nil)
        var held: [CGPoint?] = Array(repeating: nil, count: points.count)
        for index in 0..<count {
            guard let whole = await picture(index) else { break }
            let piece = whole.cropped(to: cut).transformed(by: CGAffineTransform(translationX: -cut.minX, y: -cut.minY))
                .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 704 / cut.width, kCIInputAspectRatioKey: 1.0])
            if index == 0 { track.first = context.createCGImage(piece, from: CGRect(x: 0, y: 0, width: 704, height: 704)) }
            let request = VNDetectHumanBodyPoseRequest()
            try? VNImageRequestHandler(ciImage: piece).perform([request])
            if let person = request.results?.first, let seen = try? person.recognizedPoints(.all) {
                for (i, name) in points.enumerated() {
                    guard let point = seen[name], point.confidence > 0.15 else { continue }
                    let now = CGPoint(x: point.location.x, y: point.location.y)
                    // A little smoothing: Vision's points shimmer from frame to frame.
                    held[i] = held[i].map { CGPoint(x: $0.x * 0.45 + now.x * 0.55, y: $0.y * 0.45 + now.y * 0.55) } ?? now
                }
            }
            track.frames.append(held)
            progress?(index + 1)
        }
        guard track.frames.contains(where: { $0.contains { $0 != nil } }) else { throw Failure.nobody }
        return track
    }

    /// The body in a still, in the same eighteen points — hers, to fit a
    /// skeleton onto.
    static func body(in still: URL) -> [CGPoint?]? {
        guard let image = CIImage(contentsOf: still) else { return nil }
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(ciImage: image).perform([request])
        guard let person = request.results?.first, let seen = try? person.recognizedPoints(.all) else { return nil }
        return points.map { name in
            guard let point = seen[name], point.confidence > 0.15 else { return nil }
            return CGPoint(x: point.location.x, y: point.location.y)
        }
    }

    /// The scale and shift that lay a skeleton's first frame over a body: least
    /// squares on the shoulders, hips and knees, one scale for both axes so
    /// nobody's proportions are stretched. Identity when there is nothing to
    /// fit on.
    ///
    /// Needed because the still is not made from the skeleton: it is drawn by
    /// an editor shown the source's first frame, and comes back with her a
    /// little lower, a little larger, a little to one side. Left unfitted, the
    /// first frames of the clip are the video model dragging her to where the
    /// skeleton says she is.
    static func fit(_ skeleton: [CGPoint?], onto body: [CGPoint?]) -> CGAffineTransform {
        let pairs = anchors.compactMap { i -> (CGPoint, CGPoint)? in
            guard i < skeleton.count, i < body.count, let a = skeleton[i], let b = body[i] else { return nil }
            return (a, b)
        }
        guard pairs.count >= 3 else { return .identity }
        let n = CGFloat(pairs.count)
        let ma = CGPoint(x: pairs.map { $0.0.x }.reduce(0, +) / n, y: pairs.map { $0.0.y }.reduce(0, +) / n)
        let mb = CGPoint(x: pairs.map { $0.1.x }.reduce(0, +) / n, y: pairs.map { $0.1.y }.reduce(0, +) / n)
        var top: CGFloat = 0, bottom: CGFloat = 0
        for (a, b) in pairs {
            top += (a.x - ma.x) * (b.x - mb.x) + (a.y - ma.y) * (b.y - mb.y)
            bottom += (a.x - ma.x) * (a.x - ma.x) + (a.y - ma.y) * (a.y - ma.y)
        }
        let scale = bottom > 0 ? min(max(top / bottom, 0.6), 1.6) : 1
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: mb.x - scale * ma.x, ty: mb.y - scale * ma.y)
    }

    /// Draw the track as a control video: 704 square, 24 frames a second.
    static func render(_ frames: [[CGPoint?]], fitted: CGAffineTransform, to file: URL, size: Int = 704) async throws {
        // A writer will not write over a file; an earlier one is set aside, not thrown away.
        if FileManager.default.fileExists(atPath: file.path) {
            let aside = file.deletingPathExtension().appendingPathExtension("old-\(Int(Date().timeIntervalSince1970)).mp4")
            try? FileManager.default.moveItem(at: file, to: aside)
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
        guard writer.startWriting() else { throw writer.error ?? Failure.unreadable }
        writer.startSession(atSourceTime: .zero)
        for (index, joints) in frames.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size, height: size,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(joints.map { $0?.applying(fitted) }, in: context, size: CGFloat(size))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 24))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? Failure.unreadable }
    }

    /// One frame's stick figure. Points are in a unit square, origin bottom
    /// left — which is also how Core Graphics draws into a bitmap.
    static func draw(_ joints: [CGPoint?], in context: CGContext, size: CGFloat) {
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setLineCap(.round)
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size, y: p.y * size) }
        for (n, limb) in limbs.enumerated() {
            guard limb.0 < joints.count, limb.1 < joints.count, let a = joints[limb.0], let b = joints[limb.1] else { continue }
            let c = colours[n]
            context.setStrokeColor(CGColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 0.6))
            context.setLineWidth(size / 64)
            context.move(to: place(a)); context.addLine(to: place(b)); context.strokePath()
        }
        for (i, joint) in joints.enumerated() {
            guard let joint, i < colours.count else { continue }
            let c = colours[i], r = size / 128, p = place(joint)
            context.setFillColor(CGColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1))
            context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// A picture written as PNG.
    @discardableResult
    static func write(_ image: CGImage, to file: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
