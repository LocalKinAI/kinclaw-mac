import AppKit
import SwiftUI

/// How the panel looks, in one place.
///
/// The panel was drawn for dark glass and forced dark with
/// `.preferredColorScheme(.dark)`, which an NSHostingView inside a plain
/// NSPanel never passes on to its window. On a Mac in light mode it came up
/// flat grey: every `Color.white.opacity(…)` meant as a card vanished into it,
/// and each tab had picked its own accent — green tabs, blue-purple film
/// pills, a blue game. These are the few values things are drawn with now,
/// each with a light and a dark side; `Appearance` says which side is up.
enum Theme {
    /// The one accent: the jade the app has always had, a shade deeper so
    /// white type on it reads. Kept for what is chosen and what starts things.
    static let accent = Color(light: 0x14864D, dark: 0x3CC57E)
    /// Behind a chosen chip or row.
    static let accentWash = Color(light: 0x14864D, lightAlpha: 0.12, dark: 0x3CC57E, darkAlpha: 0.2)

    /// The window's ground. Nearly opaque, so the panel looks the same in
    /// front and behind other windows; a little of the blur still shows.
    static let canvas = Color(light: 0xF7F6F3, lightAlpha: 0.94, dark: 0x1C1C1F, darkAlpha: 0.9)
    /// Sidebars: a step down from the canvas.
    static let sidebar = Color(light: 0xEDECE8, lightAlpha: 0.94, dark: 0x151517, darkAlpha: 0.92)
    /// Cards: a step up.
    static let card = Color(light: 0xFFFFFF, dark: 0x29292D)
    /// Fields, tracks and wells on a card or the canvas.
    static let well = Color(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.07)
    /// Under the pointer.
    static let hover = Color(light: 0x000000, lightAlpha: 0.065, dark: 0xFFFFFF, darkAlpha: 0.1)
    /// Lines between things.
    static let hairline = Color(light: 0x000000, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.1)
    /// Something to notice that is not an error: a note on a shot.
    static let notice = Color(light: 0xA85B00, dark: 0xF2AA48)
    static let good = Color(light: 0x14864D, dark: 0x3CC57E)
    static let bad = Color(light: 0xC0392B, dark: 0xFF6B5E)
    /// Second opinions, told apart from the reviewer's own number.
    static let laya = Color(light: 0x2F6FD0, dark: 0x6EA4FF)
    static let jev = Color(light: 0x7A4CC2, dark: 0xB08CFF)

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 9
        static let large: CGFloat = 13
    }
}

extension Color {
    /// One colour in light mode and another in dark, picked when drawn.
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: CGFloat(isDark ? darkAlpha : lightAlpha))
        })
    }
}

extension Font {
    /// A page's or a film's name.
    static let kinTitle = Font.system(size: 17, weight: .semibold)
    /// A section, a card's name.
    static let kinHeadline = Font.system(size: 13, weight: .semibold)
    static let kinBody = Font.system(size: 13)
    /// Controls, rows in a list.
    static let kinLabel = Font.system(size: 12)
    /// What sits under a name: a status, a count.
    static let kinCaption = Font.system(size: 11)
    /// Badges on a picture.
    static let kinMicro = Font.system(size: 10, weight: .semibold)
}

/// Light, dark, or whatever the Mac is set to.
///
/// Set on the app, not on a view: the window, its blur and the SwiftUI in it
/// all follow `NSApp.appearance`, which `.preferredColorScheme` inside an
/// NSHostingView does not reach.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "kinclaw.appearance"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    @MainActor static func apply() {
        switch current {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Pieces

extension View {
    /// A card: lifted off the canvas by its colour, a hairline and a breath of shadow.
    func card(radius: CGFloat = Theme.Radius.large) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    /// A field or a group of controls sunk a little into what it sits on.
    func well(radius: CGFloat = Theme.Radius.medium) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.well))
    }
}

/// The small rounded thing a choice is shown as: on, off, or a menu's current value.
struct ChipLabel: View {
    let title: String
    var symbol: String? = nil
    var on = false
    /// A menu: a small chevron says there is more behind it.
    var menu = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(title).font(.kinLabel).lineLimit(1)
            if menu { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.55) }
        }
        .foregroundStyle(on ? Theme.accent : Color.primary.opacity(0.8))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(on ? Theme.accentWash : hovering ? Theme.hover : Theme.well))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}

/// The one button on a surface that starts the thing it is for.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

/// Everything else a hand presses: quiet until the pointer is on it.
struct QuietButtonStyle: ButtonStyle {
    var destructive = false
    /// Sunk into the bar even at rest: for a button beside a field, where
    /// a bare word reads as a label.
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, destructive: destructive, filled: filled)
    }

    private struct Styled: View {
        let configuration: Configuration
        let destructive: Bool
        let filled: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.kinLabel)
                .foregroundStyle(destructive ? Theme.bad : Color.primary.opacity(0.85))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed || (filled && hovering) ? Theme.hover
                          : hovering || filled ? Theme.well : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 && enabled }
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
    static var quietFilled: QuietButtonStyle { QuietButtonStyle(filled: true) }
}

/// A small heading over a part of a page.
struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let detail { Text(detail).font(.kinCaption).foregroundStyle(.tertiary) }
        }
    }
}

