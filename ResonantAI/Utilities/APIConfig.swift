import Foundation

// MARK: - API Configuration
struct APIConfig {
    // MARK: - OpenAI Configuration
    static let openAIAPIKey = "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"
    static let whisperAPIURL = "https://api.openai.com/v1/audio/transcriptions"
    
    // MARK: - API Limits and Configuration
    static let maxRetries = 3
    static let retryDelaySeconds = 2.0
    static let maxAudioFileSizeMB = 25 // Whisper API limit
    
    // MARK: - Supported Audio Formats
    static let supportedAudioFormats = ["m4a", "mp3", "mp4", "mpeg", "mpga", "wav", "webm"]
    
    // MARK: - Validation
    static func isValidAPIKey() -> Bool {
        return !openAIAPIKey.isEmpty && openAIAPIKey.hasPrefix("sk-")
    }
    
    static func isAudioFileSupported(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedAudioFormats.contains(fileExtension)
    }
    
    static func isAudioFileSizeValid(_ url: URL) -> Bool {
        do {
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let maxSizeBytes = maxAudioFileSizeMB * 1024 * 1024
            return fileSize <= maxSizeBytes
        } catch {
            return false
        }
    }
} 