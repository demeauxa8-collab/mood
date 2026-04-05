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

    static var serverBar: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "000000")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "e3e5e8")
        }
    }

    static var channelList: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "0a0a0a")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "f2f3f5")
        }
    }

    static var chatBackground: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "111113")
        case .amoled: return Color(hex: "050505")
        case .light:  return Color(hex: "ffffff")
        }
    }

    static var memberList: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "0a0a0a")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "f2f3f5")
        }
    }

    static var inputBg: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.06)
        case .amoled: return Color.white.opacity(0.06)
        case .light:  return Color(hex: "ebedef")
        }
    }

    static var hoverBg: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.05)
        case .amoled: return Color.white.opacity(0.05)
        case .light:  return Color.black.opacity(0.04)
        }
    }

    static var selectedBg: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.10)
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color.black.opacity(0.08)
        }
    }

    static var popupBg: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "0a0a0a")
        case .amoled: return Color(hex: "000000")
        case .light:  return Color(hex: "ffffff")
        }
    }

    // — Glass surfaces —

    static var glassBg: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.06)
        case .amoled: return Color.white.opacity(0.06)
        case .light:  return Color.black.opacity(0.04)
        }
    }

    static var glassBorder: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.10)
        case .amoled: return Color.white.opacity(0.10)
        case .light:  return Color.black.opacity(0.08)
        }
    }

    static var glassHighlight: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.15)
        case .amoled: return Color.white.opacity(0.15)
        case .light:  return Color.black.opacity(0.06)
        }
    }

    // — Texte —

    static var textPrimary: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "f5f5f7")
        case .amoled: return Color(hex: "f5f5f7")
        case .light:  return Color(hex: "060607")
        }
    }

    static var textSecondary: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "86868b")
        case .amoled: return Color(hex: "86868b")
        case .light:  return Color(hex: "4e5058")
        }
    }

    static var textMuted: Color {
        switch shared.theme {
        case .dark:   return Color(hex: "424245")
        case .amoled: return Color(hex: "424245")
        case .light:  return Color(hex: "a0a3a8")
        }
    }

    // — Accents —

    static var brandAccent: Color { shared.accent.color }

    static var brandBlue: Color { Color(hex: "2997ff") }

    static var mentionBadge: Color { Color(hex: "da373c") }

    static var onlineGreen: Color { Color(hex: "34c759") }

    // — Server icons —

    static var serverIconBg: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.06)
        case .amoled: return Color.white.opacity(0.06)
        case .light:  return Color.black.opacity(0.04)
        }
    }

    static var serverIconSelected: Color { shared.accent.color }

    // — Dividers —

    static var divider: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.08)
        case .amoled: return Color.white.opacity(0.08)
        case .light:  return Color.black.opacity(0.06)
        }
    }

    // — Message hover —

    static var messageHover: Color {
        switch shared.theme {
        case .dark:   return Color.white.opacity(0.03)
        case .amoled: return Color.white.opacity(0.03)
        case .light:  return Color.black.opacity(0.02)
        }
    }

    // — Gradients —

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [shared.accent.color, Color(hex: "2997ff")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleGlow: RadialGradient {
        RadialGradient(
            colors: [shared.accent.color.opacity(0.15), Color.clear],
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
