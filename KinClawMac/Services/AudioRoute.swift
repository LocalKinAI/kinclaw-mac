import CoreAudio
import Foundation

/// Where the sound is going, as far as echo is concerned.
///
/// Barge-in listens while the agent talks. Through headphones that is
/// safe: the microphone hears the room, and the room is you. Through
/// the built-in speakers it is not — measured on this machine, the mic
/// picks the agent's own voice up at -14…-4 dBFS even with voice
/// processing on, which trips any level-based trigger within a second
/// or two. So the policy asks the output route first.
enum AudioRoute {

    /// True when the default output is the Mac's own speakers (or any
    /// route that cannot be told apart from them). Headphones, AirPods,
    /// USB / Bluetooth headsets and external interfaces return false.
    static func isBuiltInSpeaker() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return true }

        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr else { return true }
        // Anything not built in — Bluetooth, USB, DisplayPort, AirPlay —
        // is a headset or an external speaker; only the latter echoes,
        // and it is the rarer setup, so treat external as safe.
        guard transport == kAudioDeviceTransportTypeBuiltIn else { return false }

        // Built-in output has two data sources: internal speaker and the
        // headphone jack. 'hdpn' is the jack.
        var source = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &source) == noErr {
            let hdpn: UInt32 = 0x6864_706E  // 'hdpn'
            return source != hdpn
        }
        return true
    }

    /// The user's choice for interrupting the agent by talking over it:
    /// "auto" (only when the output route cannot echo), "on", "off".
    static let bargeInKey = "kinclaw.voice.bargeIn"

    static func bargeInAllowed() -> Bool {
        switch UserDefaults.standard.string(forKey: bargeInKey) ?? "auto" {
        case "on":  return true
        case "off": return false
        default:    return !isBuiltInSpeaker()
        }
    }
}
