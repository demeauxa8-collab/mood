import SwiftUI

// MARK: - Mood Logo
// Concept : deux points ":" qui sont les deux "o" de "mood"
// Animation : les deux points s'écartent et les lettres m et d apparaissent

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
