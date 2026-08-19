import SwiftUI

// MARK: - Theme Manager (source de vérité pour le thème actif)

enum AppTheme: String, CaseIterable {
    case dark = "Sombre"
    case amoled = "AMOLED"
    case light = "Clair"
}

enum AccentColor: String, CaseIterable {
    case purple = "6e56cf"
    case blue = "2997ff"
    case green = "34c759"
    case yellow = "f0b232"
    case red = "da373c"
    case pink = "e879f9"

    var color: Color { Color(hex: rawValue) }
}

@Observable
class ThemeManager {
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app_theme") }
    }
    var accent: AccentColor {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "app_accent") }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "app_theme"),
           let t = AppTheme(rawValue: raw) {
            theme = t
        } else {
            theme = .dark
        }
        if let raw = UserDefaults.standard.string(forKey: "app_accent"),
           let a = AccentColor(rawValue: raw) {
            accent = a
        } else {
            accent = .purple
        }
    }
}

// Singleton accessible partout (les propriétés static computed en ont besoin)
private let _sharedThemeManager = ThemeManager()

// MARK: - MoodTheme (palette dynamique)

enum MoodTheme {

    static var shared: ThemeManager { _sharedThemeManager }

    // — Backgrounds —

    /// Global desktop chrome sampled from the Figma Discord reference.
    static var windowBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "121214")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "e3e5e8")
        }
    }

    static var titleBar: Color { windowBackground }

    static var serverBar: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "121214")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "e3e5e8")
        }
    }

    static var channelList: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "121214")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "f2f3f5")
        }
    }

    static var chatBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "1a1a1e")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "ffffff")
        }
    }

    static var memberList: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "17171a")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "f2f3f5")
        }
    }

    static var inputBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "222327")
        case .amoled: return Color(hex: "101114")
        case .light:  return Color(hex: "ebedef")
        }
    }

    /// One-pixel outline around Discord's desktop message composer.
    static var composerBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "27282c")
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color.black.opacity(0.10)
        }
    }

    static var hoverBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "202024")
        case .amoled: return Color.white.opacity(0.05)
        case .light:  return Color.black.opacity(0.04)
        }
    }

    static var selectedBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "222225")
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color.black.opacity(0.08)
        }
    }

    /// Selected text/voice channel surface in Discord's server sidebar.
    static var channelSelectedBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "2c2c30")
        case .amoled: return Color.white.opacity(0.14)
        case .light:  return Color.black.opacity(0.10)
        }
    }

    static var headerSearchBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "17171a")
        case .amoled: return Color(hex: "0c0c0e")
        case .light:  return Color(hex: "ffffff")
        }
    }

    static var headerSearchBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "303035")
        case .amoled: return Color.white.opacity(0.14)
        case .light:  return Color.black.opacity(0.12)
        }
    }

    // — Friends list —

    /// Search placeholder sampled from Discord's desktop friends view.
    static var friendsSearchPlaceholder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "8f9097")
        case .amoled: return Color(hex: "949ba4")
        case .light:  return Color(hex: "5c5e66")
        }
    }

    /// Hover surface used by a full row in the desktop friends list.
    static var friendRowHover: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "29292d")
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color.black.opacity(0.07)
        }
    }

    static var friendRowSeparator: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "29292d")
        case .amoled: return Color.white.opacity(0.08)
        case .light:  return Color.black.opacity(0.08)
        }
    }

    static var friendOfflineStatus: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "84858c")
        case .amoled: return Color(hex: "80848e")
        case .light:  return Color(hex: "80848e")
        }
    }

    // — Floating server menu —

    static var serverMenuBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "28282d")
        case .amoled: return Color(hex: "151519")
        case .light:  return Color(hex: "ffffff")
        }
    }

    static var serverMenuHover: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "38393f")
        case .amoled: return Color.white.opacity(0.12)
        case .light:  return Color.black.opacity(0.07)
        }
    }

    static var serverMenuBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "36363b")
        case .amoled: return Color.white.opacity(0.14)
        case .light:  return Color.black.opacity(0.12)
        }
    }

    static var serverMenuSeparator: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "36363b")
        case .amoled: return Color.white.opacity(0.14)
        case .light:  return Color.black.opacity(0.10)
        }
    }

    static var serverMenuDanger: Color {
        switch shared.theme {
        case .dark, .amoled: return Color(hex: "f87f7a")
        case .light:         return Color(hex: "d83c3e")
        }
    }

    static var serverMenuTagBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "3e3e44")
        case .amoled: return Color.white.opacity(0.14)
        case .light:  return Color.black.opacity(0.09)
        }
    }

    static var serverMenuCheckboxBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "252529")
        case .amoled: return Color(hex: "18181c")
        case .light:  return Color.white
        }
    }

    static var serverMenuCheckboxBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "6e6e75")
        case .amoled: return Color.white.opacity(0.42)
        case .light:  return Color.black.opacity(0.32)
        }
    }

    /// Search field surface sampled from the Discord desktop DM sidebar.
    static var dmSearchBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "222225")
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color(hex: "ebedef")
        }
    }

    static var dmSearchBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "262629")
        case .amoled: return Color.white.opacity(0.12)
        case .light:  return Color.black.opacity(0.10)
        }
    }

    static var popupBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "242428")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "ffffff")
        }
    }

    // — Glass surfaces (Discord-style solid fills) —

    static var glassBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "202024")
        case .amoled: return Color.white.opacity(0.055)
        case .light:  return Color.black.opacity(0.04)
        }
    }

    static var glassBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "252529")
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color.black.opacity(0.08)
        }
    }

    /// The workspace outline is darker than floating-panel outlines.
    static var workspaceBorder: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "222225")
        case .amoled: return Color.white.opacity(0.08)
        case .light:  return Color.black.opacity(0.08)
        }
    }

    static var glassHighlight: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "303036")
        case .amoled: return Color.white.opacity(0.15)
        case .light:  return Color.black.opacity(0.06)
        }
    }

    // — Texte (Discord exact) —

    static var textPrimary: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "fbfbfb")
        case .amoled: return Color(hex: "dbdee1")
        case .light:  return Color(hex: "060607")
        }
    }

    static var textSecondary: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "96979e")
        case .amoled: return Color(hex: "949ba4")
        case .light:  return Color(hex: "4e5058")
        }
    }

    static var textSupporting: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "abacb2")
        case .amoled: return Color(hex: "b5bac1")
        case .light:  return Color(hex: "5c5e66")
        }
    }

    static var textSubtle: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "818289")
        case .amoled: return Color(hex: "6d6f78")
        case .light:  return Color(hex: "80848e")
        }
    }

    static var textMuted: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "7d828c")
        case .amoled: return Color(hex: "6d6f78")
        case .light:  return Color(hex: "a0a3a8")
        }
    }

    // — Accents (Discord exact) —

    static var brandAccent: Color { shared.accent.color }

    static var brandBlue: Color { Color(hex: "5865f2") }

    static var mentionBadge: Color { Color(hex: "da373c") }

    static var onlineGreen: Color { Color(hex: "23a559") }

    // — Server icons —

    static var serverIconBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "202024")
        case .amoled: return Color.white.opacity(0.06)
        case .light:  return Color.black.opacity(0.04)
        }
    }

    static var serverIconSelected: Color { shared.accent.color }

    // — Dividers —

    static var divider: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "29292e")
        case .amoled: return Color.white.opacity(0.08)
        case .light:  return Color.black.opacity(0.06)
        }
    }

    // — Message hover —

    static var messageHover: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "1f1f23")
        case .amoled: return Color.white.opacity(0.03)
        case .light:  return Color.black.opacity(0.02)
        }
    }

    // — Gradients —

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [shared.accent.color, Color(hex: "5865f2")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleGlow: RadialGradient {
        RadialGradient(
            colors: [shared.accent.color.opacity(0.10), Color.clear],
            center: .top,
            startRadius: 0,
            endRadius: 300
        )
    }
}

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
