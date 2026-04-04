import SwiftUI

// MARK: - Mood Logo
// Concept : deux points ":" qui sont les deux "o" de "mood"
// Animation : les deux points s'écartent et les lettres m et d apparaissent

struct MoodLogo: View {
    var size: CGFloat = 28
    var animated: Bool = true
    @State private var expanded = false

    private var dotSize: CGFloat { size * 0.32 }

    var body: some View {
        HStack(spacing: 0) {
            // "m" — apparaît en expanded
            Text("m")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(MoodTheme.textPrimary)
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.3)
                .offset(x: expanded ? 0 : size * 0.35)

            // ∞ central (deux points compacts → symbole infini)
            ZStack {
                // Points compacts (visibles quand replié)
                VStack(spacing: size * 0.15) {
                    Circle()
                        .fill(MoodTheme.brandAccent)
                        .frame(width: dotSize, height: dotSize)

                    Circle()
                        .fill(MoodTheme.brandBlue)
                        .frame(width: dotSize, height: dotSize)
                }
                .opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 1.8 : 1)

                // Symbole ∞ (visible quand expanded)
                MoodInfinitySymbol(size: size)
                    .opacity(expanded ? 1 : 0)
                    .scaleEffect(expanded ? 1 : 0.3)
                    .offset(y: size * 0.04)
            }

            // "d" — apparaît en expanded
            Text("d")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(MoodTheme.textPrimary)
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.3)
                .offset(x: expanded ? 0 : -size * 0.35)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: expanded)
        .onHover { hovering in
            if animated {
                expanded = hovering
            }
        }
    }
}

// MARK: - Compact Logo (juste les deux points, vertical)

struct MoodLogoDots: View {
    var dotSize: CGFloat = 8
    var spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: spacing) {
            Circle()
                .fill(MoodTheme.brandAccent)
                .frame(width: dotSize, height: dotSize)

            Circle()
                .fill(MoodTheme.brandBlue)
                .frame(width: dotSize, height: dotSize)
        }
    }
}

// MARK: - Splash Screen Logo Animation

struct MoodSplashLogo: View {
    @State private var phase: SplashPhase = .dots
    @State private var dotScale: CGFloat = 0
    @State private var dotOpacity: Double = 0
    @State private var dotsSpacing: CGFloat = 6
    @State private var showText = false
    @State private var glowOpacity: Double = 0

    enum SplashPhase {
        case dots, expand, text
    }

    var body: some View {
        ZStack {
            // Glow derrière le logo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MoodTheme.brandAccent.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .opacity(glowOpacity)
                .blur(radius: 20)

            VStack(spacing: 0) {
                if !showText {
                    // Phase 1 & 2 : les deux points
                    VStack(spacing: dotsSpacing) {
                        Circle()
                            .fill(MoodTheme.brandAccent)
                            .frame(width: 14, height: 14)

                        Circle()
                            .fill(MoodTheme.brandBlue)
                            .frame(width: 14, height: 14)
                    }
                    .scaleEffect(dotScale)
                    .opacity(dotOpacity)
                } else {
                    // Phase 3 : "m∞d" complet
                    HStack(spacing: 0) {
                        Text("m")
                            .foregroundStyle(MoodTheme.textPrimary)
                        MoodInfinitySymbol(size: 42)
                            .offset(y: 2)
                        Text("d")
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            // Phase 1 : les points apparaissent
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                dotScale = 1
                dotOpacity = 1
            }

            // Phase 1.5 : glow
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) {
                glowOpacity = 1
            }

            // Phase 2 : les points s'écartent
            withAnimation(.easeInOut(duration: 0.4).delay(0.8)) {
                dotsSpacing = 20
            }

            // Phase 3 : transformation en "mood"
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(1.3)) {
                showText = true
            }

            // Glow pulse
            withAnimation(.easeInOut(duration: 1.2).delay(1.3)) {
                glowOpacity = 0.5
            }
        }
    }
}

// MARK: - Infinity Symbol (deux "o" qui se chevauchent pour former ∞)

/// Deux vrais "o" en police rounded bold qui se chevauchent.
/// Croisement au centre : le violet passe devant en haut, le bleu devant en bas.
/// Cela crée un vrai effet ∞ tout en gardant l'aspect "oo" de la police.
struct MoodInfinitySymbol: View {
    var size: CGFloat = 24

    // Chevauchement entre les deux "o" (~18% de la taille)
    private var overlap: CGFloat { size * 0.18 }

    private var font: Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    var body: some View {
        ZStack {
            // Couche 1 : violet "o" complet (en arrière-plan)
            HStack(spacing: -overlap) {
                Text("o")
                    .font(font)
                    .foregroundStyle(MoodTheme.brandAccent)
                Text("o")
                    .font(font)
                    .foregroundStyle(.clear) // placeholder pour le spacing
            }

            // Couche 2 : bleu "o" complet (en arrière-plan)
            HStack(spacing: -overlap) {
                Text("o")
                    .font(font)
                    .foregroundStyle(.clear) // placeholder pour le spacing
                Text("o")
                    .font(font)
                    .foregroundStyle(MoodTheme.brandBlue)
            }

            // Couche 3 : la moitié haute du violet (passe devant le bleu en haut)
            HStack(spacing: -overlap) {
                Text("o")
                    .font(font)
                    .foregroundStyle(MoodTheme.brandAccent)
                Text("o")
                    .font(font)
                    .foregroundStyle(.clear)
            }
            .mask(
                VStack(spacing: 0) {
                    Color.white // moitié haute visible
                    Color.clear // moitié basse masquée
                }
            )
        }
    }
}

// MARK: - Infinity Logo pour la toolbar

struct MoodInfinityLogo: View {
    var size: CGFloat = 24

    var body: some View {
        MoodInfinitySymbol(size: size)
    }
}

#Preview("Infinity Symbol") {
    VStack(spacing: 30) {
        MoodInfinitySymbol(size: 16)
        MoodInfinitySymbol(size: 24)
        MoodInfinitySymbol(size: 34)
        MoodInfinitySymbol(size: 52)

        // "m∞d" test
        HStack(spacing: 0) {
            Text("m")
                .foregroundStyle(MoodTheme.textPrimary)
            MoodInfinitySymbol(size: 34)
                .offset(y: 2)
            Text("d")
                .foregroundStyle(MoodTheme.textPrimary)
        }
        .font(.system(size: 34, weight: .bold, design: .rounded))
    }
    .padding(60)
    .background(MoodTheme.serverBar)
    .preferredColorScheme(.dark)
}

#Preview("Logo Hover") {
    VStack(spacing: 40) {
        MoodLogo(size: 36)
        MoodLogoDots(dotSize: 10, spacing: 5)
    }
    .padding(60)
    .background(MoodTheme.serverBar)
    .preferredColorScheme(.dark)
}

#Preview("Splash") {
    MoodSplashLogo()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.serverBar)
        .preferredColorScheme(.dark)
}
