import Foundation
import SwiftData

@Model
final class Segment: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var audioFileURL: URL
    var transcription: String?
    var status: TranscriptionStatus
    var duration: TimeInterval
    var metadata: [String: String]
    @Relationship var session: Session?

    init(audioFileURL: URL, duration: TimeInterval, session: Session) {
        self.id = UUID()
        self.createdAt = Date()
        self.audioFileURL = audioFileURL
        self.duration = duration
        self.status = .pending
        self.metadata = [:]
        self.session = session
    }
} 