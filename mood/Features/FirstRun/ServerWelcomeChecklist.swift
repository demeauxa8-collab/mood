import SwiftUI

struct ServerWelcomeChecklist: View {
    @Environment(\.layoutMode) private var layoutMode
    let server: MoodServer
    let scope: ServerWelcomeScope
    let progress: ServerWelcomeProgress
    let onInvite: () -> Void
    let onSettings: () -> Void
    let onCompose: () -> Void
    @State private var showOtherDevice = false

    private var otherDevice: String {
        #if targetEnvironment(macCatalyst)
        "ton iPhone"
        #else
        "ton Mac"
        #endif
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(16)) {
            Group {
                if let url = server.iconURL {
                    AuthenticatedImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else { Text(server.iconEmoji).font(.mood(36)) }
                    }
                } else { Text(server.iconEmoji).font(.mood(36)) }
            }
            .frame(width: LayoutMetrics.mobile(72), height: LayoutMetrics.mobile(72))
            .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(20)))
            .accessibilityHidden(true)
            Text("Bienvenue sur \(server.name)").firstRunFont(28, weight: .bold)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text("Voici ton tout nouveau serveur. Quelques étapes pour bien démarrer :")
                .firstRunFont(14).multilineTextAlignment(.center).foregroundStyle(MoodTheme.textSecondary)
            VStack(spacing: LayoutMetrics.mobile(8)) {
                step(.invite, label: "Inviter tes amis", icon: "person.2.fill", action: onInvite)
                step(.icon, label: "Choisir une icône", icon: "photo", action: onSettings)
                step(.message, label: "Envoyer ton premier message", icon: "paperplane.fill", action: onCompose)
                step(.otherDevice, label: "Ouvrir Mood sur \(otherDevice)", icon: "laptopcomputer.and.iphone") { showOtherDevice = true }
            }
        }
        .foregroundStyle(MoodTheme.textPrimary).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: layoutMode == .regular ? LayoutMetrics.mobile(440) : .infinity)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showOtherDevice) {
            MobileSheet(title: "Mood sur \(otherDevice)", onClose: { showOtherDevice = false }) {
                List {
                    Section {
                        Text("Ouvre Mood sur \(otherDevice) et connecte-toi avec le même compte.")
                        Text("Tu n'as pas encore l'app ? Demande la version pour cet appareil à la personne qui t'a invité.")
                            .foregroundStyle(MoodTheme.textSecondary)
                    }.listRowBackground(MoodTheme.inputBg)
                    Section {
                        Button("J'ai ouvert Mood sur \(otherDevice)") {
                            progress.complete(.otherDevice, in: scope)
                            showOtherDevice = false
                        }.frame(minHeight: LayoutMetrics.mobile(44))
                    } footer: {
                        Text("Cette étape se coche quand tu le confirmes. Mood ne peut pas le vérifier ici.")
                    }.listRowBackground(MoodTheme.inputBg)
                }.mobileGroupedList()
            }
        }
    }

    private func step(_ step: ServerWelcomeStep, label: String, icon: String, action: @escaping () -> Void) -> some View {
        let done = progress.completed(step, in: scope)
        return Button(action: action) {
            HStack(spacing: LayoutMetrics.mobile(12)) {
                Image(systemName: icon).font(.mood(18)).foregroundStyle(MoodTheme.brandAccent)
                    .frame(width: LayoutMetrics.mobile(28)).accessibilityHidden(true)
                Text(label).firstRunFont(15, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(done ? MoodTheme.onlineGreen : MoodTheme.textSecondary).accessibilityHidden(true)
            }
            .padding(.horizontal, LayoutMetrics.mobile(16)).padding(.vertical, LayoutMetrics.mobile(12))
            .frame(minHeight: LayoutMetrics.mobile(56))
            .background(MoodTheme.serverBar, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(8)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(done ? "Terminé" : "À faire")
    }
}
