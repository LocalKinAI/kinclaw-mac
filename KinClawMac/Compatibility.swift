// Compatibility.swift
//
// Cross-platform shims so SwiftUI views ported from localkin-ios stay
// readable. Anything iOS-only that has a macOS equivalent goes here.
//
// Convention: don't sprinkle `#if os(iOS)` through views; call the
// shim names defined here. A view ported here should compile on both
// platforms unmodified.

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Open URL (UIApplication / NSWorkspace)

func openExternalURL(_ url: URL) {
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
}

// MARK: - Navigation title display mode (iOS-only modifier)

extension View {
    /// Inline (compact) nav title on iOS; no-op on macOS.
    @ViewBuilder
    func compactNavTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Large nav title on iOS; no-op on macOS.
    @ViewBuilder
    func largeNavTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}

// MARK: - System background (iOS UIColor.systemBackground / macOS NSColor.windowBackgroundColor)

extension Color {
    /// Primary surface — UIColor.systemBackground / NSColor.windowBackgroundColor.
    static var platformBackground: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #elseif os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    /// Slightly elevated surface — UIColor.secondarySystemBackground /
    /// NSColor.controlBackgroundColor.
    static var platformSecondaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #elseif os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    /// Highest elevation surface — UIColor.tertiarySystemBackground /
    /// NSColor.underPageBackgroundColor.
    static var platformTertiaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.tertiarySystemBackground)
        #elseif os(macOS)
        return Color(NSColor.underPageBackgroundColor)
        #endif
    }
}

// MARK: - Toolbar placement (iOS .navigationBarTrailing / macOS .primaryAction)

extension ToolbarItemPlacement {
    /// Trailing edge of nav bar on iOS; primary action on macOS.
    static var trailingAction: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #elseif os(macOS)
        return .primaryAction
        #endif
    }
}
