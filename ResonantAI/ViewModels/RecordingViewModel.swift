import Foundation
import Combine
import Speech

final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var audioLevel: Float = 0.0
    @Published var error: RecordingManager.RecordingError?
    @Published var audioLevels: [Float] = []
    let maxWaveformBars = 30

    let manager: RecordingManager
    private var cancellables = Set<AnyCancellable>()

    init(manager: RecordingManager) {
        self.manager = manager
        // Bind manager's published properties to view model
        manager.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
        manager.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
                self?.updateWaveformLevel(level)
            }.store(in: &cancellables)
        manager.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    private func updateWaveformLevel(_ newLevel: Float) {
        audioLevels.append(newLevel)
        if audioLevels.count > maxWaveformBars {
            audioLevels.removeFirst(audioLevels.count - maxWaveformBars)
        }
    }

    func toggleRecording() {
        isRecording ? manager.stopRecording() : manager.startRecording()
    }

    func pauseResume() {
        isPaused ? manager.resumeRecording() : manager.pauseRecording()
        isPaused.toggle()
    }

    // Permission helpers for RecordingView
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        manager.requestPermission(completion: completion)
    }

    func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
} 
