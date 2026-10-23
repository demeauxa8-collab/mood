import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The received file is copied before the transfer's temporary security scope ends.
nonisolated struct PickedMediaFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: url)
            return PickedMediaFile(url: url)
        }
    }
}

struct MediaAttachmentPicker: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(\.dismiss) private var dismiss
    let onFiles: ([URL]) -> Void
    @State private var selections: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var camera = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Group {
            if layoutMode == .compact {
                MobileSheet(title: "Pièces jointes", onClose: { dismiss() }) {
                    List {
                        Section { choices }.listRowBackground(MoodTheme.inputBg)
                        if busy { Section { ProgressView("Préparation…") }.listRowBackground(MoodTheme.inputBg) }
                        if let error { Section { Text(error).foregroundStyle(MoodTheme.mentionBadge) }.listRowBackground(MoodTheme.inputBg) }
                    }.mobileGroupedList()
                }
            } else {
                VStack(alignment: .leading, spacing: 6 * LayoutMetrics.scale) {
                    HStack(spacing: 12 * LayoutMetrics.scale) { choices }.font(.mood(13)).disabled(busy)
                    if busy { ProgressView("Préparation…").font(.mood(12)) }
                    if let error { Text(error).font(.mood(12)).foregroundStyle(MoodTheme.mentionBadge) }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): onFiles(urls)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onChange(of: selections) { _, items in
            guard !items.isEmpty else { return }
            busy = true
            Task { @MainActor in
                var files: [URL] = []
                for item in items {
                    do {
                        guard let file = try await item.loadTransferable(type: PickedMediaFile.self) else { throw CocoaError(.fileReadUnknown) }
                        files.append(file.url)
                    } catch { self.error = "Impossible d’importer un média. Réessaie depuis la photothèque." }
                }
                onFiles(files)
                selections = []; busy = false
            }
        }
        .sheet(isPresented: $camera) { MediaCamera { onFiles([$0]); camera = false } }
    }

    @ViewBuilder private var choices: some View {
                Button { importing = true } label: { Label("Fichiers", systemImage: "doc") }
                PhotosPicker(selection: $selections, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                    Label("Photothèque", systemImage: "photo")
                }
                #if !targetEnvironment(macCatalyst)
                if UIImagePickerController.isSourceTypeAvailable(.camera), Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil {
                    Button { camera = true } label: { Label("Appareil photo", systemImage: "camera") }
                }
                #endif

    }
}

private struct MediaCamera: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onFile: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaCamera
        init(_ parent: MediaCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { parent.onFile(url) }
            else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                if (try? data.write(to: url)) != nil { parent.onFile(url) }
            }
            parent.dismiss()
        }
    }
}
