import AVFoundation
import Vision
import simd

/// A movement in three dimensions, from an ordinary video of one person.
///
/// `MotionPose` takes a flat skeleton off a reference video, and a flat skeleton
/// can only be filmed from where the reference was filmed. Vision also estimates
/// the body in 3D, seventeen joints a frame, and a body in 3D can be put on a
/// set and walked round (`MotionStage`). What Vision gives is a separate guess
/// for every frame, and four repairs make a movement of them:
///
///   - **The pose.** The joints come in the pelvis's own frame, which turns
///     with her hips; the camera matrix that comes with them says how that
///     frame sits before the camera (the matrix, not its inverse: the camera
///     looks down −z). Side-on, front and back look alike to one camera, and
///     for a few frames the estimate is the depth-mirrored body, or has left
///     and right swapped, or is neither: each frame is compared with the last
///     one believed, as it is and in its three disguises; the nearest is taken
///     if a body could have got there in the time, and otherwise the frame is
///     dropped and filled in from its neighbours. (Brush Knee, ten seconds:
///     222 frames as they were, 3 mirrored, 16 dropped.)
///   - **Where she is.** Vision's own estimate of where the pelvis is: steady
///     to millimetres sideways and in height, wandering by centimetres in
///     depth, so depth is averaged over most of a second. The first idea —
///     chain her feet together, each planted foot carrying the body — turned a
///     sidestep into a metre's walk away from the camera, because the relative
///     depth of two feet is what one camera sees worst.
///   - **Upright.** The reference camera looked a little down, so everything
///     leans. She starts standing straight: the line from her feet to the top
///     of her head over the first half second is made vertical (10.5° on the
///     first clip), and the ground is put where her feet mostly are.
///   - **Feet on the ground stay put** — as a correction to where she is, and
///     no more. A planted foot's drift is taken out of the whole body,
///     smoothly; a lock that would drag her more than ten centimetres is a
///     lock on a bad estimate and is let go; what the feet ask for fades, since
///     a slow slide shows less than a body pulled off its path; and with both
///     feet down a small, slow turn is allowed so that both stay.
enum MotionPose3D {
    static let names = ["root", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle", "spine", "centerShoulder",
                        "centerHead", "topHead", "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"]
    private static let joints: [VNHumanBodyPose3DObservation.JointName] = [
        .root, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .spine, .centerShoulder,
        .centerHead, .topHead, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
    ]
    private static let leftAnkle = 5, rightAnkle = 6, topHead = 10
    /// An ankle joint's height over the ground it stands on, metres.
    private static let ankleHeight = 0.09

    enum Failure: LocalizedError {
        case unreadable, nobody
        case unsteady(second: Double, metres: Double)
        var errorDescription: String? {
            switch self {
            case .unreadable: return "参考视频读不出来"
            case .nobody: return "参考视频里没找到一个完整的人（3D 姿态要看得到全身）"
            case .unsteady(let second, let metres):
                return String(format: "3D 追踪在第 %.1f 秒跳了 %.2f 米：这段动作转身或走动太大，单个镜头估不稳（侧身时前后会认反）。这类动作先用「骨架」机位；3D 机位目前适合原地的动作", second, metres)
            }
        }
    }

    /// Seventeen joints, in metres.
    typealias Pose = [SIMD3<Double>]

    /// One frame as Vision saw it, in the camera's space (x right, y up, z toward
    /// the camera): the joints about the pelvis, and where the pelvis is.
    struct Seen {
        var pose: Pose
        var pelvis: SIMD3<Double>
    }

    /// `count` frames from `start`, 24 a second, as a movement in a world:
    /// metres, X to the old camera's right, Y away from it, Z up, the midpoint
    /// of her feet in the first frame at the origin.
    static func track(_ video: URL, from start: Double, frames count: Int,
                      progress: (@Sendable (Int) -> Void)? = nil) async throws -> [Pose] {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var seen: [Seen?] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let time = CMTime(seconds: start + Double(index) / 24, preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
                if index == 0 { throw Failure.unreadable }
                seen.append(nil); continue
            }
            seen.append(pose(in: image))
            if index % 8 == 0 { progress?(index) }
        }
        guard seen.compactMap({ $0 }).count * 2 > count else { throw Failure.nobody }
        let frames = world(seen)
        // A body does not move a quarter of a metre in a twenty-fourth of a
        // second. When a joint does, the estimate has flipped — it happens
        // when she turns side-on and front and back look alike — and what
        // follows would be a mannequin teleporting round a park. On the first
        // clip with stepping and a quarter turn the right ankle "jumped" a metre.
        if let jump = leap(in: frames), jump.metres > 0.25 {
            throw Failure.unsteady(second: start + Double(jump.frame) / 24, metres: jump.metres)
        }
        return frames
    }

    /// The largest distance any joint covers between two frames, and where.
    static func leap(in frames: [Pose]) -> (frame: Int, metres: Double)? {
        var worst: (frame: Int, metres: Double)?
        for index in frames.indices.dropFirst() {
            let moved = zip(frames[index], frames[index - 1]).map { simd_distance($0, $1) }.max() ?? 0
            if moved > (worst?.metres ?? 0) { worst = (index, moved) }
        }
        return worst
    }

    private static func pose(in image: CGImage) -> Seen? {
        let request = VNDetectHumanBodyPose3DRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let body = request.results?.first else { return nil }
        // The camera looks down −z at a pelvis that is in front of it; this
        // matrix (not its inverse) takes the pelvis's frame to the camera's.
        let m = body.cameraOriginMatrix
        let turn = simd_double3x3(SIMD3(Double(m[0].x), Double(m[0].y), Double(m[0].z)),
                                  SIMD3(Double(m[1].x), Double(m[1].y), Double(m[1].z)),
                                  SIMD3(Double(m[2].x), Double(m[2].y), Double(m[2].z)))
        var pose: Pose = []
        for joint in joints {
            guard let point = try? body.recognizedPoint(joint) else { return nil }
            let at = point.position.columns.3
            pose.append(turn * SIMD3(Double(at.x), Double(at.y), Double(at.z)))
        }
        return Seen(pose: pose, pelvis: SIMD3(Double(m[3].x), Double(m[3].y), Double(m[3].z)))
    }

    /// The repairs. Pure arithmetic, so it can be checked on its own.
    static func world(_ seen: [Seen?]) -> [Pose] {
        let count = seen.count, joints = names.count
        guard seen.contains(where: { $0 != nil }) else { return [] }
        func mean<T>(_ values: [T], _ k: Int, _ zero: T, _ add: (T, T) -> T, _ over: (T, Double) -> T) -> [T] {
            values.indices.map { i in
                let window = values[max(0, i - k)...min(values.count - 1, i + k)]
                return over(window.reduce(zero, add), Double(window.count))
            }
        }
        func smooth(_ values: [Double], _ k: Int) -> [Double] { mean(values, k, 0, +, /) }
        func smooth(_ values: [SIMD2<Double>], _ k: Int) -> [SIMD2<Double>] { mean(values, k, .zero, +, /) }
        /// Straight lines across the frames that are not to be believed.
        func filled<T>(_ values: [T?], _ mix: (T, T, Double) -> T) -> [T] {
            let known = values.indices.filter { values[$0] != nil }
            return values.indices.map { i in
                if let value = values[i] { return value }
                let before = known.last { $0 < i }, after = known.first { $0 > i }
                guard let a = before ?? after, let b = after ?? before else { fatalError("nothing known") }
                return a == b ? values[a]! : mix(values[a]!, values[b]!, Double(i - a) / Double(b - a))
            }
        }

        // 1. The pose: believe, disguise, or drop.
        let swap = names.map { name -> Int in
            let other = name.hasPrefix("left") ? "right" + name.dropFirst(4) : name.hasPrefix("right") ? "left" + name.dropFirst(5) : name
            return names.firstIndex(of: String(other))!
        }
        var believed = [Pose?](repeating: nil, count: count)
        var last: (pose: Pose, at: Int)?
        for (index, frame) in seen.enumerated() {
            guard let pose = frame?.pose else { continue }
            guard let held = last else { believed[index] = pose; last = (pose, index); continue }
            let mirrored = pose.map { SIMD3($0.x, $0.y, -$0.z) }
            let disguises = [pose, mirrored, swap.map { pose[$0] }, swap.map { mirrored[$0] }]
            let far = disguises.map { guess in zip(guess, held.pose).reduce(0) { $0 + simd_distance($1.0, $1.1) } / Double(joints) }
            let best = far.indices.min { far[$0] < far[$1] }!
            let gap = index - held.at
            if far[best] <= 0.055 * Double(min(gap, 6)) + 0.03 { believed[index] = disguises[best]; last = (disguises[best], index) }
            else if gap > 30 { believed[index] = pose; last = (pose, index) }       // lost for over a second: start believing again
        }
        let poses = filled(believed) { a, b, t in zip(a, b).map { $0 + ($1 - $0) * t } }

        // 2. Where she is. A frame whose pose was not believed does not say where she is either.
        let pelvis = filled(seen.indices.map { believed[$0] == nil ? nil : seen[$0]?.pelvis }) { $0 + ($1 - $0) * $2 }
        let sideways = smooth(pelvis.map { SIMD2($0.x, $0.y) }, 2)
        let spikeless = pelvis.indices.map { i -> Double in
            let window = pelvis[max(0, i - 6)...min(count - 1, i + 6)].map(\.z).sorted()
            return window.count % 2 == 1 ? window[window.count / 2] : (window[window.count / 2 - 1] + window[window.count / 2]) / 2
        }
        let depth = smooth(spikeless, 9)

        // To the stage's axes — X right, Y away from the old camera, Z up — and upright.
        var frames: [Pose] = poses.indices.map { i in
            poses[i].map { SIMD3($0.x + sideways[i].x, -($0.z + depth[i]), $0.y + sideways[i].y) }
        }
        let opening = frames.prefix(12)
        let lean = opening.reduce(SIMD3<Double>.zero) { $0 + ($1[topHead] - ($1[leftAnkle] + $1[rightAnkle]) / 2) } / Double(opening.count)
        let pitch = atan2(lean.y, lean.z), c = cos(pitch), s = sin(pitch)
        frames = frames.map { $0.map { SIMD3($0.x, c * $0.y - s * $0.z, s * $0.y + c * $0.z) } }
        // The ground is where her feet mostly are: the tenth percentile of the lower ankle.
        let lows = frames.map { min($0[leftAnkle].z, $0[rightAnkle].z) }.sorted()
        let rank = 0.1 * Double(lows.count - 1), under = Int(rank)
        let ground = lows[under] + (lows[min(under + 1, lows.count - 1)] - lows[under]) * (rank - Double(under))
        frames = frames.map { $0.map { SIMD3($0.x, $0.y, $0.z + ankleHeight - ground) } }

        // 3. Planted feet, as a correction.
        func flat(_ p: SIMD3<Double>) -> SIMD2<Double> { SIMD2(p.x, p.y) }
        let gap = smooth(frames.map { $0[leftAnkle].z - $0[rightAnkle].z }, 2)
        var leftDown = true, rightDown = true, leftRun = 0, rightRun = 0
        var lockedLeft: SIMD2<Double>? = flat(frames[0][leftAnkle]), lockedRight: SIMD2<Double>? = flat(frames[0][rightAnkle])
        var carried = SIMD2<Double>.zero
        var shifts: [SIMD2<Double>] = [], turns: [Double] = []
        for index in frames.indices {
            let leftSeems = gap[index] < 0.06, rightSeems = gap[index] > -0.06
            leftRun = leftSeems == leftDown ? 0 : leftRun + 1
            rightRun = rightSeems == rightDown ? 0 : rightRun + 1
            if leftRun >= 3 { leftDown = leftSeems; leftRun = 0 }
            if rightRun >= 3 { rightDown = rightSeems; rightRun = 0 }
            if !leftDown { lockedLeft = nil }
            if !rightDown { lockedRight = nil }
            let l = flat(frames[index][leftAnkle]), r = flat(frames[index][rightAnkle])
            if let lock = lockedLeft, simd_length(lock - l - carried) > 0.10 { lockedLeft = nil }
            if let lock = lockedRight, simd_length(lock - r - carried) > 0.10 { lockedRight = nil }
            if leftDown, lockedLeft == nil { lockedLeft = l + carried }
            if rightDown, lockedRight == nil { lockedRight = r + carried }
            var turn = turns.last ?? 0
            if leftDown, rightDown, let a = lockedLeft, let b = lockedRight {
                carried = ((a - l) + (b - r)) / 2
                let now = l - r, was = a - b
                if simd_length(was) > 0.25 {
                    var angle = atan2(was.y, was.x) - atan2(now.y, now.x)
                    angle = (angle + .pi).truncatingRemainder(dividingBy: 2 * .pi)
                    if angle < 0 { angle += 2 * .pi }
                    turn = min(max(angle - .pi, -12 * .pi / 180), 12 * .pi / 180)
                }
            } else if leftDown, let a = lockedLeft { carried = a - l
            } else if rightDown, let b = lockedRight { carried = b - r }
            carried *= 0.97
            shifts.append(carried); turns.append(turn)
        }
        let shift = smooth(shifts, 3), turn = smooth(turns, 4)
        frames = frames.indices.map { index in
            let pose = frames[index], mid = (flat(pose[leftAnkle]) + flat(pose[rightAnkle])) / 2
            let cz = cos(turn[index]), sz = sin(turn[index])
            return pose.map { p in
                let d = flat(p) - mid
                return SIMD3(cz * d.x - sz * d.y + mid.x + shift[index].x, sz * d.x + cz * d.y + mid.y + shift[index].y, p.z)
            }
        }

        // 4. Five frames' smoothing; her first footing is the origin.
        let smoothed: [Pose] = frames.indices.map { index in
            let window = frames[max(0, index - 2)...min(count - 1, index + 2)]
            return (0..<joints).map { joint in window.reduce(SIMD3<Double>.zero) { $0 + $1[joint] } / Double(window.count) }
        }
        let origin = (flat(smoothed[0][leftAnkle]) + flat(smoothed[0][rightAnkle])) / 2
        return smoothed.map { $0.map { SIMD3($0.x - origin.x, $0.y - origin.y, $0.z) } }
    }

    /// What `MotionStage`'s script reads.
    static func json(_ frames: [Pose]) -> Data {
        let rows = frames.map { $0.map { [($0.x * 10000).rounded() / 10000, ($0.y * 10000).rounded() / 10000, ($0.z * 10000).rounded() / 10000] } }
        return (try? JSONSerialization.data(withJSONObject: ["fps": 24, "names": names, "frames": rows])) ?? Data()
    }
}
