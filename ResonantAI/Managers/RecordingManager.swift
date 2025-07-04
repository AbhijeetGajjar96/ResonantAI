import Foundation
import UIKit
import AVFoundation
import Combine
import SwiftData

final class RecordingManager: ObservableObject {
    enum RecordingError: Error, LocalizedError {
        case permissionDenied, recordingFailed, storageFull, unknown
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone permission denied."
            case .recordingFailed: return "Recording failed."
            case .storageFull: return "Insufficient storage."
            case .unknown: return "Unknown error."
            }
        }
    }
    
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0 // For level meter
    @Published var error: RecordingError?
    
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private var audioFile: AVAudioFile?
    private var cancellables = Set<AnyCancellable>()
    private var bufferQueue = DispatchQueue(label: "audioBufferQueue")
    private var segmentDuration: TimeInterval = 30
    private var currentSegmentStart: Date?
    private var segmentBuffers: [AVAudioPCMBuffer] = []
    private var segmentTimer: Timer?
    private var audioFormat: AVAudioFormat?
    private var fileManager: EncryptedFileManager
    private var modelContext: ModelContext?
    var currentSession: Session?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    
    // DSA: Sliding window/buffer for segmenting audio
    // DSA: Queue for segment processing
    
    init(fileManager: EncryptedFileManager, modelContext: ModelContext? = nil) {
        self.fileManager = fileManager
        self.modelContext = modelContext
        setupNotifications()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func setCurrentSession(_ session: Session) {
        self.currentSession = session
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }
    
    func startRecording() {
        do {
            try configureSession()
            let input = engine.inputNode
            let inputFormat = input.inputFormat(forBus: 0)
            audioFormat = inputFormat
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                self?.processBuffer(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            currentSegmentStart = Date()
            startSegmentTimer()
        } catch {
            self.error = .recordingFailed
        }
    }
    
    func pauseRecording() {
        engine.pause()
        isRecording = false
    }
    
    func resumeRecording() {
        do {
            try engine.start()
            isRecording = true
        } catch {
            self.error = .recordingFailed
        }
    }
    
    func stopRecording() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        stopSegmentTimer()
        flushSegment()
    }
    
    private func configureSession() throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in self?.handleInterruption(notification) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in self?.handleRouteChange(notification) }
            .store(in: &cancellables)
    }
    
    // Handles audio interruptions (Siri, calls, etc.)
    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            pauseRecording()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                resumeRecording()
            }
        @unknown default: break
        }
    }
    
    // Handles audio route changes (headphones, Bluetooth, etc.)
    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            pauseRecording()
            // Optionally: alert user, auto-resume if possible
        }
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.segmentBuffers.append(copy)
                self.updateAudioLevel(copy) // Or any UI update
            }
        }
    }
    
    private func updateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        let rms: Float
        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            rms = sqrt(sum / Float(frameLength))
        } else {
            rms = 0
        }
        DispatchQueue.main.async { self.audioLevel = rms }
    }
    
    private func startSegmentTimer() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.flushSegment()
        }
    }
    
    private func stopSegmentTimer() {
        segmentTimer?.invalidate()
        segmentTimer = nil
    }
    
    // Flushes the current segment buffer to disk and notifies for transcription
    func flushSegment() {
        guard !segmentBuffers.isEmpty, let format = audioFormat else { return }
        let segmentID = UUID()
        // Write as WAV (PCM) for AVFoundation compatibility
        let url = fileManager.encryptedAudioURL(for: segmentID).deletingPathExtension().appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            for buffer in segmentBuffers {
                try file.write(from: buffer)
            }
            fileManager.encryptFile(at: url)
            // --- Save Segment to SwiftData ---
            if let context = modelContext, let session = currentSession {
                let duration = segmentBuffers.reduce(0) { $0 + Double($1.frameLength) / 44100.0 }
                let segment = Segment(audioFileURL: url, duration: duration, session: session)
                segment.id = segmentID // Ensure the segment ID matches
                context.insert(segment)
                try? context.save()
                print("[RecordingManager] Created segment with ID: \(segmentID)")
            }
            // Post notification with segment ID instead of URL
            NotificationCenter.default.post(name: .didFinishSegment, object: segmentID)
        } catch {
            print("Audio file write error: \(error)")
            self.error = .recordingFailed
        }
        segmentBuffers.removeAll()
        currentSegmentStart = Date()
    }
    
    func checkPermissions(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
#if canImport(UIKit)
    func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinishRecording") {
            self.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
#endif
}

extension Notification.Name {
    static let didFinishSegment = Notification.Name("didFinishSegment")
}
