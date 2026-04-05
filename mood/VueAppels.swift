import SwiftUI

// MARK: - Call Type & State

enum CallType {
    case voice
    case video
    case screenShare
}

enum CallState {
    case connecting
    case ringing
    case connected
    case ended
}

// MARK: - Voice Channel Lobby (style Discord 2025)

struct VoiceChannelLobby: View {
    let channel: Channel
    let server: MoodServer
    @State private var connectedUsers: [MoodUser] = []
    @State private var isMuted = false
    @State private var isDeafened = false
    @State private var isCameraOn = false
    @State private var isScreenSharing = false
    @State private var speakingUsers: Set<UUID> = []
    @State private var isConnected = false
    @State private var isControlBarVisible = false
    @State private var showInviteAlert = false
    @State private var showActivityAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header minimal
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textSecondary)

                Text(channel.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // Zone principale
            ZStack {
                MoodTheme.chatBackground

                if !isConnected {
                    // Pas connecté — bouton rejoindre
                    VStack(spacing: 20) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 36))
                            .foregroundStyle(MoodTheme.textMuted)

                        Text("Salon vocal — \(channel.name)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)

                        Text("Personne n'est dans ce salon.")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)

                        Button { joinChannel() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 13))
                                Text("Rejoindre le vocal")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(MoodTheme.onlineGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Connecté — grille de participants Discord
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            // Grille participants
                            GeometryReader { geo in
                                let count = connectedUsers.count
                                let cols = count <= 1 ? 1 : count <= 4 ? 2 : 3
                                let spacing: CGFloat = 8
                                let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols)

                                ScrollView {
                                    LazyVGrid(columns: columns, spacing: spacing) {
                                        ForEach(connectedUsers) { user in
                                            DiscordParticipantTile(
                                                user: user,
                                                isSpeaking: speakingUsers.contains(user.id),
                                                availableWidth: (geo.size.width - CGFloat(cols + 1) * spacing) / CGFloat(cols)
                                            )
                                        }
                                    }
                                    .padding(spacing)
                                }
                            }

                            // Boutons d'action
                            HStack(spacing: 10) {
                                LobbyActionButton(icon: "person.badge.plus", label: "Inviter dans le salon vocal") { showInviteAlert = true }
                                LobbyActionButton(icon: "star.fill", label: "Choisis une Activité") { showActivityAlert = true }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }

                        // Zone hover en bas pour révéler la barre
                        VStack {
                            Spacer()
                            Color.clear
                                .frame(height: 60)
                                .onHover { hovering in
                                    if hovering {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isControlBarVisible = true
                                        }
                                    }
                                }
                        }
                        .allowsHitTesting(!isControlBarVisible)

                        // Barre de contrôles — apparaît au survol du bas
                        if isControlBarVisible {
                            VStack {
                                Spacer()
                                DiscordVoiceControlBar(
                                    isMuted: $isMuted,
                                    isDeafened: $isDeafened,
                                    isCameraOn: $isCameraOn,
                                    isScreenSharing: $isScreenSharing,
                                    onDisconnect: { disconnectChannel() }
                                )
                                .onHover { hovering in
                                    if !hovering {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isControlBarVisible = false
                                        }
                                    }
                                }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .background(MoodTheme.chatBackground)
        .onAppear {
            if let users = MockData.voiceUsers[channel.id], !users.isEmpty {
                connectedUsers = users
                isConnected = true
                startSpeakingSimulation()
            }
        }
        .alert("Inviter", isPresented: $showInviteAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Les invitations vocales seront disponibles dans une prochaine version.")
        }
        .alert("Activités", isPresented: $showActivityAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Les activités seront disponibles dans une prochaine version.")
        }
        .onChange(of: isMuted) {
            if isMuted {
                withAnimation(.easeInOut(duration: 0.15)) {
                    _ = speakingUsers.remove(MockData.currentUser.id)
                }
            }
        }
    }

    private func joinChannel() {
        withAnimation(.easeInOut(duration: 0.25)) {
            connectedUsers = [MockData.currentUser] + (MockData.voiceUsers[channel.id] ?? [])
            isConnected = true
        }
        startSpeakingSimulation()
    }

    private func disconnectChannel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            connectedUsers = []
            isConnected = false
        }
    }

    private func startSpeakingSimulation() {
        func cycle() {
            let delay = Double.random(in: 0.8...2.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !connectedUsers.isEmpty else { return }
                // Ne pas faire parler l'utilisateur local s'il est muté
                let eligibleUsers = connectedUsers.filter { user in
                    if user.id == MockData.currentUser.id && isMuted { return false }
                    return true
                }
                guard let randomUser = eligibleUsers.randomElement() else { cycle(); return }
                _ = withAnimation(.easeInOut(duration: 0.15)) {
                    speakingUsers.insert(randomUser.id)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.3...1.5)) {
                    _ = withAnimation(.easeInOut(duration: 0.15)) {
                        speakingUsers.remove(randomUser.id)
                    }
                }
                cycle()
            }
        }
        cycle()
    }
}

// MARK: - Discord Participant Tile (grand carré sombre avec avatar)

struct DiscordParticipantTile: View {
    let user: MoodUser
    let isSpeaking: Bool
    var availableWidth: CGFloat = 200

    var body: some View {
        ZStack(alignment: .bottom) {
            // Fond sombre du tile
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MoodTheme.glassBg)

            // Avatar centré
            VStack {
                Spacer()
                ZStack {
                    // Anneau de parole vert
                    if isSpeaking {
                        Circle()
                            .stroke(MoodTheme.onlineGreen, lineWidth: 3)
                            .frame(width: 74, height: 74)
                    }

                    Text(user.avatarEmoji)
                        .font(.system(size: 36))
                        .frame(width: 64, height: 64)
                        .background(Color(hex: "5865f2"))
                        .clipShape(Circle())
                }
                Spacer()
            }

            // Nom en bas
            HStack {
                Text(user.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .aspectRatio(16/10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSpeaking ? MoodTheme.onlineGreen : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

// MARK: - Discord Voice Control Bar (bottom)

struct DiscordVoiceControlBar: View {
    @Binding var isMuted: Bool
    @Binding var isDeafened: Bool
    @Binding var isCameraOn: Bool
    @Binding var isScreenSharing: Bool
    var onDisconnect: () -> Void
    @State private var showActivities = false
    @State private var showSoundboard = false
    @State private var showUsers = false
    @State private var showMoreOptions = false

    var body: some View {
        HStack(spacing: 6) {
            // Micro (avec dropdown)
            DiscordControlButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                isActive: isMuted,
                isDestructive: isMuted,
                hasDropdown: true
            ) {
                isMuted.toggle()
            }

            // Casque / Sourdine (avec dropdown)
            DiscordControlButton(
                icon: isDeafened ? "speaker.slash.fill" : "headphones",
                isActive: isDeafened,
                isDestructive: isDeafened,
                hasDropdown: true
            ) {
                isDeafened.toggle()
                if isDeafened { isMuted = true }
            }

            // Caméra
            DiscordControlButton(
                icon: isCameraOn ? "video.fill" : "video.slash",
                isActive: isCameraOn,
                activeColor: MoodTheme.onlineGreen
            ) {
                isCameraOn.toggle()
            }

            // Partage d'écran
            DiscordControlButton(
                icon: "rectangle.on.rectangle.angled",
                isActive: isScreenSharing
            ) {
                isScreenSharing.toggle()
            }

            // Activités
            DiscordControlButton(icon: "sparkles", isActive: showActivities) { showActivities.toggle() }

            // Soundboard
            DiscordControlButton(icon: "music.note", isActive: showSoundboard) { showSoundboard.toggle() }

            // Utilisateurs
            DiscordControlButton(icon: "person.2", isActive: showUsers) { showUsers.toggle() }

            // Plus d'options
            DiscordControlButton(icon: "ellipsis", isActive: showMoreOptions) { showMoreOptions.toggle() }

            Spacer()

            // Déconnecter (texte + icône, style Discord)
            Button(action: onDisconnect) {
                HStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 14))
                    Text("Déconnecter")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(MoodTheme.mentionBadge)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Déconnecter")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(MoodTheme.serverBar)
    }
}

// MARK: - Discord Control Button

struct DiscordControlButton: View {
    let icon: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    var activeColor: Color = .clear
    var hasDropdown: Bool = false
    var action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showDeviceMenu = false

    private var iconColor: Color {
        if isDestructive { return .white }
        if isActive && activeColor != .clear { return activeColor }
        if isActive { return .white }
        return MoodTheme.textPrimary
    }

    private var bgColor: Color {
        if isDestructive {
            return isHovered ? Color(hex: "d83c3e") : Color(hex: "b5383a")
        }
        return isHovered ? MoodTheme.hoverBg : MoodTheme.glassBg
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: hasDropdown ? 30 : 36, height: 36)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            if hasDropdown {
                Rectangle()
                    .fill(isDestructive ? Color.white.opacity(0.2) : MoodTheme.divider)
                    .frame(width: 1, height: 18)

                Button { showDeviceMenu = true } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isDestructive ? Color.white.opacity(0.7) : MoodTheme.textSecondary)
                        .frame(width: 18, height: 36)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDeviceMenu, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PÉRIPHÉRIQUE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MoodTheme.onlineGreen)
                            Text("Par défaut")
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                    }
                    .padding(12)
                    .frame(width: 200)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bgColor)
        )
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: isDestructive)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Lobby Action Button

struct LobbyActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MoodTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovered ? MoodTheme.hoverBg : MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - DM Voice Call View (style Discord 2025)

enum CallMode {
    case voice
    case camera
    case screenShare
}

struct VoiceCallView: View {
    let participant: MoodUser
    let onEnd: () -> Void
    @State private var callState: CallState = .ringing
    @State private var callMode: CallMode = .voice
    @State private var isMuted = false
    @State private var isDeafened = false
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            MoodTheme.chatBackground.ignoresSafeArea()

            // Contenu principal selon le mode
            Group {
                switch callMode {
                case .voice:
                    voiceContent
                case .camera:
                    cameraContent
                case .screenShare:
                    screenShareContent
                }
            }

            // Bandeau en haut + contrôles en bas (overlay)
            VStack(spacing: 0) {
                // Bandeau mode
                if callState == .connected {
                    callTopBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Contrôles en bas dans barre translucide
                callControlBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
            }
        }
        .onAppear { startCall() }
        .onDisappear { timer?.invalidate() }
        .animation(.easeInOut(duration: 0.25), value: callMode)
    }

    // MARK: - Mode Voix

    private var voiceContent: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                if callState == .ringing {
                    Circle()
                        .stroke(MoodTheme.textSecondary.opacity(0.15), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                        .opacity(2 - pulseScale)
                }
                if callState == .connected {
                    Circle()
                        .stroke(MoodTheme.onlineGreen, lineWidth: 3)
                        .frame(width: 112, height: 112)
                }
                Text(participant.avatarEmoji)
                    .font(.system(size: 48))
                    .frame(width: 100, height: 100)
                    .background(MoodTheme.brandAccent)
                    .clipShape(Circle())
            }

            Text(participant.displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)

            callStatusText

            e2eBadge

            Spacer()
            Spacer()
        }
    }

    // MARK: - Mode Caméra

    private var cameraContent: some View {
        ZStack {
            // Flux vidéo simulé (plein écran)
            MoodTheme.glassBg
            VStack(spacing: 8) {
                Text(participant.avatarEmoji).font(.system(size: 48))
                Text(participant.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("Caméra activée")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            // Self-view PiP en haut à droite
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MoodTheme.glassBg)
                            .frame(width: 120, height: 80)
                        Text("🙂").font(.system(size: 24))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.divider, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    .padding(.top, 56)
                    .padding(.trailing, 12)
                }
                Spacer()
            }
        }
    }

    // MARK: - Mode Partage d'écran

    private var screenShareContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MoodTheme.glassBg)
                .padding(.horizontal, 12)
                .padding(.top, 56)
                .padding(.bottom, 100)

            VStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundStyle(MoodTheme.brandAccent)
                Text("Partage d'écran actif")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("Le contenu apparaîtra ici")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
        }
    }

    // MARK: - Bandeau en haut

    private var callTopBar: some View {
        HStack(spacing: 8) {
            // Indicateur mode
            HStack(spacing: 6) {
                Circle()
                    .fill(MoodTheme.onlineGreen)
                    .frame(width: 7, height: 7)

                Text(callMode == .screenShare ? "Partage d'écran" :
                     callMode == .camera ? "Appel vidéo" : "Appel vocal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)

                Text("·").foregroundStyle(MoodTheme.textSecondary)

                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(MoodTheme.glassBg.opacity(0.9))
            .clipShape(Capsule())

            Spacer()

            // Badge E2E
            e2eBadge
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Contrôles en bas

    private var callControlBar: some View {
        HStack(spacing: 12) {
            // Micro
            CallControlCircle(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                isDestructive: isMuted
            ) { isMuted.toggle() }

            // Casque
            CallControlCircle(
                icon: isDeafened ? "speaker.slash.fill" : "headphones",
                isDestructive: isDeafened
            ) {
                isDeafened.toggle()
                if isDeafened { isMuted = true }
            }

            // Caméra
            CallControlCircle(
                icon: callMode == .camera ? "video.fill" : "video.slash.fill",
                isHighlighted: callMode == .camera
            ) {
                withAnimation { callMode = callMode == .camera ? .voice : .camera }
            }

            // Partage d'écran
            CallControlCircle(
                icon: "rectangle.on.rectangle.angled",
                isHighlighted: callMode == .screenShare
            ) {
                withAnimation { callMode = callMode == .screenShare ? .voice : .screenShare }
            }

            // Raccrocher
            CallControlCircle(
                icon: "phone.down.fill",
                isDestructive: true,
                alwaysDestructive: true
            ) { endCall() }
        }
    }

    // MARK: - Composants réutilisables

    private var callStatusText: some View {
        Group {
            switch callState {
            case .connecting:
                Text("Connexion...")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
            case .ringing:
                Text("Appel en cours...")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
            case .connected:
                Text(formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(MoodTheme.onlineGreen)
            case .ended:
                Text("Appel terminé")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
        }
    }

    private var e2eBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 8))
            Text("E2E").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(MoodTheme.onlineGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MoodTheme.onlineGreen.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Logique

    private var formattedDuration: String {
        let m = Int(callDuration) / 60; let s = Int(callDuration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func startCall() {
        callState = .ringing
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
            pulseScale = 1.8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                callState = .connected
                pulseScale = 1.0
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in callDuration += 1 }
        }
    }

    private func endCall() {
        timer?.invalidate()
        withAnimation(.easeInOut(duration: 0.2)) { callState = .ended }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onEnd() }
    }
}

// MARK: - Call Control Circle Button (style Discord DM call)

struct CallControlCircle: View {
    let icon: String
    var isDestructive: Bool = false
    var alwaysDestructive: Bool = false
    var isHighlighted: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    private var bgColor: Color {
        if alwaysDestructive || isDestructive {
            return isHovered ? Color(hex: "da373c") : Color(hex: "f23f43")
        }
        if isHighlighted {
            return isHovered ? MoodTheme.brandAccent.opacity(0.8) : MoodTheme.brandAccent
        }
        return isHovered ? MoodTheme.hoverBg : MoodTheme.glassBg
    }

    private var fgColor: Color {
        if alwaysDestructive || isDestructive || isHighlighted { return .white }
        return MoodTheme.textPrimary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(fgColor)
                .frame(width: 52, height: 52)
                .background(bgColor)
                .clipShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isDestructive)
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - DM Video Call View

struct VideoCallView: View {
    let participant: MoodUser
    let onEnd: () -> Void
    @State private var callState: CallState = .ringing
    @State private var isMuted = false
    @State private var isCameraOff = false
    @State private var isDeafened = false
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showControls = true
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            MoodTheme.chatBackground.ignoresSafeArea()

            // Contenu principal
            if callState == .connected {
                if isCameraOff {
                    // Caméra off — avatar centré
                    VStack(spacing: 12) {
                        Text(participant.avatarEmoji)
                            .font(.system(size: 48))
                            .frame(width: 100, height: 100)
                            .background(MoodTheme.brandAccent)
                            .clipShape(Circle())
                        Text(participant.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MoodTheme.textPrimary)
                        Text("Caméra désactivée")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }
                } else {
                    // Simulation flux vidéo
                    ZStack {
                        MoodTheme.glassBg
                        VStack(spacing: 8) {
                            Text(participant.avatarEmoji).font(.system(size: 48))
                            Text(participant.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                    }
                }
            }

            // Sonnerie
            if callState == .ringing || callState == .connecting {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(MoodTheme.textSecondary.opacity(0.15), lineWidth: 2)
                            .frame(width: 120, height: 120)
                            .scaleEffect(pulseScale)
                            .opacity(2 - pulseScale)

                        Text(participant.avatarEmoji)
                            .font(.system(size: 48))
                            .frame(width: 100, height: 100)
                            .background(MoodTheme.brandAccent)
                            .clipShape(Circle())
                    }
                    Text(participant.displayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Appel vidéo en cours...")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
            }

            // Self-view PiP
            if callState == .connected {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MoodTheme.glassBg)
                                .frame(width: 120, height: 80)
                            if isCameraOff {
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 16)).foregroundStyle(MoodTheme.textMuted)
                            } else {
                                Text("🙂").font(.system(size: 24))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MoodTheme.divider, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                        .padding(12)
                    }
                    Spacer()
                }
            }

            // Contrôles (tap pour afficher/cacher)
            VStack {
                // Top bar
                if showControls && callState == .connected {
                    HStack {
                        Text(formattedDuration)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(MoodTheme.onlineGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MoodTheme.glassBg.opacity(0.9))
                            .clipShape(Capsule())

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.system(size: 8))
                            Text("E2E").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(MoodTheme.onlineGreen)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(MoodTheme.onlineGreen.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14).padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Boutons circulaires en bas
                if showControls {
                    HStack(spacing: 12) {
                        CallControlCircle(icon: isMuted ? "mic.slash.fill" : "mic.fill", isDestructive: isMuted) {
                            isMuted.toggle()
                        }
                        CallControlCircle(icon: isDeafened ? "speaker.slash.fill" : "headphones", isDestructive: isDeafened) {
                            isDeafened.toggle()
                            if isDeafened { isMuted = true }
                        }
                        CallControlCircle(icon: isCameraOff ? "video.slash.fill" : "video.fill") {
                            isCameraOff.toggle()
                        }
                        CallControlCircle(icon: "phone.down.fill", isDestructive: true, alwaysDestructive: true) {
                            endCall()
                        }
                    }
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
        .onAppear { startCall() }
        .onDisappear { timer?.invalidate() }
    }

    private var formattedDuration: String {
        let m = Int(callDuration) / 60; let s = Int(callDuration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func startCall() {
        callState = .ringing
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
            pulseScale = 1.8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                callState = .connected
                pulseScale = 1.0
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in callDuration += 1 }
        }
    }

    private func endCall() {
        timer?.invalidate()
        withAnimation(.easeInOut(duration: 0.2)) { callState = .ended }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onEnd() }
    }
}

// MARK: - Screen Share View

struct ScreenShareView: View {
    let participant: MoodUser
    let onEnd: () -> Void
    @State private var isMuted = false
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showControls = true

    var body: some View {
        ZStack {
            MoodTheme.chatBackground.ignoresSafeArea()

            // Contenu partagé
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MoodTheme.glassBg)

                VStack(spacing: 12) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 34))
                        .foregroundStyle(MoodTheme.brandAccent)
                    Text("\(participant.displayName) partage son écran")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Le contenu apparaîtra ici")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
            }
            .padding(12)

            // Overlay contrôles
            VStack {
                if showControls {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: "f23f43")).frame(width: 7, height: 7)
                            Text("Partage d'écran").font(.system(size: 12, weight: .medium)).foregroundStyle(MoodTheme.textPrimary)
                            Text("·").foregroundStyle(MoodTheme.textSecondary)
                            Text(formattedDuration).font(.system(size: 12, design: .monospaced)).foregroundStyle(MoodTheme.textSecondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(MoodTheme.glassBg.opacity(0.9))
                        .clipShape(Capsule())

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.system(size: 8))
                            Text("E2E").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(MoodTheme.onlineGreen)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(MoodTheme.onlineGreen.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14).padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if showControls {
                    HStack(spacing: 12) {
                        CallControlCircle(icon: isMuted ? "mic.slash.fill" : "mic.fill", isDestructive: isMuted) {
                            isMuted.toggle()
                        }

                        Spacer()

                        Button { onEnd() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.on.rectangle.slash").font(.system(size: 14))
                                Text("Arrêter le partage").font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color(hex: "f23f43"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in callDuration += 1 }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var formattedDuration: String {
        let m = Int(callDuration) / 60; let s = Int(callDuration) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Previews

#Preview("Lobby Vocal") {
    VoiceChannelLobby(
        channel: Channel(id: UUID(), name: "Lobby", type: .voice, topic: "", unreadCount: 0, isE2E: true),
        server: MockData.servers[0]
    )
    .frame(width: 550, height: 450)
    .preferredColorScheme(.dark)
}

#Preview("Appel vocal DM") {
    VoiceCallView(
        participant: MockData.users[0],
        onEnd: {}
    )
    .frame(width: 400, height: 450)
    .preferredColorScheme(.dark)
}

#Preview("Appel vidéo DM") {
    VideoCallView(
        participant: MockData.users[1],
        onEnd: {}
    )
    .frame(width: 500, height: 400)
    .preferredColorScheme(.dark)
}
