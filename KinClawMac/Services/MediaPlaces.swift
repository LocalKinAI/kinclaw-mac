import Foundation
import Security

/// Where each of the four media capabilities runs.
///
/// Until now every picture, clip and spoken word came from the box — the
/// LAN Mac the app reaches over ssh — and somebody without one had none of
/// them. Now each capability is placed on its own: the box (the way it was,
/// and the default), or a cloud API paid for with the user's own key, which
/// the app relays without a markup. This Mac as its own box is designed too
/// (docs/three-places-plan.md) and waits for a machine to be tested on.
///
/// The Studio's heavy work — H3, Motion, ComfyUI workflows, Montage — stays
/// on the box whatever is chosen here: it needs ComfyUI and ssh, and no
/// cloud API is the same thing.
enum MediaCapability: String, CaseIterable, Identifiable {
    case draw, edit, film, voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw:  return "画"
        case .edit:  return "改"
        case .film:  return "拍"
        case .voice: return "声音"
        }
    }

    /// What the capability is, in a word or two, for the settings row.
    var detail: String {
        switch self {
        case .draw:  return "文生图"
        case .edit:  return "改图、换装、换地方，带参考图"
        case .film:  return "图生视频"
        case .voice: return "说话和听写（克隆、旁白造声音仍在盒子上）"
        }
    }

    /// The places that can do it.
    var places: [MediaPlace] {
        switch self {
        case .draw, .edit: return [.box, .boxFlux, .openai, .google, .xai, .fal, .bailian]
        case .film:        return [.box, .fal]
        case .voice:       return [.box, .bailian, .openai]
        }
    }
}

enum MediaPlace: String, CaseIterable, Identifiable {
    /// The box with its default model (Qwen-Image-2.1-Turbo for 画 and 改), and
    /// the box with FLUX 3 Image Klein instead — a second picture model there,
    /// not another provider: no key, nothing leaves the LAN.
    case box, boxFlux, fal, bailian, openai, google, xai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .box:     return "盒子"
        case .boxFlux: return "盒子·FLUX 3"
        case .fal:     return "fal.ai"
        case .bailian: return "百炼"
        case .openai:  return "OpenAI"
        case .google:  return "Google"
        case .xai:     return "xAI"
        }
    }

    var isCloud: Bool { self != .box && self != .boxFlux }
}

/// The choice for each capability, kept in UserDefaults. A value that is not
/// one of the capability's places — a provider later dropped, a typo from a
/// `defaults write` — reads as the box, the way it always worked.
enum MediaPlacement {
    static func key(_ capability: MediaCapability) -> String { "kinclaw.place.\(capability.rawValue)" }

    static func place(_ capability: MediaCapability) -> MediaPlace {
        let raw = UserDefaults.standard.string(forKey: key(capability)) ?? ""
        guard let place = MediaPlace(rawValue: raw), capability.places.contains(place) else { return .box }
        return place
    }

    static func set(_ place: MediaPlace, for capability: MediaCapability) {
        if place == .box {
            UserDefaults.standard.removeObject(forKey: key(capability))
        } else {
            UserDefaults.standard.set(place.rawValue, forKey: key(capability))
        }
    }
}

/// A cloud provider's API key, in the login Keychain: typed in by the user,
/// read only to be sent as that provider's Authorization header, never
/// logged, never shown. (JevKey's way, for every provider.)
///
/// The environment variable each provider's own tools read wins when it is
/// set — but it only reaches this app when it was started from a shell.
enum CloudKey {
    private static let service = "dev.localkin.kinclawmac.cloud"
    private static let lock = NSLock()
    /// Keys once read, so the Keychain is asked once a launch per provider.
    private static var held: [MediaPlace: String] = [:]
    /// Why the last read of a provider got nothing, when the Keychain said no
    /// rather than "not found".
    private(set) static var refusals: [MediaPlace: OSStatus] = [:]

    static func environmentName(_ place: MediaPlace) -> String? {
        switch place {
        case .box, .boxFlux: return nil
        case .fal:     return "FAL_KEY"
        case .bailian: return "DASHSCOPE_API_KEY"
        case .openai:  return "OPENAI_API_KEY"
        case .google:  return "GEMINI_API_KEY"
        case .xai:     return "XAI_API_KEY"
        }
    }

    private static func query(_ place: MediaPlace) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: place.rawValue]
    }

    private static func environment(_ place: MediaPlace) -> String? {
        guard let name = environmentName(place) else { return nil }
        let value = (ProcessInfo.processInfo.environment[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Is there a key? Only the item's attributes are asked for, which no
    /// access list guards — so looking never raises a dialog. (This app is
    /// signed ad hoc: to the Keychain every rebuild is a different program
    /// from the one that stored the key.)
    static func present(_ place: MediaPlace) -> Bool {
        guard place.isCloud else { return true }
        if environment(place) != nil { return true }
        var ask = query(place)
        ask[kSecReturnAttributes as String] = true
        ask[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        return SecItemCopyMatching(ask as CFDictionary, &found) == errSecSuccess
    }

    /// The key. `asking` says whether the Keychain may put up its consent
    /// dialog: yes when somebody just pressed a button and is there to answer;
    /// no for everything unattended (a film drawing its shots, a tool call),
    /// where an unexpected dialog would stall the work until somebody came
    /// back. Unasked, a refusal is an error that says what to do.
    static func read(_ place: MediaPlace, asking: Bool = false) -> String? {
        guard place.isCloud else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let key = held[place] { return key }
        if let key = environment(place) { held[place] = key; refusals[place] = nil; return key }
        var ask = query(place)
        ask[kSecReturnData as String] = true
        ask[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        if !asking { SecKeychainSetUserInteractionAllowed(false) }
        let status = SecItemCopyMatching(ask as CFDictionary, &found)
        if !asking { SecKeychainSetUserInteractionAllowed(true) }
        if status == errSecSuccess, let data = found as? Data, let key = String(data: data, encoding: .utf8) {
            held[place] = key; refusals[place] = nil
            return key
        }
        refusals[place] = status == errSecItemNotFound ? nil : status
        return nil
    }

    /// Store a key, or with an empty one forget it.
    @discardableResult
    static func write(_ key: String, for place: MediaPlace) -> Bool {
        guard place.isCloud else { return false }
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); held[place] = nil; refusals[place] = nil; lock.unlock()
        SecItemDelete(query(place) as CFDictionary)
        guard !cleaned.isEmpty else { return true }
        var item = query(place)
        item[kSecValueData as String] = Data(cleaned.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// The key or an error a person can act on.
    static func required(_ place: MediaPlace, asking: Bool = false) throws -> String {
        if let key = read(place, asking: asking) { return key }
        if refusals[place] != nil {
            throw MediaCloudError.message("钥匙串没让读 \(place.title) 的 key（这个 App 每次重新编译，钥匙串都当它是新程序）：到 设置 → 画·改·拍·声音 里点一次「试一下」，在弹出的对话框里允许")
        }
        throw MediaCloudError.message("还没有 \(place.title) 的 key：到 设置 → 画·改·拍·声音 里填上")
    }
}

enum MediaCloudError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}
