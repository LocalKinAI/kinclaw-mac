import CoreImage
import Foundation
import Vision

/// A reference picture made ready for the editor: cut to the camera the shot
/// asks for, and with her face taken out of it.
///
/// Both come from one measurement. In a full-length wide shot at 704 pixels
/// her face is about fifty pixels across, and at fifty pixels neither the
/// image editor nor the video model holds an identity: the woman in the first
/// three shots of 公园太极 was nobody in particular, a little older in each clip
/// ("三脸也变了啊"). Asking for "medium shot, waist up" did not help, because the
/// two pictures the editor is shown — the master and the last frame — are wide
/// shots, and it composes what it is shown. So:
///
/// - **The references are cropped to the framing** before they are sent. Shown
///   two waist-up pictures, the editor makes a waist-up picture: face 128 px
///   instead of 57. The camera is set by a rectangle, not by an adjective.
/// - **Her face is blurred out of every reference but the anchor.** The last
///   frame of a video clip carries a face that has already drifted, and with
///   it in view the editor copies that one: cropped only, the result was a
///   sharp portrait of the wrong woman. With the face blurred there is one
///   face on the table, the anchor's, and the result is recognisably her.
enum FilmReference {

    /// How much of her the camera takes in, as a multiple of the height of
    /// her face: the side of the square that is kept. Nil keeps everything.
    ///
    /// Only what the storyboard asked for. An earlier version cut everything
    /// it did not recognise to waist-up, to keep her face large — and a film
    /// of tai chi became a film of a woman moving her arms (Jacky: "拉近镜头完全就
    /// 不是太极动作了"). The camera belongs to the film; her face is looked after
    /// by `restoreFace`, where she stands.
    static func reach(of framing: String?) -> CGFloat? {
        let words = (framing ?? "").lowercased()
        if ["whole body", "full body", "full-length", "full length", "wide", "establishing", "head to foot"]
            .contains(where: words.contains) { return nil }
        if words.contains("hand") { return 4.4 }        // hands at chest or waist height stay in
        if ["close", "chest", "shoulders", "portrait"].contains(where: words.contains) { return 3.4 }
        if ["knee", "three-quarter length", "thigh"].contains(where: words.contains) { return 7.5 }
        if ["medium", "waist"].contains(where: words.contains) { return 5.5 }
        return nil                                       // not said, or not understood: as the pictures are
    }

    /// Writes the prepared picture to `file` and returns it; returns `source`
    /// untouched when there is nothing to do or no face to work from — she
    /// has her back to the camera, or the picture has nobody in it.
    static func prepare(_ source: URL, as file: URL, framing: String?, faceless: Bool) -> URL {
        guard let picture = CIImage(contentsOf: source), let face = face(in: picture) else { return source }
        let reach = reach(of: framing)
        guard faceless || reach != nil else { return source }
        var made = picture
        if faceless {
            let margin = face.width * 0.25
            let area = face.insetBy(dx: -margin, dy: -margin).intersection(picture.extent)
            let soft = picture.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: face.width * 0.35])
                .cropped(to: area)
            made = soft.composited(over: picture)
        }
        if let reach {
            let side = face.height * reach
            let bounds = picture.extent
            if side < min(bounds.width, bounds.height) {
                // A little air above her head, then down from there; slid back
                // inside the picture when she stands near an edge of it.
                let top = min(face.maxY + face.height * 0.9, bounds.maxY)
                let x = min(max(face.midX - side / 2, bounds.minX), bounds.maxX - side)
                let y = min(max(top - side, bounds.minY), bounds.maxY - side)
                let cut = made.cropped(to: CGRect(x: x, y: y, width: side, height: side))
                made = cut.transformed(by: CGAffineTransform(translationX: -x, y: -y))
                    .applyingFilter("CILanczosScaleTransform",
                                    parameters: [kCIInputScaleKey: 768 / side, kCIInputAspectRatioKey: 1.0])
            }
        }
        let context = CIContext()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              (try? context.writePNGRepresentation(of: made, to: file, format: .RGBA8, colorSpace: space)) != nil
        else { return source }
        return file
    }

    /// The largest face in the picture, in the picture's own coordinates
    /// (origin bottom left, as Core Image and Vision both have it).
    static func face(in picture: CIImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: picture, options: [:])
        guard (try? handler.perform([request])) != nil,
              let found = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return nil }
        let box = found.boundingBox, size = picture.extent
        return CGRect(x: size.minX + box.minX * size.width, y: size.minY + box.minY * size.height,
                      width: box.width * size.width, height: box.height * size.height)
    }

    // MARK: Her face, where the camera is too far away to have kept it

    /// Below this many pixels across, a face that an editor drew is nobody's.
    static let smallFace: CGFloat = 110

    /// The head, cut out of a still and enlarged for the editor to work on.
    /// Returns where it was cut from, to put the answer back.
    static func head(of still: URL, to file: URL) -> (face: CGRect, cut: CGRect)? {
        guard let picture = CIImage(contentsOf: still), let face = face(in: picture),
              face.width < smallFace else { return nil }
        let bounds = picture.extent
        let side = min(face.width * 3.2, bounds.width, bounds.height)
        let x = min(max(face.midX - side / 2, bounds.minX), bounds.maxX - side)
        let y = min(max(face.midY - side / 2, bounds.minY), bounds.maxY - side)
        let cut = CGRect(x: x, y: y, width: side, height: side)
        let enlarged = picture.cropped(to: cut)
            .transformed(by: CGAffineTransform(translationX: -x, y: -y))
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 768 / side, kCIInputAspectRatioKey: 1.0])
        return write(enlarged, to: file) ? (face, cut) : nil
    }

    /// What the editor is asked to do with that head.
    static let headPrompt = """
        Replace the face in image 1 with the face of the woman in image 2: her exact eyes, eyebrows, nose, mouth \
        and face shape. Keep everything else in image 1 exactly as it is: the angle of the head, the hair, the \
        collar and shoulders, the background, the light and the colours. Neutral relaxed expression, mouth \
        closed. Sharp, natural photograph.
        """

    /// Put the editor's face into the still, where the still's own face is.
    ///
    /// The editor does not keep image 1's composition, whatever it is told —
    /// asked to change only the face, it hands back a fresh head-and-shoulders
    /// portrait, and pasted back as it came that was a face twice the size of
    /// the head it landed on. So its answer is *aligned*: the face found in
    /// it is scaled and moved onto the face found in the still, and only an
    /// ellipse inside the face is taken, feathered, so the hair, the collar
    /// and the background stay the still's own. Measured on a full-length
    /// still with a 66-pixel face: sharper, the anchor's brows and eyes, no
    /// seam to be seen at the size it is shown — and the camera where it was.
    static func inlay(_ answer: URL, into still: URL, at face: CGRect, as file: URL) -> Bool {
        guard let picture = CIImage(contentsOf: still), let drawn = CIImage(contentsOf: answer),
              let theirs = Self.face(in: drawn), theirs.width > 0 else { return false }
        let scale = face.width / theirs.width
        let moved = drawn
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: face.midX - theirs.midX * scale,
                                               y: face.midY - theirs.midY * scale))
        // A soft-edged disc, stretched into the ellipse of a face.
        let tall: CGFloat = 1.28
        let disc = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: face.midX, y: face.midY / tall),
            "inputRadius0": face.width * 0.40, "inputRadius1": face.width * 0.60,
            "inputColor0": CIColor.white, "inputColor1": CIColor.clear,
        ])?.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 1, y: tall))
            .cropped(to: picture.extent)
        guard let mask = disc else { return false }
        let made = moved.cropped(to: picture.extent)
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: picture, kCIInputMaskImageKey: mask])
            .cropped(to: picture.extent)
        return write(made, to: file)
    }

    private static func write(_ picture: CIImage, to file: URL) -> Bool {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        return (try? CIContext().writePNGRepresentation(of: picture, to: file, format: .RGBA8, colorSpace: space)) != nil
    }

    /// How wide her face is in a picture, in pixels — what a reviewer, or a
    /// log line, can say about whether a frame is close enough to hold her.
    static func faceWidth(in url: URL) -> Int? {
        guard let picture = CIImage(contentsOf: url), let face = face(in: picture) else { return nil }
        return Int(face.width)
    }
}
