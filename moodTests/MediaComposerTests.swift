import Foundation
import Testing
import ImageIO
import UIKit
@testable import mood

struct MediaComposerTests {
    @Test func attachmentLimitAndRemoval() {
        let urls = (0..<12).map { URL(fileURLWithPath: "/tmp/\($0).png") }
        let selected = AttachmentSelectionPolicy.appending(urls, to: [])
        #expect(selected == Array(urls.prefix(10)))
        #expect(AttachmentSelectionPolicy.appending([urls[0]], to: selected) == selected)
        var removed = selected
        removed.remove(at: 4)
        #expect(AttachmentSelectionPolicy.appending([urls[10]], to: removed).last == urls[10])
    }

    @MainActor @Test func draftsSurviveReloadAndSeparateRoomsAndAccounts() throws {
        let suite = "n2-drafts-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = ComposerDraft(text: "Bonjour\nà tous", replyEventID: "$reply")
        ComposerDrafts(defaults: defaults).save(draft, account: "a", room: "room1")
        let restored = ComposerDrafts(defaults: defaults)
        #expect(restored.load(account: "a", room: "room1") == draft)
        #expect(restored.load(account: "b", room: "room1") == nil)
        #expect(restored.load(account: "a", room: "room2") == nil)
        restored.save(ComposerDraft(text: "", replyEventID: nil), account: "a", room: "room1")
        #expect(restored.load(account: "a", room: "room1") == nil)
    }

    @Test func waveformIsBoundedFiniteAndReduced() {
        #expect(VoiceWaveform.normalized([]).isEmpty)
        #expect(VoiceWaveform.normalized([0, -20, -160]) == [1024, 102, 0])
        let reduced = VoiceWaveform.normalized(Array(repeating: Float(-10), count: 1000))
        #expect(reduced.count == 64)
        #expect(reduced.allSatisfy { (0...1024).contains($0) })
        #expect(VoiceWaveform.normalized([.nan, -.infinity]) == [0, 0])
    }

    @Test func previewDecodesOpenGraphAndFindsSafeLinks() throws {
        let preview = try JSONDecoder().decode(MediaLinkPreview.self, from: Data(#"{"og:title":"Titre","og:description":"Description","og:image":"mxc://host/image"}"#.utf8))
        #expect(preview.title == "Titre")
        #expect(preview.image == "mxc://host/image")
        #expect(MediaLinkPreview.firstURL(in: "Lis https://github.com ensuite")?.host == "github.com")
        #expect(MediaLinkPreview.firstURL(in: "file:///private/file") == nil)
        #expect(MediaLinkPreview.firstURL(in: "sans lien") == nil)
    }

    @Test func frenchEmojiSearchAndRecents() {
        let entries = [CatalogEmoji(emoji: "❤️", category: "Symboles", keywords: "cœur amour"), CatalogEmoji(emoji: "🎉", category: "Activités", keywords: "fête célébration")]
        #expect(MediaEmojiCatalog.matching("FETE", in: entries).map(\.emoji) == ["🎉"])
        #expect(MediaEmojiCatalog.matching("amour", in: entries).map(\.emoji) == ["❤️"])
        #expect(MediaEmojiCatalog.recording("🎉", in: ["❤️", "🎉", "👍"]) == ["🎉", "❤️", "👍"])
    }

    @Test func voiceEventAndQueuePersistence() throws {
        var attachment = OutgoingAttachment(kind: .audio, fileName: "voice.m4a", localFile: "v.m4a", mimeType: "audio/mp4", size: 200)
        attachment.duration = 1200
        attachment.voiceWaveform = [0, 512, 1024]
        attachment.contentURI = "mxc://host/voice"
        let content = attachment.eventContent()
        #expect(content["msgtype"] as? String == "m.audio")
        #expect(content["org.matrix.msc3245.voice"] != nil)
        let audio = try #require(content["org.matrix.msc1767.audio"] as? [String: Any])
        #expect(audio["waveform"] as? [Int] == [0, 512, 1024])
        #expect(audio["duration"] as? Int == 1200)
        let message = OutgoingMessage(txnId: "voice", roomId: "room", body: "voice.m4a", replyToEventId: nil, threadRootEventId: nil, createdAt: Date(), attachment: attachment)
        let queue = OutboxQueue(messages: [message])
        #expect(try JSONDecoder().decode(OutboxQueue.self, from: JSONEncoder().encode(queue)) == queue)
    }
    @Test func animatedGIFSurvivesPreparationAndDecode() async throws {
        let source = try #require(Bundle.main.url(forResource: "n2-animation", withExtension: "gif"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("n2-gif-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let attachment = try await MediaPreparation.prepare(sourceURL: source, txnId: "animation", folder: folder, limit: 1_000_000)
        let output = try Data(contentsOf: folder.appendingPathComponent(attachment.localFile))
        let imageSource = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        #expect(CGImageSourceGetCount(imageSource) == 2)
        let image = try #require(await MediaLoader.decode(output, maxPixelSize: 1600))
        #expect((image.images?.count ?? 0) > 1)
        #expect(image.duration > 0)
    }

    @Test func realVideoAndAudioMetadata() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("n2-av-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = try #require(Bundle.main.url(forResource: "n2-clip", withExtension: "mp4"))
        let prepared = try await MediaPreparation.prepare(sourceURL: video, txnId: "clip", folder: folder, limit: 1_000_000)
        #expect(prepared.kind == .video)
        #expect((prepared.duration ?? 0) >= 900)
        #expect(prepared.width == 320)
        #expect(prepared.height == 180)
        #expect(prepared.thumbnailFile != nil)
        #expect(prepared.thumbnailMimeType == "image/jpeg")
        let audio = try #require(Bundle.main.url(forResource: "n2-tone", withExtension: "m4a"))
        let sound = try await MediaPreparation.prepare(sourceURL: audio, txnId: "tone", folder: folder, limit: 1_000_000)
        #expect(sound.kind == .audio)
        #expect((sound.duration ?? 0) >= 900)
        #expect(sound.size > 0)
    }

    @Test func fullCatalogIncludesFrenchNamesAndSkinTones() {
        #expect(MediaEmojiCatalog.entries.count > 3000)
        #expect(MediaEmojiCatalog.matching("chat").contains { $0.emoji == "🐱" })
        #expect(MediaEmojiCatalog.entries.contains { $0.emoji == "👍🏽" })
    }

}
