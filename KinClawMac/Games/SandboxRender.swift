import AppKit
import SceneKit

/// 沙盒搭建 drawn in 3D: every block a cube with a 16-pixel texture, only the
/// faces that can be seen, corners and crevices darkened as light would be
/// kept out of them, the sun casting shadows, a sky that fades into fog at
/// the edge of the world.

enum SandboxArt {
    static let tile = 16, cols = 8, rows = 4

    enum Face { case top, side, bottom }

    /// Which picture in the atlas a block shows on a face.
    static func picture(_ b: Block, _ face: Face) -> Int {
        switch b {
        case .grass: return face == .top ? 0 : face == .side ? 1 : 2
        case .dirt: return 2
        case .stone: return 3
        case .sand: return 4
        case .water: return 5
        case .log: return face == .side ? 6 : 7
        case .leaves: return 8
        case .planks: return 9
        case .cobble: return 10
        case .bricks: return 11
        case .glass: return 12
        case .snow: return 13
        case .gold: return 15
        case .roof: return 16
        case .wool: return 17
        case .lamp: return 18
        case .pine: return 19
        case .sandstone: return face == .side ? 20 : 21
        case .ice: return 22
        case .coal: return 23
        case .air: return 0
        }
    }

    /// The picture's corner in texture coordinates, a hair inside so neighbours do not bleed in.
    static func uv(_ index: Int) -> (Float, Float, Float, Float) {
        let c = index % cols, r = index / cols
        let w = 1 / Float(cols), h = 1 / Float(rows), e: Float = 0.002
        return (Float(c) * w + e, Float(r) * h + e, Float(c + 1) * w - e, Float(r + 1) * h - e)
    }

    /// All the pictures, painted pixel by pixel.
    static func atlas() -> CGImage {
        let W = cols * tile, H = rows * tile
        var pixels = [UInt8](repeating: 0, count: W * H * 4)
        func noise(_ x: Int, _ y: Int, _ s: Int) -> Double { Double(JevDraw.hash(x * 131 + s * 7919, y * 977 + s) % 1000) / 1000 }
        func paint(_ index: Int, _ f: (Int, Int) -> (Double, Double, Double, Double)) {
            let ox = (index % cols) * tile, oy = (index / cols) * tile
            for y in 0..<tile { for x in 0..<tile {
                let (r, g, b, a) = f(x, y)
                let i = ((oy + y) * W + ox + x) * 4
                pixels[i] = UInt8(max(0, min(1, r)) * 255 * a); pixels[i + 1] = UInt8(max(0, min(1, g)) * 255 * a)
                pixels[i + 2] = UInt8(max(0, min(1, b)) * 255 * a); pixels[i + 3] = UInt8(max(0, min(1, a)) * 255)
            } }
        }
        func tone(_ c: (Double, Double, Double), _ k: Double) -> (Double, Double, Double, Double) { (c.0 * k, c.1 * k, c.2 * k, 1) }
        let grass = (0.38, 0.64, 0.24), dirt = (0.55, 0.38, 0.24)
        paint(0) { x, y in tone(grass, 0.82 + noise(x, y, 1) * 0.3 + (noise(x, y, 2) > 0.9 ? 0.15 : 0)) }
        paint(1) { x, y in
            let edge = 3 + Int(noise(x, 0, 3) * 3)
            return y < edge ? tone(grass, 0.8 + noise(x, y, 4) * 0.28) : tone(dirt, 0.8 + noise(x, y, 5) * 0.3)
        }
        paint(2) { x, y in tone(dirt, 0.78 + noise(x, y, 6) * 0.32 + (noise(x, y, 7) > 0.93 ? -0.25 : 0)) }
        paint(3) { x, y in
            let crack = noise(x / 2, y, 8) > 0.86 && noise(x, y, 9) > 0.4
            return tone((0.52, 0.52, 0.54), crack ? 0.72 : 0.86 + noise(x, y, 10) * 0.24)
        }
        paint(4) { x, y in tone((0.88, 0.8, 0.56), 0.92 + noise(x, y, 11) * 0.14) }
        paint(5) { x, y in
            let streak = (x + y * 2) % 7 == 0 ? 0.12 : 0
            return (0.22 + streak, 0.46 + streak, 0.82 + streak * 0.5, 0.72)
        }
        paint(6) { x, y in
            let stripe = (x % 4 == 0 || noise(x, y / 3, 12) > 0.85) ? 0.72 : 0.92 + noise(x, y, 13) * 0.14
            return tone((0.44, 0.31, 0.19), stripe)
        }
        paint(7) { x, y in
            let d = hypot(Double(x) - 7.5, Double(y) - 7.5)
            if d > 6.8 { return tone((0.44, 0.31, 0.19), 0.85) }
            return tone((0.74, 0.58, 0.36), Int(d) % 2 == 0 ? 0.88 : 1.02)
        }
        paint(8) { x, y in
            let hole = noise(x, y, 14) > 0.82
            return hole ? tone((0.1, 0.26, 0.08), 1) : tone((0.24, 0.52, 0.18), 0.78 + noise(x, y, 15) * 0.38)
        }
        paint(9) { x, y in
            let seam = y % 4 == 3 || (x == (y / 4 * 5 + 3) % 16 && y % 4 != 3)
            return tone((0.74, 0.57, 0.34), seam ? 0.68 : 0.9 + noise(x / 3, y, 16) * 0.14)
        }
        paint(10) { x, y in
            // Stones: the nearest of a few centres, with dark mortar where two meet.
            let centres = (0..<9).map { k in (Double(k % 3) * 5.5 + 2 + noise(k, 1, 17) * 2, Double(k / 3) * 5.5 + 2 + noise(k, 2, 17) * 2) }
            let d = centres.map { hypot(Double(x) - $0.0, Double(y) - $0.1) }.sorted()
            let mortar = d[1] - d[0] < 1.1
            return tone((0.5, 0.5, 0.52), mortar ? 0.55 : 0.82 + noise(x, y, 18) * 0.3)
        }
        paint(11) { x, y in
            let row = y / 4, offset = row % 2 == 0 ? 0 : 4
            let mortar = y % 4 == 3 || (x + offset) % 8 == 7
            return mortar ? tone((0.8, 0.76, 0.7), 1) : tone((0.66, 0.3, 0.23), 0.86 + noise(x / 2, y, 19) * 0.24)
        }
        paint(12) { x, y in
            let frame = x == 0 || y == 0 || x == 15 || y == 15
            let shine = (x + y == 10 || x + y == 12) && x > 2 && y > 2
            return frame ? (0.86, 0.92, 0.96, 0.95) : shine ? (1, 1, 1, 0.6) : (0.72, 0.86, 0.95, 0.22)
        }
        paint(13) { x, y in tone((0.95, 0.96, 0.99), 0.94 + noise(x, y, 20) * 0.08) }
        paint(14) { x, y in
            let edge = 3 + Int(noise(x, 0, 21) * 3)
            return y < edge ? tone((0.95, 0.96, 0.99), 0.95) : tone(dirt, 0.8 + noise(x, y, 22) * 0.3)
        }
        paint(15) { x, y in
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            let shine = x > 2 && x < 7 && y > 2 && y < 6
            return tone((0.98, 0.8, 0.22), edge ? 0.72 : shine ? 1.18 : 0.92 + noise(x, y, 23) * 0.12)
        }
        paint(16) { x, y in
            let row = y / 4, curve = abs(Double((x + row * 2) % 5) - 2) / 2
            return tone((0.66, 0.27, 0.2), y % 4 == 3 ? 0.62 : 0.84 + curve * 0.2 + noise(x, y, 24) * 0.08)
        }
        paint(17) { x, y in tone((0.93, 0.91, 0.87), (x + y) % 3 == 0 ? 0.9 : 0.98 + noise(x, y, 25) * 0.05) }
        paint(18) { x, y in
            let frame = x < 2 || y < 2 || x > 13 || y > 13
            return frame ? tone((0.42, 0.3, 0.18), 1) : tone((1, 0.86, 0.46), 0.92 + noise(x, y, 26) * 0.12)
        }
        paint(19) { x, y in
            let needle = (x + y * 3) % 5 == 0
            return tone((0.13, 0.36, 0.22), needle ? 1.25 : 0.78 + noise(x, y, 27) * 0.3)
        }
        paint(20) { x, y in tone((0.86, 0.78, 0.56), y % 5 == 4 ? 0.82 : 0.95 + noise(x, y / 2, 28) * 0.08) }
        paint(21) { x, y in tone((0.88, 0.8, 0.58), 0.94 + noise(x, y, 29) * 0.08) }
        paint(22) { x, y in
            let crack = (x * 3 + y * 5) % 17 == 0
            return crack ? (0.95, 0.98, 1, 0.85) : (0.66, 0.84, 0.96, 0.72)
        }
        paint(23) { x, y in
            let fleck = noise(x, y, 30) > 0.9
            return tone((0.15, 0.15, 0.17), fleck ? 1.9 : 0.8 + noise(x / 2, y / 2, 31) * 0.4)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// The scene: chunks of land, the sun, the sky, the camera, and the cursor's outline.
@MainActor
final class SandboxStage {
    let scene = SCNScene()
    let camera = SCNNode()
    let sun = SCNNode()
    let cursor = SCNNode()
    let ghost = SCNNode()
    /// What the camera turns around.
    private(set) var focus = SCNVector3(Float(SandboxWorld.sx) / 2, 14, Float(SandboxWorld.sz) / 2)
    private var chunks: [Int: SCNNode] = [:]
    private let solid = SCNMaterial(), seeThrough = SCNMaterial(), water = SCNMaterial()

    init() {
        let atlas = SandboxArt.atlas()
        for m in [solid, seeThrough, water] {
            m.diffuse.contents = atlas
            m.diffuse.magnificationFilter = .nearest
            m.diffuse.minificationFilter = .nearest
            m.diffuse.mipFilter = .none
            m.lightingModel = .lambert
        }
        seeThrough.transparencyMode = .aOne
        seeThrough.isDoubleSided = true
        water.transparencyMode = .aOne
        water.isDoubleSided = true
        water.writesToDepthBuffer = false
        water.lightingModel = .blinn
        water.specular.contents = NSColor(white: 0.6, alpha: 1)
        water.shininess = 0.8

        // The sky, and haze at the edge of the world.
        let sky = NSColor(red: 0.56, green: 0.74, blue: 0.95, alpha: 1)
        scene.background.contents = Self.skyImage()
        scene.fogColor = NSColor(red: 0.74, green: 0.84, blue: 0.95, alpha: 1)
        scene.fogStartDistance = 60
        scene.fogEndDistance = 150
        scene.fogDensityExponent = 1.3

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 420
        ambient.light!.color = NSColor(red: 0.78, green: 0.84, blue: 0.96, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 900
        sun.light!.color = NSColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        sun.light!.castsShadow = true
        sun.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light!.shadowRadius = 1.5
        sun.light!.shadowSampleCount = 4
        sun.light!.shadowColor = NSColor(white: 0, alpha: 0.62)
        sun.light!.automaticallyAdjustsShadowProjection = true
        sun.light!.maximumShadowDistance = 120
        sun.position = SCNVector3(Float(SandboxWorld.sx) / 2 - 55, 62, Float(SandboxWorld.sz) / 2 - 25)
        sun.look(at: SCNVector3(Float(SandboxWorld.sx) / 2, 8, Float(SandboxWorld.sz) / 2))
        scene.rootNode.addChildNode(sun)
        _ = sky

        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = 52
        camera.camera!.zNear = 0.2
        camera.camera!.zFar = 400
        camera.camera!.wantsHDR = false
        camera.position = SCNVector3(focus.x + 26, focus.y + 22, focus.z + 30)
        camera.look(at: focus)
        scene.rootNode.addChildNode(camera)

        cursor.geometry = Self.outline()
        cursor.isHidden = true
        scene.rootNode.addChildNode(cursor)
        let box = SCNBox(width: 1.02, height: 1.02, length: 1.02, chamferRadius: 0)
        let glow = SCNMaterial()
        glow.diffuse.contents = NSColor(white: 1, alpha: 0.28)
        glow.lightingModel = .constant
        glow.transparencyMode = .aOne
        box.materials = [glow]
        ghost.geometry = box
        ghost.isHidden = true
        scene.rootNode.addChildNode(ghost)
    }

    static func skyImage() -> NSImage {
        let size = NSSize(width: 8, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor(red: 0.74, green: 0.84, blue: 0.95, alpha: 1), NSColor(red: 0.42, green: 0.62, blue: 0.92, alpha: 1)], atLocations: [0, 1], colorSpace: .deviceRGB)
            gradient?.draw(in: rect, angle: 90)
            return true
        }
    }

    /// Twelve edges of a block, for the one under the pointer.
    static func outline() -> SCNGeometry {
        let e: Float = 0.004
        let corners = [SCNVector3(-e, -e, -e), SCNVector3(1 + e, -e, -e), SCNVector3(1 + e, -e, 1 + e), SCNVector3(-e, -e, 1 + e),
                       SCNVector3(-e, 1 + e, -e), SCNVector3(1 + e, 1 + e, -e), SCNVector3(1 + e, 1 + e, 1 + e), SCNVector3(-e, 1 + e, 1 + e)]
        let edges: [UInt16] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: corners)], elements: [SCNGeometryElement(indices: edges, primitiveType: .line)])
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(white: 0.05, alpha: 1)
        m.lightingModel = .constant
        g.materials = [m]
        return g
    }

    /// Draw again the chunks whose blocks changed.
    func refresh(_ world: inout SandboxWorld) {
        for c in world.dirty.sorted() {
            chunks[c]?.removeFromParentNode()
            chunks[c] = nil
            if let geometry = mesh(world, chunk: c) {
                let node = SCNNode(geometry: geometry)
                node.castsShadow = true
                scene.rootNode.addChildNode(node)
                chunks[c] = node
            }
        }
        world.dirty = []
    }

    // MARK: Meshing

    private static let faces: [(normal: (Int, Int, Int), u: (Int, Int, Int), v: (Int, Int, Int), face: SandboxArt.Face)] = [
        ((0, 1, 0), (1, 0, 0), (0, 0, -1), .top), ((0, -1, 0), (1, 0, 0), (0, 0, 1), .bottom),
        ((1, 0, 0), (0, 0, -1), (0, 1, 0), .side), ((-1, 0, 0), (0, 0, 1), (0, 1, 0), .side),
        ((0, 0, 1), (1, 0, 0), (0, 1, 0), .side), ((0, 0, -1), (-1, 0, 0), (0, 1, 0), .side),
    ]

    /// One chunk as triangles: opaque blocks, see-through blocks, water — only the faces that show.
    func mesh(_ w: SandboxWorld, chunk c: Int) -> SCNGeometry? {
        let cx = (c % SandboxWorld.chunksX) * SandboxWorld.chunk, cz = (c / SandboxWorld.chunksX) * SandboxWorld.chunk
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], colors: [Float] = []
        var opaque: [UInt32] = [], clear: [UInt32] = [], wet: [UInt32] = []
        func occludes(_ x: Int, _ y: Int, _ z: Int) -> Bool { let b = w[x, y, z]; return b != .air && !b.clear }
        for y in 0..<SandboxWorld.sy {
            for z in cz..<min(cz + SandboxWorld.chunk, SandboxWorld.sz) {
                for x in cx..<min(cx + SandboxWorld.chunk, SandboxWorld.sx) {
                    let b = w[x, y, z]
                    guard b != .air else { continue }
                    for f in Self.faces {
                        let n = w[x + f.normal.0, y + f.normal.1, z + f.normal.2]
                        let show: Bool
                        switch b {
                        case .water: show = n == .air
                        case .glass, .ice: show = n != b && n.clear
                        default: show = n.clear
                        }
                        guard show else { continue }
                        // The face's four corners, counter-clockwise seen from outside, with light kept out of the corners.
                        let (u0, v0, u1, v1) = SandboxArt.uv(SandboxArt.picture(b, f.face))
                        let base = UInt32(positions.count)
                        let nx = f.normal.0, ny = f.normal.1, nz = f.normal.2
                        var ao: [Int] = []
                        let lower: Float = b == .water && ny == 1 ? 0.12 : 0
                        for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] {
                            // Corner position: centre of the face plus half steps along u and v.
                            let px = Float(x) + 0.5 + Float(nx) * 0.5 + Float(su * f.u.0 + sv * f.v.0) * 0.5
                            let py = Float(y) + 0.5 + Float(ny) * 0.5 + Float(su * f.u.1 + sv * f.v.1) * 0.5 - (ny == 1 ? lower : 0)
                            let pz = Float(z) + 0.5 + Float(nz) * 0.5 + Float(su * f.u.2 + sv * f.v.2) * 0.5
                            positions.append(SCNVector3(px, py, pz))
                            normals.append(SCNVector3(Float(nx), Float(ny), Float(nz)))
                            uvs.append(CGPoint(x: CGFloat(su < 0 ? u0 : u1), y: CGFloat(sv < 0 ? v1 : v0)))
                            let ox = x + nx, oy = y + ny, oz = z + nz
                            let s1 = occludes(ox + su * f.u.0, oy + su * f.u.1, oz + su * f.u.2)
                            let s2 = occludes(ox + sv * f.v.0, oy + sv * f.v.1, oz + sv * f.v.2)
                            let cn = occludes(ox + su * f.u.0 + sv * f.v.0, oy + su * f.u.1 + sv * f.v.1, oz + su * f.u.2 + sv * f.v.2)
                            let level = s1 && s2 ? 0 : 3 - ((s1 ? 1 : 0) + (s2 ? 1 : 0) + (cn ? 1 : 0))
                            ao.append(level)
                            let light: Float = b == .lamp ? 1.35 : [0.52, 0.68, 0.84, 1.0][level]
                            colors += [light, light, light, 1]
                        }
                        // Split the quad along the diagonal that keeps the corner shading even.
                        let flip = ao[0] + ao[2] < ao[1] + ao[3]
                        let tris: [UInt32] = flip ? [1, 2, 3, 1, 3, 0] : [0, 1, 2, 0, 2, 3]
                        let target = tris.map { base + $0 }
                        switch b {
                        case .water: wet += target
                        case .glass, .ice: clear += target
                        default: opaque += target
                        }
                    }
                }
            }
        }
        guard !positions.isEmpty else { return nil }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: positions.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        var elements: [SCNGeometryElement] = [], materials: [SCNMaterial] = []
        for (indices, material) in [(opaque, solid), (clear, seeThrough), (wet, water)] where !indices.isEmpty {
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
            materials.append(material)
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs), colorSource], elements: elements)
        geometry.materials = materials
        return geometry
    }

    // MARK: Pointing

    /// The block under a hit on the scene, and the empty cell in front of the face that was hit.
    /// Walk the camera and what it turns around together: across the ground in the direction it faces, or up and down.
    func walk(right: CGFloat, forward: CGFloat, up: CGFloat) {
        var ahead = camera.worldFront
        ahead.y = 0
        let length = (ahead.x * ahead.x + ahead.z * ahead.z).squareRoot()
        guard length > 0.001 else { return }
        ahead.x /= length; ahead.z /= length
        let dx = ahead.x * forward - ahead.z * right, dz = ahead.z * forward + ahead.x * right
        go(to: SCNVector3(focus.x + dx, focus.y + up, focus.z + dz))
    }

    /// Carry the view over to look at a place, keeping how it looks.
    func go(to place: SCNVector3) {
        let target = SCNVector3(min(max(place.x, 0), CGFloat(SandboxWorld.sx)), min(max(place.y, 1), CGFloat(SandboxWorld.sy)), min(max(place.z, 0), CGFloat(SandboxWorld.sz)))
        camera.position = SCNVector3(camera.position.x + target.x - focus.x, camera.position.y + target.y - focus.y, camera.position.z + target.z - focus.z)
        focus = target
    }

    static func target(_ hit: SCNHitTestResult) -> (block: BlockPos, before: BlockPos) {
        let p = hit.worldCoordinates, n = hit.worldNormal
        let inside = SCNVector3(p.x - n.x * 0.05, p.y - n.y * 0.05, p.z - n.z * 0.05)
        let block = BlockPos(x: Int(floor(inside.x)), y: Int(floor(inside.y)), z: Int(floor(inside.z)))
        let before = BlockPos(x: block.x + Int(n.x.rounded()), y: block.y + Int(n.y.rounded()), z: block.z + Int(n.z.rounded()))
        return (block, before)
    }
}
