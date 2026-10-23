import SwiftUI
import AVFoundation

/// A hold/drag gesture owns its pending permission task: releasing while permission is open cannot
/// leave a recorder running. The caller queues the returned file only after a successful release.
struct VoiceRecorderButton: View {
    let onRecorded: (URL, [Int], Int) -> Void
    var onPermissionDenied: () -> Void = {}
    var onFailure: (String) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder: AVAudioRecorder?
    @State private var powers: [Float] = []
    @State private var holding = false
    @State private var cancelled = false
    @State private var permissionTask: Task<Void, Never>?
    @State private var meterTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4 * LayoutMetrics.scale) {
            Image(systemName: "mic.fill").font(.mood(20))
                .foregroundStyle(holding ? MoodTheme.mentionBadge : MoodTheme.textSecondary)
                .frame(width: 44 * LayoutMetrics.scale, height: 44 * LayoutMetrics.scale)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !holding { holding = true; cancelled = false; begin() }
                        cancelled = value.translation.width < -70 * LayoutMetrics.scale
                    }
                    .onEnded { _ in finish(send: !cancelled) })
                .accessibilityLabel("Maintenir pour enregistrer, glisser à gauche pour annuler")
            if holding { Text(cancelled ? "Relâche pour annuler" : "Glisse à gauche pour annuler").font(.mood(11)).foregroundStyle(MoodTheme.textSecondary) }
        }.onDisappear { finish(send: false) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { finish(send: false) } }
    }
    private func begin() {
        permissionTask = Task { @MainActor in
            let permitted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard holding, !Task.isCancelled else { return }
            guard permitted else { onPermissionDenied(); return }
            do {
                #if !targetEnvironment(macCatalyst)
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocal-\(UUID().uuidString).m4a")
                let recording = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
                recording.isMeteringEnabled = true
                guard recording.record(forDuration: 120) else { throw CocoaError(.fileWriteUnknown) }
                recorder = recording
                powers = []
                meterTask = Task { @MainActor in
                    while !Task.isCancelled, holding {
                        recording.updateMeters()
                        powers.append(recording.averagePower(forChannel: 0))
                        try? await Task.sleep(for: .milliseconds(50))
                        if !recording.isRecording { finish(send: false); onFailure("Limite de 2 minutes atteinte. Maintiens le micro pour enregistrer un vocal plus court."); return }
                    }
                }
            } catch { onFailure("Le vocal n’a pas pu être enregistré. Maintiens le micro pour réessayer, ou écris ton message.") }
        }
    }
    private func finish(send: Bool) {
        holding = false
        permissionTask?.cancel(); permissionTask = nil
        meterTask?.cancel(); meterTask = nil
        guard let recording = recorder else { return }
        let milliseconds = Int(recording.currentTime * 1000)
        recording.stop(); recorder = nil
        if send, milliseconds >= 300 { onRecorded(recording.url, VoiceWaveform.normalized(powers), milliseconds) }
        else { try? FileManager.default.removeItem(at: recording.url) }
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
