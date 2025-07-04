import Foundation
import ActivityKit
import Speech
import AVFoundation

// Common error types for the app

enum AppError: Error, LocalizedError {
    case audio(RecordingManager.RecordingError)
    case transcription(String)
    case storage(String)
    case recordingFailed(String)
    case transcriptionFailed(String)
    case fileOperationFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case networkError(String)
    case permissionDenied(String)
    case deviceNotSupported(String)
    case localSpeechRecognitionUnavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .audio(let err): return err.localizedDescription
        case .transcription(let msg): return "Transcription error: \(msg)"
        case .storage(let msg): return "Storage error: \(msg)"
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .deviceNotSupported(let message):
            return "Device not supported: \(message)"
        case .localSpeechRecognitionUnavailable:
            return "Local speech recognition is not available on this device. Please check your device settings or try using server-based transcription."
        case .unknown: return "Unknown error."
        }
    }
}

struct ErrorActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var message: String
    }
}

extension AppError {
    static var errorActivity: Activity<ErrorActivityAttributes>?
    static func showLiveActivity(for error: AppError) {
        let attributes = ErrorActivityAttributes()
        let contentState = ErrorActivityAttributes.ContentState(message: error.errorDescription ?? "Unknown error")
        errorActivity = try? Activity<ErrorActivityAttributes>.request(attributes: attributes, contentState: contentState)
    }
    static func dismissLiveActivity() {
        Task {
            await errorActivity?.end(dismissalPolicy: .immediate)
            errorActivity = nil
        }
    }
}

// MARK: - Device Capability Checker
class DeviceCapabilityChecker {
    
    /// Checks if the device supports speech recognition and provides detailed diagnostics
    static func checkSpeechRecognitionCapabilities() async -> SpeechRecognitionStatus {
        var status = SpeechRecognitionStatus()
        
        // Check speech recognition authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        status.authorizationStatus = authStatus
        
        // Check if speech recognizer is available
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            status.isRecognizerAvailable = false
            status.diagnostics.append("Speech recognizer could not be created for locale")
            return status
        }
        
        status.isRecognizerAvailable = recognizer.isAvailable
        
        // Check for local speech recognition support
        if #available(iOS 13.0, *) {
            status.supportsOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            if !recognizer.supportsOnDeviceRecognition {
                status.diagnostics.append("On-device speech recognition not supported")
            }
        } else {
            status.diagnostics.append("On-device speech recognition requires iOS 13.0+")
        }
        
        // Check microphone permission
        let hasMicrophonePermission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        status.hasMicrophonePermission = hasMicrophonePermission
        
        // Check device capabilities
        let audioSession = AVAudioSession.sharedInstance()
        status.hasAudioInput = audioSession.isInputAvailable
        
        // Check for specific error conditions
        if !status.isRecognizerAvailable {
            status.diagnostics.append("Speech recognizer is not available")
        }
        
        if !status.hasMicrophonePermission {
            status.diagnostics.append("Microphone permission not granted")
        }
        
        if !status.hasAudioInput {
            status.diagnostics.append("No audio input available")
        }
        
        return status
    }
    
    /// Provides specific guidance for kAFAssistantErrorDomain Code=1101 error
    static func getLocalSpeechRecognitionGuidance() -> [String] {
        return [
            "Local speech recognition service is unavailable",
            "Possible solutions:",
            "1. Check if your device supports local speech recognition (iOS 13.0+)",
            "2. Go to Settings > General > Language & Region > Add Language to download speech recognition data",
            "3. Ensure you have sufficient storage space for speech recognition data",
            "4. Try restarting your device",
            "5. Use server-based transcription as fallback"
        ]
    }
}

// MARK: - Speech Recognition Status
struct SpeechRecognitionStatus {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var isRecognizerAvailable: Bool = false
    var supportsOnDeviceRecognition: Bool = false
    var hasMicrophonePermission: Bool = false
    var hasAudioInput: Bool = false
    var diagnostics: [String] = []
    
    var isFullySupported: Bool {
        return authorizationStatus == .authorized &&
               isRecognizerAvailable &&
               hasMicrophonePermission &&
               hasAudioInput
    }
    
    var canUseLocalRecognition: Bool {
        return isFullySupported && supportsOnDeviceRecognition
    }
    
    var canUseServerRecognition: Bool {
        return isFullySupported
    }
} 