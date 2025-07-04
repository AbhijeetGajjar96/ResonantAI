import Foundation

enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending, processing, completed, failed, queued, offlineFallback, transcribing, whisperAPI
} 
