import Foundation
// import Speech // <-- Commented out: Local speech recognition is disabled in favor of Whisper API
// import AVFoundation

class LocalTranscriber: ObservableObject {
    // All local speech recognition code is now commented out.
    // This class is retained for possible future use if you want to re-enable on-device/local transcription.
    // For now, all transcription is handled by the Whisper API (see TranscriptionAPIClient).
    // To re-enable local transcription, uncomment the code and restore the original implementation.
    
    @Published var isTranscribing = false
    @Published var transcriptionText = ""
    @Published var error: String?
    
    // Placeholder for API compatibility
    init() {}
    
    // Placeholder async function for API compatibility
    func requestPermissions() async -> Bool {
        return true
    }
    
    // Placeholder async function for API compatibility
    func transcribeAudioFile(at url: URL) async throws -> String {
        throw TranscriptionError.localRecognitionUnavailable
    }
    
    func cancelTranscription() {
        // No-op
    }
    
    enum TranscriptionError: Error, LocalizedError {
        case recognizerNotAvailable
        case permissionDenied
        case localRecognitionUnavailable
        
        var errorDescription: String? {
            switch self {
            case .recognizerNotAvailable:
                return "Speech recognizer is not available"
            case .permissionDenied:
                return "Speech recognition permission denied"
            case .localRecognitionUnavailable:
                return "Local speech recognition is not available on this device (Whisper API is used instead)"
            }
        }
    }
} 