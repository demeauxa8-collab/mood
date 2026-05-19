import SwiftUI

// Brouillon UI basé sur la frame Figma "Mood - UI Discord Calage".
// Calage = proportions de référence. Les carrés rouges sur la maquette
// sont des placeholders à remplacer par les icônes de serveur.

struct BrouillonUI: View {
    // Dimensions de calage tirées de la frame
    private let serverBarWidth: CGFloat = 72
    private let channelListWidth: CGFloat = 240
    private let headerHeight: CGFloat = 48
    private let inputBarHeight: CGFloat = 56
    private let profileBarHeight: CGFloat = 56
    private let serverIconSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            serverBar
            leftColumn
            mainColumn
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Colonne 1 : barre serveurs

    private var serverBar: some View {
        VStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { _ in
                serverIconPlaceholder
            }
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: serverBarWidth)
        .frame(maxHeight: .infinity)
        .background(MoodTheme.serverBar)
    }

    private var serverIconPlaceholder: some View {
        // TODO: remplacer par l'icône réelle du serveur (cf. BarreServeurs.swift)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.red)
            .frame(width: serverIconSize, height: serverIconSize)
    }

    // MARK: - Colonne 2 : liste channels + profil

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Header de la colonne (nom du serveur)
            HStack {
                Spacer()
            }
            .frame(height: headerHeight)
            .frame(maxWidth: .infinity)
            .background(MoodTheme.channelList)
            .overlay(Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .bottom)

            // Liste vide (à câbler sur ListeChannels)
            Spacer()
                .frame(maxWidth: .infinity)
                .background(MoodTheme.channelList)

            // Profil pinned en bas
            HStack {
                Spacer()
            }
            .frame(height: profileBarHeight)
            .frame(maxWidth: .infinity)
            .background(MoodTheme.inputBg)
        }
        .frame(width: channelListWidth)
    }

    // MARK: - Colonne 3 : zone chat

    private var mainColumn: some View {
        VStack(spacing: 0) {
            // Header du channel
            ZStack {
                MoodTheme.chatBackground
                // Trait rouge de calage visible sur la frame (marque de mesure).
                // À retirer une fois l'UI réelle branchée.
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 1, height: headerHeight * 0.6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(x: 160)
            }
            .frame(height: headerHeight)
            .overlay(Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .bottom)

            // Zone messages
            Spacer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MoodTheme.chatBackground)

            // Barre de saisie
            HStack {
                Spacer()
            }
            .frame(height: inputBarHeight)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .background(MoodTheme.inputBg)
        }
    }
}

#Preview {
    BrouillonUI()
        .frame(width: 1280, height: 760)
}
