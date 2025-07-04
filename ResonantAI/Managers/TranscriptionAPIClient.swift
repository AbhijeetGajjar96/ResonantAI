import Foundation
import Speech
import AVFoundation

// MARK: - Protocol for Speech-to-Text Service
protocol SpeechToTextServiceProtocol {
    func authorize() async throws
    func transcribe() -> AsyncThrowingStream<String, Error>
    func stopTranscribing()
}

// MARK: - Error Types
enum RecognizerError: Error {
    case recognizerUnavailable
    case notAuthorizedToRecognize
    case notPermittedToRecord
    case localRecognitionUnavailable
    case deviceNotSupported
}

// MARK: - Local Speech-to-Text Client (Apple Example)
final class TranscriptionAPIClient {
    // MARK: - Local Speech Transcription (Apple Example)
    func transcribe(url: URL, locale: Locale = Locale(identifier: "en-US"), contextualStrings: [String]? = nil, forceOnDevice: Bool = true) async throws -> String {
        // Request authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            throw TranscriptionError.permissionDenied
        }

        // Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerNotAvailable
        }

        // Create request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if #available(iOS 13.0, *) {
            if forceOnDevice && recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                print("[TranscriptionAPIClient] Forcing on-device recognition.")
            } else {
                request.requiresOnDeviceRecognition = false
                print("[TranscriptionAPIClient] Allowing server-based recognition.")
            }
        }
        if let vocab = contextualStrings, !vocab.isEmpty {
            request.contextualStrings = vocab
            print("[TranscriptionAPIClient] Using contextual vocabulary: \(vocab)")
        }
        request.taskHint = .dictation

        // Run recognition task
        let startTime = Date()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    print("[TranscriptionAPIClient] Transcription completed in \(Date().timeIntervalSince(startTime)) seconds.")
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    enum TranscriptionError: Error, LocalizedError {
        case permissionDenied
        case notAvailable
        case recognizerNotAvailable
        case networkError(String)
        case apiError(String)
        case parsingError(String)
        case conversionError(String)
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Speech recognition permission denied"
            case .notAvailable:
                return "Speech recognition not available"
            case .recognizerNotAvailable:
                return "Speech recognizer not available for this locale"
            case .networkError(let message):
                return "Network error: \(message)"
            case .apiError(let message):
                return "API error: \(message)"
            case .parsingError(let message):
                return "Parsing error: \(message)"
            case .conversionError(let message):
                return "Audio conversion error: \(message)"
            }
        }
    }
}

/*
// MARK: - OpenAI Whisper API Client (Commented Out)
// ... existing code ...
*/

// MARK: - Real-time Speech-to-Text Service
final class SpeechToTextService: @preconcurrency SpeechToTextServiceProtocol {
    private var accumulatedText: String = ""
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    
    /// Initializes a new instance of the speech recognition service with the provided locale identifier.
    /// - Parameter localeIdentifier: The locale identifier to use (defaults to the device's current locale).
    init(localeIdentifier: String = Locale.current.identifier) {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }
    
    /// Requests permissions and verifies the availability of the speech recognizer.
    /// - Throws: `RecognizerError` if the recognizer is unavailable or if the necessary permissions are not granted.
    func authorize() async throws {
        guard let recognizer = self.recognizer else {
            throw RecognizerError.recognizerUnavailable
        }
        
        let hasAuthorization = await SFSpeechRecognizer.hasAuthorizationToRecognize()
        guard hasAuthorization else {
            throw RecognizerError.notAuthorizedToRecognize
        }
        
        let hasRecordPermission = await AVAudioSession.sharedInstance().hasPermissionToRecord()
        guard hasRecordPermission else {
            throw RecognizerError.notPermittedToRecord
        }
        
        if !recognizer.isAvailable {
            throw RecognizerError.recognizerUnavailable
        }
        
        // Check for local speech recognition support
        if #available(iOS 13.0, *) {
            if !recognizer.supportsOnDeviceRecognition {
                print("[SpeechToTextService] Warning: On-device recognition not supported")
                throw RecognizerError.localRecognitionUnavailable
            }
        }
    }
    
    deinit {
        reset()
    }
    
    /// Starts the speech-to-text transcription process.
    /// - Returns: An `AsyncThrowingStream` that emits strings of transcribed text.
    @MainActor
    func transcribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (audioEngine, request) = try Self.prepareEngine()
                    self.audioEngine = audioEngine
                    self.request = request
                    
                    guard let recognizer = self.recognizer else {
                        throw RecognizerError.recognizerUnavailable
                    }
                    
                    // Configure request for better compatibility
                    request.requiresOnDeviceRecognition = false // Allow server fallback
                    
                    self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                        guard let self = self else {
                            return
                        }
                        
                        if let error = error {
                            print("[SpeechToTextService] Recognition error: \(error)")
                            
                            // Handle specific local recognition errors
                            if let nsError = error as NSError? {
                                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101 {
                                    print("[SpeechToTextService] Local speech recognition service error")
                                }
                            }
                            
                            continuation.finish(throwing: error)
                            self.reset()
                            return
                        }
                        
                        if let result = result {
                            let newText = result.bestTranscription.formattedString
                            
                            continuation.yield(self.accumulatedText + newText)
                            
                            if result.speechRecognitionMetadata != nil {
                                self.accumulatedText += newText + " "
                            }
                            
                            if result.isFinal {
                                continuation.finish()
                                self.reset()
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    self.reset()
                }
            }
        }
    }
    
    /// Stops the transcription process and releases associated resources.
    func stopTranscribing() {
        reset()
    }
    
    /// Resets and releases the resources used by the speech recognition service.
    func reset() {
        task?.cancel()
        task = nil
        audioEngine?.stop()
        audioEngine = nil
        request = nil
        accumulatedText = ""
    }
    
    /// Prepares the audio engine and speech recognition request.
    /// - Returns: A tuple containing the configured `AVAudioEngine` and `SFSpeechAudioBufferRecognitionRequest`.
    private static func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return (audioEngine, request)
    }
}

// MARK: - Extensions for Permission Checking
extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
