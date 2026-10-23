import SwiftUI
import UIKit

/// A missing cache during a connection failure is not evidence that the account has no conversations.
struct ConversationCacheEmptyState: View {
    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(12)) {
            Image(systemName: "bubble.left.and.bubble.right").font(.mood(32)).accessibilityHidden(true)
            Text("Aucune conversation chargée").font(.mood(17, weight: .semibold))
            Text("Cet appareil n’a pas encore de conversations à lire hors ligne. Elles réapparaîtront au retour de la connexion.")
                .font(.mood(14)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(MoodTheme.textSecondary).padding(LayoutMetrics.mobile(24))
            .frame(maxWidth: .infinity)
    }
}

/// A single recovery language for inline errors, permissions and connection notices.
/// Recovery actions share Mood’s filled capsules, including pressed and disabled feedback.
struct MoodNotice: View {
    let title: String
    var detail: String? = nil
    var symbol = "exclamationmark.circle"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var busy = false
    @Environment(\.layoutMode) private var layoutMode

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(6)) {
            HStack(alignment: .top, spacing: LayoutMetrics.mobile(8)) {
                if busy { ProgressView().controlSize(.small) }
                else { Image(systemName: symbol).foregroundStyle(MoodTheme.textSecondary).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: LayoutMetrics.mobile(4)) {
                    Text(title).font(.mood(14, weight: .semibold))
                    if let detail { Text(detail).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary) }
                }.fixedSize(horizontal: false, vertical: true)
            }
            if action != nil || secondaryAction != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LayoutMetrics.mobile(16)) { actions }
                    VStack(alignment: .leading, spacing: 0) { actions }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MoodTheme.textPrimary)
        .padding(LayoutMetrics.mobile(16))
        .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(layoutMode == .compact ? 20 : 8)))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action).buttonStyle(MoodRecoveryButtonStyle()).disabled(busy)
        }
        if let secondaryTitle, let secondaryAction {
            Button(secondaryTitle, action: secondaryAction).buttonStyle(MoodRecoveryButtonStyle(secondary: true))
        }
    }
}

/// No scaling or spring: a press changes only the fill, as elsewhere in Mood.
struct MoodRecoveryButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.mood(14, weight: .semibold))
            .foregroundStyle(secondary ? MoodTheme.textPrimary : MoodTheme.mobileIndicator)
            .padding(.horizontal, LayoutMetrics.mobile(18))
            .frame(minHeight: LayoutMetrics.mobile(44))
            .background(secondary ? MoodTheme.glassBg : MoodTheme.brandAccent, in: Capsule())
            .opacity(!enabled ? 0.45 : (configuration.isPressed ? 0.72 : 1))
    }
}

struct ConversationConnectionNotice: View {
    @Environment(MatrixStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.layoutMode) private var layoutMode
    @State private var showDetails = false
    @State private var showLogin = false
    @State private var reconnectAfterDetails = false
    @State private var loginState = AuthState()

    private var symbol: String {
        switch store.connection {
        case .offline: "wifi.slash"
        case .connecting: "arrow.triangle.2.circlepath"
        case .sessionExpired: "person.crop.circle.badge.exclamationmark"
        default: "exclamationmark.bubble"
        }
    }

    var body: some View {
        Group {
            if store.connection != .connected, store.userId != nil || PremiumPreview.screen != nil {
                Button { showDetails = true } label: {
                    HStack(spacing: LayoutMetrics.mobile(8)) {
                        if store.isRetryingConnection { ProgressView().controlSize(.mini) }
                        else { Image(systemName: symbol).accessibilityHidden(true) }
                        Text(store.connection.capsuleLabel(waiting: store.pendingMessageCount))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right").font(.mood(9, weight: .semibold)).accessibilityHidden(true)
                    }
                    .font(.mood(12, weight: .medium)).foregroundStyle(MoodTheme.textSecondary)
                    .padding(.horizontal, LayoutMetrics.mobile(14))
                    .padding(.vertical, LayoutMetrics.mobile(8))
                    .frame(minHeight: LayoutMetrics.mobile(44))
                    .modifier(ConnectionSurface(compact: layoutMode == .compact))
                }
                .buttonStyle(DeliveryActionStyle())
                .accessibilityHint("Ouvre les détails et les actions de connexion")
                .accessibilityIdentifier("conversation-connection")
                .padding(.horizontal, LayoutMetrics.mobile(16)).padding(.vertical, LayoutMetrics.mobile(6))
                .frame(maxWidth: .infinity)
            } else if store.recoveredDeliveryCount > 0 {
                Label(ConversationRecovery.sentLabel(store.recoveredDeliveryCount), systemImage: "checkmark")
                    .font(.mood(12, weight: .medium)).foregroundStyle(MoodTheme.textSecondary)
                    .padding(LayoutMetrics.mobile(10)).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("conversation-recovered")
            }
        }
        .sheet(isPresented: $showDetails, onDismiss: reconnectIfRequested) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(20)) {
                        Image(systemName: symbol).font(.mood(28)).foregroundStyle(MoodTheme.brandAccent).accessibilityHidden(true)
                        Text(store.connection.title).font(.mood(24, weight: .bold)).accessibilityAddTraits(.isHeader)
                        Text(store.connection.detail).font(.mood(16)).foregroundStyle(MoodTheme.textSecondary)
                        if store.pendingMessageCount > 0 {
                            Label(ConversationRecovery.waitingLabel(store.pendingMessageCount), systemImage: "clock").font(.mood(14))
                        }
                        Button(store.connection == .sessionExpired ? "Se reconnecter" : "Réessayer") {
                            if store.connection == .sessionExpired {
                                reconnectAfterDetails = true
                                showDetails = false
                            } else { store.retryConnection() }
                        }.buttonStyle(MoodRecoveryButtonStyle()).disabled(store.isRetryingConnection || account.isProvisioning)
                    }
                    .padding(LayoutMetrics.mobile(24)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(MoodTheme.textPrimary).background(MoodTheme.mobileSurface)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showDetails = false }.tint(MoodTheme.textPrimary) } }
            }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .presentationBackground(MoodTheme.mobileSurface)
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                AuthContainer(authState: loginState, matrixStore: store)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { showLogin = false } } }
            }
            .environment(account)
            .onChange(of: account.session?.accessToken) { _, _ in
                Task {
                    await account.connectMood(matrixStore: store)
                    if store.connection != .sessionExpired { showLogin = false }
                }
            }
            .onChange(of: store.connection) { _, state in
                if state == .connected { showLogin = false }
            }
        }
    }

    private func reconnectIfRequested() {
        guard reconnectAfterDetails else { return }
        reconnectAfterDetails = false
        if account.isSignedIn {
            Task {
                await account.connectMood(matrixStore: store)
                if store.connection == .sessionExpired { showLogin = true }
            }
        } else { showLogin = true }
    }
}

private struct ConnectionSurface: ViewModifier {
    let compact: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if compact { content.mobileGlassCapsule() }
        else { content.frame(maxWidth: .infinity).background(MoodTheme.inputBg) }
    }
}

/// Delivery stays attached to the message, rather than taking over the conversation.
struct MessageDeliveryStatus: View {
    let message: ChatMessage
    let roomID: String
    @Environment(MatrixStore.self) private var store
    @State private var showSent = false

    var body: some View {
        Group {
            if message.sendState == .failed {
                HStack(spacing: LayoutMetrics.mobile(6)) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(MoodTheme.deliveryFailed).accessibilityLabel("Échec de l’envoi")
                    Button("Renvoyer") { store.retryMessage(message.id, roomId: roomID) }
                    Text("·").accessibilityHidden(true)
                    Button("Supprimer") { store.discardUnsentMessage(message.id, roomId: roomID) }
                }
                .buttonStyle(DeliveryActionStyle()).foregroundStyle(MoodTheme.deliveryFailed)
                .font(.mood(12, weight: .medium))
            } else if message.sendState == .sending {
                Label(store.connection == .connected ? "Envoi en cours…" : "En attente · partira tout seul", systemImage: "clock")
                    .font(.mood(12)).foregroundStyle(MoodTheme.textMuted)
            } else if showSent {
                Label("Envoyé", systemImage: "checkmark").font(.mood(12)).foregroundStyle(MoodTheme.textSecondary)
                    .accessibilityIdentifier("message-sent")
            }
        }
        .onChange(of: message.sendState) { old, new in
            if old == .sending, new == .sent { showSent = true }
        }
        .task(id: showSent) {
            guard showSent else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showSent = false
        }
    }
}

private struct DeliveryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minHeight: LayoutMetrics.mobile(44))
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Reserve space for the floating capsule so the last message remains readable.
extension View {
    func messageUndoAccessory() -> some View { modifier(MessageUndoAccessory()) }
}

private struct MessageUndoAccessory: ViewModifier {
    @Environment(MatrixStore.self) private var store
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if !store.pendingDeletions.isEmpty || !store.committingDeletions.isEmpty || store.deletionFailure != nil {
                MessageDeletionNotices()
                    .padding(.horizontal, LayoutMetrics.mobile(16)).padding(.bottom, LayoutMetrics.mobile(8))
            }
            content
        }
    }
}

struct ConversationRecoveryNotices: View {
    @Environment(MatrixStore.self) private var store
    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(6)) {
            ConversationConnectionNotice()
            ServerLeaveNotice()
            if let error = store.errorMessage {
                ErrorBanner(message: error, onRetry: store.retryAction) { store.errorMessage = nil }
            }
        }
    }
}

struct ServerLeaveNotice: View {
    @Environment(MatrixStore.self) private var store
    var body: some View {
        if !store.leavingServers.isEmpty {
            MoodNotice(title: "Départ du serveur en cours…", detail: "Mood confirme la sortie de ses salons.", busy: true)
        }
    }
}

struct MessageDeletionNotices: View {
    @Environment(MatrixStore.self) private var store
    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(6)) {
            ForEach(store.pendingDeletions) { deletion in
                VStack(spacing: 0) {
                    HStack(spacing: LayoutMetrics.mobile(10)) {
                        Image(systemName: "trash").font(.mood(13)).foregroundStyle(MoodTheme.textSecondary).accessibilityHidden(true)
                        Text("Message supprimé").font(.mood(14, weight: .medium))
                        Text("·").foregroundStyle(MoodTheme.textMuted).accessibilityHidden(true)
                        Button("Annuler") { store.undoMessageDeletion(deletion.id) }
                            .font(.mood(14, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                            .buttonStyle(DeliveryActionStyle())
                    }.padding(.horizontal, LayoutMetrics.mobile(16))
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        GeometryReader { geometry in
                            Capsule().fill(MoodTheme.textSecondary.opacity(0.5))
                                .frame(width: geometry.size.width * deletion.remainingFraction(at: context.date))
                        }.frame(height: LayoutMetrics.mobile(2))
                    }.padding(.horizontal, LayoutMetrics.mobile(20)).padding(.bottom, LayoutMetrics.mobile(6))
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: false, vertical: true).mobileGlassCapsule()
                .accessibilityElement(children: .contain)
            }
            if !store.committingDeletions.isEmpty {
                MoodNotice(title: "Suppression en cours…", detail: "Mood confirme la suppression pour tout le monde.", busy: true)
            }
            if let failure = store.deletionFailure {
                MoodNotice(title: "Le message n’a pas été supprimé", detail: "Il est toujours dans la conversation. Vérifie ta connexion, puis réessaie.",
                    actionTitle: "Réessayer", action: { store.scheduleMessageDeletion(roomID: failure.roomID, eventID: failure.eventID) },
                    secondaryTitle: "Fermer", secondaryAction: { store.dismissDeletionFailure() })
            }
        }
    }
}

enum MoodPermission: String, CaseIterable {
    case microphone, photos, notifications
    var title: String {
        switch self {
        case .microphone: "Le microphone est désactivé"
        case .photos: "Cette photo n’est pas accessible"
        case .notifications: "Les notifications sont désactivées"
        }
    }
    var detail: String {
        switch self {
        case .microphone: "Autorise le micro dans Réglages pour envoyer un vocal. Tu peux toujours écrire ou joindre un fichier."
        case .photos: "Choisis une autre photo ou joins un fichier. Seules les photos que tu choisis sont accessibles à Mood."
        case .notifications: "Autorise les notifications dans Réglages pour être prévenu pendant que Mood fonctionne. L’app fermée, les alertes ne sont pas encore disponibles."
        }
    }
}

struct MoodPermissionNotice: View {
    let permission: MoodPermission
    var alternative: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    var body: some View {
        MoodNotice(title: permission.title, detail: permission.detail,
            symbol: permission == .microphone ? "mic.slash" : (permission == .photos ? "photo" : "bell.slash"),
            actionTitle: permission == .photos ? "Choisir un fichier" : "Ouvrir Réglages",
            action: {
                if permission == .photos { alternative?() }
                else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            })
    }
}
