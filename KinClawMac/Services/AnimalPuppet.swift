import SwiftUI
import Vision
import AppKit
import Foundation

/// Turning one photograph of an animal into something that can look at
/// you.
///
/// The digital human moves its mouth, because a person talking is a
/// mouth moving. An animal is not that: a dog does not lip sync, and
/// making one would land squarely in the uncanny. What reads as a
/// living animal in the room is attention — it breathes, it blinks,
/// its ears move when you speak, it tilts its head when it does not
/// understand you, and it looks at you.
///
/// All of which are displacements of parts of the picture, so the whole
/// problem is knowing where those parts are. macOS's animal pose model
/// answers that: eyes and ears at better than 0.85 confidence on most
/// ordinary pet photos. Where it cannot — the animal too small, turned
/// away, half behind something — there is no rig and the picture stays
/// a picture, which is the honest outcome rather than a guess that
/// makes the ears move somewhere in the grass.
struct PuppetRig: Codable, Equatable {
    /// Everything is in unit coordinates with the origin top-left, the
    /// way SwiftUI lays out — Vision's y is flipped on the way in.
    var eyeLeft: CGPoint
    var eyeRight: CGPoint
    var earLeft: CGPoint
    var earRight: CGPoint
    var nose: CGPoint

    /// Middle of the face, and how much of the frame it takes up. The
    /// head is moved as one soft-edged disc, so these are the only two
    /// numbers the renderer really needs.
    var headCenter: CGPoint { CGPoint(x: (eyeLeft.x + eyeRight.x) / 2,
                                      y: (eyeLeft.y + eyeRight.y) / 2) }

    /// Generous: the mask is feathered, so it is better to include some
    /// neck than to cut through an ear.
    var headRadius: CGFloat {
        let ears = hypot(earLeft.x - earRight.x, earLeft.y - earRight.y)
        let eyes = hypot(eyeLeft.x - eyeRight.x, eyeLeft.y - eyeRight.y)
        return max(0.10, max(ears, eyes * 2.2) * 0.95)
    }

    /// How far apart the eyes are — the scale for a blink.
    var eyeSize: CGFloat {
        max(0.012, hypot(eyeLeft.x - eyeRight.x, eyeLeft.y - eyeRight.y) * 0.34)
    }

    /// The head's own lean in the photograph, so added tilt starts from
    /// where the animal already is rather than from level.
    var restAngle: Angle {
        Angle(radians: atan2(Double(eyeLeft.y - eyeRight.y), Double(eyeLeft.x - eyeRight.x)))
    }
}

@MainActor
enum AnimalPuppet {

    /// The rig for an image, computed once and cached beside it.
    ///
    /// Vision on a full-size photo costs a couple hundred milliseconds
    /// — nothing once, everything if it ran on every crossfade. The
    /// cache is a small JSON sidecar, same shape as the credit files
    /// already sitting there.
    static func rig(for url: URL) -> PuppetRig? {
        if let cached = readCache(url) { return cached.rig }
        let computed = analyse(url)
        writeCache(url, computed)
        return computed
    }

    /// True when this file can be puppeteered — used to decide whether
    /// a picture is worth showing as the living one.
    static func canAnimate(_ url: URL) -> Bool { rig(for: url) != nil }

    // MARK: Vision

    private static func analyse(_ url: URL) -> PuppetRig? {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let req = VNDetectAnimalBodyPoseRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        guard let obs = req.results?.first,
              let pts = try? obs.recognizedPoints(.all) else { return nil }

        // Vision's origin is bottom-left; SwiftUI's is top-left.
        func pt(_ j: VNAnimalBodyPoseObservation.JointName, min conf: Float = 0.5) -> CGPoint? {
            guard let p = pts[j], p.confidence >= conf else { return nil }
            return CGPoint(x: p.location.x, y: 1 - p.location.y)
        }
        // Eyes are the load-bearing pair: without both there is no
        // face axis, no blink and no sensible head disc.
        guard let eL = pt(.leftEye, min: 0.6), let eR = pt(.rightEye, min: 0.6) else { return nil }
        // Ears and nose are nice to have; fall back to a shape derived
        // from the eyes so a dog with one ear hidden still works.
        let span = hypot(eL.x - eR.x, eL.y - eR.y)
        let aL = pt(.leftEarTop) ?? CGPoint(x: eL.x + span * 0.35, y: eL.y - span * 1.1)
        let aR = pt(.rightEarTop) ?? CGPoint(x: eR.x - span * 0.35, y: eR.y - span * 1.1)
        let nose = pt(.nose) ?? CGPoint(x: (eL.x + eR.x) / 2, y: (eL.y + eR.y) / 2 + span * 0.7)

        return PuppetRig(eyeLeft: eL, eyeRight: eR, earLeft: aL, earRight: aR, nose: nose)
    }

    // MARK: Cache

    private struct Cache: Codable {
        let version: Int
        let modified: Date
        let rig: PuppetRig?
    }
    private static let version = 1

    private static func cacheURL(_ url: URL) -> URL {
        url.appendingPathExtension("puppet.json")
    }

    private static func readCache(_ url: URL) -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL(url)),
              let c = try? JSONDecoder().decode(Cache.self, from: data),
              c.version == version else { return nil }
        // A replaced file with the same name is a different animal.
        let mod = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        if let mod, abs(mod.timeIntervalSince(c.modified)) > 1 { return nil }
        return c
    }

    private static func writeCache(_ url: URL, _ rig: PuppetRig?) {
        let mod = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? Date()
        let c = Cache(version: version, modified: mod, rig: rig)
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: cacheURL(url))
        }
    }
}
