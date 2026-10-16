import SwiftUI
import UIKit

struct AttachmentDraftPreview: View {
    @Environment(\.layoutMode) private var layoutMode
    let url: URL
    let onCancel: () -> Void
    let onSend: () -> Void
    var showsSendButton = true
    @State private var image: UIImage?
    @State private var showMediaDemo = false

    var body: some View {
        Group {
            if layoutMode == .compact {
                VStack(alignment: .leading, spacing: LayoutMetrics.mobile(12)) {
                    HStack(alignment: .top, spacing: LayoutMetrics.mobile(8)) {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48))
                        } else {
                            Image(systemName: "doc.fill").font(.mood(24)).foregroundStyle(MoodTheme.textSecondary)
                                .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                        }
                        Text(url.lastPathComponent).font(.mood(14)).foregroundStyle(MoodTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: onCancel) { Image(systemName: "xmark.circle.fill").font(.mood(20)) }
                            .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                            .accessibilityLabel("Retirer " + url.lastPathComponent)
                    }
                    if showsSendButton { Button("Envoyer", action: onSend).buttonStyle(MobilePrimaryButtonStyle()) }
                }
                .padding(LayoutMetrics.mobile(12))
                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16)))
            } else { desktopBody }
        }
        .tint(MoodTheme.brandAccent)
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            showMediaDemo = args.contains("-uiPreview") && args.contains("-mediaPreview")
        }
        .fullScreenCover(isPresented: $showMediaDemo) { MediaPreviewGallery() }
        .task(id: url) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            image = UIImage(contentsOfFile: url.path)
        }
    }

    private var desktopBody: some View {
        HStack(spacing: 8 * LayoutMetrics.scale) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: 64 * LayoutMetrics.scale, height: 64 * LayoutMetrics.scale)
            }
            Text(url.lastPathComponent).font(.mood(13)).foregroundStyle(MoodTheme.textPrimary).lineLimit(layoutMode == .compact ? nil : 1)
            Spacer()
            Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                .frame(minWidth: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil, minHeight: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil)
                .font(.mood(18)).accessibilityLabel("Retirer " + url.lastPathComponent)
            if showsSendButton {
                Button("Envoyer", action: onSend).frame(minHeight: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil).font(.mood(13, weight: .semibold)).fixedSize()
            }
        }
        .padding(8 * LayoutMetrics.scale).background(MoodTheme.inputBg)
        .tint(MoodTheme.brandAccent)
    }
}
