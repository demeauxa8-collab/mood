import SwiftUI

/// Deterministic, account-free component gallery. Only presented by the -uiPreview -mediaPreview flags.
struct MediaPreviewGallery: View {
    @State private var text = "Un message avec plusieurs pièces jointes"
    @State private var reply: ChatMessage?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16 * LayoutMetrics.scale) {
                Text("Médias · Démonstration N2").font(.mood(22, weight: .bold)).foregroundStyle(MoodTheme.textPrimary)
                Text("Composants isolés, sans compte ni envoi réseau").font(.mood(12)).foregroundStyle(MoodTheme.textMuted)
                if ProcessInfo.processInfo.arguments.contains("-emojiPreview") {
                    MediaEmojiPicker { text = $0 }
                } else {
                    if let url = Bundle.main.url(forResource: "n2-animation", withExtension: "gif") {
                        Text("GIF animé").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                        AuthenticatedImage(url: url) { phase in phase.image?.resizable().scaledToFit() }
                            .frame(width: 180 * LayoutMetrics.scale, height: 80 * LayoutMetrics.scale)
                    }
                    if let url = Bundle.main.url(forResource: "n2-clip", withExtension: "mp4") {
                        PlayableMedia(url: url, name: "n2-clip.mp4", autoplay: true)
                    }
                    if let url = Bundle.main.url(forResource: "n2-tone", withExtension: "m4a") {
                        PlayableMedia(url: url, name: "n2-tone.m4a", waveform: [100, 250, 500, 800, 1024, 800, 500, 250, 100], autoplay: true)
                    }
                    MediaComposer(roomID: "demo-n2", channelName: "#général", text: $text, replyingTo: $reply, members: MessagingPreview.members)
                }
            }.padding(16 * LayoutMetrics.scale)
        }.background(MoodTheme.chatBackground)
    }
}
