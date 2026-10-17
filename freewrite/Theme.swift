//
//  Theme.swift
//  Considered
//
//  Palette and typography. Warm paper, soft ink, one quiet accent.
//

import SwiftUI
import AppKit

struct Palette {
    let paper: NSColor
    let sidebar: NSColor
    let ink: NSColor
    let secondaryInk: NSColor
    let faintInk: NSColor
    let focusDim: NSColor
    let hairline: NSColor
    let accent: NSColor
    let selection: NSColor
    let thoughtStage: NSColor
    let developingStage: NSColor
    let consideredStage: NSColor

    static let light = Palette(
        paper: NSColor(srgbRed: 0.973, green: 0.965, blue: 0.945, alpha: 1),
        sidebar: NSColor(srgbRed: 0.949, green: 0.937, blue: 0.910, alpha: 1),
        ink: NSColor(srgbRed: 0.165, green: 0.157, blue: 0.149, alpha: 1),
        secondaryInk: NSColor(srgbRed: 0.478, green: 0.459, blue: 0.427, alpha: 1),
        faintInk: NSColor(srgbRed: 0.700, green: 0.678, blue: 0.639, alpha: 1),
        focusDim: NSColor(srgbRed: 0.780, green: 0.765, blue: 0.735, alpha: 1),
        hairline: NSColor(srgbRed: 0.165, green: 0.157, blue: 0.149, alpha: 0.08),
        accent: NSColor(srgbRed: 0.761, green: 0.376, blue: 0.243, alpha: 1),
        selection: NSColor(srgbRed: 0.761, green: 0.376, blue: 0.243, alpha: 0.16),
        thoughtStage: NSColor(srgbRed: 0.600, green: 0.580, blue: 0.545, alpha: 1),
        developingStage: NSColor(srgbRed: 0.835, green: 0.600, blue: 0.239, alpha: 1),
        consideredStage: NSColor(srgbRed: 0.373, green: 0.576, blue: 0.443, alpha: 1)
    )

    static let dark = Palette(
        paper: NSColor(srgbRed: 0.094, green: 0.090, blue: 0.086, alpha: 1),
        sidebar: NSColor(srgbRed: 0.118, green: 0.114, blue: 0.106, alpha: 1),
        ink: NSColor(srgbRed: 0.871, green: 0.855, blue: 0.824, alpha: 1),
        secondaryInk: NSColor(srgbRed: 0.561, green: 0.541, blue: 0.510, alpha: 1),
        faintInk: NSColor(srgbRed: 0.380, green: 0.365, blue: 0.341, alpha: 1),
        focusDim: NSColor(srgbRed: 0.300, green: 0.290, blue: 0.275, alpha: 1),
        hairline: NSColor(srgbRed: 0.871, green: 0.855, blue: 0.824, alpha: 0.08),
        accent: NSColor(srgbRed: 0.878, green: 0.541, blue: 0.384, alpha: 1),
        selection: NSColor(srgbRed: 0.878, green: 0.541, blue: 0.384, alpha: 0.22),
        thoughtStage: NSColor(srgbRed: 0.561, green: 0.541, blue: 0.510, alpha: 1),
        developingStage: NSColor(srgbRed: 0.910, green: 0.698, blue: 0.361, alpha: 1),
        consideredStage: NSColor(srgbRed: 0.502, green: 0.718, blue: 0.561, alpha: 1)
    )

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }

    func stageColor(_ stage: Stage) -> NSColor {
        switch stage {
        case .thought: return thoughtStage
        case .developing: return developingStage
        case .considered: return consideredStage
        }
    }

    var paperColor: Color { Color(nsColor: paper) }
    var sidebarColor: Color { Color(nsColor: sidebar) }
    var inkColor: Color { Color(nsColor: ink) }
    var secondaryColor: Color { Color(nsColor: secondaryInk) }
    var faintColor: Color { Color(nsColor: faintInk) }
    var hairlineColor: Color { Color(nsColor: hairline) }
    var accentColor: Color { Color(nsColor: accent) }
    func stageSwiftColor(_ stage: Stage) -> Color { Color(nsColor: stageColor(stage)) }
}

enum Typeface: String, CaseIterable, Identifiable {
    case serif
    case mono
    case sans
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .sans: return "Sans"
        case .system: return "System"
        }
    }

    /// PostScript name of the regular face. The Plex faces ship in the bundle (see fonts/).
    var postScriptName: String {
        switch self {
        case .serif: return "IBMPlexSerif-Regular"
        case .mono: return "IBMPlexMono"
        case .sans: return "Lato-Regular"
        case .system: return ".AppleSystemUIFont"
        }
    }

    func nsFont(size: CGFloat) -> NSFont {
        if self == .system {
            return NSFont.systemFont(ofSize: size)
        }
        return NSFont(name: postScriptName, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func swiftUIFont(size: CGFloat) -> Font {
        if self == .system {
            return .system(size: size)
        }
        return .custom(postScriptName, size: size)
    }

    /// Comfortable measure: roughly 64–72 characters per line.
    func columnWidth(fontSize: CGFloat) -> CGFloat {
        switch self {
        case .mono: return fontSize * 38
        case .serif, .sans, .system: return fontSize * 35
        }
    }

    /// Mono keeps headings at body size, like iA Writer; proportional faces scale them gently.
    var scalesHeadings: Bool { self != .mono }
}

enum FontRegistry {
    /// Registers every bundled .ttf so NSFont(name:) can find all weights and styles.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
