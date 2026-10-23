import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// Uses a downloaded local file: AVPlayer never receives an unauthenticated remote media URL.
struct PlayableMedia: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var store
    let url: URL
    let name: String
    var waveform: [Int] = []
    var roomID: String? = nil
    var eventID: String? = nil
    var autoplay = false
    @State private var receivedWaveform: [Int] = []
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var loading = false
    @State private var fullscreen = false
    @State private var audioPlaying = false

    static func supports(_ name: String) -> Bool {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * LayoutMetrics.scale) {
            Text(name).font(.mood(layoutMode == .compact ? 15 : 13)).foregroundStyle(MoodTheme.textSecondary).lineLimit(layoutMode == .compact ? nil : 1)
            if let player {
                if isVideo {
                    VideoPlayer(player: player)
                        .frame(height: 220 * LayoutMetrics.scale)
                    Button("Plein écran") { fullscreen = true }.font(.mood(layoutMode == .compact ? 16 : 13)).frame(minHeight: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil)
                } else {
                    audioBar(player)
                }
            } else {
                Button {
                    Task { await load() }
                } label: {
                    Label(loading ? "Téléchargement…" : "Lire", systemImage: "play.circle.fill").font(.mood(24))
                }.disabled(loading)
            }
            if let error { Text(error).font(.mood(12)).foregroundStyle(MoodTheme.mentionBadge) }
        }
        .padding(10 * LayoutMetrics.scale)
        .frame(maxWidth: 400 * LayoutMetrics.scale, alignment: .leading)
        .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: layoutMode == .compact ? LayoutMetrics.mobile(16) : 8 * LayoutMetrics.scale))
        .tint(MoodTheme.brandAccent)
        .fullScreenCover(isPresented: $fullscreen) {
            if let player {
                ZStack(alignment: .topTrailing) {
                    VideoPlayer(player: player).ignoresSafeArea()
                    if layoutMode == .compact {
                        MobileCloseButton { fullscreen = false }.mobileGlassCapsule().padding(LayoutMetrics.mobile(16))
                    } else { Button("Fermer") { fullscreen = false }.padding(16 * LayoutMetrics.scale) }
                }
            }
        }
        .task(id: url) { if autoplay { await load() } }
        .task(id: eventID) {
            if let roomID, let eventID, !isVideo {
                receivedWaveform = await store.mediaVoiceWaveform(roomId: roomID, eventId: eventID)
            }
        }
        .onDisappear { player?.pause() }
    }
    /// Voice notes and audio files: play/pause and the waveform, not an empty black video surface.
    private func audioBar(_ player: AVPlayer) -> some View {
        let samples = waveform.isEmpty ? receivedWaveform : waveform
        return HStack(spacing: 10 * LayoutMetrics.scale) {
            Button {
                if audioPlaying { player.pause() } else { player.play() }
                audioPlaying.toggle()
            } label: {
                Image(systemName: audioPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.mood(layoutMode == .compact ? 36 : 28)).foregroundStyle(MoodTheme.brandAccent)
                    .frame(minWidth: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil, minHeight: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil)
            }
            .buttonStyle(.plain).accessibilityLabel(audioPlaying ? "Pause" : "Lire")
            if samples.isEmpty {
                Capsule().fill(MoodTheme.brandAccent.opacity(0.35)).frame(height: 4 * LayoutMetrics.scale).frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 2 * LayoutMetrics.scale) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                        Capsule().fill(MoodTheme.brandAccent)
                            .frame(width: 3 * LayoutMetrics.scale, height: max(2, CGFloat(value) / 1024 * 32) * LayoutMetrics.scale)
                    }
                }.accessibilityLabel("Forme d’onde du message vocal")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)) { _ in
            audioPlaying = false
            player.seek(to: .zero)
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        do {
            let local = url.isFileURL ? url : try await MediaLoader.shared.temporaryFile(for: url, fileName: name)
            guard !Task.isCancelled else { loading = false; return }
            player = AVPlayer(url: local)
            player?.play()
            audioPlaying = true
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private var isVideo: Bool {
        UTType(filenameExtension: (name as NSString).pathExtension)?.conforms(to: .movie) == true
    }
}

struct MediaLinkPreviewCard: View {
    @Environment(MatrixStore.self) private var store
    let url: URL
    @State private var preview: MediaLinkPreview?
    var body: some View {
        Group {
            if let preview, preview.title != nil || preview.description != nil {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 6 * LayoutMetrics.scale) {
                        Text(url.host ?? "Lien").font(.mood(12)).foregroundStyle(MoodTheme.textMuted)
                        if let title = preview.title { Text(title).font(.mood(15, weight: .semibold)).foregroundStyle(MoodTheme.brandAccent).lineLimit(2) }
                        if let description = preview.description { Text(description).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary).lineLimit(3) }
                        if let image = preview.image, image.hasPrefix("mxc://"), let remote = store.resolveMediaURL(image) {
                            AuthenticatedImage(url: remote) { phase in phase.image?.resizable().scaledToFit() }
                                .frame(maxHeight: 160 * LayoutMetrics.scale)
                        }
                    }.padding(12 * LayoutMetrics.scale).frame(maxWidth: 360 * LayoutMetrics.scale, alignment: .leading)
                        .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale))
                }
            }
        }.task(id: url) { preview = await store.mediaLinkPreview(url) }
    }
}
